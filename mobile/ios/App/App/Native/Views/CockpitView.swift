import SwiftUI

struct CockpitView: View {
    @ObservedObject var ctrl: CockpitController
    @ObservedObject var s: ControllerState
    @StateObject private var discovery = Discovery()
    @State private var showSettings = false
    @StateObject private var layout = LayoutStore()
    @StateObject private var profiles = GameProfileStore()
    /// 点开组件库弹窗的那个组件类型；nil = 弹窗关闭。
    /// 用 `.sheet(item:)`：把类型当成弹窗的输入，避免「先改 state 再 isPresented」拿到旧值。
    @State private var libraryKind: WidgetKind?
    @State private var showTutorial = false
    @State private var savingPreset = false
    @State private var presetName = ""
    /// 编辑条上「存为预设」的结果回执（成功/失败都说话）。空字符串=不显示。
    @State private var presetNote = ""
    /// 已连接时点另一个模式：先弹确认（换模式=电脑端换后端，游戏里手柄会掉一下）。
    @State private var pendingMode: CockpitMode?
    var onExit: () -> Void = {}
    private var stripH: CGFloat { 28 }   // 底部仪表条高度
    /// 画布上方那一行（连接横幅）的固定高度：
    /// 连接状态怎么变都不改它，`WidgetCanvas` 的高度就不变，组件不会被「顶」得重排。
    private let deckTopRowH: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let topH: CGFloat = 42
            let gap: CGFloat = 8
            let bodyH = H - topH - stripH - gap * 2

