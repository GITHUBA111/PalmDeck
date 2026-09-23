import SwiftUI

/// 归一化矩形（相对可用画布的 0~1）
struct WRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    static func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WRect {
        WRect(x: x, y: y, w: w, h: h)
    }
}

/// 各模式的组件列表（可自定义、持久化）
final class LayoutStore: ObservableObject {
    @Published var editing = false
    @Published var flight: [DeckWidget] = []
    @Published var drive: [DeckWidget] = []

    private let key = "palmdeck_widgets_v7"

    init() {
        load()
        if flight.isEmpty { flight = LayoutStore.defaultFlight() }
        if drive.isEmpty { drive = LayoutStore.defaultDrive() }
    }

    func widgets(mode: CockpitMode) -> [DeckWidget] { mode == .drive ? drive : flight }

    private func setWidgets(_ list: [DeckWidget], mode: CockpitMode) {
        if mode == .drive { drive = list } else { flight = list }
        save()
    }

    func add(kind: WidgetKind, binding: WidgetBinding, mode: CockpitMode) {
        // 新组件放在中间偏下，尺寸按类型
        let size: WRect
        switch kind {
        case .wheel:  size = .r(0.30, 0.30, 0.30, 0.45)
        case .slider: size = .r(0.35, 0.40, 0.30, 0.12)
        case .pad:    size = .r(0.35, 0.35, 0.20, 0.28)
        case .button: size = .r(0.40, 0.45, 0.12, 0.12)
        case .stick:  size = .r(0.38, 0.35, 0.18, 0.30)
        case .hat:    size = .r(0.40, 0.35, 0.12, 0.20)
        case .attitude: size = .r(0.40, 0.10, 0.22, 0.34)
        }
        var list = widgets(mode: mode)
        list.append(.make(kind, binding, size))
        setWidgets(list, mode: mode)
    }

    func remove(id: String, mode: CockpitMode) {
        setWidgets(widgets(mode: mode).filter { $0.id != id }, mode: mode)
    }

    func update(_ w: DeckWidget, mode: CockpitMode) {
        var list = widgets(mode: mode)
        if let i = list.firstIndex(where: { $0.id == w.id }) { list[i] = w; setWidgets(list, mode: mode) }
    }

    func clear(mode: CockpitMode) { setWidgets([], mode: mode) }

    func reset(mode: CockpitMode) {
        setWidgets(mode == .drive ? LayoutStore.defaultDrive() : LayoutStore.defaultFlight(), mode: mode)
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let obj = try? JSONDecoder().decode([String: [DeckWidget]].self, from: data) else { return }
        flight = obj["flight"] ?? []
        drive = obj["drive"] ?? []
    }

