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
///
/// 命名快照（“我摆好的一套”）已不分居两处：**统一走 `GameProfileStore`**
/// （整机预设 / 布局预设 / 内置「默认」），见 `docs/PalmDeck-v4-unified-presets.md`。
/// 本类只负责：当前布局、组件增删改、还原点、撤销槽、对齐线、与电脑同步。
final class LayoutStore: ObservableObject {
    @Published var editing = false {
        didSet { if !editing { clearGuides() } }   // 退出编辑别留一条线
    }
    /// 拖动中要显示的对齐线（归一化坐标；空 = 不显示）。**不落盘**，只是一帧的提示。
    @Published private(set) var guidesX: [Double] = []
    @Published private(set) var guidesY: [Double] = []
    /// 各模式组件列表（key = `CockpitMode.rawValue`）
    @Published private var layouts: [String: [DeckWidget]] = [:]
    /// 与电脑同步的状态提示（设置页显示）
    @Published var syncMessage = ""
    /// 撤销槽（单格 / 按模式）：破坏性操作前压入
    @Published private(set) var undoSlots: [String: [DeckWidget]] = [:]
    /// 整表替换计数。画布用 `.id(revision)` 强制重建，
    /// 否则 `EditableWidget` 的 `@State dragStart` 会残留到新布局上。
    @Published private(set) var revision = 0

    private let key = "palmdeck_widgets_v10"
    private let undoKey = "palmdeck_layout_undo_v1"

    init() {
        load()
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

    /// 拖动中的对齐线。值没变就不发布（同 §12.8：没变就别惊动整棵视图树）。
    func setGuides(x: Double?, y: Double?) {
        let nx = x.map { [$0] } ?? []
        let ny = y.map { [$0] } ?? []
        if guidesX != nx { guidesX = nx }
        if guidesY != ny { guidesY = ny }
    }

    func clearGuides() {
        if !guidesX.isEmpty { guidesX = [] }
        if !guidesY.isEmpty { guidesY = [] }
    }

    private func setWidgets(_ list: [DeckWidget], mode: CockpitMode) {
        layouts[mode.rawValue] = list
        save()
    }

    func add(kind: WidgetKind, binding: WidgetBinding, mode: CockpitMode) {
        // 压一道撤销槽：误点「添加」、误点 ✕ 都该能退回来
        //（✕ 只有 22pt，而且就在抓组件拖拽时手会按到的角上）
        pushUndo(mode: mode)
        // 新组件放在中间偏下，尺寸按类型
        let size: WRect
        switch kind {
        case .wheel:  size = .r(0.30, 0.30, 0.30, 0.45)
        case .slider: size = .r(0.35, 0.40, 0.30, 0.12)
        case .pad:    size = .r(0.35, 0.35, 0.20, 0.28)
        case .button: size = .r(0.40, 0.45, 0.12, 0.12)
        case .stick:  size = .r(0.38, 0.35, 0.18, 0.30)
        case .collective: size = .r(0.06, 0.30, 0.24, 0.40)
        case .hat:    size = .r(0.40, 0.35, 0.12, 0.20)
        case .attitude: size = .r(0.40, 0.10, 0.22, 0.34)
        case .panel:  size = .r(0.30, 0.28, 0.40, 0.28)
        }
        var list = widgets(mode: mode)
        list.append(.make(kind, binding, size))
        setWidgets(list, mode: mode)
    }

    func remove(id: String, mode: CockpitMode) {
        pushUndo(mode: mode)
        setWidgets(widgets(mode: mode).filter { $0.id != id }, mode: mode)
    }

    /// 拖动 / 改名用。**高频调用，不得压撤销槽**（会打断手势），也不得递增 `revision`。

    func update(_ w: DeckWidget, mode: CockpitMode) {
        var list = widgets(mode: mode)
        if let i = list.firstIndex(where: { $0.id == w.id }) { list[i] = w; setWidgets(list, mode: mode) }
    }

    func clear(mode: CockpitMode) {
        pushUndo(mode: mode)
        replaceWidgets([], mode: mode)
    }

    /// 整表替换：落盘 + 通知画布重建。
    /// 仅用于 clear / applyDefault / 应用预设布局 / 撤销——**不得**用于拖拽保存（`update`），
    /// 否则拖动中画布会被重建，手势直接断掉。
    private func replaceWidgets(_ list: [DeckWidget], mode: CockpitMode) {
        layouts[mode.rawValue] = list
        save()
        revision &+= 1
    }

    // MARK: - 还原点与「当前」判定（命名快照本身在 `GameProfileStore`）

    /// 内置还原点名（= 预设列表里那一行只读的「默认」）。
    static var builtinName: String { GameProfileBuiltin.reservedLayoutName }

    /// 「遥控器双杆（Mode 2）」内置还原点名（预设列表里那一行只读的内置布局）。
    static var rcMode2Name: String { "遥控器双杆" }

    /// 把该模式铺回出厂布局（应用前先压撤销槽），= 应用内置「默认」预设。
    func applyDefault(mode: CockpitMode) {
        pushUndo(mode: mode)
        replaceWidgets(LayoutStore.defaults(mode: mode), mode: mode)
    }

    /// 当前布局是否就是出厂默认。
    func isCurrentDefault(mode: CockpitMode) -> Bool {
        sameShape(widgets(mode: mode), LayoutStore.defaults(mode: mode))
    }

    /// 把该模式铺成「遥控器双杆（Mode 2）」内置布局（应用前先压撤销槽）。
    func applyRCMode2(mode: CockpitMode) {
        pushUndo(mode: mode)
        replaceWidgets(LayoutStore.defaultRCMode2(), mode: mode)
    }

    /// 当前布局是否就是「遥控器双杆」。
    func isCurrentRCMode2(mode: CockpitMode) -> Bool {
        sameShape(widgets(mode: mode), LayoutStore.defaultRCMode2())
    }

    /// 当前布局是否等于某个预设带的布局（解码失败 = 不相等）。
    func isCurrentLayout(_ widgetsJSON: Data?, mode: CockpitMode) -> Bool {
        guard let data = widgetsJSON,
              let list = try? JSONDecoder().decode([DeckWidget].self, from: data),
              !list.isEmpty else { return false }
        return sameShape(widgets(mode: mode), list)
    }

    /// 某个预设带的组件数（列表里显示「N 个组件」用）。
    func widgetCount(_ widgetsJSON: Data?) -> Int {
        guard let data = widgetsJSON,
              let list = try? JSONDecoder().decode([DeckWidget].self, from: data) else { return 0 }
        return list.count
    }

    /// 当前模式的组件数。
    func widgetCount(mode: CockpitMode) -> Int { widgets(mode: mode).count }

    /// 只比“形状”（kind / binding / rect / label，顺序敏感），忽略每次重建都变的 UUID。
    func sameShape(_ a: [DeckWidget], _ b: [DeckWidget]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.kind == $1.kind && $0.binding == $1.binding && $0.rect == $1.rect && $0.label == $1.label
        }
    }

