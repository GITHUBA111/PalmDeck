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

/// 命名布局快照（布局模板）。
///
/// 内置「默认」**不入库**：直接取 `LayoutStore.defaults(mode:)`，只读、不可删。
struct LayoutTemplate: Codable, Identifiable, Equatable {
    var name: String
    var widgets: [DeckWidget]
    var id: String { name }
}

/// 各模式的组件列表（可自定义、持久化）
final class LayoutStore: ObservableObject {
    /// 内置只读模板名（即“还原点”）
    static let builtinName = "默认"
    /// 每模式模板数上限（UserDefaults 不是数据库，防手滑存爆）
    static let maxTemplates = 12
    /// 模板名长度上限
    static let maxNameLength = 16

    @Published var editing = false
    /// 各模式组件列表（key = `CockpitMode.rawValue`）
    @Published private var layouts: [String: [DeckWidget]] = [:]
    /// 与电脑同步的状态提示（设置页显示）
    @Published var syncMessage = ""
    /// 模板：`{模式: [模板]}`（不含内置「默认」）
    @Published private(set) var templatesByMode: [String: [LayoutTemplate]] = [:]
    /// 撤销槽（单格 / 按模式）：破坏性操作前压入
    @Published private(set) var undoSlots: [String: [DeckWidget]] = [:]
    /// 整表替换计数。画布用 `.id(revision)` 强制重建，
    /// 否则 `EditableWidget` 的 `@State dragStart` 会残留到新布局上。
    @Published private(set) var revision = 0

    private let key = "palmdeck_widgets_v10"
    private let tplKey = "palmdeck_layout_templates_v1"
    private let undoKey = "palmdeck_layout_undo_v1"

    init() {
        load()
        loadTemplates()
        loadUndo()
        // 只在「从未存过该模式」时播种内置默认。
        // 用 == nil（而不是 isEmpty），否则用户主动「清空」的空白布局会在重启后被默认布局覆盖。
        //
        // 只播种 .gamepad：heli/drive 在 P4/P5 之后走固定硬件皮肤，
        // 全仓库唯一的 WidgetCanvas 在 CockpitView 的 gamepad 分支里，
        // 给它们播种等于往 UserDefaults 写一份永远没人读的数据。
        if layouts[CockpitMode.gamepad.rawValue] == nil {
            layouts[CockpitMode.gamepad.rawValue] = LayoutStore.defaultGamepad()
        }
    }

    func widgets(mode: CockpitMode) -> [DeckWidget] { layouts[mode.rawValue] ?? [] }

    private func setWidgets(_ list: [DeckWidget], mode: CockpitMode) {
        layouts[mode.rawValue] = list
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

    func clear(mode: CockpitMode) {
        pushUndo(mode: mode)
        replaceWidgets([], mode: mode)
    }

    func reset(mode: CockpitMode) {
        pushUndo(mode: mode)
        replaceWidgets(LayoutStore.defaults(mode: mode), mode: mode)
    }

    /// 整表替换：落盘 + 通知画布重建。
    /// 仅用于 clear / reset / 应用模板 / 撤销——**不得**用于拖拽保存（`update`），
    /// 否则拖动中画布会被重建，手势直接断掉。
    private func replaceWidgets(_ list: [DeckWidget], mode: CockpitMode) {
        layouts[mode.rawValue] = list
        save()
        revision &+= 1
    }

    // MARK: - 布局模板（本地）

    /// 全部模板（内置「默认」永远排第一）。
    func templates(mode: CockpitMode) -> [LayoutTemplate] {
        [LayoutTemplate(name: LayoutStore.builtinName, widgets: LayoutStore.defaults(mode: mode))]
            + (templatesByMode[mode.rawValue] ?? [])
    }

    /// 用户自建模板（不含内置）——滑动删除/重命名只对它生效。
    func customTemplates(mode: CockpitMode) -> [LayoutTemplate] {
        templatesByMode[mode.rawValue] ?? []
    }

    func isBuiltin(_ tpl: LayoutTemplate) -> Bool { tpl.name == LayoutStore.builtinName }

    /// 模板内容是否等于当前布局。
    ///
    /// **不能直接 `==`**：`DeckWidget.make`（`Widgets.swift:76`）每次都生成新 `UUID`，
    /// 而 `Equatable` 是合成实现、含 `id`——内置默认布局回回重建都是新 id，永远比不等。
    /// 所以只比“形状”：kind / binding / rect / label（顺序敏感）。
    func isCurrent(_ tpl: LayoutTemplate, mode: CockpitMode) -> Bool {
        let cur = widgets(mode: mode)
        guard cur.count == tpl.widgets.count else { return false }
        return zip(cur, tpl.widgets).allSatisfy { a, b in
            a.kind == b.kind && a.binding == b.binding && a.rect == b.rect && a.label == b.label
        }
    }

    /// 存为模板（快照当前布局）。重名覆盖。返回错误文案，nil = 成功。
    @discardableResult
    func saveTemplate(name raw: String, mode: CockpitMode) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let err = LayoutStore.validate(name: name) { return err }
        var list = customTemplates(mode: mode)
        let tpl = LayoutTemplate(name: name, widgets: widgets(mode: mode))
        if let i = list.firstIndex(where: { $0.name == name }) {
            list[i] = tpl                                   // 覆盖
        } else {
            guard list.count < LayoutStore.maxTemplates else {
                return "最多 \(LayoutStore.maxTemplates) 个模板，请先删掉一个"
            }
            list.append(tpl)
        }
        templatesByMode[mode.rawValue] = list
        saveTemplates()
        return nil
    }

