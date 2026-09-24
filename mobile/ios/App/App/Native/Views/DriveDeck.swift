import SwiftUI

// MARK: - 驾驶模式硬件皮肤（v4 P5）
//
// 参照真实驾驶舱：中控仪表盘（转速表 + 车速 + 档位）、方向盘、三踏板
// （离合 / 刹车 / 油门）、序列式档杆 + 拨片、视角触摸板、中控按键簇。

/// 线性液位条（0..1，自底向上填充）。
struct LevelBar: View {
    var title: String
    var value: Double
    var accent: Color = Theme.green

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let frac = max(0, min(1, value))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.panelHi)
                RoundedRectangle(cornerRadius: 4)
                    .fill(accent)
                    .frame(height: max(1, frac * h))
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

/// 转速表：270° 刻度 + 红线 + 指针；中央显示档位与估算车速。
struct Tachometer: View {
    var rpm: Double            // 0..1
    var gear: String
    var speed: Int

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let frac = max(0, min(1, rpm))
            ZStack {
                Canvas { ctx, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let R = min(size.width, size.height) / 2
                    // 刻度 0..8（×1000）
                    for i in 0...8 {
                        let a = (135.0 + Double(i) / 8.0 * 270.0) * .pi / 180
                        let out = R * 0.93
                        let inn = (i >= 7) ? R * 0.74 : R * 0.81
                        var p = Path()
                        p.move(to: CGPoint(x: cx + cos(a) * inn, y: cy + sin(a) * inn))
                        p.addLine(to: CGPoint(x: cx + cos(a) * out, y: cy + sin(a) * out))
                        ctx.stroke(p, with: .color(i >= 7 ? Theme.red : Theme.textDim),
                                   lineWidth: i >= 7 ? 3 : 1.5)
                    }
                    // 红线弧
                    var red = Path()
                    red.addArc(center: CGPoint(x: cx, y: cy), radius: R * 0.72,
                               startAngle: .degrees(135 + 0.78 * 270), endAngle: .degrees(135 + 270),
                               clockwise: false)
                    ctx.stroke(red, with: .color(Theme.red.opacity(0.5)), lineWidth: 6)
                    // 指针
                    let na = (135.0 + frac * 270.0) * .pi / 180
                    var np = Path()
                    np.move(to: CGPoint(x: cx, y: cy))
                    np.addLine(to: CGPoint(x: cx + cos(na) * R * 0.60, y: cy + sin(na) * R * 0.60))
                    ctx.stroke(np, with: .color(Theme.amber),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                Circle().fill(Theme.panelHi)
                    .frame(width: d * 0.13, height: d * 0.13)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                VStack(spacing: 0) {
                    Text(gear)
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                    Text("\(speed)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.text)
                    Text("km/h")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textFaint)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Circle().fill(Theme.panel.opacity(0.85)))
                .offset(y: d * 0.20)
            }
        }
        .aspectRatio(1.15, contentMode: .fit)
    }
}

/// 中控仪表盘。
struct DashPanel: View {
    @ObservedObject var s: ControllerState
    var gear: String

    var body: some View {
        HStack(spacing: 8) {
            Tachometer(rpm: 0.12 + s.throttle * 0.82,
                       gear: gear,
                       speed: Int(s.throttle * 240))
            VStack(spacing: 6) {
                LevelBar(title: "THR", value: s.throttle, accent: Theme.green)
                LevelBar(title: "BRK", value: s.lt, accent: Theme.red)
                LevelBar(title: "CLT", value: s.clutch, accent: Theme.amber)
                LevelBar(title: "STR", value: (s.smRoll + 1) / 2, accent: Theme.cyan)
            }
            .frame(width: 42)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }
}

/// 单块踏板（0..1，松手保持）。
struct DeckPedal: View {
    var label: String
    @Binding var value: Double
    var accent: Color
    var onTouch: ((Bool) -> Void)? = nil

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let plateH = max(26, h * 0.30)
            let travel = max(1, h - plateH - 12)
            let y = 6 + value * travel
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Theme.panelHi, Theme.panel],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                // 行程槽
                Capsule().fill(Theme.border.opacity(0.35))
                    .frame(width: 8, height: h - 12)
                    .padding(.top, 6)
                // 踏板面
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.white.opacity(0.86), Color(white: 0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: plateH)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent, lineWidth: 2))
                    .overlay(
                        VStack(spacing: 4) {
                            Text(label)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                            Text("\(Int(value * 100))%")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.black.opacity(0.65))
                        }
                    )
                    .glow(accent, radius: value > 0.02 ? 4 : 0)
                    .offset(y: y)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { dragging = true; onTouch?(true); Haptics.tap() }
                        let rel = (g.location.y - 6 - plateH / 2) / travel
                        value = max(0, min(1, rel))
                    }
                    .onEnded { _ in dragging = false; onTouch?(false) }
            )
            .frame(width: w, height: h)
        }
    }
}

/// 三踏板（离合 / 刹车 / 油门）。
struct DrivePedals: View {
    @Binding var clutch: Double
    @Binding var brake: Double
    @Binding var throttle: Double
    var onTouch: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            DeckPedal(label: "CLT", value: $clutch, accent: Theme.amber, onTouch: onTouch)
            DeckPedal(label: "BRK", value: $brake, accent: Theme.red, onTouch: onTouch)
            DeckPedal(label: "THR", value: $throttle, accent: Theme.green, onTouch: onTouch)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }
}

