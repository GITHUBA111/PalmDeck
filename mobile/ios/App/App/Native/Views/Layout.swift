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
        // 播种 .gamepad / .heli / .drive：三个模式都能切到「自定义模块布局」
        // （`CockpitView.moduleBody`）。
        if layouts[CockpitMode.gamepad.rawValue] == nil {
            layouts[CockpitMode.gamepad.rawValue] = LayoutStore.defaultGamepad()
        }
        if layouts[CockpitMode.heli.rawValue] == nil {
            layouts[CockpitMode.heli.rawValue] = LayoutStore.defaultHeli()
        }
        if layouts[CockpitMode.drive.rawValue] == nil {
            layouts[CockpitMode.drive.rawValue] = LayoutStore.defaultDrive()
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

    // MARK: - 游戏预设（G2）

    /// 预设自带布局整表替换：落盘 + `revision++`（同 `applyTemplate` 的语义）。
    ///
    /// 接收**编码后的 JSON** 而不是 `[DeckWidget]`，因为 `GameProfile` 是纯类型
    /// （见 `Model/GameProfile.swift`）；解码在这一层做，坏数据退化成空布局。
    /// 也压撤销槽 —— 切预设是一次整表替换，用户可能想退回上一套布局。
    func applyProfile(widgetsJSON: Data?, mode: CockpitMode) {
        pushUndo(mode: mode)
        let list: [DeckWidget] = widgetsJSON.flatMap {
            try? JSONDecoder().decode([DeckWidget].self, from: $0)
        } ?? []
        replaceWidgets(list, mode: mode)
    }

    /// 把当前模式的布局编成 JSON，塞进新建的预设里（「快照当前状态」用）。
    func snapshotWidgetsJSON(mode: CockpitMode) -> Data? {
        let list = widgets(mode: mode)
        guard !list.isEmpty else { return nil }
        return try? JSONEncoder().encode(list)
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

    static func defaults(mode: CockpitMode) -> [DeckWidget] {
        switch mode {
        case .gamepad: return defaultGamepad()
        case .heli:    return defaultHeli()
        case .drive:   return defaultDrive()
        }
    }

    /// 游戏手柄皮肤默认布局（P4 会再细化外观，这里先给出可用控件集）。
    static func defaultGamepad() -> [DeckWidget] {
        [
            .make(.stick,  .roll,     .r(0.05, 0.30, 0.20, 0.34), label: "左摇杆"),
            .make(.pad,    .look,     .r(0.75, 0.30, 0.20, 0.34), label: "右摇杆"),
            .make(.slider, .brake,    .r(0.29, 0.70, 0.18, 0.13), label: "LT"),
            .make(.slider, .rt,       .r(0.51, 0.70, 0.18, 0.13), label: "RT"),
            .make(.button, .vjoy1,    .r(0.74, 0.70, 0.10, 0.10), label: "A"),
            .make(.button, .vjoy2,    .r(0.855, 0.70, 0.10, 0.10), label: "B"),
            .make(.button, .vjoy3,    .r(0.74, 0.82, 0.10, 0.10), label: "X"),
            .make(.button, .vjoy4,    .r(0.855, 0.82, 0.10, 0.10), label: "Y"),
            // gearUp → pulse(5) → b6 → X360["b6"] = RIGHT_SHOULDER = RB
            // gearDown → pulse(4) → b5 → X360["b5"] = LEFT_SHOULDER = LB
            .make(.button, .gearUp,   .r(0.04, 0.70, 0.11, 0.09), label: "RB"),
            .make(.button, .gearDown, .r(0.16, 0.70, 0.11, 0.09), label: "LB"),
            .make(.button, .vjoy7,    .r(0.04, 0.82, 0.11, 0.09), label: "视图"),
            .make(.button, .vjoy8,    .r(0.16, 0.82, 0.11, 0.09), label: "菜单"),
            .make(.button, .fire,     .r(0.30, 0.85, 0.12, 0.09), label: "开火"),
        ]
    }

    /// 飞机默认布局（**只有轴，没有任何按键**）。
    ///
    /// 按键完全由用户自己添加、命名——“开火/投弹/起落架”这些语义
    /// 在竞品之间并不通用，硬编码进去只会闦用户。
    static func defaultHeli() -> [DeckWidget] {
        [
            // 周期变距杆：2D，写 roll + pitch
            .make(.stick,  .roll,     .r(0.06, 0.34, 0.26, 0.44), label: "周期杆"),
            // 总距杆：单极，写 throttle
            .make(.slider, .throttle, .r(0.36, 0.16, 0.14, 0.62), label: "总距"),
            // 脚舵：双极，写 yaw
            .make(.slider, .yaw,      .r(0.54, 0.34, 0.16, 0.44), label: "脚舵"),
            // 视角：触摸板，写 lookX/lookY
            .make(.pad,    .look,     .r(0.78, 0.34, 0.18, 0.44), label: "视角"),
        ]
    }

    /// 开车默认布局（**只有轴，没有任何按键**）。
    ///
    /// 之前误把「升/降档」等按键固定成 LB/RB，结果和欧卡2 默认的
    /// “向左/右看”（同样是 LB/RB）撞车——降档会连带切镜头。
    /// 所以现在开车默认只给方向盘/三踏板/视角，换档键由用户在游戏里自己绑。
    static func defaultDrive() -> [DeckWidget] {
        [
            .make(.wheel,  .roll,     .r(0.05, 0.10, 0.48, 0.52), label: "方向盘"),
            .make(.pad,    .look,     .r(0.82, 0.10, 0.14, 0.24), label: "视角"),
            .make(.slider, .clutch,   .r(0.06, 0.66, 0.20, 0.30), label: "离合"),
            .make(.slider, .brake,    .r(0.28, 0.66, 0.20, 0.30), label: "刹车"),
            .make(.slider, .throttle, .r(0.50, 0.66, 0.20, 0.30), label: "油门"),
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
    @State private var renaming = false
    @State private var nameDraft = ""

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
                // 重命名：名称留给用户（按键就是个序号，含义由用户在游戏里绑）
                Button {
                    nameDraft = widget.title
                    renaming = true
                } label: {
                    Image(systemName: "character")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.orange))
                }
                .offset(x: pw / 2 - 12, y: -ph / 2 + 12)
            }
        }
        .frame(width: pw, height: ph)
        .position(x: px + pw / 2, y: py + ph / 2)
        .alert("重命名组件", isPresented: $renaming) {
            TextField("名称", text: $nameDraft)
                .onChange(of: nameDraft) { v in
                    if v.count > 12 { nameDraft = String(v.prefix(12)) }
                }
            Button("取消", role: .cancel) { }
            Button("确定") {
                var nw = widget
                nw.label = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                store.update(nw, mode: mode)
                Haptics.success()
            }
        } message: {
            Text("留空则恢复默认（如「按钮 3」）。名称只存本机，不影响发出去的键位。")
        }
    }
}