    func save() {
        let obj = ["flight": flight, "drive": drive]
        if let data = try? JSONEncoder().encode(obj) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: 默认布局（沿用改造前的控件集）
    static func defaultFlight() -> [DeckWidget] {
        [
            .make(.attitude, .roll, .r(0.28, 0.02, 0.22, 0.42)),
            // 左列
            .make(.slider, .throttle, .r(0.01, 0.02, 0.20, 0.14)),
            .make(.slider, .roll,     .r(0.01, 0.19, 0.20, 0.12)),
            .make(.slider, .pitch,    .r(0.01, 0.33, 0.20, 0.12)),
            .make(.hat,    .look,     .r(0.02, 0.50, 0.14, 0.26)),
            // 右列
            .make(.stick,  .roll,     .r(0.80, 0.02, 0.15, 0.26)),
            .make(.button, .fire,     .r(0.78, 0.30, 0.18, 0.10), label: "开火"),
            .make(.slider, .yaw,      .r(0.77, 0.42, 0.21, 0.12)),
            .make(.button, .vjoy1,    .r(0.77, 0.56, 0.10, 0.11), label: "武器投放"),
            .make(.button, .vjoy2,    .r(0.88, 0.56, 0.10, 0.11), label: "锁定目标"),
            .make(.button, .vjoy3,    .r(0.77, 0.69, 0.10, 0.11), label: "干扰弹"),
            .make(.button, .vjoy4,    .r(0.88, 0.69, 0.10, 0.11), label: "起落架"),
            .make(.button, .vjoy5,    .r(0.77, 0.82, 0.10, 0.11), label: "切视角"),
            .make(.button, .vjoy6,    .r(0.88, 0.82, 0.10, 0.11), label: "语音"),
            // 中下 10 键（两行）
            .make(.button, .vjoy7,    .r(0.235, 0.76, 0.095, 0.105), label: "襟翼收"),
            .make(.button, .vjoy8,    .r(0.337, 0.76, 0.095, 0.105), label: "襟翼放"),
            .make(.button, .vjoy9,    .r(0.439, 0.76, 0.095, 0.105), label: "减速板"),
            .make(.button, .vjoy10,   .r(0.541, 0.76, 0.095, 0.105), label: "配平"),
            .make(.button, .vjoy11,   .r(0.643, 0.76, 0.095, 0.105), label: "自驾"),
            .make(.button, .vjoy12,   .r(0.235, 0.875, 0.095, 0.105), label: "按钮12"),
            .make(.button, .vjoy13,   .r(0.337, 0.875, 0.095, 0.105), label: "按钮13"),
            .make(.button, .vjoy14,   .r(0.439, 0.875, 0.095, 0.105), label: "按钮14"),
            .make(.button, .vjoy15,   .r(0.541, 0.875, 0.095, 0.105), label: "按钮15"),
            .make(.button, .vjoy16,   .r(0.643, 0.875, 0.095, 0.105), label: "按钮16"),
        ]
    }

    static func defaultDrive() -> [DeckWidget] {
        [
            .make(.wheel,  .roll,     .r(0.02, 0.06, 0.40, 0.84)),
            .make(.slider, .throttle, .r(0.60, 0.02, 0.38, 0.13)),
            .make(.slider, .brake,    .r(0.60, 0.17, 0.38, 0.13)),
            .make(.slider, .clutch,   .r(0.60, 0.32, 0.38, 0.13)),
            .make(.button, .gearUp,   .r(0.60, 0.48, 0.17, 0.12)),
            .make(.button, .gearDown, .r(0.60, 0.62, 0.17, 0.12)),
            .make(.pad,    .look,     .r(0.79, 0.48, 0.19, 0.30)),
            .make(.button, .vjoy1,    .r(0.015, 0.795, 0.118, 0.086), label: "左转向"),
            .make(.button, .vjoy2,    .r(0.1385, 0.795, 0.118, 0.086), label: "右转向"),
            .make(.button, .vjoy3,    .r(0.262, 0.795, 0.118, 0.086), label: "危险灯"),
            .make(.button, .vjoy4,    .r(0.3855, 0.795, 0.118, 0.086), label: "喇叭"),
            .make(.button, .vjoy5,    .r(0.509, 0.795, 0.118, 0.086), label: "手刹"),
            .make(.button, .vjoy6,    .r(0.6325, 0.795, 0.118, 0.086), label: "雨刷"),
            .make(.button, .vjoy7,    .r(0.756, 0.795, 0.118, 0.086), label: "大灯"),
            .make(.button, .vjoy8,    .r(0.8795, 0.795, 0.118, 0.086), label: "远光"),
            .make(.button, .vjoy9,    .r(0.015, 0.893, 0.118, 0.086), label: "升档"),
            .make(.button, .vjoy10,   .r(0.1385, 0.893, 0.118, 0.086), label: "降档"),
            .make(.button, .vjoy11,   .r(0.262, 0.893, 0.118, 0.086), label: "切视角"),
            .make(.button, .vjoy12,   .r(0.3855, 0.893, 0.118, 0.086), label: "巡航"),
            .make(.button, .vjoy13,   .r(0.509, 0.893, 0.118, 0.086), label: "发动机"),
            .make(.button, .vjoy14,   .r(0.6325, 0.893, 0.118, 0.086), label: "差速锁"),
            .make(.button, .vjoy15,   .r(0.756, 0.893, 0.118, 0.086), label: "警示"),
            .make(.button, .vjoy16,   .r(0.8795, 0.893, 0.118, 0.086), label: "自由"),
        ]
    }
}

/// 画布：渲染组件列表（编辑时可拖动/缩放/删除）。
struct WidgetCanvas: View {
    @ObservedObject var store: LayoutStore
    let mode: CockpitMode
    @ObservedObject var s: ControllerState
    var ctrl: CockpitController

    var body: some View {
        GeometryReader { geo in
            let W = max(1, geo.size.width)
            let H = max(1, geo.size.height)
            ZStack {
                ForEach(store.widgets(mode: mode)) { w in
                    EditableWidget(widget: w, store: store, mode: mode,
                                   canvas: CGSize(width: W, height: H), s: s, ctrl: ctrl)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.editing {
                HStack(spacing: 8) {
                    Button("完成") { store.editing = false }
                        .buttonStyle(CardButton(active: true, fillWidth: false, height: 34))
                    Button("清空") { store.clear(mode: mode) }
                        .buttonStyle(CardButton(fillWidth: false, height: 34))
                }
                .padding(8)
            }
        }
    }
}

/// 单个可编辑组件
struct EditableWidget: View {
    let widget: DeckWidget
    @ObservedObject var store: LayoutStore
    let mode: CockpitMode
    let canvas: CGSize
    @ObservedObject var s: ControllerState
    var ctrl: CockpitController

    @State private var dragStart: WRect?

    private var r: WRect { widget.rect }

    var body: some View {
        let W = canvas.width, H = canvas.height
        let px = r.x * W, py = r.y * H
        let pw = max(24, r.w * W), ph = max(24, r.h * H)

        ZStack {
            WidgetView(widget: widget, s: s, ctrl: ctrl)
                .frame(width: pw, height: ph)
                .allowsHitTesting(!store.editing)   // 编辑时禁功能，避免误触

            if store.editing {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.cyan.opacity(0.001))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                if dragStart == nil { dragStart = r }
                                guard let st = dragStart else { return }
                                var nw = widget
                                nw.rect = WRect(x: st.x + g.translation.width / W,
                                                y: st.y + g.translation.height / H,
                                                w: st.w, h: st.h)
                                store.update(nw, mode: mode)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                // 缩放
                Circle().fill(Theme.cyan)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .frame(width: 24, height: 24)
                    .offset(x: pw / 2 - 12, y: ph / 2 - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                if dragStart == nil { dragStart = r }
                                guard let st = dragStart else { return }
                                var nw = widget
                                nw.rect = WRect(x: st.x, y: st.y,
                                                w: max(0.04, st.w + g.translation.width / W),
                                                h: max(0.04, st.h + g.translation.height / H))
                                store.update(nw, mode: mode)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                // 删除
                Button {
                    store.remove(id: widget.id, mode: mode)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.red))
                }
                .offset(x: -pw / 2 + 12, y: -ph / 2 + 12)
            }
        }
        .frame(width: pw, height: ph)
        .position(x: px + pw / 2, y: py + ph / 2)
    }
}