/// 序列式档杆：竖向闸口，拖动选档，每次换位发一次升/降档脉冲。
struct GearLever: View {
    var gears: [String]
    @Binding var index: Int
    var onShift: (Int) -> Void      // +1 升档 / -1 降档

    @State private var dragging = false
    @State private var startIndex = 0
    @State private var startY = 0.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = max(1, gears.count - 1)
            let step = max(1, (h - 24) / CGFloat(n))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Theme.panelHi, Theme.panel],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                // 闸口刻度
                ForEach(gears.indices, id: \.self) { i in
                    Text(gears[i])
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(i == index ? Theme.cyan : Theme.textFaint)
                        .position(x: w * 0.22, y: 12 + CGFloat(i) * step)
                }
                // 档杆把手
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.white.opacity(0.9), Color(white: 0.58)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.42, height: max(22, step * 0.72))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.cyan, lineWidth: 2))
                    .overlay(Text(gears[index])
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(.black))
                    .glow(Theme.cyan, radius: 4)
                    .offset(x: w * 0.50, y: 12 + CGFloat(index) * step - max(22, step * 0.72) / 2)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        if !dragging {
                            dragging = true; startIndex = index
                            startY = g.startLocation.y; Haptics.tap()
                        }
                        let delta = Int(((g.location.y - startY) / step).rounded())
                        let next = min(gears.count - 1, max(0, startIndex + delta))
                        if next != index {
                            let dir = next > index ? 1 : -1
                            index = next
                            onShift(dir)
                            Haptics.tap()
                        }
                    }
                    .onEnded { _ in dragging = false }
            )
        }
    }
}

/// 驾驶模式整屏硬件皮肤。
struct DriveDeck: View {
    @ObservedObject var s: ControllerState
    var ctrl: CockpitController

    @AppStorage("palmdeck_gear") private var gearIndex = 2   // 持久化：切模式/重启保留档位
    private let gears = ["R", "N", "1", "2", "3", "4", "5", "6"]

    private var touch: (Bool) -> Void { { ctrl.setTouchActive($0) } }
    private var gearText: String { gears[min(gearIndex, gears.count - 1)] }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    DashPanel(s: s, gear: gearText)
                        .frame(width: W * 0.27)
                    SteeringWheel(value: $s.roll,
                                  maxDeg: s.wheelMaxDeg,
                                  returnToCenter: s.wheelReturnSpeed > 0,
                                  returnSpeed: s.wheelReturnSpeed,
                                  onTouch: touch)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 8) {
                        LookPad(lookX: $s.lookX, lookY: $s.lookY, accent: Theme.cyan)
                            .frame(maxHeight: .infinity)
                        buttonCluster
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: W * 0.28)
                }
                .frame(height: H * 0.60)
                HStack(spacing: 8) {
                    DrivePedals(clutch: $s.clutch, brake: $s.lt,
                                throttle: $s.throttle, onTouch: touch)
                        .frame(maxWidth: .infinity)
                    GearLever(gears: gears, index: $gearIndex, onShift: shift)
                        .frame(width: W * 0.24)
                }
                .frame(height: H * 0.40 - 8)
            }
        }
    }

    private var buttonCluster: some View {
        let cols = [GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: cols, spacing: 6) {
            DeckButton(title: "左转", active: isActive(.vjoy1)) { toggle(.vjoy1) }
            DeckButton(title: "右转", active: isActive(.vjoy2)) { toggle(.vjoy2) }
            DeckButton(title: "危险灯", active: isActive(.vjoy3), accent: Theme.amber) { toggle(.vjoy3) }
            DeckButton(title: "喇叭", active: isActive(.vjoy4)) { toggle(.vjoy4) }
            DeckButton(title: "手刹", active: isActive(.vjoy7), accent: Theme.red) { toggle(.vjoy7) }
            DeckButton(title: "雨刷", active: isActive(.vjoy8)) { toggle(.vjoy8) }
            DeckButton(title: "大灯", active: isActive(.vjoy9), accent: Theme.amber) { toggle(.vjoy9) }
            DeckButton(title: "远光", active: isActive(.vjoy10), accent: Theme.amber) { toggle(.vjoy10) }
            DeckButton(title: "视角键", active: isActive(.vjoy5)) { toggle(.vjoy5) }
        }
    }

    // MARK: 按键 / 换档语义
    private func shift(_ dir: Int) {
        pulse(dir > 0 ? 5 : 4)   // b6 = 升档(RB) / b5 = 降档(LB)
    }

    private func isActive(_ b: WidgetBinding) -> Bool {
        if let idx = b.vjoyIndex { return (s.btnMask & (1 << idx)) != 0 }
        return false
    }

    private func toggle(_ b: WidgetBinding) {
        guard let idx = b.vjoyIndex else { return }
        let bit = UInt16(1 << idx)
        let down = (s.btnMask & bit) == 0
        if down { s.btnMask |= bit } else { s.btnMask &= ~bit }
        s.onButton?(idx + 1, down)
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
