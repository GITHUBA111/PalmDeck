import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 双色主题色

extension Color {
    /// 浅/深两套色值，运行时按 `colorScheme` 自动解析。
    ///
    /// 之所以走 `UIColor` 的动态 provider 而不是在每个视图里读 `@Environment(\.colorScheme)`：
    /// `Theme` 在 ~120 处被引用，让「主题」变成一个纯查表动作，视图层一行都不用改。
    /// 切换靠根视图上的 `.preferredColorScheme(...)`（见 `AppAppearance`）。
    static func pd(_ light: Color, _ dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        return dark
        #endif
    }
}

/// 座舱统一主题：一套浅色 + 一套深色，单一青色主强调 + 语义色（绿=连接/橙=编辑/红=危险）。
/// 设计取向：克制、细边框、微光晕——「科技感」而非霓虹堆砌。
///
/// **仪表例外**：姿态球是「真仪表」，无论主题都保持深底亮线（`instr*` / `hud*` 那几个固定值），
/// 白底上放一块黑表盘反而更像真机，也更清楚。
enum Theme {
    // ---- 背景层次（由浅到深）----
    static let bgTop    = Color.pd(Color(red: 0.945, green: 0.965, blue: 0.984),
                                   Color(red: 0.07,  green: 0.10,  blue: 0.15))
    static let bgBottom = Color.pd(Color(red: 0.878, green: 0.910, blue: 0.945),
                                   Color(red: 0.02,  green: 0.03,  blue: 0.06))
    static let panel    = Color.pd(Color(red: 1.000, green: 1.000, blue: 1.000),
                                   Color(red: 0.11,  green: 0.15,  blue: 0.21))   // 卡片/面板底
    static let panelHi  = Color.pd(Color(red: 0.949, green: 0.965, blue: 0.980),
                                   Color(red: 0.16,  green: 0.21,  blue: 0.29))   // 浮起/按下
    static let border   = Color.pd(Color(red: 0.741, green: 0.788, blue: 0.843),
                                   Color(red: 0.22,  green: 0.29,  blue: 0.40))   // 细边框

    // ---- 文本 ----
    static let text      = Color.pd(Color(red: 0.055, green: 0.090, blue: 0.140), .white)
    static let textDim   = Color.pd(Color(red: 0.278, green: 0.333, blue: 0.404),
                                    Color(red: 0.62,  green: 0.70,  blue: 0.80))
    static let textFaint = Color.pd(Color(red: 0.451, green: 0.506, blue: 0.573),
                                    Color(red: 0.42,  green: 0.49,  blue: 0.58))
    /// 彩色底上的字：两种模式都用白（强调色两套都够深，白字都立得住）。
    static let onAccent = Color.white

    // ---- 强调色（浅色模式压深一档，否则白底上对比度不够）----
    static let cyan   = Color.pd(Color(red: 0.000, green: 0.478, blue: 0.686),
                                 Color(red: 0.20,  green: 0.82,  blue: 1.00))
    static let green  = Color.pd(Color(red: 0.055, green: 0.545, blue: 0.290),
                                 Color(red: 0.30,  green: 0.86,  blue: 0.50))
    static let orange = Color.pd(Color(red: 0.804, green: 0.435, blue: 0.000),
                                 Color(red: 1.00,  green: 0.62,  blue: 0.20))
    static let red    = Color.pd(Color(red: 0.804, green: 0.161, blue: 0.157),
                                 Color(red: 1.00,  green: 0.36,  blue: 0.36))
    static let amber  = Color.pd(Color(red: 0.667, green: 0.478, blue: 0.000),
                                 Color(red: 1.00,  green: 0.85,  blue: 0.25))

    // ---- 玻璃（半透明面板：深色加白、浅色加黑）----
    static let glass       = Color.pd(Color.black.opacity(0.045), Color.white.opacity(0.05))
    static let glassBorder = Color.pd(Color.black.opacity(0.090), Color.white.opacity(0.10))

    // ---- 座舱背景装饰 ----
    static let gridStroke = Color.pd(Color(red: 0.30, green: 0.42, blue: 0.60).opacity(0.07),
                                     Color(red: 0.20, green: 0.82, blue: 1.00).opacity(0.045))
    static let glowTop    = Color.pd(Theme.cyan.opacity(0.10), Theme.cyan.opacity(0.13))
    static let glowBottom = Color.pd(Color(red: 0.30, green: 0.40, blue: 0.85).opacity(0.07),
                                     Color(red: 0.30, green: 0.40, blue: 0.85).opacity(0.10))

