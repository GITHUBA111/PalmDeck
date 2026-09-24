import Foundation
import Combine

/// 座舱模式
/// 持久化键（P7 手感参数）
private enum PKey {
    static let sensX = "palmdeck_sens_x"
    static let sensY = "palmdeck_sens_y"
    static let dz = "palmdeck_dz"
    static let invX = "palmdeck_inv_x"
    static let invY = "palmdeck_inv_y"
    static let invYaw = "palmdeck_inv_yaw"
    static let invColl = "palmdeck_inv_coll"
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
    @Published var mode: CockpitMode = CockpitMode.parse(
        UserDefaults.standard.string(forKey: "palmdeck_mode"))
    @Published var link: LinkState = .idle
    @Published var backend: String = ""      // vjoy+vgamepad / none …
    @Published var deviceName: String = ""
    /// 电脑端上报的协议版本（hello 帧的 `version`，如 "4.0"）。空 = 尚未拿到。
    @Published var pcVersion: String = ""
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

    // ---- 参数（全部持久化：改一次，重启仍在）----
    @Published var sensX: Double = ControllerState.loadDouble(PKey.sensX, 1.0) {
        didSet { UserDefaults.standard.set(sensX, forKey: PKey.sensX) }
    }
    @Published var sensY: Double = ControllerState.loadDouble(PKey.sensY, 1.0) {
        didSet { UserDefaults.standard.set(sensY, forKey: PKey.sensY) }
    }
    @Published var dz: Double = ControllerState.loadDouble(PKey.dz, 0.06) {
        didSet { UserDefaults.standard.set(dz, forKey: PKey.dz) }
    }
    @Published var invX: Bool = ControllerState.loadBool(PKey.invX, false) {   // 反转横滚
        didSet { UserDefaults.standard.set(invX, forKey: PKey.invX) }
    }
    @Published var invY: Bool = ControllerState.loadBool(PKey.invY, false) {   // 反转俯仰
        didSet { UserDefaults.standard.set(invY, forKey: PKey.invY) }
    }
    @Published var invYaw: Bool = ControllerState.loadBool(PKey.invYaw, false) {  // 反转方向舵
        didSet { UserDefaults.standard.set(invYaw, forKey: PKey.invYaw) }
    }
    @Published var invColl: Bool = ControllerState.loadBool(PKey.invColl, false) { // 反转总距
        didSet { UserDefaults.standard.set(invColl, forKey: PKey.invColl) }
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