            VStack(spacing: gap) {
                topBar(height: topH)
                deckBody(W: W, H: bodyH)
                statusStrip
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: W, height: H, alignment: .top)
            // 座舱是固定横排 HUD：字号收到 `.xxLarge`，不至于把顶栏 / 状态条 / 编辑条挤裂。
            // 设置 / 首启 / 速览是文字为主、可滚动，各自用 `.palmDynamicType()` 放开。
            .palmCockpitType()
        }
        .background(CockpitBackdrop())
        .palmAppearance()
        .sheet(item: $libraryKind) { kind in
            LibrarySheet(store: layout, mode: s.mode, initialKind: kind)
        }
        .fullScreenCover(isPresented: $showTutorial) {
            CockpitTutorialView()
        }
        .onAppear {
            discovery.start()
            // 电脑端下发布局 → 写入 LayoutStore。
            // 先落到局部变量再弱引用：直接写 [weak layout] 会同时把 self 强引用起来
            // （闭包里的 discovery / showSettings 等），Swift 会报
            // “'weak' ownership of capture 'layout' differs from implicitly-captured strong reference”。
            let store = layout
            ctrl.onLayouts = { [weak store] raw in store?.applyServer(raw: raw) }            // 首次进入座舱自动弹一次速览（可在设置里重新打开）；延迟一帧确保能正常弹出
            if !UserDefaults.standard.bool(forKey: "palmdeck_tutored") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showTutorial = true }
            }
        }
        .onDisappear { discovery.stop() }
    }

    /// 库按钮：带绑定的直接加；滑条/按键弹选择（弹窗从被点的类型开始）
    private func libraryButton(_ title: String, _ kind: WidgetKind, _ defaultBinding: WidgetBinding?) -> some View {
        Button(title) {
            if let b = defaultBinding {
                layout.add(kind: kind, binding: b, mode: s.mode)
            } else {
                libraryKind = kind
            }
        }
        .buttonStyle(CardButton(fillWidth: false, height: 28))
    }

    // MARK: 底部仪表条
    /// 轴那几格由 `HudReadout` 按模式给（吃的就是 `s.wireAxes`：真正发出去的值）。
    /// 以前三个模式都写死 ROL/PIT/YAW/THR，开车模式明明不发 Rz 也在显示「方向」。
    private var statusStrip: some View {
        let cells = HudReadout.axis(mode: s.mode, out: s.wireAxes)
        return HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { i in
                if i > 0 { divider }
                HudCell(label: cells[i].label, value: cells[i].value,
                        accent: cells[i].tone == .active ? Theme.cyan : Theme.textDim)
            }
            divider
            HudCell(label: "链路", value: s.link == .live ? String(format: "%.0fHz", s.hz) : linkShort,
                    accent: s.link == .live ? Theme.green : (s.link == .connecting ? Theme.orange : Theme.textFaint))
            Spacer(minLength: 0)
            HudCell(label: "模式", value: s.mode.label, accent: Theme.cyan)
            divider
            HudCell(label: "通道", value: s.transport == "idle" ? "—" : s.transport.uppercased(),
                    accent: s.transport == "udp" ? Theme.green : (s.transport == "ws" ? Theme.cyan : Theme.textDim))
        }
        .frame(height: stripH)
        .padding(.horizontal, 10)
        .hudPanel(corner: 8, accent: Theme.cyan.opacity(0.5))
    }

    private var divider: some View {
        Rectangle().fill(Theme.border.opacity(0.5)).frame(width: 1, height: 14).padding(.horizontal, 5)
    }

    private var linkShort: String {
        switch s.link {
        case .live: return "在线"
        case .connecting: return "连接中"
        case .lost: return "断线"
        case .idle: return "未连"
        }
    }

    // MARK: 顶部
    private func topBar(height: CGFloat) -> some View {
        ZStack {
            // 居中：模式开关（贴顶）
            HStack(spacing: 6) {
                ForEach(CockpitMode.allCases, id: \.self) { m in
                    Button(m.label) { requestMode(m) }
                        .buttonStyle(CardButton(active: s.mode == m, accent: Theme.cyan, height: height))
                        .frame(width: 68)
                }
            }
            // 右侧：连接状态 + 齿轮 + 编辑
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                connectionChip(height: height)
                Button { showSettings = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill").pdFont(13)
                        Text("设置").pdFont(11, weight: .medium)
                    }
                }
                .buttonStyle(CardButton(fillWidth: false, height: height))
                .frame(width: 64)
                Button {
                    if layout.editing { layout.commitEditing(mode: s.mode) }
                    else { layout.beginEditing(mode: s.mode) }
                    layout.editing.toggle()
                    Haptics.press()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: layout.editing ? "checkmark.circle.fill" : "square.grid.2x2")
                            .pdFont(13)
                        Text(layout.editing ? "完成" : "布局")
                            .pdFont(11, weight: .medium)
                    }
                }
                .buttonStyle(CardButton(active: layout.editing, accent: Theme.orange, fillWidth: false, height: height))
                .frame(width: 64)
                .padding(.leading, 4)
            }
        }
        .frame(height: height)
        .alert("切换到「\(pendingMode?.label ?? "")」？", isPresented: Binding(
            get: { pendingMode != nil },
            set: { if !$0 { pendingMode = nil } }
        )) {
            Button("切换") { if let m = pendingMode { applyMode(m) } }
            Button("取消", role: .cancel) { pendingMode = nil }
        } message: {
            Text("电脑端要从 vJoy 换成虚拟 Xbox 手柄（或换回来），游戏里这只手柄会掉一下，重连或重进即可。当前的布局会先保存。")
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [Theme.cyan.opacity(0.55), Theme.cyan.opacity(0.05)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1.5)
                .padding(.horizontal, 2)
        }
        .sheet(isPresented: $showSettings) { SettingsView(ctrl: ctrl, s: s, layout: layout, profiles: profiles, discovery: discovery, onExit: onExit, onShowTutorial: {
            showSettings = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showTutorial = true }
        }) }
    }

    /// 切模式：**未连接就直接切**（本机换模式没有代价）；
    /// 已连接先问一句 —— 电脑端会换后端（vJoy ↔ 虚拟 Xbox），游戏里手柄会掉一下，
    /// 用户却只会看到「手柄没了」。
    private func requestMode(_ m: CockpitMode) {
        guard m != s.mode else { return }
        if s.link == .live { pendingMode = m; Haptics.tap() } else { applyMode(m) }
    }

    private func applyMode(_ m: CockpitMode) {
        pendingMode = nil
        // 换模式即结束编辑会话（已改的先当成「完成」留下）
        if layout.editing { layout.commitEditing(mode: s.mode); layout.editing = false }
        ctrl.setMode(m); Haptics.press()
    }

    /// 顶栏连接胶囊：已连显示 IP + Hz + 绿灯；未连显示“连接”按钮
    @ViewBuilder
    private func connectionChip(height: CGFloat) -> some View {
        if s.link == .live {
            Button {
                ctrl.disconnect(); Haptics.tap()
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Theme.green).frame(width: 7, height: 7)
                        .glow(Theme.green, radius: 3)
                    Text(ctrl.savedHostForUI)
                        .pdFont(11, design: .monospaced)
                        .foregroundColor(Theme.green)
                    Text(String(format: "%.0fHz", s.hz))
                        .pdFont(10, design: .monospaced)
                        .foregroundColor(Theme.textFaint)
                }
            }
            .buttonStyle(CardButton(active: false, fillWidth: false, height: height))
            .frame(width: 140)
        } else {
            Button {
                if let d = discovery.found.first { ctrl.connect(host: d.ip, ws: d.ws, udp: d.udp) }
                else if !ctrl.savedHostForUI.isEmpty { ctrl.connect(host: ctrl.savedHostForUI) }
                else { showSettings = true }
                Haptics.tap()
            } label: {
                HStack(spacing: 5) {
                    if s.link == .connecting { ProgressView().scaleEffect(0.6).tint(Theme.cyan) }
                    else {
                        Image(systemName: !discovery.found.isEmpty ? "wifi" : "wifi.slash")
                            .pdFont(12)
                            .foregroundColor(!discovery.found.isEmpty ? Theme.green : Theme.textFaint)
                    }
                    Text(s.link == .connecting ? "连接中…" : (!discovery.found.isEmpty ? "一键连接" : "连接"))
                        .pdFont(11, weight: .medium)
                        .foregroundColor(!discovery.found.isEmpty ? Theme.green : Theme.textFaint)
                }
            }
            .buttonStyle(CardButton(active: false, accent: Theme.cyan, fillWidth: false, height: height))
            .frame(width: 96)
        }
    }

    // MARK: 座舱主体（通用模块画布）
    /// 三个模式共用同一块画布：没有内置皮肤、没有游戏语义，
    /// 所有积木（含按键）由用户自己添加 / 命名 / 绑定。
    ///
    /// 提示横幅 / 编辑工具条一律**占位**（VStack 的一行），不用 overlay：
    /// 以前它们浮在画布上，被盖住的组件既点不动也拖不动（画布还在它们下面接着手势），
    /// 默认布局为了躲横幅只好从 y=0.10 开始。占位后画布自己变矮，没有“看不到却存在”的区域。
    @ViewBuilder
    private func deckBody(W: CGFloat, H: CGFloat) -> some View {
        VStack(spacing: 0) {
            if layout.editing { editBar }
            else { connectionBannerRow }
            presetNoteRow
            // 应用模板 / 撤销 / 恢复默认是整表替换，用 revision 强制重建画布，
            // 否则 EditableWidget 的 @State dragStart 会残留到新布局上。
            WidgetCanvas(store: layout, mode: s.mode, s: s, ctrl: ctrl)
                .id(layout.revision)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: W, height: H)
        .hudPanel(corner: 10, accent: Theme.cyan.opacity(0.5))
        // 只有 `live` 会把上面那一行收成 0；让它平滑展开 / 收起，而不是“呿”一下。
        .animation(.easeInOut(duration: 0.22), value: s.link)
        .alert("存为布局预设", isPresented: $savingPreset) {
            TextField("预设名称", text: $presetName)
                .onChange(of: presetName) { v in
                    if v.count > GameProfileStore.maxNameLength {
                        presetName = String(v.prefix(GameProfileStore.maxNameLength))
                    }
                }
            Button("取消", role: .cancel) { }
            Button("确定") {
                saveLayoutPreset()
                Haptics.success()
            }
        } message: {
            Text("只存这 \(layout.widgetCount(mode: s.mode)) 个组件（不含手感），可在「设置 → 预设」里切换。名称最多 \(GameProfileStore.maxNameLength) 个字符。")
        }
    }

    /// 「存为预设」的回执：占编辑条下面一行，不盖画布（和提示横幅同规矩）。
    /// 存成功、重名、名字非法都在这里说一句 —— 以前失败是静默的，点了跟没点一样。
    @ViewBuilder
    private var presetNoteRow: some View {
        if layout.editing && !presetNote.isEmpty {
            Text(presetNote)
                .pdFont(12, weight: .medium)
                .foregroundColor(Theme.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
    }

    /// 编辑条上的「存为预设」：存的是**布局**预设（人在摆布局，手感不在这件事的范围里）。
    /// 想连手感一起存，去设置 → 预设里的「存为整机预设」。
    private func saveLayoutPreset() {
        let p = GameProfile.layoutOnly(name: presetName, mode: s.mode,
                                       widgetsJSON: layout.snapshotWidgetsJSON(mode: s.mode))
        presetNote = profiles.save(p) ?? "已存为「\(p.name.trimmingCharacters(in: .whitespacesAndNewlines))」· 设置 → 预设里能看到"
    }

    /// 编辑态下的顶部工具条（加组件 / 存模板 / 放弃 / 完成）。
    /// 组件越来越多，左边的「添加」一行改成横向可滚，窄屏（iPhone 竖屏）也不会挤成一团。
    /// 它是画布**上面的一行**（不是浮层）——占位后画布顶部的组件照样拖得动。
    private var editBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("添加：").pdFont(12).foregroundColor(Theme.orange)
                    libraryButton("按键", .button, nil)
                    libraryButton("触摸板", .pad, .look)
                    libraryButton("摇杆", .stick, .look)
                    libraryButton("方向盘", .wheel, .roll)
                    libraryButton("滑条", .slider, nil)
                    libraryButton("苦力帽", .hat, .look)
                    libraryButton("姿态球", .attitude, .roll)
                    libraryButton("仪表盘", .panel, .roll)
                }
            }
            Button("存为预设") {
                presetName = "布局 \(profiles.custom.filter { !$0.hasShaping && $0.mode == s.mode }.count + 1)"
                presetNote = ""
                savingPreset = true
            }
            .disabled(layout.widgetCount(mode: s.mode) == 0)
            .buttonStyle(CardButton(accent: Theme.orange, fillWidth: false, height: 30))
            // 整表操作放这里：以前「清空 / 恢复默认 / 撤销」只藏在设置 → 布局，
            // 而它们恰恰是改布局时最想用的三个（清空、恢复默认都会压一道撤销槽，能后悔）。
            Menu {
                Button(role: .destructive) {
                    layout.applyDefault(mode: s.mode)
                    presetNote = ""
                    Haptics.success()
                } label: { Label("恢复默认布局", systemImage: "arrow.counterclockwise") }
                Button(role: .destructive) {
                    layout.clear(mode: s.mode)
                    presetNote = ""
                    Haptics.warning()
                } label: { Label("清空画布", systemImage: "trash") }
                Divider()
                Button {
                    layout.undoLast(mode: s.mode)
                    presetNote = ""
                    Haptics.select()
                } label: { Label("撤销上一次改动", systemImage: "arrow.uturn.backward") }
                    .disabled(!layout.canUndo(mode: s.mode))
            } label: {
                Image(systemName: "ellipsis.circle").pdFont(15)
            }
            .buttonStyle(CardButton(fillWidth: false, height: 30))
            .frame(width: 40)
            Button("放弃") {
                layout.discardEditing(mode: s.mode)
                layout.editing = false
                presetNote = ""
                Haptics.tap()
            }
            .disabled(!layout.canDiscardEditing(mode: s.mode))
            .buttonStyle(CardButton(accent: Theme.red, fillWidth: false, height: 30))
            Button("完成") {
                layout.commitEditing(mode: s.mode)
                layout.editing = false
                presetNote = ""
                Haptics.press()
            }
            .buttonStyle(CardButton(active: true, accent: Theme.cyan, fillWidth: false, height: 30))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.orange.opacity(0.7), lineWidth: 1))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var dotColor: Color {
        switch s.link {
        case .live: return Theme.green
        case .connecting: return Theme.orange
        case .lost: return Theme.red
        case .idle: return Theme.textFaint
        }
    }

    /// 未连接提示横幅（占画布上方一行，不遮挡任何组件；点击即连）。
    ///
    /// **`.connecting` 不收起**（只换文案 + 变亮），否则点按那一瞬间整行消失、
    /// 下面画布变高 → 所有组件按归一化坐标重排，看上去就是「点一下全闪了」。
    /// 行高固定为 `deckTopRowH`，只有真正 `live` 才收成 0（带 0.22s 动画）。
    /// 方案：`docs/PalmDeck-v4-connect-banner-stable.md`。
    @ViewBuilder
    private var connectionBannerRow: some View {
        if s.link == .live {
            Color.clear.frame(height: 0)
        } else {
            let connecting = (s.link == .connecting)
            Button {
                guard !connecting else { return }   // 连接中不重复发
                if let d = discovery.found.first { ctrl.connect(host: d.ip, ws: d.ws, udp: d.udp) }
                else if !ctrl.savedHostForUI.isEmpty { ctrl.connect(host: ctrl.savedHostForUI) }
                else { showSettings = true }
                Haptics.tap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: connecting ? "wifi"
                          : (!discovery.found.isEmpty ? "wifi" : "exclamationmark.triangle.fill"))
                    Text(connecting ? "正在连接…"
                         : (!discovery.found.isEmpty ? "点此连接电脑 \(discovery.found.first!.ip)"
                            : "未连接电脑（先在电脑启动 PalmDeck）"))
                        .pdFont(12, weight: .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Capsule().fill((connecting ? Theme.cyan : Theme.orange).opacity(0.9)))
                .foregroundColor(Theme.onAccent)
                .frame(height: deckTopRowH)   // 行高锛死：状态怎么变都不影响画布
            }
            .buttonStyle(.plain)
            // 不去 `.disabled`：那会把胶囊变灰、跟旁边“正在连接”的亮度对不上。
            .allowsHitTesting(!connecting)
        }
    }

}

