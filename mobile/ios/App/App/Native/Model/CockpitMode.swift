import Foundation

/// 座舱模式。**纯类型，不依赖任何框架** —— 这样测试目标可以直接编译它，
/// 不需要宿主 App（见 `AxisCoreTests`）。
enum CockpitMode: String, CaseIterable, Codable {
    case heli = "heli"
    case drive = "drive"
    case gamepad = "gamepad"

    var label: String {
        switch self {
        case .heli: return "飞机"
        case .drive: return "开车"
        case .gamepad: return "手柄"
        }
    }

    /// 是否使用可自定义的组件画布（只有手柄）。heli/drive 走固定硬件皮肤。
    var usesWidgetCanvas: Bool { self == .gamepad }

    /// 兼容旧值：UserDefaults / 旧服务端可能仍给 `infantry`（v3 遗留）。
    static func parse(_ raw: String?) -> CockpitMode {
        switch raw {
        case "infantry": return .gamepad
        default: return CockpitMode(rawValue: raw ?? "") ?? .heli
        }
    }
}
