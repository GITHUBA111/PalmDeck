import SwiftUI

/// 组件类型
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case wheel      // 方向盘
    case slider     // 滑条
    case pad        // 触摸板（视角）
    case button     // 按键
    case stick      // 2D 摇杆
    case hat        // 苦力帽
    case attitude   // 姿态球
    case panel      // 飞行仪表盘（只读）

    /// 给 `.sheet(item:)` 用：把「点的是哪个组件」当成弹窗的输入，
    /// 而不是先改一个 `@State` 再 `isPresented = true` —— 后者在同一个
    /// action 里设两个 state 时，sheet 内容闭包可能拿到旧值（点「按键」却从「滑条」起）。
    var id: String { rawValue }

    var label: String {
        switch self {
        case .wheel: return "方向盘"
        case .slider: return "滑条"
        case .pad: return "触摸板"
        case .button: return "按键"
        case .stick: return "摇杆"
        case .hat: return "苦力帽"
        case .attitude: return "姿态球"
        case .panel: return "仪表盘"
        }
    }

    /// 只读组件：不绑定任何轴/键，摆上去只做显示。
    var isReadOnly: Bool { self == .panel }

    /// 组件库里「绑定」下拉该给哪些选项。空 = 这个组件不读 `widget.binding`：
    /// 方向盘 / 触摸板 / 摇杆 / 苦力帽 / 姿态球渲染时各走固定通道，仪表盘只读。
    /// 给了下拉就是让人选一个存下去却不生效的值（历史 bug：选「按键」能选「油门」，
    /// 而 `tapButton` 对轴绑定是空实现 ⇒ 按了没反应）。
    var bindingOptions: [WidgetBinding] {
        switch self {
        case .slider: return WidgetBinding.axes
        case .button: return WidgetBinding.buttons
        default:      return []
        }
    }

    /// 绑定被忽略时，说清它到底发什么（给下拉的替身文案用）。
    var fixedBindingNote: String {
        switch self {
        case .wheel:    return "固定发「横滚/转向」"
        case .pad:      return "固定发「视角」"
        case .stick:    return "固定发「横滚 + 俯仰」"
        case .hat:      return "固定发「苦力帽 + 视角」"
        case .attitude: return "只显示本机杆位"
        case .panel:    return "只读显示，不绑定"
        default:        return ""
        }
    }

    /// 组件被「直接加上画布」或换到该类型时的绑定占位。
    /// 固定通道组件的值在渲染时被忽略，这里只保证存下去的是一个看似合理的名字。
    var defaultBinding: WidgetBinding {
        switch self {
        case .pad, .stick, .hat: return .look
        case .button:            return .vjoy1
        default:                 return .roll
        }
    }
}

/// 组件绑定的功能（轴或按钮）
enum WidgetBinding: String, Codable, CaseIterable {
    // 轴
    case roll, pitch, yaw, throttle, brake, clutch, rt, look
    // 按钮
    case vjoy1, vjoy2, vjoy3, vjoy4, vjoy5, vjoy6, vjoy7, vjoy8
    case vjoy9, vjoy10, vjoy11, vjoy12, vjoy13, vjoy14, vjoy15, vjoy16
    case gearUp, gearDown
    case fire       // 开火（→ vJoy 16 / rt）

    var label: String {
        switch self {
        case .roll: return "横滚/转向"
        case .pitch: return "俯仰"
        case .yaw: return "方向舵"
        case .throttle: return "油门"
        case .brake: return "刹车（LT）"
        case .clutch: return "离合"
        case .rt: return "右扳机（RT）"
        case .look: return "视角"
        case .gearUp: return "升档"
        case .gearDown: return "降档"
        case .fire: return "开火（vJoy 16）"
        default:
            if let n = Int(rawValue.dropFirst(4)) { return "按钮 \(n)" }
            return rawValue
        }
    }

    var isAxis: Bool {
        switch self {
        case .roll, .pitch, .yaw, .throttle, .brake, .clutch, .rt, .look: return true
        default: return false
        }
    }

    /// 滑条真正会用的轴：必须与 `WidgetView.bindAxis` 的 case 一一对应。
    /// 显式列出而不用 `filter(isAxis)` —— 后者会把 `look` 带进来，
    /// 而 `look` 只被那些「写死通道」的组件内部使用，滑条 `bindAxis` 并不处理它。
    static let axes: [WidgetBinding] = [.roll, .pitch, .yaw, .throttle, .brake, .clutch, .rt]

