import SwiftUI

// MARK: - 飞行模式硬件皮肤（v4 P4）
//
// 参照真实直升机座舱：左侧总距杆（Collective）、中间周期变距杆（Cyclic）、
// 底部尾桨踏板（Pedals）、中央仪表盘（PFD + 发动机/飞行仪表）。
// 与通用组件画布（WidgetCanvas）不同，这里是固定硬件布局，贴近真机手感。

/// 圆弧仪表：270° 表盘 + 中央读数。
struct ArcGauge: View {
    var title: String
    var value: Double            // 0..1
    var unit: String = ""
    var accent: Color = Theme.green
    var danger: Bool = false

    var body: some View {
        GeometryReader { geo in
            let lw = max(4, min(geo.size.width, geo.size.height) * 0.11)
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
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .minimumScaleFactor(0.5)
                    Text(unit.isEmpty ? title : "\(title)")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textFaint)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .padding(lw)
        }
        .aspectRatio(1, contentMode: .fit)
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
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textFaint)
                    .padding(.top, 1)
            }
        }
    }
}

/// 总距杆（Collective）：竖直拉杆，带 IDLE/FLY/MAX 卡位标记。
struct CollectiveLever: View {
    @Binding var value: Double   // 0..1（原始油门，未反转）
    var onTouch: ((Bool) -> Void)? = nil

    @State private var dragging = false

    private let detents: [(String, Double)] = [("MAX", 1.0), ("FLY", 0.5), ("IDLE", 0.0)]

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let gripH = max(26, h * 0.11)
            let travel = max(1, h - gripH - 16)
            let gripY = 8 + (1 - value) * travel
            ZStack(alignment: .top) {
                Capsule().fill(Theme.border.opacity(0.30))
                    .frame(width: 10, height: h - 16)
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    .padding(.top, 8)
                // 卡位刻度
                ForEach(Array(detents.enumerated()), id: \.offset) { _, d in
                    HStack(spacing: 2) {
                        Text(d.0)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.textFaint)
                        Rectangle().fill(Theme.border).frame(width: w * 0.16, height: 1)
                    }
                    .position(x: w * 0.5, y: 8 + (1 - d.1) * travel)
                }
                // 把手
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.white.opacity(0.92), Color(white: 0.58)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: gripH)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.cyan, lineWidth: 2))
                    .overlay(Text("\(Int(value * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black))
                    .glow(Theme.cyan, radius: 4)
                    .offset(y: gripY)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { dragging = true; onTouch?(true); Haptics.tap() }
                        let rel = (g.location.y - 8 - gripH / 2) / travel
                        let nv = max(0, min(1, 1 - rel))
                        // 越过 IDLE/FLY/MAX 卡位 → 一次轻震（手感定位）
                        if value != nv, detents.contains(where: { d in
                            (value - d.1) * (nv - d.1) < 0 || (nv == d.1 && value != d.1)
                        }) {
                            Haptics.tap()
                        }
                        value = nv
                    }
                    .onEnded { _ in dragging = false; onTouch?(false) }
            )
        }
    }
}

/// 尾桨踏板（Rudder Pedals）：左右两块，整体一个偏航轴，松手回中。
struct RudderPedals: View {
    @Binding var yaw: Double
    var onTouch: ((Bool) -> Void)? = nil

    @State private var dragging = false
    @State private var timer: Timer? = nil
    @State private var lastTick = 0.0
    @State private var startYaw = 0.0
    @State private var startX = 0.0

