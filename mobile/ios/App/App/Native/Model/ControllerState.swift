import Foundation
import Combine

/// 持久化键（P7 手感参数；G1 起手感参数**按模式分键**，见 `ShapingKeys`）
private enum PKey {
    static let stickReturn = "palmdeck_stick_return"
    static let wheelMaxDeg = "palmdeck_wheel_max_deg"
    static let wheelReturn = "palmdeck_wheel_return"
}

/// 连接状态
enum LinkState {
    case idle, connecting, live, lost
}

/// 单个按键的边沿事件（供原生触发振动等）
struct ButtonEdge {
    var index: Int   // 1..10
    var down: Bool
}

/// 座舱共享状态。UI 直接绑定，热路径 60Hz 读取打包发送。
final class ControllerState: ObservableObject {

    // ---- 语义轴 ----
    @Published var roll: Double = 0        // [-1, 1] 横滚
    @Published var pitch: Double = 0       // [-1, 1] 俯仰
    @Published var yaw: Double = 0         // [-1, 1] 方向舵
    @Published var throttle: Double = 0.35 // [0, 1] 油门/总距
    @Published var lookX: Double = 0
    @Published var lookY: Double = 0
    @Published var lt: Double = 0          // 左扳机 / 刹车
    @Published var rt: Double = 0          // 右扳机 / 开火
    @Published var clutch: Double = 0      // 开车：离合（0~1），走左摇杆 Y（0 → 中位，1 → -1）

    // ---- 帽 / 按键 ----
    @Published var hat: UInt8 = 255        // 0上 1右 2下 3左 255无
    @Published var btnMask: UInt16 = 0     // bit0..bit9 = b1..b10

    // ---- 模式 / 连接 ----
    /// 模式（`palmdeck_mode`）。属性初始化早于 `self` 可用，所以先算静态值。
    @Published var mode: CockpitMode = CockpitMode.parse(
        UserDefaults.standard.string(forKey: "palmdeck_mode"))
    @Published var link: LinkState = .idle
    @Published var backend: String = ""      // vjoy+vgamepad / none …
    @Published var deviceName: String = ""
    /// 电脑端上报的协议版本（hello 帧的 `version`，如 "4.0"）。空 = 尚未拿到。
    @Published var pcVersion: String = ""
    /// 电脑端**实际生效**的轴表名（hello/status 的 `axis_profile`，如 "hotas"）。
    /// G3 之前 App 不能改它，只能显示它，用来提示「选中的预设与电脑是否对得上」。
    @Published var axisProfile: String = ""
    @Published var hz: Double = 0
    @Published var transport: String = "idle" // udp / ws / idle
    @Published var lastError: String = ""

    // ---- 平滑后的发送值（EMA）----
    private(set) var smRoll: Double = 0
    private(set) var smPitch: Double = 0
    private(set) var smYaw: Double = 0

    /// 按键/帽变化回调（b1..b10, hat）
    var onButton: ((Int, Bool) -> Void)?
    var onHat: ((UInt8) -> Void)?

    // ---- 手感参数（G1：全部**按模式分键**持久化）----
    // 初始值是兜底常量；真正的读取只走 `reloadShaping()` 一条路径，
    // 免得「默认值写在属性上、读取写在 init 里」两处会漂。
    @Published var sensX: Double = 1.0 {
        didSet { ShapingParams.set(shapingStore, sensX, ShapingKeys.sensX, mode) }
    }
    @Published var sensY: Double = 1.0 {
        didSet { ShapingParams.set(shapingStore, sensY, ShapingKeys.sensY, mode) }
    }
    @Published var dz: Double = 0.06 {
        didSet { ShapingParams.set(shapingStore, dz, ShapingKeys.dz, mode) }
    }
    @Published var invX: Bool = false {   // 反转横滚
        didSet { ShapingParams.set(shapingStore, invX, ShapingKeys.invX, mode) }
    }
    @Published var invY: Bool = false {   // 反转俯仰
        didSet { ShapingParams.set(shapingStore, invY, ShapingKeys.invY, mode) }
    }
    @Published var invYaw: Bool = false {  // 反转方向舵
        didSet { ShapingParams.set(shapingStore, invYaw, ShapingKeys.invYaw, mode) }
    }
    @Published var invColl: Bool = false { // 反转总距
        didSet { ShapingParams.set(shapingStore, invColl, ShapingKeys.invColl, mode) }
    }
    @Published var stickReturn: Bool = ControllerState.loadBool(PKey.stickReturn, true) {
        didSet { UserDefaults.standard.set(stickReturn, forKey: PKey.stickReturn) }
    }
    @Published var wheelReturnSpeed: Double = ControllerState.loadDouble(PKey.wheelReturn, 720) {  // 度/秒；0 = 不回正
        didSet { UserDefaults.standard.set(wheelReturnSpeed, forKey: PKey.wheelReturn) }
    }
    @Published var wheelMaxDeg: Double = ControllerState.loadDouble(PKey.wheelMaxDeg, 540) {  // 满舵角度
        didSet { UserDefaults.standard.set(wheelMaxDeg, forKey: PKey.wheelMaxDeg) }
    }