    // MARK: - 游戏预设（G2）

    /// 预设携带的布局：**整表替换**，落盘 + `revision++`（同 `replaceWidgets` 的语义）。
    ///
    /// 接收**编码后的 JSON** 而不是 `[DeckWidget]`，因为 `GameProfile` 是纯类型
    /// （见 `Model/GameProfile.swift`）；解码在这一层做。
    ///
    /// **预设不带布局时绝不碰用户布局**（`widgetsJSON == nil` / 空表 / 坏数据都算“不带”）。
    /// 内置的 WARDOGS / 欧洲卡车模拟就是这种情况（见 `docs/PalmDeck-v4-game-profiles.md` §3.6），
    /// 它们的价值是“手感快照”，不该顺手把用户摆好的画布擦掉 ——
    /// 早期版本把 `nil` 当空数组整表替换，症状就是「选任意预设 → 面板变白板」。
    ///
    /// 唯一例外：该模式**当前就是空表**（用户清空过，或踩过上面那个坑），
    /// 那就铺回该模式的默认模块 —— 预设的承诺是“给我一套能用的”，不是“给我一块白板”。
    func applyProfile(widgetsJSON: Data?, mode: CockpitMode) {
        let provided = widgetsJSON.flatMap {
            try? JSONDecoder().decode([DeckWidget].self, from: $0)
        }
        let target: [DeckWidget]?
        if let list = provided, !list.isEmpty {
            target = list                                          // 预设自带布局
        } else if widgets(mode: mode).isEmpty {
            target = LayoutStore.defaults(mode: mode)               // 不带布局 + 当前空表
        } else {
            target = nil                                            // 不带布局 + 用户已有布局 → 不碰
        }
        guard let list = target else { return }
        pushUndo(mode: mode)
        replaceWidgets(list, mode: mode)
    }

