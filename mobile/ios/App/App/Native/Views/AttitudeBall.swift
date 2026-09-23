import SwiftUI

/// 飞行姿态球（PFD）：天地 + 俯仰刻度 + 滚转弧 + 飞机符。
/// 显示 displayRoll/displayPitch：默认本地杆位，切换到「游戏遥测」后用真实姿态。
struct AttitudeBall: View {
    @ObservedObject var s: ControllerState

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = d / 2
            let roll = s.displayRoll
            let pitch = s.displayPitch
            let yaw = s.displayYaw
            let heading = yaw * 180   // -180..+180

            ZStack {
                Canvas { ctx, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let D = min(size.width, size.height)
                    let R = D / 2

                    ctx.clip(to: Path(ellipseIn: CGRect(x: cx-R, y: cy-R, width: D, height: D)))

                    // 天地：整块随 roll 旋转、随 pitch 平移
                    ctx.drawLayer { c in
                        c.translateBy(x: cx, y: cy)
                        c.rotate(by: .degrees(-roll * 90))
                        c.translateBy(x: 0, y: pitch * D * 0.30)
                        let big = D * 3
                        // 天
                        c.fill(Path(CGRect(x: -big/2, y: -big/2, width: big, height: big/2)),
                               with: .linearGradient(Gradient(colors: [Color(red: 0.25, green: 0.48, blue: 0.69), Color(red: 0.06, green: 0.14, blue: 0.22)]),
                                                     startPoint: .init(x: 0, y: -big/2), endPoint: .init(x: 0, y: 0)))
                        // 地
                        c.fill(Path(CGRect(x: -big/2, y: 0, width: big, height: big/2)),
                               with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.28, blue: 0.14), Color(red: 0.14, green: 0.09, blue: 0.05)]),
                                                     startPoint: .init(x: 0, y: 0), endPoint: .init(x: 0, y: big/2)))
                        // 地平线
                        c.stroke(Path { p in
                            p.move(to: CGPoint(x: -big/2, y: 0)); p.addLine(to: CGPoint(x: big/2, y: 0))
                        }, with: .color(.white.opacity(0.9)), lineWidth: 2)
                        // 俯仰刻度
                        let K = (D * 0.30) / 38
                        for deg in [-20, -10, 10, 20] {
                            let y = -CGFloat(deg) * K
                            let half = abs(deg) == 10 ? D*0.10 : D*0.07
                            c.stroke(Path { p in
                                p.move(to: CGPoint(x: -half, y: y)); p.addLine(to: CGPoint(x: half, y: y))
                            }, with: .color(.white.opacity(0.65)), lineWidth: 1.5)
                        }
                    }

                    // 顶部滚转弧（固定）
                    let arcR = R * 0.92
                    do {
                        var p = Path()
                        p.addArc(center: CGPoint(x: cx, y: cy), radius: arcR,
                                 startAngle: .degrees(-115), endAngle: .degrees(-65), clockwise: false)
                        ctx.stroke(p, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
                        for deg in [-60, -45, -30, -15, 0, 15, 30, 45, 60] {
                            let a = Double(deg) * .pi / 180
                            let outer = arcR
                            let inner = arcR - (deg == 0 ? 12 : 8)
                            let x1 = cx + CGFloat(cos(a - .pi/2)) * outer
                            let y1 = cy + CGFloat(sin(a - .pi/2)) * outer
                            let x2 = cx + CGFloat(cos(a - .pi/2)) * inner
                            let y2 = cy + CGFloat(sin(a - .pi/2)) * inner
                            var q = Path(); q.move(to: CGPoint(x: x1, y: y1)); q.addLine(to: CGPoint(x: x2, y: y2))
                            ctx.stroke(q, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
                        }
                        // 中央指示三角
                        var t = Path()
                        t.move(to: CGPoint(x: cx, y: cy - arcR + 2))
                        t.addLine(to: CGPoint(x: cx - 5, y: cy - arcR - 8))
                        t.addLine(to: CGPoint(x: cx + 5, y: cy - arcR - 8))
                        t.closeSubpath()
                        ctx.fill(t, with: .color(Theme.orange))
                    }

                    // 飞机符号（固定中心）
                    var ac = Path()
                    ac.move(to: CGPoint(x: cx - 26, y: cy))
                    ac.addLine(to: CGPoint(x: cx - 8, y: cy))
                    ac.move(to: CGPoint(x: cx + 8, y: cy))
                    ac.addLine(to: CGPoint(x: cx + 26, y: cy))
                    ac.move(to: CGPoint(x: cx, y: cy - 6))
                    ac.addLine(to: CGPoint(x: cx, y: cy + 6))
                    ctx.stroke(ac, with: .color(Theme.amber), lineWidth: 2.5)

                    // 顶部航向带（随 yaw 滑动，±40° 窗口）
                    let tapeY = D * 0.16
                    let tapeW = D * 0.90
                    ctx.fill(Path(CGRect(x: cx - tapeW/2, y: tapeY - 11, width: tapeW, height: 34)),
                             with: .color(Color.black.opacity(0.32)))
                    let pxPerDeg = Double(tapeW) / 80.0
                    let startDeg = floor((heading - 40) / 10) * 10
                    for d in stride(from: startDeg, through: heading + 40, by: 10.0) {
                        let x = cx + CGFloat(Double(d) - heading) * CGFloat(pxPerDeg)
                        let major = Int(d.rounded()) % 30 == 0
                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: tapeY))
                        tick.addLine(to: CGPoint(x: x, y: tapeY + (major ? 11 : 6)))
                        ctx.stroke(tick, with: .color(.white.opacity(major ? 0.85 : 0.45)), lineWidth: 1)
                        if major {
                            var deg = Int(d.rounded()) % 360
                            if deg < 0 { deg += 360 }
                            let label = deg == 0 ? "N" : deg == 90 ? "E" : deg == 180 ? "S" : deg == 270 ? "W" : "\(deg)"
                            ctx.draw(Text(label).font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85)),
                                     at: CGPoint(x: x, y: tapeY + 20))
                        }
                    }
                    // 航向指示（lubber 三角，指向当前航向）
                    var lp = Path()
                    lp.move(to: CGPoint(x: cx, y: tapeY - 3))
                    lp.addLine(to: CGPoint(x: cx - 4, y: tapeY - 9))
                    lp.addLine(to: CGPoint(x: cx + 4, y: tapeY - 9))
                    lp.closeSubpath()
                    ctx.fill(lp, with: .color(Theme.orange))
                }
                .background(Color(red: 0.04, green: 0.07, blue: 0.12))
                .clipShape(Circle())

                // 外圈
                Circle().stroke(Theme.border, lineWidth: 2.5)
                // 锁定标记
                if s.paused {
                    Text("HOLD").font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.orange)
                        .position(x: 30, y: 20)
                }
            }
            .frame(width: d, height: d)
            .position(x: geo.size.width/2, y: geo.size.height/2)
        }
    }
}
