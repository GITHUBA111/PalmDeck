import Foundation
import Combine

/// 3D 直升机显示的姿态来源
enum DisplaySource: String, CaseIterable {
    case stick = "stick"        // 本地杆位（默认，永远可用）
    case telemetry = "telemetry" // 游戏遥测（需电脑侧开启遥测）

    var label: String {
        switch self {
        case .stick: return "本地杆位"
        case .telemetry: return "游戏遥测"
        }
    }
}

/// 座舱模式
enum CockpitMode: String, CaseIterable {
    case heli = "heli"
    case drive = "drive"
    case infantry = "infantry"

    var label: String {
        switch self {
        case .heli: return "飞机"
        case .drive: return "开车"
        case .infantry: return "步兵"
        }
    }
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
    @Published var clutch: Double = 0      // 开车：离合（0~1），走 vJoy Rz

    // ---- 开车分页 ----
    @Published var drivePage: Int = 0      // 0=驾驶 1=按键

    // ---- 帽 / 按键 ----
    @Published var hat: UInt8 = 255        // 0上 1右 2下 3左 255无
    @Published var btnMask: UInt16 = 0     // bit0..bit9 = b1..b10

    // ---- 模式 / 连接 ----
    @Published var mode: CockpitMode = CockpitMode(
        rawValue: UserDefaults.standard.string(forKey: "palmdeck_mode") ?? "heli") ?? .heli
    @Published var link: LinkState = .idle
    @Published var backend: String = ""      // vjoy+vgamepad / none …
    @Published var deviceName: String = ""
    @Published var hz: Double = 0
    @Published var transport: String = "idle" // udp / ws / idle
    @Published var lastError: String = ""

    // ---- 体感 / 姿态 ----
    @Published var paused: Bool = false      // 锁定
    @Published var haveCenter: Bool = false  // 已校准

    // ---- 游戏遥测（可选）----
    @Published var telemRoll: Double = 0
    @Published var telemPitch: Double = 0
    @Published var telemYaw: Double = 0
    @Published var telemValid: Bool = false
    @Published var displaySource: DisplaySource = .stick

    // ---- 平滑后的发送值（EMA）----
    private(set) var smRoll: Double = 0
    private(set) var smPitch: Double = 0
    private(set) var smYaw: Double = 0

    /// 按键/帽变化回调（b1..b10, hat）
    var onButton: ((Int, Bool) -> Void)?
    var onHat: ((UInt8) -> Void)?

    // ---- 参数 ----
    var sensX: Double = 1.0
    var sensY: Double = 1.0
    var dz: Double = 0.06
    var invX: Bool = false      // 反转横滚
    var invY: Bool = false      // 反转俯仰
    var invYaw: Bool = false    // 反转方向舵
    var invColl: Bool = false   // 反转总距
    var stickReturn: Bool = true
    var wheelReturnSpeed: Double = 720   // 方向盘回正速度（度/秒）；0 = 不回正
    var wheelMaxDeg: Double = 540        // 方向盘满舵角度

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
        let r = invX ? -roll : roll
        let p = invY ? -pitch : pitch
        let y = invYaw ? -yaw : yaw
        smRoll += (shape(r, dz: dz) - smRoll) * kXY
        smPitch += (shape(p, dz: dz) - smPitch) * kXY
        smYaw += (shape(y, dz: 0.08) - smYaw) * kYaw
    }

    /// 总距（应用反转后）
    var collective: Double { invColl ? (1 - throttle) : throttle }

    /// 3D 显示用的姿态（按来源选择）
    var displayRoll: Double { displaySource == .telemetry && telemValid ? telemRoll : smRoll }
    var displayPitch: Double { displaySource == .telemetry && telemValid ? telemPitch : smPitch }
    var displayYaw: Double { displaySource == .telemetry && telemValid ? telemYaw : smYaw }

    private func shape(_ v: Double, dz: Double) -> Double {
        let s = v < 0 ? -1.0 : 1.0
        let a = abs(v)
        if a < dz { return 0 }
        return s * pow((a - dz) / (1 - dz), 1.35)
    }
}