    private func startReturn() {
        stopReturn()
        lastTick = Date().timeIntervalSince1970
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            let dt = now - lastTick
            lastTick = now
            let k = min(1.0, 6.0 * dt)
            yaw += (0 - yaw) * k
            if abs(yaw) < 0.004 { yaw = 0; stopReturn() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func stopReturn() {
        timer?.invalidate()
        timer = nil
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pedalW = w * 0.34
            let travel = w * 0.30
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Theme.panelHi, Theme.panel],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                Rectangle().fill(Theme.cyan.opacity(0.5)).frame(width: 2, height: h * 0.5)
                pedal(label: "L", active: yaw < -0.05)
                    .frame(width: pedalW, height: h * 0.62)
                    .offset(x: -w * 0.18 - yaw * travel)
                pedal(label: "R", active: yaw > 0.05)
                    .frame(width: pedalW, height: h * 0.62)
                    .offset(x: w * 0.18 - yaw * travel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        if !dragging {
                            dragging = true; stopReturn(); onTouch?(true)
                            startYaw = yaw; startX = g.startLocation.x
                            Haptics.tap()
                        }
                        let nx = startYaw + (g.location.x - startX) / travel
                        let nv = max(-1, min(1, nx))
                        // 过中位 → selection 轻震
                        if (yaw < 0 && nv >= 0) || (yaw > 0 && nv <= 0) { Haptics.select() }
                        yaw = nv
                    }
                    .onEnded { _ in
                        dragging = false; onTouch?(false); startReturn()
                    }
            )
        }
        .onDisappear { stopReturn() }
    }

    private func pedal(label: String, active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(RadialGradient(colors: [Theme.panelHi, Theme.panel],
                                 center: .center, startRadius: 2, endRadius: 80))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(active ? Theme.cyan : Theme.border, lineWidth: active ? 2 : 1))
            .overlay(
                VStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(Theme.border.opacity(0.5))
                            .frame(height: 3).padding(.horizontal, 10)
                    }
                }
            )
            .overlay(Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(active ? Theme.cyan : Theme.textFaint),
                alignment: .topLeading)
            .glow(active ? Theme.cyan : .clear, radius: 4)
    }
}

/// 周期变距杆（Cyclic）：真机握把造型，拖动控制横滚/俯仰，松手回中。
struct CyclicControl: View {
    @Binding var x: Double
    @Binding var y: Double
    var onTouch: ((Bool) -> Void)? = nil

    @State private var dragging = false
    @State private var timer: Timer? = nil
    @State private var lastTick = 0.0
    @State private var grabX = 0.0
    @State private var grabY = 0.0
    @State private var startX = 0.0
    @State private var startY = 0.0

    private func startReturn() {
        stopReturn()
        lastTick = Date().timeIntervalSince1970
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            let dt = now - lastTick
            lastTick = now
            let k = min(1.0, 5.0 * dt)
            x += (0 - x) * k
            y += (0 - y) * k
            if abs(x) < 0.004 && abs(y) < 0.004 { x = 0; y = 0; stopReturn() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func stopReturn() {
        timer?.invalidate()
        timer = nil
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let baseD = min(w, h) * 0.72
            let travel = max(24, baseD * 0.30)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Theme.panel, Theme.bgBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Circle()
                    .fill(RadialGradient(colors: [Theme.panelHi, Theme.panel],
                                         center: .init(x: 0.5, y: 0.4), startRadius: 1, endRadius: baseD / 2))
                    .frame(width: baseD, height: baseD)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                // 行程十字
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: h / 2 - travel - 6))
                    p.addLine(to: CGPoint(x: w / 2, y: h / 2 + travel + 6))
                    p.move(to: CGPoint(x: w / 2 - travel - 6, y: h / 2))
                    p.addLine(to: CGPoint(x: w / 2 + travel + 6, y: h / 2))
                }.stroke(Theme.border.opacity(0.6), lineWidth: 1)
                // 杆身 + 握把
                VStack(spacing: -8) {
                    grip(d: baseD)
                    Capsule()
                        .fill(LinearGradient(colors: [Color(white: 0.75), Theme.panel],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, baseD * 0.14), height: baseD * 0.46)
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    Circle()
                        .fill(Theme.panelHi)
                        .frame(width: baseD * 0.24, height: baseD * 0.24)
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .offset(x: x * travel, y: -y * travel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        if !dragging {
                            dragging = true; stopReturn(); onTouch?(true)
                            grabX = x; grabY = y
                            startX = g.startLocation.x
                            startY = g.startLocation.y
                            Haptics.tap()
                        }
                        var nx = grabX + (g.location.x - startX) / travel
                        var ny = grabY - (g.location.y - startY) / travel
                        if nx > 0.95 { nx = 1 } else if nx < -0.95 { nx = -1 } else if abs(nx) < 0.05 { nx = 0 }
                        if ny > 0.95 { ny = 1 } else if ny < -0.95 { ny = -1 } else if abs(ny) < 0.05 { ny = 0 }
                        x = max(-1, min(1, nx))
                        y = max(-1, min(1, ny))
                    }
                    .onEnded { _ in
                        dragging = false; onTouch?(false); startReturn()
                    }
            )
        }
        .onDisappear { stopReturn() }
    }

    private func grip(d: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: d * 0.10)
            .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.14)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: d * 0.30, height: d * 0.44)
            .overlay(RoundedRectangle(cornerRadius: d * 0.10).stroke(Theme.border, lineWidth: 1))
            .overlay(
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.white.opacity(0.12))
                            .frame(width: d * 0.18, height: 3)
                    }
                }
            )
            .glow(Theme.cyan.opacity(0.5), radius: 3)
    }
}