/// 卡片式按钮样式（灰底 / 灰字，激活变绿）
struct CardButton: ButtonStyle {
    var active: Bool = false
    var accent: Color = Theme.cyan
    var fillWidth: Bool = true
    var height: CGFloat = 0   // 0 = 自适应父容器高度

    @Environment(\.isEnabled) private var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = (active || pressed) ? accent : Theme.panel
        let base = configuration.label
            .pdFont(12, weight: .semibold)
            .foregroundColor(active ? Theme.onAccent : (pressed ? accent : Theme.textDim))
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 6)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder((active || pressed) ? accent.opacity(0.55) : Theme.border, lineWidth: 1)
                    )
                    .shadow(color: (active || pressed) ? accent.opacity(0.45) : .clear, radius: (active || pressed) ? 7 : 0, y: 0)
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(pressed && !active ? 0.85 : 1)
        if height > 0 {
            return AnyView(base.frame(height: height).opacity(enabled ? 1 : 0.35))
        } else {
            return AnyView(base.frame(maxHeight: .infinity).opacity(enabled ? 1 : 0.35))
        }
    }
}

/// 组件库：选类型 + 绑定，加到画布
struct LibrarySheet: View {
    @ObservedObject var store: LayoutStore
    let mode: CockpitMode
    let initialKind: WidgetKind
    @Environment(\.dismiss) private var dismiss

