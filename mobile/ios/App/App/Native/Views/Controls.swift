import SwiftUI

/// 2D 触摸摇杆。拖动改绑定的两轴，松手按 `returnToCenter` 回中。
///
/// 两种用法：
/// - **周期杆**（默认）：X=横滚、Y=俯仰，两轴都回中；
/// - **总距/尾桨杆**（`centerY: false`）：X=方向舵（回中）、Y=总距（**保持**）——
///   对位航模遥控器的左杆（尾桨松手回中、总距停在原地）。
struct StickControl: View {
    @Binding var x: Double
    @Binding var y: Double
    var returnToCenter: Bool = true
    /// Y 轴是否也跟着回中。左杆（总距）给 `false`：松手只把 X 拉回中点。
    var centerY: Bool = true
    /// 无障碍读数用词（自绘控件读不出「推到哪了」，VoiceOver 靠这两句）。
    var xLabel: String = "横滚"
    var yLabel: String = "俯仰"
    var accent: Color = Theme.cyan
    var onTouch: ((Bool) -> Void)? = nil

    @State private var dragging = false
    @State private var returnTimer: Timer? = nil
    @State private var lastTick: Double = 0
    // 抓取增量：按下时记录参考点（避免一点就跳到手指位置）
    @State private var grabX: Double = 0
    @State private var grabY: Double = 0
    @State private var startX: Double = 0   // 手指起点（屏幕坐标）
    @State private var startY: Double = 0

    /// 60Hz 平滑回中（而非瞬跳）
    private func startReturn(speed: Double = 4.5) {
        stopReturn()
        lastTick = Date().timeIntervalSince1970
        returnTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            let dt = now - lastTick
            lastTick = now
            let k = min(1.0, speed * dt)
            x += (0 - x) * k
            if centerY { y += (0 - y) * k }
            if abs(x) < 0.004 && (!centerY || abs(y) < 0.004) {
                x = 0
                if centerY { y = 0 }
                stopReturn()
            }
        }
        RunLoop.main.add(returnTimer!, forMode: .common)
    }

    private func stopReturn() {
        returnTimer?.invalidate()
        returnTimer = nil
    }

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let rad = d / 2
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.panelHi, Theme.panel],
                                         center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: rad))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                // 十字辅助
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width/2, y: geo.size.height*0.08))
                    p.addLine(to: CGPoint(x: geo.size.width/2, y: geo.size.height*0.92))
                    p.move(to: CGPoint(x: geo.size.width*0.08, y: geo.size.height/2))
                    p.addLine(to: CGPoint(x: geo.size.width*0.92, y: geo.size.height/2))
                }.stroke(Theme.border.opacity(0.7), lineWidth: 1)
                // 摇杆头
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: 0.72)],
                                         center: .init(x: 0.38, y: 0.34), startRadius: 1, endRadius: d*0.2))
                    .frame(width: d*0.34, height: d*0.34)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    .offset(x: x * rad * 0.62, y: -y * rad * 0.62)
                    .overlay(Circle().stroke(accent.opacity(0.7), lineWidth: 1.5).frame(width: d*0.34, height: d*0.34)
                        .offset(x: x * rad * 0.62, y: -y * rad * 0.62)
                        .glow(accent, radius: 3))
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            stopReturn()
                            onTouch?(true)
                            // 记住当前值与手指起点（抓取增量）
                            grabX = x; grabY = y
                            startX = g.startLocation.x
                            startY = g.startLocation.y
                            // 轻震：告诉你“抓住了”
                            Haptics.tap()
                        }
                        // 只按“位移增量”调整，不跳值
                        let travel = rad * 0.62
                        var nx = grabX + (g.location.x - startX) / travel
                        var ny = grabY - (g.location.y - startY) / travel
                        // 边界吸附（到底就是满值）
                        if nx > 0.92 { nx = 1 } else if nx < -0.92 { nx = -1 }
                        else if abs(nx) < 0.05 { nx = 0 }
                        if ny > 0.92 { ny = 1 } else if ny < -0.92 { ny = -1 }
                        else if abs(ny) < 0.05 { ny = 0 }
                        let px = x, py = y
                        x = max(-1, min(1, nx))
                        y = max(-1, min(1, ny))
                        // 中位咔哒：刚回到中点时给一次轻反馈，闭着眼也知道回没回中
                        if abs(x) < 0.05 && abs(px) >= 0.05 { Haptics.select() }
                        if centerY && abs(y) < 0.05 && abs(py) >= 0.05 { Haptics.select() }
                    }
                    .onEnded { _ in
                        dragging = false
                        onTouch?(false)
                        if returnToCenter { startReturn() } else {
                            grabX = 0; grabY = 0
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        // VoiceOver：自绘摇杆本身没有文字，读不出「现在推到哪了」。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("摇杆")
        .accessibilityValue("\(xLabel) \(String(format: "%+.0f%%", x * 100))，\(yLabel) \(String(format: "%+.0f%%", y * 100))")
        .onDisappear { stopReturn() }
    }
}