    // ---- 仪表专用（固定值：不随主题变）----
    static let instrBg       = Color(red: 0.04, green: 0.07, blue: 0.12)
    static let instrSkyHi    = Color(red: 0.25, green: 0.48, blue: 0.69)
    static let instrSkyLo    = Color(red: 0.06, green: 0.14, blue: 0.22)
    static let instrGroundHi = Color(red: 0.42, green: 0.28, blue: 0.14)
    static let instrGroundLo = Color(red: 0.14, green: 0.09, blue: 0.05)
    static let instrLine     = Color.white
    static let hudAmber      = Color(red: 1.00, green: 0.85, blue: 0.25)
    static let hudOrange     = Color(red: 1.00, green: 0.62, blue: 0.20)
}

// MARK: - 外观（跟随系统 / 浅色 / 深色）

/// 全局外观。存 `UserDefaults`（`@AppStorage`），根视图靠 `preferredColorScheme` 落下去，
/// 上面那些 `Color.pd(_:_:)` 会自动跟着解析——不需要任何全局可变状态。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "palmdeck_appearance"
    /// 默认浅色：这是产品当前的主形态（深色作为可选项保留）。
    static let fallback: AppAppearance = .light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// nil = 跟随系统（不覆盖）。
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func parse(_ raw: String?) -> AppAppearance {
        guard let raw, let v = AppAppearance(rawValue: raw) else { return fallback }
        return v
    }
}

/// 把当前外观落到这个子树上（根 WindowGroup + 每个 sheet/cover 各来一份，
/// 免得某个 presentation 不继承窗口的 override）。
private struct AppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.key) private var raw = AppAppearance.fallback.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(AppAppearance.parse(raw).scheme)
    }
}

extension View {
    func palmAppearance() -> some View { modifier(AppearanceModifier()) }
}

/// 座舱背景：渐变 + 顶部/底部微光晕 + 细网格（HUD 感）。浅色/深色各一套。
struct CockpitBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)

            // 顶部青色氛围光 + 底部蓝紫微光（高级感的来源：不喧宾夺主）
            RadialGradient(colors: [Theme.glowTop, .clear],
                           center: .topLeading, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Theme.glowBottom, .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 640)

            // 细网格（很淡，HUD 纹理）
            Canvas { ctx, size in
                let step: CGFloat = 30
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step
                }
                ctx.stroke(p, with: .color(Theme.gridStroke), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 柔光（科技感微光晕）：主光 + 大范围淡光。
    func glow(_ color: Color, radius: CGFloat = 6) -> some View {
        self.shadow(color: color.opacity(0.55), radius: radius)
            .shadow(color: color.opacity(0.25), radius: radius * 2.2)
    }

    /// 仪表面板：面板底 + 细边 + 四角括号（专业模拟器感）。
    func hudPanel(corner: CGFloat = 10, accent: Color = Theme.cyan) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(LinearGradient(colors: [Theme.panelHi.opacity(0.7), Theme.panel.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Theme.border.opacity(0.8), lineWidth: 1))
            )
            .overlay(CornerBrackets(color: accent.opacity(0.45), length: 12).padding(4))
    }
}

/// 四角括号（HUD 取景框感）。
struct CornerBrackets: View {
    var color: Color = Theme.cyan
    var length: CGFloat = 14
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // 左上
                p.move(to: CGPoint(x: 0, y: length)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: length, y: 0))
                // 右上
                p.move(to: CGPoint(x: w - length, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: length))
                // 右下
                p.move(to: CGPoint(x: w, y: h - length)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - length, y: h))
                // 左下
                p.move(to: CGPoint(x: length, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - length))
            }
            .stroke(color.opacity(0.6), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

/// 仪表数据单元（标签 + 值，等宽字）。
struct HudCell: View {
    let label: String
    let value: String
    var accent: Color = Theme.cyan

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textFaint)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(accent)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 滑条刻度（模拟器刻度线）。count 条均布；highlightIndex 高亮（如中心卡位）。
struct TickMarks: View {
    var count: Int = 9
    var highlightIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ForEach(0..<count, id: \.self) { i in
                let on = highlightIndex == i
                Rectangle()
                    .fill(on ? Theme.textDim.opacity(0.9) : Theme.border.opacity(0.5))
                    .frame(width: 1, height: on ? 12 : 7)
                    .position(x: count == 1 ? w/2 : w * CGFloat(i) / CGFloat(count - 1),
                              y: h/2)
            }
        }
        .allowsHitTesting(false)
    }
}