    @State private var kind: WidgetKind
    @State private var binding: WidgetBinding

    init(store: LayoutStore, mode: CockpitMode, initialKind: WidgetKind) {
        self.store = store
        self.mode = mode
        self.initialKind = initialKind
        _kind = State(initialValue: initialKind)
        // 只接受这个类型真正会用到的绑定；固定通道组件退回它的占位值。
        _binding = State(initialValue: initialKind.bindingOptions.first ?? initialKind.defaultBinding)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("组件类型") {
                    Picker("类型", selection: $kind) {
                        ForEach(WidgetKind.allCases, id: \.self) { k in Text(k.label).tag(k) }
                    }.pickerStyle(.segmented)
                }
                if kind.isReadOnly {
                    Section {
                        Label("\(kind.label)是只读显示，不绑定轴或按键：弧表/杆位条读的是本机发出去的杆位。",
                              systemImage: "gauge")
                            .pdFont(12)
                            .foregroundColor(Theme.textDim)
                    }
                } else if kind.bindingOptions.isEmpty {
                    // 方向盘 / 触摸板 / 摇杆 / 苦力帽 / 姿态球：渲染时各走写死通道，
                    // `widget.binding` 被忽略 —— 不给下拉，免得让人选一个不生效的值。
                    Section {
                        Label("「\(kind.label)」\(kind.fixedBindingNote)，这里不用选绑定。",
                              systemImage: "pin")
                            .pdFont(12)
                            .foregroundColor(Theme.textDim)
                    }
                } else {
                    Section("绑定功能") {
                        Picker("绑定", selection: $binding) {
                            ForEach(kind.bindingOptions, id: \.self) { b in
                                Text(b.onlyOnVJoy ? "\(b.label) · 开车/手柄不生效" : b.label).tag(b)
                            }
                        }
                    }
                    if binding.onlyOnVJoy {
                        Section {
                            Label("第 11–16 号键只在飞行模式里存在（电脑侧那只 vJoy 手柄）。开车与手柄模式用的是 Xbox 虚拟手柄，只有 A/B/X/Y、LB/RB、视图/菜单、L3/R3 十个键，选它不会生效。",
                                  systemImage: "exclamationmark.triangle")
                                .pdFont(12)
                                .foregroundColor(Theme.amber)
                        }
                    }
                }
                Section {
                    Button("添加到画布") {
                        store.add(kind: kind, binding: binding, mode: mode)
                        dismiss()
                    }
                }
            }
            .navigationTitle("添加组件")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onChange(of: kind) { newKind in
                // 换类型就把绑定归到该类的第一个：滑条→横滚/转向，按键→按钮 1；
                // 固定通道组件退回它的占位值（渲染时不读，只为持久化/改名预填好看）。
                binding = newKind.bindingOptions.first ?? newKind.defaultBinding
            }
        }
        // 表单可滚动，放开到无障碍档（覆盖座舱 chrome 的收紧）。
        .palmDynamicType()
    }
}