/// 座舱硬件按键（读 vJoy 绑定，按下高亮）。
struct DeckButton: View {
    var title: String
    var sub: String? = nil
    var active: Bool = false
    var accent: Color = Theme.cyan
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                if let sub {
                    Text(sub).font(.system(size: 7, design: .monospaced))
                        .foregroundColor(Theme.textFaint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(active ? accent.opacity(0.32) : Theme.panelHi))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(active ? accent : Theme.border, lineWidth: 1))
            .foregroundColor(active ? accent : Theme.textDim)
        }
        .buttonStyle(.plain)
        .glow(active ? accent : .clear, radius: 3)
    }
}

/// 飞行模式整屏硬件皮肤。
struct FlightDeckView: View {
    @ObservedObject var s: ControllerState
    var ctrl: CockpitController

    private var touch: (Bool) -> Void { { ctrl.setTouchActive($0) } }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            HStack(spacing: 8) {
                CollectiveLever(value: $s.throttle, onTouch: touch)
                    .frame(width: max(56, W * 0.11))
                VStack(spacing: 8) {
                    instrumentPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    RudderPedals(yaw: $s.yaw, onTouch: touch)
                        .frame(height: H * 0.38)
                }
                VStack(spacing: 8) {
                    CyclicControl(x: $s.roll, y: $s.pitch, onTouch: touch)
                        .frame(height: H * 0.56)
                    buttonCluster
                        .frame(height: H * 0.44)
                }
                .frame(width: max(150, W * 0.30))
            }
        }
    }

    private var instrumentPanel: some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                ArcGauge(title: "COLL", value: s.collective, accent: Theme.cyan)
                ArcGauge(title: "TRQ", value: 0.25 + s.collective * 0.72,
                         accent: Theme.green, danger: s.collective > 0.92)
            }
            .frame(width: 62)
            AttitudeBall(s: s)
                .hudPanel(corner: 8, accent: Theme.cyan.opacity(0.4))
            VStack(spacing: 6) {
                BarGauge(title: "ROLL", value: s.smRoll, accent: Theme.cyan)
                BarGauge(title: "PITCH", value: s.smPitch, accent: Theme.green)
                BarGauge(title: "YAW", value: s.smYaw, accent: Theme.orange)
            }
            .frame(width: 46)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }

    private var buttonCluster: some View {
        let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: cols, spacing: 6) {
            DeckButton(title: "开火", active: isActive(.fire), accent: Theme.red) { toggle(.fire) }
            DeckButton(title: "投弹", active: isActive(.vjoy1), accent: Theme.orange) { toggle(.vjoy1) }
            DeckButton(title: "起落架", active: isActive(.gearUp), accent: Theme.cyan) { toggle(.gearUp) }
            DeckButton(title: "灯光", active: isActive(.vjoy7), accent: Theme.amber) { toggle(.vjoy7) }
            DeckButton(title: "悬停", active: isActive(.vjoy3), accent: Theme.green) { toggle(.vjoy3) }
            DeckButton(title: "视角", active: isActive(.vjoy4), accent: Theme.cyan) { toggle(.vjoy4) }
        }
    }

    // MARK: 按键绑定（复用 WidgetView 的语义）
    private func isActive(_ b: WidgetBinding) -> Bool {
        if let idx = b.vjoyIndex { return (s.btnMask & (1 << idx)) != 0 }
        if b == .fire { return s.rt > 0.5 }
        if b == .gearUp { return (s.btnMask & (1 << 5)) != 0 }
        if b == .gearDown { return (s.btnMask & (1 << 4)) != 0 }
        return false
    }

    private func toggle(_ b: WidgetBinding) {
        if let idx = b.vjoyIndex {
            let bit = UInt16(1 << idx)
            let down = (s.btnMask & bit) == 0
            if down { s.btnMask |= bit } else { s.btnMask &= ~bit }
            s.onButton?(idx + 1, down)
        } else if b == .gearUp {
            pulse(5)
        } else if b == .gearDown {
            pulse(4)
        } else if b == .fire {
            let down = s.rt <= 0.5
            s.rt = down ? 1 : 0
            if down { Haptics.rigidTap() }
        }
    }

    private func pulse(_ idx: Int) {
        let bit = UInt16(1 << idx)
        s.btnMask |= bit
        s.onButton?(idx + 1, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            s.btnMask &= ~bit
            s.onButton?(idx + 1, false)
        }
    }
}
