import Foundation

/// 底部仪表条的一格：只描述「显示什么」，颜色/字体留给视图层
/// （`Model/` 一层不许 import SwiftUI，这一层要能被 `swiftc` 单测直跑）。
enum HudTone {
    /// 轴有动作
    case active
    /// 轴在中位/静止
    case quiet
}

struct HudReadoutCell: Equatable {
    let label: String
    let value: String
    let tone: HudTone
}

/// 底部仪表条**按模式**取字段。
///
/// 原来三个模式共用一套 `ROL/PIT/YAW/THR`，可它显示的东西并不一样：
/// 开车模式压根不发 Rz（`AxisMap` 里恒 0），手柄模式的 `thr/lt/rt` 也全清零，
/// 屏幕上却照旧摆着「方向 / 油门」——「界面说的」和「真正发出去的」又分家了
/// （E1 修的就是这一类问题）。
///
/// 所以这里吃的是 `AxisMap.resolve(...)` 的输出（`AxisOutputs`，与 `Packet.pack` 同源），
/// 逐格对着真值表里有值的槽位摆。改真值表就得跟着改这里，`AxisCoreTests` 会拦。
enum HudReadout {

    /// 双极轴（-1…1）→ `+0.32`。
    /// 以前是 `%+.1f°`：把归一化杆位当角度显示（0.32 读成「0.32 度」），单位是错的。
    /// 小于显示精度（0.005）的一律归到 `+0.00`：自回中后残留 -1e-5
    /// 会被打印成 `-0.00`，看着像有信号。
    static func bipolar(_ v: Double) -> String {
        abs(v) < 0.005 ? "+0.00" : String(format: "%+.2f", v)
    }

    /// 单极轴（0…1）→ 百分比。
    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    /// 中位附近算「没动」（与视图层原来的 0.01 阈值一致）。
    static func tone(_ v: Double) -> HudTone { abs(v) < 0.01 ? .quiet : .active }

    /// 每模式 4 格，顺序 = 该模式下用户最常看的量。
    static func axis(mode: CockpitMode, out: AxisOutputs) -> [HudReadoutCell] {
        switch mode {
        case .heli:
            return [
                HudReadoutCell(label: "横滚", value: bipolar(out.roll), tone: tone(out.roll)),
                HudReadoutCell(label: "俯仰", value: bipolar(out.pitch), tone: tone(out.pitch)),
                HudReadoutCell(label: "方向", value: bipolar(out.yaw), tone: tone(out.yaw)),
                HudReadoutCell(label: "总距", value: percent(out.thr), tone: tone(out.thr)),
            ]
        case .drive:
            // 记住真值表：开车模式的 pitch 槽是**离合**，rt 也是油门（rt 真值被忽略）。
            return [
                HudReadoutCell(label: "转向", value: bipolar(out.roll), tone: tone(out.roll)),
                HudReadoutCell(label: "离合", value: bipolar(out.pitch), tone: tone(out.pitch)),
                HudReadoutCell(label: "油门", value: percent(out.thr), tone: tone(out.thr)),
                HudReadoutCell(label: "刹车", value: percent(out.lt), tone: tone(out.lt)),
            ]
        case .gamepad:
            // 手柄模式不发 thr/lt/rt（恒 0），所以一格油门/刹车都不该出现。
            return [
                HudReadoutCell(label: "摇杆X", value: bipolar(out.roll), tone: tone(out.roll)),
                HudReadoutCell(label: "摇杆Y", value: bipolar(out.pitch), tone: tone(out.pitch)),
                HudReadoutCell(label: "视角X", value: bipolar(out.lookX), tone: tone(out.lookX)),
                HudReadoutCell(label: "视角Y", value: bipolar(out.lookY), tone: tone(out.lookY)),
            ]
        }
    }
}