/// 双极水平滑条（舵 / 横滚轴 / 俯仰轴）
struct BipolarSlider: View {
    @Binding var value: Double   // [-1,1]
    var label: String = ""
    var centerLabel: String = "回中"
    var accent: Color = Theme.orange
    var onTouch: ((Bool) -> Void)? = nil

    // 确定感：按下时先“抓住”当前值，随后只按手指位移增量调整（不跳值）
    @State private var grabValue: Double = 0
    @State private var grabX: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = (value + 1) / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panelHi).frame(height: 4)
                    .overlay(Capsule().strokeBorder(Theme.border.opacity(0.5), lineWidth: 0.5))
                // 从中心填充
                Capsule().fill(accent)
                    .frame(width: abs(t - 0.5) * w, height: 4)
                    .offset(x: t >= 0.5 ? w/2 : t*w)
                    .glow(accent, radius: 4)
                TickMarks(count: 9, highlightIndex: 4)
                    .frame(width: w, height: 36)
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: 0.75)],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 1, endRadius: 16))
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: t*w - 15)
            }
            .frame(height: 36)
            .contentShape(Rectangle())
            // 必须拖拽（点击不生效）：minimumDistance 使按下不动不触发
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { g in
                        if grabX == 0 && grabValue == 0 && g.translation.width == 0 && g.translation.height == 0 { return }
                        onTouch?(true)
                        // 首帧：记录参考点（当前值 + 手指起点）
                        if grabX == 0 {
                            grabX = g.startLocation.x
                            grabValue = value
                        }
                        // 只按“位移增量”调整
                        let delta = (g.location.x - grabX) / w * 2
                        var v = grabValue + delta
                        // 边界吸附
                        if v > 0.94 { v = 1 }
                        else if v < -0.94 { v = -1 }
                        else if abs(v) < 0.06 { v = 0 }   // 中心吸附
                        value = max(-1, min(1, v))
                    }
                    .onEnded { _ in
                        onTouch?(false)
                        grabX = 0; grabValue = 0
                        // 自回中轴（横滚 / 俯仰 / 方向舵）：松手**立即**回正。
                        // 会「保持」的轴（油门 / 刹车 / 离合 / RT）在 `WidgetView` 里走 `UniSlider`，
                        // 所以这里不用开关。走查反馈「脚舵松手立即回正」。
                        // 方案：`docs/PalmDeck-v4-instant-recenter.md`。
                        value = 0
                    }
            )
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "滑条" : label)
        .accessibilityValue(String(format: "%+.0f%%", value * 100))
    }
}

/// 单极水平滑条（油门 [0,1]）
struct UniSlider: View {
    @Binding var value: Double
    var label: String = "油门"
    var accent: Color = Theme.cyan
    /// 触觉止动位置（归一化 0~1）：滑过时给一次强反馈，松手 ±2.5% 内吸附。
    /// 直升机总距用它做「总距怠速 / 悬停 / 最大」三个不靠眼睛的参照
    /// （借航模遥控器的止动档位，v3 网页座舱的老参数）。
    var detents: [Double] = []
    /// 棘轮：每滑过 10% 给一次轻反馈 —— 闭着眼也知道总距推到哪了。
    var ratchet: Bool = false
    var onTouch: ((Bool) -> Void)? = nil

    // 确定感：抓取增量（按下不跳值）
    @State private var grabValue: Double = 0
    @State private var grabX: Double = -1
    /// 上一帧所在的 10% 格，棘轮只在跨格时响，不按帧刷屏。
    @State private var lastDecile: Int = -1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panelHi).frame(height: 4)
                    .overlay(Capsule().strokeBorder(Theme.border.opacity(0.5), lineWidth: 0.5))
                Capsule().fill(accent).frame(width: value * w, height: 4).glow(accent, radius: 4)
                TickMarks(count: 5)
                    .frame(width: w, height: 36)
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: 0.75)],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 1, endRadius: 16))
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: value*w - 15)
            }
            .frame(height: 36)
            .contentShape(Rectangle())
            // 必须拖拽（点击不生效，避免误触油门）
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { g in
                        onTouch?(true)
                        if grabX < 0 {
                            grabX = g.startLocation.x
                            grabValue = value
                            lastDecile = Int(value * 10)
                        }
                        let delta = (g.location.x - grabX) / w
                        var v = grabValue + delta
                        // 边界吸附：接近满/空时吸附，保证“到底就是满值”
                        if v > 0.96 { v = 1 }
                        else if v < 0.04 { v = 0 }
                        v = max(0, min(1, v))
                        if v != value {
                            // 棘轮：每 10% 一格轻反馈
                            if ratchet {
                                let d = Int(v * 10)
                                if d != lastDecile { lastDecile = d; Haptics.select() }
                            }
                            // 止动：滑过刻度线时强反馈（不看屏也能定位）
                            for t in detents where (value - t) * (v - t) < 0 { Haptics.rigidTap() }
                        }
                        value = v
                    }
                    .onEnded { _ in
                        onTouch?(false)
                        grabX = -1; grabValue = 0
                        lastDecile = -1
                        // 松手吸附到最近止动（±2.5%，v3 网页座舱的老参数）
                        if let d = detents.min(by: { abs($0 - value) < abs($1 - value) }),
                           abs(d - value) <= 0.025 {
                            value = d
                            Haptics.tap()
                        }
                    }
            )
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.0f%%", value * 100))
    }
}