    /// 把当前模式的布局编成 JSON，塞进新建的预设里（「快照当前状态」用）。
    func snapshotWidgetsJSON(mode: CockpitMode) -> Data? {
        let list = widgets(mode: mode)
        guard !list.isEmpty else { return nil }
        return try? JSONEncoder().encode(list)
    }

    // MARK: - 编辑会话（「放弃」的回滚点）

    /// 进入编辑那一刻的布局快照，按模式一份、只存内存。
    /// 「完成」丢掉它，「放弃」整表回滚到它。
    private var editBaseline: [String: [DeckWidget]] = [:]

    /// 进入编辑：记下当前布局，作为「放弃」的回滚点。
    func beginEditing(mode: CockpitMode) {
        editBaseline[mode.rawValue] = widgets(mode: mode)
    }

    /// 进编辑后真的改过东西吗？（没改就不该让「放弃」可点）
    func canDiscardEditing(mode: CockpitMode) -> Bool {
        guard let base = editBaseline[mode.rawValue] else { return false }
        return !sameShape(base, widgets(mode: mode))
    }

    /// 放弃本次编辑：整表回滚到进入编辑前。
    /// 不进撤销槽——「放弃」本身就是一次回退，再叠一层「撤销放弃」只会绕。
    func discardEditing(mode: CockpitMode) {
        guard let base = editBaseline[mode.rawValue] else { return }
        editBaseline[mode.rawValue] = nil
        replaceWidgets(base, mode: mode)
    }

    /// 完成编辑：改动保留，只丢掉回滚点。
    func commitEditing(mode: CockpitMode) {
        editBaseline[mode.rawValue] = nil
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

    /// 游戏手柄默认布局（Xbox 式的起步布局；可自由改）。
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

    /// 飞机默认布局（**只有轴 + 只读仪表盘，没有任何按键**）。
    ///
    /// 按键完全由用户自己添加、命名——“开火/投弹/起落架”这些语义
    /// 在竞品之间并不通用，硬编码进去只会闦用户。
    /// 仪表盘（`panel`）是只读显示，不携带任何游戏语义，所以默认留下。
    static func defaultHeli() -> [DeckWidget] {
        [
            // 仪表盘：COLL/TRQ 弧表 + 姿态球 + ROL/PIT/YAW 条（只读）
            // y 从 0.10 起：顶部留白（原来是为了躲未连接横幅，横幅改成占位后不再是必需，
            // 但保留此值 —— 老用户本地存的就是它，新装跟着一致）
            .make(.panel,  .roll,     .r(0.37, 0.10, 0.49, 0.38), label: "仪表盘"),
            // 总距杆：单极，写 throttle
            .make(.slider, .throttle, .r(0.02, 0.10, 0.10, 0.78), label: "总距"),
            // 脚舵：双极，写 yaw
            .make(.slider, .yaw,      .r(0.14, 0.10, 0.21, 0.24), label: "脚舵"),
            // 周期变距杆：2D，写 roll + pitch
            .make(.stick,  .roll,     .r(0.14, 0.38, 0.21, 0.50), label: "周期杆"),
            // 视角：触摸板，写 lookX/lookY
            .make(.pad,    .look,     .r(0.60, 0.54, 0.26, 0.34), label: "视角"),
        ]
    }

    /// 遥控器双杆（Mode 2）内置布局：左杆 = 总距 + 尾桨，右杆 = 副翼 + 升降。
    ///
    /// 给有航模遥控器肌肉记忆的玩家（WARDOGS / 无人机模拟）。
    /// **不改**飞机出厂布局（那仍是「真机座舱手」的 `defaultHeli()`）——这是一份可选还原点。
    /// 左杆的 Y 是**保持型**（渲染时 `centerY: false`），对位遥控器左杆：尾桨松手回中、总距不动。
    static func defaultRCMode2() -> [DeckWidget] {
        [
            // 左杆：X = 尾桨（回中），Y = 总距（单极，松手保持）
            .make(.collective, .yaw,  .r(0.03, 0.20, 0.32, 0.56), label: "总距/尾桨"),
            // 右杆：副翼 + 升降
            .make(.stick,      .roll, .r(0.42, 0.28, 0.28, 0.50), label: "副翼/升降"),
            // 视角：触摸板，写 lookX/lookY
            .make(.pad,        .look, .r(0.78, 0.10, 0.18, 0.26), label: "视角"),
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
                // 吸附对齐线：只在真吸上时出现（那条边就是信息本身）
                ForEach(store.guidesX.indices, id: \.self) { i in
                    vGuide(store.guidesX[i] * W, W: W, H: H)
                }
                ForEach(store.guidesY.indices, id: \.self) { i in
                    hGuide(store.guidesY[i] * H, W: W, H: H)
                }
                emptyHint
            }
        }
    }