    /// 手感参数的落盘位置（G1）。默认就是 `UserDefaults.standard`；
    /// 测试注入字典替身，这样跑测试不会往真实偏好设置里写东西。
    let shapingStore: ShapingStore

    init(shapingStore: ShapingStore = UserDefaults.standard) {
        self.shapingStore = shapingStore
        // G1 迁移：旧的全局手感键 → 三个模式各自一份，然后删旧键。
        // 先跑迁移再读，所以不会漏掉老用户的值。
        ShapingMigration.run(shapingStore)
        reloadShaping()
    }

    /// 把**当前模式**的手感参数读进来。初始化与切模式共用这一条路径。
    ///
    /// 赋值会触发 `didSet`，把值写回同一个键 —— 等于把默认值也落成显式值，
    /// 于是每个模式从一开始就各有一份完整参数（读的时候不用再想兜底）。
    private func reloadShaping() {
        let ud = shapingStore
        sensX = ShapingParams.double(ud, ShapingKeys.sensX, mode, 1.0)
        sensY = ShapingParams.double(ud, ShapingKeys.sensY, mode, 1.0)
        dz = ShapingParams.double(ud, ShapingKeys.dz, mode, 0.06)
        invX = ShapingParams.bool(ud, ShapingKeys.invX, mode, false)
        invY = ShapingParams.bool(ud, ShapingKeys.invY, mode, false)
        invYaw = ShapingParams.bool(ud, ShapingKeys.invYaw, mode, false)
        invColl = ShapingParams.bool(ud, ShapingKeys.invColl, mode, false)
    }

    /// 切模式：换成本模式自己的手感参数（G1）。
    ///
    /// 先换 `mode` 再读值 —— `didSet` 的保存键跟着 `mode` 走，
    /// 所以写回去的就是刚读出来的那个键，**不会把旧模式的参数写进新模式**。
    func applyMode(_ m: CockpitMode) {
        mode = m
        reloadShaping()
    }

    private static func loadDouble(_ key: String, _ def: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? def
    }
    private static func loadBool(_ key: String, _ def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    func resetAxes() {
        roll = 0; pitch = 0; yaw = 0
        lookX = 0; lookY = 0; lt = 0; rt = 0
        clutch = 0
        btnMask = 0
        smRoll = 0; smPitch = 0; smYaw = 0
    }

    /// 每帧 EMA 平滑（在发送前调用）。反转在此应用，sm* 即最终发送/显示值。
    func tickSmoothing() {
        let kXY = 0.45, kYaw = 0.5
        // 灵敏度先乘、再夹到单位区间，最后进死区/曲线（避免 sm 溢出显示）
        // 夹紧顺序不能反：先乘灵敏度再夹到 [-1,1]，然后才进死区/曲线。
        // 曲线数学在 AxisCurve（唯一实现），设置里的预览调的是同一个函数。
        let r = AxisCurve.clampUnit((invX ? -roll : roll) * sensX)
        let p = AxisCurve.clampUnit((invY ? -pitch : pitch) * sensY)
        let y = invYaw ? -yaw : yaw
        smRoll += (AxisCurve.shape(r, dz: dz) - smRoll) * kXY
        smPitch += (AxisCurve.shape(p, dz: dz) - smPitch) * kXY
        smYaw += (AxisCurve.shape(y, dz: ControllerState.yawDeadzone) - smYaw) * kYaw
    }

    /// 方向舵固定死区（不跟随「摇杆死区」滑条：偏航是自回中轴，太大死区会转不动尾桨）。
    static let yawDeadzone = 0.08

    /// 总距（应用反转后）
    var collective: Double { invColl ? (1 - throttle) : throttle }
}

/// G2：`GameProfileApplier` 把预设的手感参数写回本对象。
/// 这些存储属性满足 `ShapingTarget` 的 get/set；conformance 在这里声明，
/// 让 `GameProfile.swift` 不必 import Combine。
extension ControllerState: ShapingTarget {}