/// 4 向苦力帽（free look）。拖动/点击方向键 → hat(0上/1右/2下/3左, 255无) + lookX/lookY。
struct HatPad: View {
    @Binding var hat: UInt8
    @Binding var lookX: Double
    @Binding var lookY: Double
    var accent: Color = Theme.green

    private func set(_ dir: Int?) {
        let changed = (hat == 255 && dir != nil) || (dir == nil && hat != 255) || (dir != nil && hat != UInt8(dir!))
        if let d = dir {
            hat = UInt8(d)
            lookX = d == 3 ? -1 : d == 1 ? 1 : 0
            lookY = d == 0 ? 1 : d == 2 ? -1 : 0
        } else {
            hat = 255
            lookX = 0; lookY = 0
        }
        if changed { Haptics.tap() }   // 确定感：每次变向给个反馈
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Circle().fill(RadialGradient(colors: [Theme.panelHi, Theme.panel],
                                             center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: w/2))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1.5))
                // 四向命中
                ForEach(0..<4, id: \.self) { d in
                    let on = hat == UInt8(d)
                    Image(systemName: ["arrowtriangle.up.fill", "arrowtriangle.right.fill",
                                       "arrowtriangle.down.fill", "arrowtriangle.left.fill"][d])
                        .font(.system(size: w * 0.16))
                        .foregroundColor(on ? accent : Theme.textDim)
                        .glow(on ? accent : .clear, radius: 3)
                        .position(x: d == 3 ? w*0.16 : d == 1 ? w*0.84 : w*0.5,
                                  y: d == 0 ? w*0.16 : d == 2 ? w*0.84 : w*0.5)
                }
                // 中心头：随方向偏移（视觉反馈）
                Circle().fill(Color(white: 0.85)).frame(width: w*0.2, height: w*0.2)
                    .offset(x: hat == 1 ? w*0.22 : hat == 3 ? -w*0.22 : 0,
                            y: hat == 2 ? w*0.22 : hat == 0 ? -w*0.22 : 0)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let cx = w/2, cy = w/2
                        let dx = g.location.x - cx, dy = g.location.y - cy
                        if hypot(dx, dy) < w*0.14 { set(nil); return }
                        // 判断主方向
                        if abs(dy) >= abs(dx) { set(dy < 0 ? 0 : 2) }
                        else { set(dx > 0 ? 1 : 3) }
                    }
                    .onEnded { _ in set(nil) }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("苦力帽")
        .accessibilityValue(hat == 255 ? "中立" : ["上", "右", "下", "左"][Int(min(hat, 3))])
    }
}

/// 视角触摸板：手指滑动 → 视角偏移（累计），松手**立即**回正。
/// 映射到 lookX/lookY（Rx/Ry）。适合 ETS2 看四周。
struct LookPad: View {
    @Binding var lookX: Double
    @Binding var lookY: Double
    var accent: Color = Theme.cyan

    @State private var dragging = false
    @State private var anchor: CGPoint = .zero   // 按下点
    @State private var baseX: Double = 0
    @State private var baseY: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(RadialGradient(colors: [Theme.panelHi, Theme.panel],
                                         center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: max(w,h)*0.7))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1.5))
                // 十字 + 当前朝向指示点
                Path { p in
                    p.move(to: CGPoint(x: w/2, y: h*0.1)); p.addLine(to: CGPoint(x: w/2, y: h*0.9))
                    p.move(to: CGPoint(x: w*0.1, y: h/2)); p.addLine(to: CGPoint(x: w*0.9, y: h/2))
                }.stroke(Theme.border.opacity(0.6), lineWidth: 1)
                Circle().fill(accent)
                    .frame(width: 16, height: 16)
                    .offset(x: lookX * w * 0.42, y: -lookY * h * 0.42)
                    .shadow(color: accent.opacity(0.6), radius: 6)
                Text("视角").pdFont(11).foregroundColor(Theme.textFaint)
                    .position(x: w/2, y: h - 12)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            dragging = true
                            anchor = g.startLocation
                            baseX = lookX; baseY = lookY
                        }
                        // 相对按下点的滑动 → 视角偏移
                        let dx = (g.location.x - anchor.x) / (w * 0.42)
                        let dy = (g.location.y - anchor.y) / (h * 0.42)
                        lookX = max(-1, min(1, baseX + dx))
                        lookY = max(-1, min(1, baseY - dy))
                    }
                    .onEnded { _ in
                        dragging = false
                        // 松手**立即**回正（原来是 60Hz 指数缓动，尾巴约 1.5s，太黏）。
                        lookX = 0; lookY = 0
                    }
            )
        }
        .aspectRatio(1.3, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("视角触摸板")
        .accessibilityValue(String(format: "左右 %+.0f%%，上下 %+.0f%%", lookX * 100, lookY * 100))
    }
}
