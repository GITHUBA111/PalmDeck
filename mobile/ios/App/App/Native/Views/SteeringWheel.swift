import SwiftUI

/// 触摸方向盘：手指沿圆周拖动 → 转动角度（支持多圈）→ 映射到 [-1,1]。
/// maxDeg = 满舵角度（单边），默认 540°（1.5 圈）。
struct SteeringWheel: View {
    @Binding var value: Double          // [-1,1]（roll）
    var maxDeg: Double = 540
    var returnToCenter: Bool = true
    var returnSpeed: Double = 720       // 回正速度（度/秒，可调）
    var onTouch: ((Bool) -> Void)? = nil

    @State private var angleDeg: Double = 0      // 当前方向盘角度（度，可累计多圈）
    @State private var dragging = false
    @State private var lastFingerAngle: Double = 0
    @State private var returnTimer: Timer? = nil
    @State private var lastTick: Double = 0

    /// 用 60Hz 定时器逐步回正（速度可控，value 与视觉同步）
    private func startReturn() {
        stopReturn()
        lastTick = Date().timeIntervalSince1970
        returnTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            let dt = now - lastTick
            lastTick = now
            let step = returnSpeed * dt
            if abs(angleDeg) <= step {
                angleDeg = 0
                value = 0
                stopReturn()
            } else {
                angleDeg -= (angleDeg > 0 ? step : -step)
                value = max(-1, min(1, angleDeg / maxDeg))
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
            let r = d / 2
            let c = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
            ZStack {
                // 轮盘
                Circle()
                    .fill(RadialGradient(colors: [Theme.panelHi, Theme.panel],
                                         center: .init(x: 0.5, y: 0.45), startRadius: 0, endRadius: r))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 3))
                // 轮辐 + 握把（不穿中心）
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(Theme.textDim)
                        .frame(width: r*0.52, height: r*0.11)
                        .offset(x: r*0.6)
                        .rotationEffect(.degrees(Double(i) * 120))
                }
                // 顶部标记（看转动）
                Circle().fill(Theme.orange)
                    .frame(width: r*0.16, height: r*0.16)
                    .offset(y: -r*0.8)
                    .glow(Theme.orange, radius: 4)
                // 中心毂
                Circle().fill(Theme.panel)
                    .frame(width: r*0.46, height: r*0.46)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1.5))
            }
            .rotationEffect(.degrees(angleDeg))
            // 角度数字固定在中心（不随轮转）
            .overlay(
                Text(String(format: "%.0f°", angleDeg))
                    .font(.system(size: r*0.18, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
            )
            // 顶部回中参考（固定三角，不随轮转；橙色标记对齐即回正）
            .overlay(
                Path { p in
                    let cx = geo.size.width / 2
                    p.move(to: CGPoint(x: cx, y: 14))
                    p.addLine(to: CGPoint(x: cx - 5, y: 3))
                    p.addLine(to: CGPoint(x: cx + 5, y: 3))
                    p.closeSubpath()
                }
                .fill(Theme.cyan)
                .glow(Theme.cyan, radius: 3)
                .allowsHitTesting(false)
            )
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let dx = g.location.x - c.x
                        let dy = g.location.y - c.y
                        let dist = hypot(dx, dy)
                        guard dist > r * 0.15 else { return } // 太靠中心不算
                        let fingerAng = atan2(dy, dx) * 180 / .pi   // -180..180
                        if !dragging {
                            dragging = true
                            stopReturn()
                            lastFingerAngle = fingerAng
                            onTouch?(true)
                            Haptics.tap()   // 抓住反馈
                        } else {
                            // 角度增量（处理环绕）
                            var delta = fingerAng - lastFingerAngle
                            if delta > 180 { delta -= 360 }
                            if delta < -180 { delta += 360 }
                            let old = angleDeg
                            angleDeg += delta
                            lastFingerAngle = fingerAng
                            // 限制到满舵
                            angleDeg = max(-maxDeg, min(maxDeg, angleDeg))
                            // 过中位（0°）→ selection 轻震
                            if (old < 0 && angleDeg >= 0) || (old > 0 && angleDeg <= 0) { Haptics.select() }
                            value = max(-1, min(1, angleDeg / maxDeg))
                        }
                    }
                    .onEnded { _ in
                        dragging = false
                        onTouch?(false)
                        if returnToCenter { startReturn() }
                    }
            )
        }
        .onChange(of: value) { v in
            // 外部改值（如弹簧回中）时同步角度
            if !dragging { angleDeg = v * maxDeg }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("方向盘")
        .accessibilityValue(String(format: "%.0f°，满舵 %.0f°", angleDeg, maxDeg))
    }
}
