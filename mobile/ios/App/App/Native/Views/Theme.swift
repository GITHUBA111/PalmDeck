import SwiftUI

/// 座舱统一主题：暗色 + 单一青色主强调 + 语义色（绿=连接/橙=编辑/红=危险）。
/// 设计取向：克制、深底、细边框、微光晕——「科技感」而非霓虹堆砌。
enum Theme {
    // ---- 背景层次（由浅到深）----
    static let bgTop    = Color(red: 0.07, green: 0.10, blue: 0.15)
    static let bgBottom = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let panel    = Color(red: 0.11, green: 0.15, blue: 0.21)   // 卡片/面板底
    static let panelHi  = Color(red: 0.16, green: 0.21, blue: 0.29)   // 浮起/按下
    static let border   = Color(red: 0.22, green: 0.29, blue: 0.40)   // 细边框

    // ---- 文本 ----
    static let text      = Color.white
    static let textDim   = Color(red: 0.62, green: 0.70, blue: 0.80)
    static let textFaint = Color(red: 0.42, green: 0.49, blue: 0.58)

    // ---- 强调色 ----
    static let cyan   = Color(red: 0.20, green: 0.82, blue: 1.00)
    static let green  = Color(red: 0.30, green: 0.86, blue: 0.50)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.20)
    static let red    = Color(red: 1.00, green: 0.36, blue: 0.36)
    static let amber  = Color(red: 1.00, green: 0.85, blue: 0.25)

    // ---- 玻璃（半透明面板）----
    static let glass       = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.10)
}

/// 座舱背景：深色渐变 + 顶部/底部微光晕 + 细网格（HUD 感）。
struct CockpitBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)

            // 顶部青色氛围光 + 底部蓝紫微光（高级感的来源：不喧宾夺主）
            RadialGradient(colors: [Theme.cyan.opacity(0.13), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Color(red: 0.30, green: 0.40, blue: 0.85).opacity(0.10), .clear],
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
                ctx.stroke(p, with: .color(Theme.cyan.opacity(0.045)), lineWidth: 0.5)
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

    /// 仪表面板：暗底 + 细边 + 四角括号（专业模拟器感）。
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
