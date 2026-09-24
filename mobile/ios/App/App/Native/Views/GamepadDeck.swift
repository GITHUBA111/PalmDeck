import SwiftUI

// MARK: - 游戏手柄硬件皮肤（v4 P6）
//
// 参照真实 Xbox 手柄：左摇杆、右摇杆、十字键、ABXY 菱形、LB/RB、LT/RT、视图/菜单。
// 服务端在 gamepad 模式下停掉 thr/lt/rt 轴、不抢电脑键鼠；按键走 vJoy 位掩码。

/// 圆形面键（ABXY）。
struct PadButton: View {
    var title: String
    var active: Bool
    var accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundColor(active ? .black : accent)
                .frame(width: 46, height: 46)
                .background(Circle().fill(active ? accent : Theme.panelHi))
                .overlay(Circle().stroke(accent, lineWidth: 1.5))
                .glow(active ? accent : .clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
}

/// 肩键 / 扳机键（LB/RB/LT/RT）。
struct TriggerBtn: View {
    var title: String
    var active: Bool
    var accent: Color = Theme.cyan
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
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

/// 游戏手柄整屏硬件皮肤。
struct GamepadDeck: View {
    @ObservedObject var s: ControllerState
    var ctrl: CockpitController

    private var touch: (Bool) -> Void { { ctrl.setTouchActive($0) } }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            HStack(spacing: 10) {
                // 左手：L3 / 左摇杆 / LB
                VStack(spacing: 10) {
                    TriggerBtn(title: "L3", active: isActive(.vjoy9), accent: Theme.orange) { toggle(.vjoy9) }
                        .frame(height: H * 0.15)
                    StickControl(x: $s.roll, y: $s.pitch,
                                 returnToCenter: s.stickReturn,
                                 accent: Theme.cyan, onTouch: touch)
                        .frame(maxHeight: .infinity)
                    TriggerBtn(title: "LB", active: isActive(.vjoy5), accent: Theme.cyan) { toggle(.vjoy5) }
                        .frame(height: H * 0.15)
                }
                .frame(width: W * 0.30)

                // 中间：视图/菜单 / 十字键 / ABXY
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        TriggerBtn(title: "视图", active: isActive(.vjoy7)) { toggle(.vjoy7) }
                            .frame(width: 74, height: 30)
                        TriggerBtn(title: "菜单", active: isActive(.vjoy8)) { toggle(.vjoy8) }
                            .frame(width: 74, height: 30)
                    }
                    HatPad(hat: $s.hat, lookX: $s.lookX, lookY: $s.lookY, accent: Theme.green)
                        .frame(width: min(W * 0.20, H * 0.34))
                    diamond
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)

                // 右手：R3 / 右摇杆 / RB
                VStack(spacing: 10) {
                    TriggerBtn(title: "R3", active: isActive(.vjoy10), accent: Theme.orange) { toggle(.vjoy10) }
                        .frame(height: H * 0.15)
                    LookPad(lookX: $s.lookX, lookY: $s.lookY, accent: Theme.cyan)
                        .frame(maxHeight: .infinity)
                    TriggerBtn(title: "RB", active: isActive(.vjoy6), accent: Theme.cyan) { toggle(.vjoy6) }
                        .frame(height: H * 0.15)
                }
                .frame(width: W * 0.30)
            }
        }
    }

    private var diamond: some View {
        ZStack {
            PadButton(title: "Y", active: isActive(.vjoy4), accent: Theme.amber) { toggle(.vjoy4) }
                .offset(y: -48)
            PadButton(title: "A", active: isActive(.vjoy1), accent: Theme.green) { toggle(.vjoy1) }
                .offset(y: 48)
            PadButton(title: "X", active: isActive(.vjoy3), accent: Theme.cyan) { toggle(.vjoy3) }
                .offset(x: -48)
            PadButton(title: "B", active: isActive(.vjoy2), accent: Theme.red) { toggle(.vjoy2) }
                .offset(x: 48)
        }
        .frame(width: 140, height: 140)
    }

    // MARK: 按钮语义
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
}