    /// 竖向对齐线（1pt，贯穿画布）。不提交互：它只是个提示。
    private func vGuide(_ x: Double, W: Double, H: Double) -> some View {
        Rectangle().fill(Theme.cyan.opacity(0.85))
            .frame(width: 1, height: H)
            .frame(width: W, height: H, alignment: .topLeading)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    /// 横向对齐线
    private func hGuide(_ y: Double, W: Double, H: Double) -> some View {
        Rectangle().fill(Theme.cyan.opacity(0.85))
            .frame(width: W, height: 1)
            .frame(width: W, height: H, alignment: .topLeading)
            .offset(y: y)
            .allowsHitTesting(false)
    }

    /// 空画布提示。
    /// 原来清空 / 拖走最后一个组件后就是一块白板，看不出「本来就空」还是「没加载出来」。
    /// 不提交互：不抢手势（`allowsHitTesting(false)`）。
    @ViewBuilder
    private var emptyHint: some View {
        if store.widgets(mode: mode).isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "square.dashed")
                    .pdFont(30, weight: .light)
                Text("画布是空的")
                    .pdFont(13, weight: .semibold)
                Text(store.editing
                     ? "点上方「添加：」放一个组件；拖动移动、拖右下角缩放、✕ 删除"
                     : "点顶栏「布局」开始添加，或进「⋯」恢复默认布局")
                    .pdFont(11)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(Theme.textFaint)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
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

    /// 拖动落点 = 起点 + 位移 → 吸附（吸边/中线）→ 夹取（至少留 40pt 在画布里）。
    /// 规则全在 `Snap`（纯函数、有 swiftc 单测），这里只做坐标换算与接线。
    /// `others` 必须排除自己，否则会被自己吸住、怎么拖都不动。
    private func dragOutcome(from st: WRect, translation: CGSize,
                             W: Double, H: Double) -> Snap.Outcome {
        Snap.drag(Snap.Rect(x: st.x + translation.width / W,
                            y: st.y + translation.height / H,
                            w: st.w, h: st.h),
                  others: store.widgets(mode: mode)
                      .filter { $0.id != widget.id }
                      .map { Snap.Rect(x: $0.rect.x, y: $0.rect.y,
                                       w: $0.rect.w, h: $0.rect.h) },
                  canvas: (w: W, h: H))
    }

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
                        // 必须用 .global：组件自己会跟着手指跑，而在 .local（手势视图自己的坐标空间）
                        // 里量位移，视图一动、同一根手指的位移就被抵消掉一半 ——
                        // 表现就是「组件总追不上手指」（跟到一半就不动了）。缩放把手同理。
                        DragGesture(coordinateSpace: .global)
                            .onChanged { g in
                                if dragStart == nil { dragStart = r }
                                guard let st = dragStart else { return }
                                let o = dragOutcome(from: st, translation: g.translation, W: W, H: H)
                                var nw = widget
                                nw.rect = WRect(x: o.rect.x, y: o.rect.y, w: o.rect.w, h: o.rect.h)
                                store.update(nw, mode: mode)
                                store.setGuides(x: o.guideX, y: o.guideY)
                            }
                            .onEnded { _ in
                                dragStart = nil
                                store.clearGuides()
                            }
                    )
                // 缩放
                Circle().fill(Theme.cyan)
                    .overlay(Circle().stroke(Theme.onAccent, lineWidth: 2))
                    .frame(width: 24, height: 24)
                    .offset(x: pw / 2 - 12, y: ph / 2 - 12)
                    .gesture(
                        DragGesture(coordinateSpace: .global)
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
                        .pdFont(11, weight: .bold)
                        .foregroundColor(Theme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.red))
                }
                .accessibilityLabel("删除组件")
                .offset(x: -pw / 2 + 12, y: -ph / 2 + 12)
                // 重命名：名称留给用户（按键就是个序号，含义由用户在游戏里绑）
                Button {
                    nameDraft = widget.title
                    renaming = true
                } label: {
                    Image(systemName: "character")
                        .pdFont(11, weight: .bold)
                        .foregroundColor(Theme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.orange))
                }
                .accessibilityLabel("重命名组件")
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