    @discardableResult
    func renameTemplate(_ old: String, to raw: String, mode: CockpitMode) -> String? {
        let new = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let err = LayoutStore.validate(name: new) { return err }
        var list = customTemplates(mode: mode)
        guard let i = list.firstIndex(where: { $0.name == old }) else { return "模板不存在" }
        if new != old, list.contains(where: { $0.name == new }) { return "已有同名模板" }
        list[i].name = new
        templatesByMode[mode.rawValue] = list
        saveTemplates()
        return nil
    }

    func deleteTemplate(_ name: String, mode: CockpitMode) {
        var list = customTemplates(mode: mode)
        list.removeAll { $0.name == name }
        templatesByMode[mode.rawValue] = list
        saveTemplates()
    }

    /// 应用模板（应用前先压撤销槽）。
    func applyTemplate(_ tpl: LayoutTemplate, mode: CockpitMode) {
        pushUndo(mode: mode)
        replaceWidgets(tpl.widgets, mode: mode)
    }

    private static func validate(name: String) -> String? {
        if name.isEmpty { return "名称不能为空" }
        if name.count > maxNameLength { return "名称最多 \(maxNameLength) 个字符" }
        if name == builtinName { return "「\(builtinName)」是内置模板，换个名字" }
        return nil
    }

    // MARK: - 撤销（单格 / 按模式）

    func canUndo(mode: CockpitMode) -> Bool { undoSlots[mode.rawValue] != nil }

    func undoLast(mode: CockpitMode) {
        guard let prev = undoSlots[mode.rawValue] else { return }
        undoSlots[mode.rawValue] = nil
        saveUndo()
        replaceWidgets(prev, mode: mode)
    }

    private func pushUndo(mode: CockpitMode) {
        undoSlots[mode.rawValue] = widgets(mode: mode)
        saveUndo()
    }

    private func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: tplKey),
              let obj = try? JSONDecoder().decode([String: [LayoutTemplate]].self, from: data) else { return }
        templatesByMode = obj
    }

    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(templatesByMode) {
            UserDefaults.standard.set(data, forKey: tplKey)
        }
    }

    private func loadUndo() {
        guard let data = UserDefaults.standard.data(forKey: undoKey),
              let obj = try? JSONDecoder().decode([String: [DeckWidget]].self, from: data) else { return }
        undoSlots = obj
    }

    private func saveUndo() {
        if let data = try? JSONEncoder().encode(undoSlots) {
            UserDefaults.standard.set(data, forKey: undoKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let obj = try? JSONDecoder().decode([String: [DeckWidget]].self, from: data) else { return }
        layouts = obj
    }

    func save() {
        if let data = try? JSONEncoder().encode(layouts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - 与电脑同步（v4 P3）
    /// 服务端下发的布局（`{"heli": [widget...], ...}`）。
    func applyServer(raw: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode([String: [DeckWidget]].self, from: data) else { return }
        var changed = false
        for (k, v) in decoded where CockpitMode(rawValue: k) != nil {
            layouts[k] = v
            changed = true
        }
        guard changed else { return }
        save()
        syncMessage = "已同步电脑布局"
    }

    /// 把当前模式的布局回传到电脑。
    func upload(mode: CockpitMode, via ctrl: CockpitController) {
        guard let data = try? JSONEncoder().encode(widgets(mode: mode)),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        ctrl.sendLayoutPut(mode: mode.rawValue, layout: arr)
        syncMessage = "已上传到电脑"
    }

    // MARK: 默认布局

    /// 只有手柄模式会渲染组件画布（`CockpitView` 的 `gamepadBody`），
    /// 其余模式返回空数组。
    ///
    /// v3 时期 heli/drive 各有一套精细的滑块/按键布局，P4/P5 换成固定硬件皮肤后
    /// 就没有任何渲染路径了；数据留在 git 历史里（`git show <v0.3.2>:.../Layout.swift`），
    /// 不再放进二进制，免得和皮肤里的控件重复两套真相。
    static func defaults(mode: CockpitMode) -> [DeckWidget] {
        switch mode {
        case .gamepad: return defaultGamepad()
        case .heli, .drive: return []
        }
    }

    /// 游戏手柄皮肤默认布局（P4 会再细化外观，这里先给出可用控件集）。
    static func defaultGamepad() -> [DeckWidget] {
        [
            .make(.stick,  .roll,     .r(0.05, 0.30, 0.20, 0.34), label: "左摇杆"),
            .make(.pad,    .look,     .r(0.75, 0.30, 0.20, 0.34), label: "右摇杆"),
            .make(.slider, .brake,    .r(0.29, 0.70, 0.18, 0.13), label: "LT"),
            .make(.slider, .throttle, .r(0.51, 0.70, 0.18, 0.13), label: "RT"),
            .make(.button, .vjoy1,    .r(0.74, 0.70, 0.10, 0.10), label: "A"),
            .make(.button, .vjoy2,    .r(0.855, 0.70, 0.10, 0.10), label: "B"),
            .make(.button, .vjoy3,    .r(0.74, 0.82, 0.10, 0.10), label: "X"),
            .make(.button, .vjoy4,    .r(0.855, 0.82, 0.10, 0.10), label: "Y"),
            .make(.button, .gearUp,   .r(0.04, 0.70, 0.11, 0.09), label: "LB"),
            .make(.button, .gearDown, .r(0.16, 0.70, 0.11, 0.09), label: "RB"),
            .make(.button, .vjoy7,    .r(0.04, 0.82, 0.11, 0.09), label: "视图"),
            .make(.button, .vjoy8,    .r(0.16, 0.82, 0.11, 0.09), label: "菜单"),
            .make(.button, .fire,     .r(0.30, 0.85, 0.12, 0.09), label: "开火"),
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
