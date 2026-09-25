import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 主题色

/// 座舱统一主题：**只有浅色一套**，单一青色主强调 + 语义色（绿=连接/橙=编辑/红=危险）。
/// 设计取向：克制、细边框、微光晕——「科技感」而非霓虹堆砌。
///
/// **没有深色模式**（走查要求「不要再出现任何深色模式」）：
/// 色值就是常量，`Info.plist` 里 `UIUserInterfaceStyle = Light` 把系统深色也一并挡在门外 ——
/// alert / 键盘 / 分享面板 / Catalyst 菜单栏都不会再变黑。
/// 谁要加回深色，得同时改 Info.plist、重做这套色值、并接受下面这条例外。
///
/// **仪表例外**：姿态球是「真仪表」，即使浅色界面也保持深底亮线（`instr*` / `hud*` 固定值），
/// 白底上放一块黑表盘反而更像真机，也更清楚。这是表盘语义，不是主题。
enum Theme {
    // ---- 背景层次（由浅到深）----
    static let bgTop    = Color(red: 0.945, green: 0.965, blue: 0.984)
    static let bgBottom = Color(red: 0.878, green: 0.910, blue: 0.945)
    static let panel    = Color(red: 1.000, green: 1.000, blue: 1.000)   // 卡片/面板底
    static let panelHi  = Color(red: 0.949, green: 0.965, blue: 0.980)   // 浮起/按下
    static let border   = Color(red: 0.741, green: 0.788, blue: 0.843)   // 细边框

    // ---- 文本 ----
    static let text      = Color(red: 0.055, green: 0.090, blue: 0.140)
    static let textDim   = Color(red: 0.278, green: 0.333, blue: 0.404)
    /// 最弱一档：只给 10pt 的组件标题、轴名用。刻意压暗到 #5F6D80——
    /// 白底 + 小字号下 #738192 只能算“勉强看得见”，扫一眼读不出来。
    static let textFaint = Color(red: 0.373, green: 0.427, blue: 0.502)
    /// 彩色底上的字：白字（强调色都够深，白字立得住）。
    static let onAccent = Color.white

    // ---- 强调色（白底上要压深一档，否则对比度不够）----
    static let cyan   = Color(red: 0.000, green: 0.478, blue: 0.686)
    static let green  = Color(red: 0.055, green: 0.545, blue: 0.290)
    static let orange = Color(red: 0.804, green: 0.435, blue: 0.000)
    static let red    = Color(red: 0.804, green: 0.161, blue: 0.157)
    static let amber  = Color(red: 0.667, green: 0.478, blue: 0.000)

    // ---- 玻璃（半透明面板：浅底上加黑）----
    static let glass       = Color.black.opacity(0.045)
    static let glassBorder = Color.black.opacity(0.090)

    // ---- 座舱背景装饰 ----
    static let gridStroke = Color(red: 0.30, green: 0.42, blue: 0.60).opacity(0.07)
    static let glowTop    = Theme.cyan.opacity(0.10)
    static let glowBottom = Color(red: 0.30, green: 0.40, blue: 0.85).opacity(0.07)

    // ---- 仪表专用（固定深值：与界面主题无关，见文件头「仪表例外」）----
    static let instrBg       = Color(red: 0.04, green: 0.07, blue: 0.12)
    static let instrSkyHi    = Color(red: 0.25, green: 0.48, blue: 0.69)
    static let instrSkyLo    = Color(red: 0.06, green: 0.14, blue: 0.22)
    static let instrGroundHi = Color(red: 0.42, green: 0.28, blue: 0.14)
    static let instrGroundLo = Color(red: 0.14, green: 0.09, blue: 0.05)
    static let instrLine     = Color.white
    static let hudAmber      = Color(red: 1.00, green: 0.85, blue: 0.25)
    static let hudOrange     = Color(red: 1.00, green: 0.62, blue: 0.20)
}

// MARK: - 外观：**固定浅色**
//
// 这里原来有一套「跟随系统 / 浅色 / 深色」的外观开关和一个贴到每个弹窗上的修饰器。
// 已整体删除：产品只保留浅色，深色连「选择的可能性」都不要。
// 真正拦住系统深色的是 `Info.plist` 的 `UIUserInterfaceStyle = Light` ——
// 它在 UIWindow 层生效，alert / 键盘 / 分享面板 / Catalyst 菜单栏都跑不掉，
// 比在每个 presentation 上各自覆盖可靠（以前就漏过：组件库弹窗漏了，外面浅、里面黑）。
//
// 旧键 `palmdeck_appearance` 不再读也不再写，留在 UserDefaults 里不影响任何行为。

// MARK: - 动态字号（Dynamic Type）
//
// 全 App 原来都是固定 `pt`（`.font(.system(size: N))`），系统字号调多大都不变。
// 这里给两件工具：Canvas 用 `Font.pd`，视图层一律用 `.pdFont`（真·响应式）。
// 默认字号下 `scaledValue == base`，**外观与改造前完全一致**。

extension Font {
    /// **非响应式**缩放字号：给 Canvas / `Text.font()` 这类拿不到 `@ScaledMetric` 的地方用。
    /// 视图请优先用 `.pdFont(...)`。
    static func pd(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        #if canImport(UIKit)
        let s = UIFontMetrics.default.scaledValue(for: size)
        return .system(size: s, weight: weight, design: design)
        #else
        return .system(size: size, weight: weight, design: design)
        #endif
    }
}

/// 把固定 `pt` 字号换成随系统字号缩放的版本。内部是 `@ScaledMetric`，字号一变整棵视图重排。
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// 固定 `pt` 字号 → 随系统字号缩放。`relativeTo` 选最接近的语义档，决定缩放曲线。
    func pdFont(_ size: CGFloat,
                relativeTo style: Font.TextStyle = .body,
                weight: Font.Weight = .regular,
                design: Font.Design = .default) -> some View {
        modifier(ScaledFontModifier(size: size, relativeTo: style, weight: weight, design: design))
    }

    /// 文字为主的界面（设置 / 首启 / 速览 / 弹窗，可滚动）放开到无障碍档。
    func palmDynamicType() -> some View {
        dynamicTypeSize(.xSmall ... .accessibility2)
    }

    /// 座舱 chrome（顶栏 / 状态条 / 编辑条）：固定横排 HUD，放开到无障碍档必挤裂，
    /// 收到 `.xxLarge`（系统默认往上约两档），`minimumScaleFactor` 兜底。
    func palmCockpitType() -> some View {
        dynamicTypeSize(.xSmall ... .xxLarge)
    }
}

/// 座舱背景：渐变 + 顶部/底部微光晕 + 细网格（HUD 感）。
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
                .pdFont(8, weight: .bold, design: .monospaced)
                .foregroundColor(Theme.textFaint)
            Text(value)
                .pdFont(11, weight: .semibold, design: .monospaced)
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