/// 首次使用速览（一次性，可在设置「帮助」里重新打开）
struct CockpitTutorialView: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop,
                                    Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        section(icon: "switch.2", title: "顶部",
                                text: "中间切「飞机 / 开车 / 手柄」；右侧是连接状态 + 「设置」 + 「布局」（三个模式都有）")
                        section(icon: "arrow.triangle.2.circlepath", title: "换模式",
                                text: "已连接时换模式会问一句：电脑端要换手柄后端（vJoy ↔ 虚拟 Xbox），游戏里这只手柄会掉一下，重连或重进即可。")
                        section(icon: "airplane", title: "飞机模式",
                                text: "只读仪表盘（COLL/TRQ 弧表 + 姿态球 + ROL/PIT/YAW 条）+ 周期杆（横滚/俯仰）+ 总距 + 脚舵 + 视角。默认只有轴，按键自己加")
                        section(icon: "car", title: "开车模式",
                                text: "方向盘（多圈、可调回正速度）+ 离合/刹车/油门三踏板 + 视角。默认只有轴，换档/转向灯这些按键自己在游戏里绑")
                        section(icon: "gamepad", title: "手柄模式",
                                text: "双摇杆 / 十字键 / ABXY / LB·RB / LT·RT / 视图·菜单 的起步布局；轴停发、不抢电脑键鼠")
                        section(icon: "square.grid.2x2", title: "自定义布局（全部模式）",
                                text: "任意模式点右上角「布局」：拖动移动、拖右下角缩放、✕ 删除、Aa 改名；顶部组件库可加方向盘/滑条/触摸板/摇杆/苦力帽/姿态球/仪表盘/按键，可从电脑拉取 / 上传")
                        section(icon: "chart.bar", title: "底部状态条",
                                text: "左边按模式显示真正发出去的轴（开车是转向/离合/油门/刹车）；「链路」是连接与帧率；「模式」是当前模式；最右的「通道」是电脑实际用的传输通道：UDP 是轴的快速通道，WS 是 WebSocket 控制通道")
                        section(icon: "checklist", title: "第一次使用（三步）",
                                text: "1) 电脑先启动 PalmDeck（start.bat 或 python3 bridge.py）\n2) 手机点「连接」，顶栏变绿即连上\n3) 进游戏把这只虚拟手柄绑一次即可")
                    }
                    .padding(24)
                }

                Button {
                    UserDefaults.standard.set(true, forKey: "palmdeck_tutored")
                    onDone()
                    dismiss()
                } label: {
                    Text("开始使用")
                        .pdFont(18, weight: .bold)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(PrimaryButton())
                .padding(24)
            }
        }
        .palmAppearance()
        .palmDynamicType()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .pdFont(24).foregroundColor(Theme.cyan)
                    .rotationEffect(.degrees(-45))
                Text("PalmDeck 座舱速览")
                    .pdFont(24, weight: .heavy).foregroundColor(Theme.text)
            }
            Text("60 秒看懂每个区域，第一次上手不抓瞎")
                .pdFont(13).foregroundColor(Theme.textDim)
        }
        .padding(.bottom, 4)
    }

    private func section(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .pdFont(16).foregroundColor(Theme.cyan)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.cyan.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).pdFont(15, weight: .semibold).foregroundColor(Theme.text)
                Text(text).pdFont(12).foregroundColor(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