    /// 按键真正会发的键：必须与 `WidgetView.tapButton` 的分支一一对应。
    static let buttons: [WidgetBinding] = [
        .vjoy1, .vjoy2, .vjoy3, .vjoy4, .vjoy5, .vjoy6, .vjoy7, .vjoy8,
        .vjoy9, .vjoy10, .vjoy11, .vjoy12, .vjoy13, .vjoy14, .vjoy15, .vjoy16,
        .gearUp, .gearDown, .fire,
    ]
    var vjoyIndex: Int? {
        if rawValue.hasPrefix("vjoy"), let n = Int(rawValue.dropFirst(4)) { return n - 1 }
        return nil
    }

    /// vjoy11–vjoy16 只存在于 vJoy。Xbox 虚拟手柄（`hotas.py` 的 `X360` 字典）到
    /// b10 = 右摇杆按下为止，所以开车/手柄模式里选它等于选了一个什么都不做的键。
    var onlyOnVJoy: Bool {
        guard let idx = vjoyIndex else { return false }
        return idx >= 10
    }
}

/// 一个可配置组件实例
struct DeckWidget: Codable, Identifiable, Equatable {
    var id: String
    var kind: WidgetKind
    var binding: WidgetBinding
    var rect: WRect
    var label: String = ""

    var title: String { label.isEmpty ? binding.label : label }

    static func make(_ kind: WidgetKind, _ binding: WidgetBinding, _ rect: WRect, label: String = "") -> DeckWidget {
        DeckWidget(id: UUID().uuidString, kind: kind, binding: binding, rect: rect, label: label)
    }
}

/// 按 kind+binding 渲染一个组件，接到 ControllerState。
struct WidgetView: View {
    let widget: DeckWidget
    @ObservedObject var s: ControllerState
    var ctrl: CockpitController

    var body: some View {
        switch widget.kind {
        case .wheel:
            SteeringWheel(value: bindAxis(.roll), maxDeg: s.wheelMaxDeg,
                          returnToCenter: s.wheelReturnSpeed > 0,
                          returnSpeed: s.wheelReturnSpeed,
                          onTouch: { ctrl.setTouchActive($0) })
        case .slider:
            switch widget.binding {
            case .throttle, .brake, .clutch, .rt:
                VStack(spacing: 2) {
                    Text(widget.title).font(.system(size: 10)).foregroundColor(Theme.textFaint)
                    UniSlider(value: bindAxis(widget.binding), accent: sliderColor, onTouch: { ctrl.setTouchActive($0) })
                }
            default:
                VStack(spacing: 2) {
                    Text(widget.title).font(.system(size: 10)).foregroundColor(Theme.textFaint)
                    BipolarSlider(value: bindAxis(widget.binding), accent: sliderColor, onTouch: { ctrl.setTouchActive($0) })
                }
            }
        case .pad:
            LookPad(lookX: $s.lookX, lookY: $s.lookY)
        case .button:
            Button(widget.title) { tapButton(widget.binding) }
                .buttonStyle(CardButton(active: isButtonActive(widget.binding)))
        case .stick:
            StickControl(x: $s.roll, y: $s.pitch, returnToCenter: s.stickReturn,
                         onTouch: { ctrl.setTouchActive($0) })
        case .hat:
            HatPad(hat: $s.hat, lookX: $s.lookX, lookY: $s.lookY)
        case .attitude:
            AttitudeBall(s: s)
        case .panel:
            FlightPanel(s: s)
        }
    }

    private var sliderColor: Color {
        switch widget.binding {
        case .throttle: return Theme.green
        case .brake: return Theme.red
        case .clutch: return Theme.orange
        case .rt: return Theme.orange
        default: return Theme.cyan
        }
    }

    // 轴绑定 → Binding
    private func bindAxis(_ b: WidgetBinding) -> Binding<Double> {
        switch b {
        case .roll: return $s.roll
        case .pitch: return $s.pitch
        case .yaw: return $s.yaw
        case .throttle: return $s.throttle
        case .brake: return $s.lt
        case .clutch: return $s.clutch
        case .rt: return $s.rt
        default: return $s.roll
        }
    }

    private func isButtonActive(_ b: WidgetBinding) -> Bool {
        if let idx = b.vjoyIndex { return (s.btnMask & (1 << idx)) != 0 }
        if b == .fire { return s.rt > 0.5 }
        return false
    }

    private func tapButton(_ b: WidgetBinding) {
        if let idx = b.vjoyIndex {
            let bit = UInt16(1 << idx)
            let down = (s.btnMask & bit) == 0
            if down { s.btnMask |= bit } else { s.btnMask &= ~bit }
            if down { Haptics.tap() }
            s.onButton?(idx + 1, down)
        } else if b == .gearUp {
            pulse(5)   // b6 = RB（升档）
        } else if b == .gearDown {
            pulse(4)   // b5 = LB（降档）
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
