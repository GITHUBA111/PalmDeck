import Foundation

/// 轴整形曲线 —— **唯一实现**。
///
/// 为什么必须有这一个文件：这套数学原来在三个地方各写了一遍
/// （`ControllerState.shape`、`Packet.shape`、`SettingsView.AxisResponseCurve.output`），
/// 谁都能在不知情的情况下改歪其中一份。而「设置里的响应曲线预览」如果不等于
/// 真正发出去的整形函数，就是在骗人 —— 那比没有预览更糟。
/// 所以预览不再复刻公式，而是直接调用这里。
///
/// 曲线定义（与历史行为逐位一致，改动即为破坏性变更）：
///
///     y = sign(x) · ((|x| − dz) / (1 − dz)) ^ 1.35      |x| >= dz
///     y = 0                                              |x| <  dz
///
/// 要点：
/// - 先乘灵敏度、夹到 [-1,1]，**再**进死区/曲线（顺序不能反）。
/// - 死区是「输入侧」的绝对值阈值，不随灵敏度缩放。
/// - `dz` 被夹到 [0, 0.95)，避免除零与「全死区」。
/// - 指数 1.35 大于 1 → 中段更细腻、末端更快到底。
enum AxisCurve {

    /// 曲线指数。>1 表示 S 形（中段细腻）。
    static let exponent = 1.35

    /// 输入死区上限（留一点余量，保证 `1 - dz > 0`）。
    static let maxDeadzone = 0.95

    /// 夹到单位区间 [-1, 1]。
    static func clampUnit(_ v: Double) -> Double {
        max(-1, min(1, v))
    }

    /// 纯整形：输入已在 [-1,1] 内，只做死区 + 指数。
    static func shape(_ v: Double, dz: Double) -> Double {
        let d = max(0, min(maxDeadzone, dz))
        let s: Double = v < 0 ? -1.0 : 1.0
        let a = abs(v)
        if a < d { return 0 }
        return s * pow((a - d) / (1 - d), exponent)
    }

    /// 完整整形：反转 → 乘灵敏度 → 夹紧 → 死区/曲线。
    ///
    /// 与 `ControllerState.tickSmoothing()` 的调用顺序一致：
    /// `shape(clampUnit((invert ? -v : v) * sens), dz: dz)`
    static func output(_ v: Double, sensitivity: Double = 1, deadzone: Double = 0, inverted: Bool = false) -> Double {
        shape(clampUnit((inverted ? -v : v) * sensitivity), dz: deadzone)
    }
}
