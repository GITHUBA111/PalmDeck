import SwiftUI

// MARK: - 飞行仪表盘（只读组件）
//
// 这里只放"显示"，不放"语义"：弧表 / 杆位条 / 姿态球读的都是本机发出去的平滑杆位
// （`ControllerState.smRoll/smPitch/smYaw/collective`），不读游戏遥测，
// 也不绑定任何 vJoy 按键——所以它可以直接当组件摆在任意模式的画布上。

/// 圆弧仪表：270° 表盘 + 中央读数。
struct ArcGauge: View {
    var title: String
    var value: Double            // 0..1
    var unit: String = ""
    var accent: Color = Theme.green
    var danger: Bool = false

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let lw = max(3, d * 0.11)
            let frac = max(0, min(1, value))
            let color = danger ? Theme.red : accent
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Theme.border.opacity(0.55),
                            style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * frac)
                    .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .glow(color, radius: 3)
                VStack(spacing: 0) {
                    Text(String(format: "%.0f", frac * 100))
                        .font(.system(size: max(9, d * 0.26), weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .minimumScaleFactor(0.5)
                    Text(title)
                        .font(.system(size: max(6, d * 0.13), weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textFaint)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "%.0f%%%@", max(0, min(1, value)) * 100, unit.isEmpty ? "" : " \(unit)"))
    }
}

/// 双极竖条仪表（横滚 / 俯仰 / 方向舵）。
struct BarGauge: View {
    var title: String
    var value: Double            // -1..1
    var accent: Color = Theme.cyan

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let frac = max(-1, min(1, value))
            let fill = abs(frac) * (h / 2)
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Theme.panelHi)
                Rectangle().fill(Theme.border).frame(height: 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(height: max(1, fill))
                    .offset(y: frac >= 0 ? -(fill / 2) : (fill / 2))
                    .glow(accent, radius: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            .overlay(alignment: .top) {
                Text(title)
                    .pdFont(7, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.textFaint)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.top, 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "%+.0f%%", max(-1, min(1, value)) * 100))
    }
}

/// 飞行仪表盘组件：COLL / TRQ 弧表 + 姿态球 + ROL / PIT / YAW 杆位条。
///
/// 纯只读，无手势、无绑定——`DeckWidget.binding` 在这里被忽略。
struct FlightPanel: View {
    @ObservedObject var s: ControllerState

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            HStack(spacing: max(4, W * 0.012)) {
                VStack(spacing: max(3, H * 0.04)) {
                    ArcGauge(title: "COLL", value: s.collective, accent: Theme.cyan)
                    ArcGauge(title: "TRQ", value: 0.25 + s.collective * 0.72,
                             accent: Theme.green, danger: s.collective > 0.92)
                }
                .frame(width: max(28, W * 0.19))

                AttitudeBall(s: s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .hudPanel(corner: 8, accent: Theme.cyan.opacity(0.4))

                VStack(spacing: max(3, H * 0.04)) {
                    BarGauge(title: "ROL", value: s.smRoll, accent: Theme.cyan)
                    BarGauge(title: "PIT", value: s.smPitch, accent: Theme.green)
                    BarGauge(title: "YAW", value: s.smYaw, accent: Theme.orange)
                }
                .frame(width: max(20, W * 0.12))
            }
            .padding(max(4, W * 0.014))
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.glass))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        }
    }
}
