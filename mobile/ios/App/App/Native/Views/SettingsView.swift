import SwiftUI

// MARK: - 分类

/// 设置分类（左栏）。顺序即显示顺序。
enum SettingsCategory: String, CaseIterable, Identifiable {
    case connection, profiles, layout, controls, haptics, wheel, appearance, help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return "连接"
        case .profiles: return "游戏预设"
        case .layout: return "布局"
        case .controls: return "操纵与手感"
        case .haptics: return "触觉"
        case .wheel: return "方向盘"
        case .appearance: return "外观"
        case .help: return "帮助"
        }
    }

    /// Apple 设置同款彩色图标
    var symbol: String {
        switch self {
        case .connection: return "wifi"
        case .profiles: return "gamecontroller.fill"
        case .layout: return "square.grid.2x2.fill"
        case .controls: return "slider.horizontal.3"
        case .haptics: return "hand.tap.fill"
        case .wheel: return "steeringwheel"
        case .appearance: return "circle.lefthalf.filled"
        case .help: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .connection: return Color(red: 0.04, green: 0.52, blue: 1.00)   // 蓝
        case .profiles: return Color(red: 0.10, green: 0.64, blue: 0.60)     // 青绿
        case .layout: return Color(red: 0.69, green: 0.32, blue: 0.87)       // 紫
        case .controls: return Color(red: 0.20, green: 0.78, blue: 0.35)     // 绿
        case .haptics: return Color(red: 1.00, green: 0.18, blue: 0.33)      // 粉红
        case .wheel: return Color(red: 1.00, green: 0.58, blue: 0.00)        // 橙
        case .appearance: return Color(red: 0.37, green: 0.36, blue: 0.90)   // 靖蓝
        case .help: return Color(red: 0.56, green: 0.56, blue: 0.58)         // 灰
        }
    }

    /// 搜索索引：该分类下的所有可搜索设置项（标题 + 中英关键词）。
    var entries: [SettingsEntry] {
        switch self {
        case .connection:
            return [
                .init(self, "电脑", "电脑 主机 host ip 地址 address 连接"),
                .init(self, "连接状态", "状态 link 已连接 live 连接中 断开"),
                .init(self, "断开连接", "断开 disconnect 离线 offline"),
                .init(self, "可用电脑", "发现 discovery 搜索 scan 扫描 bonjour"),
                .init(self, "返回启动页", "退出 exit 启动页 引导 引导流程 换 ip 重连"),
            ]
        case .profiles:
            return [
                .init(self, "切换预设", "预设 profile 游戏 game 切换 switch 一键 整机 布局"),
                .init(self, "WARDOGS", "wardogs 飞机 heli 直升机 预设"),
                .init(self, "欧洲卡车模拟", "ets2 ets 欧洲卡车 卡车 truck 开车 drive 预设"),
                .init(self, "存为预设", "保存 save 预设 profile 新增 快照 整机 布局"),
                .init(self, "默认布局", "默认 default 还原 恢复 reset 内置"),
                .init(self, "电脑轴映射表", "轴 mapping 映射 axis 轴表 hotas fbw 电脑"),
            ]
        case .layout:
            return [
                .init(self, "自定义组件布局", "自定义 custom 组件 widget 布局 layout 手柄"),
                .init(self, "编辑布局", "编辑 edit 拖动 移动 缩放 删除"),
                .init(self, "放弃本次编辑", "放弃 回滚 撤销 取消 discard cancel revert"),
                .init(self, "预设里恢复默认", "默认 default 预设 恢复 还原 reset"),
                .init(self, "撤销上一次改动", "撤销 undo 还原 回退 恢复 revert"),
                .init(self, "清空当前模式", "清空 clear 删除 移除"),
                .init(self, "从电脑拉取布局", "拉取 下载 download fetch 同步 sync 电脑"),
                .init(self, "上传当前模式到电脑", "上传 upload 同步 sync 电脑"),
            ]
        case .controls:
            return [
                .init(self, "反转横滚 Roll", "反转 invert 反向 横滚 roll x 轴 axis"),
                .init(self, "反转俯仰 Pitch", "反转 invert 反向 俯仰 pitch y 轴 axis"),
                .init(self, "反转方向舵 Yaw", "反转 invert 反向 方向舵 yaw 偏航 z 轴"),
                .init(self, "反转总距 Collective", "反转 invert 反向 总距 collective 油门 throttle"),
                .init(self, "松手回中", "回中 return 松手 弹簧 spring center 摇杆"),
                .init(self, "横滚灵敏度", "灵敏度 sensitivity sens 横滚 roll 增益 gain 曲线 curve"),
                .init(self, "俯仰灵敏度", "灵敏度 sensitivity sens 俯仰 pitch 增益 gain 曲线 curve"),
                .init(self, "摇杆死区", "死区 deadzone dz 抖动 漂移 中位"),
                .init(self, "响应曲线", "曲线 curve 响应 response 手感 增益 预览"),
            ]
        case .haptics:
            return [
                .init(self, "触觉反馈", "触觉 haptics 振动 vibrate taptic 反馈 震动"),
                .init(self, "试一下振动", "测试 test 振动 试一下 预览"),
            ]
        case .wheel:
            return [
                .init(self, "满舵角度", "满舵 角度 steering 方向盘 wheel 舵角 圈"),
                .init(self, "回正速度", "回正 return 速度 方向盘 wheel 松手"),
            ]
        case .appearance:
            return [
                .init(self, "外观模式", "外观 appearance 主题 theme 皮肤 skin 深色 dark 浅色 light 夜间"),
            ]
        case .help:
            return [
                .init(self, "查看使用教程", "教程 tutorial 帮助 help 说明 引导"),
                .init(self, "App 版本", "版本 version 关于 about build"),
                .init(self, "当前模式", "皮肤 skin 模式 mode 飞机 开车 手柄"),
            ]
        }
    }
}

/// 搜索索引条目。
struct SettingsEntry: Identifiable {
    let category: SettingsCategory
    let title: String
    let keywords: String
    var id: String { category.rawValue + "/" + title }

    init(_ category: SettingsCategory, _ title: String, _ keywords: String) {
        self.category = category
        self.title = title
        self.keywords = keywords
    }
}

/// 搜索结果分组（按分类）。
struct SettingsResultGroup: Identifiable {
    let category: SettingsCategory
    let items: [SettingsEntry]
    var id: String { category.rawValue }
}

// MARK: - 设置页

/// 预设命名/重命名弹窗状态。`original == nil` 表示新建。
private struct ProfPrompt: Identifiable {
    enum NewKind { case machine, layout }
    let id = UUID()
    var original: String?
    var text: String
    /// 新建时存哪种形态（重命名时无意义）。
    var kind: NewKind = .machine
}
/// 设置页：Apple「设置」风格。横屏双栏——左分类、右详情（inset-grouped）。
struct SettingsView: View {
    @ObservedObject var ctrl: CockpitController
    @ObservedObject var s: ControllerState
    @ObservedObject var layout: LayoutStore
    @ObservedObject var profiles: GameProfileStore
    @AppStorage("palmdeck_haptics") private var haptics = true
    @AppStorage(AppAppearance.key) private var appearanceRaw = AppAppearance.fallback.rawValue
    var discovery: Discovery? = nil
    var onExit: () -> Void = {}
    var onShowTutorial: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var sel: SettingsCategory = .connection
    @State private var query = ""
    @State private var profPrompt: ProfPrompt? = nil
    @State private var profNote = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(uiColor: .separator))
            HStack(alignment: .top, spacing: 0) {
                sidebar
                Divider().overlay(Color(uiColor: .separator))
                detail
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .palmAppearance()
        .tint(Theme.cyan)
    }

    /// 顶部标题栏（“设置 + 完成”，Apple 设置同款）
    private var header: some View {
        ZStack {
            Text("设置")
                .font(.system(size: 17, weight: .semibold))
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: 左栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            if isSearching { searchResults } else { categoryList }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 搜索框（Apple 设置顶部胶囊）
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("搜索", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var categoryList: some View {
        List {
            ForEach(SettingsCategory.allCases) { c in
                Button { sel = c; Haptics.select() } label: { sidebarRow(c) }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    .listRowBackground(sel == c
                        ? Color(uiColor: .secondarySystemFill)
                        : Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
    }

    /// 跨分类搜索结果（点一下跳到该分类）
    @ViewBuilder private var searchResults: some View {
        if matchedGroups.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                Text("没有匹配的设置项").font(.system(size: 14)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(matchedGroups) { group in
                    Section(group.category.title) {
                        ForEach(group.items) { e in
                            Button {
                                sel = e.category
                                query = ""
                                Haptics.select()
                            } label: {
                                HStack(spacing: 12) {
                                    SettingsIcon(symbol: group.category.symbol, color: group.category.color)
                                    Text(e.title).foregroundColor(.primary)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var matchedGroups: [SettingsResultGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        // 三个模式都有完整的「布局」分类，搜索不再需要按模式隐藏。
        return SettingsCategory.allCases.compactMap { c in
            let items = c.entries.filter {
                $0.title.lowercased().contains(q) || $0.keywords.lowercased().contains(q)
            }
            return items.isEmpty ? nil : SettingsResultGroup(category: c, items: items)
        }
    }

    private func sidebarRow(_ c: SettingsCategory) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: c.symbol, color: c.color)
            Text(c.title)
                .font(.system(size: 16, weight: sel == c ? .semibold : .regular))
                .foregroundColor(.primary)
            Spacer(minLength: 8)
            if let v = trailingValue(c) {
                Text(v)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .contentShape(Rectangle())
    }

    private func trailingValue(_ c: SettingsCategory) -> String? {
        switch c {
        case .connection:
            return ctrl.savedHostForUI.isEmpty ? nil : ctrl.savedHostForUI
        case .profiles:
            return profiles.activeName
        case .haptics:
            return haptics ? "开" : "关"
        default:
            return nil
        }
    }

    // MARK: 右栏

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sel.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 2)

            List {
                switch sel {
                case .connection: connectionSections
                case .profiles:   profilesSections
                case .layout:     layoutSections
                case .controls:   controlsSections
                case .haptics:    hapticsSections
                case .wheel:      wheelSections
                case .appearance: appearanceSections
                case .help:       helpSections
                }
            }
            .listStyle(.insetGrouped)
            .alert(alertTitle, isPresented: Binding(get: { profPrompt != nil },
                                                   set: { if !$0 { profPrompt = nil } })) {
                TextField("预设名称", text: Binding(
                    get: { profPrompt?.text ?? "" },
                    set: { profPrompt?.text = $0 }))
                    .onChange(of: profPrompt?.text ?? "") { v in
                        if v.count > GameProfileStore.maxNameLength {
                            profPrompt?.text = String(v.prefix(GameProfileStore.maxNameLength))
                        }
                    }
                Button("取消", role: .cancel) { profPrompt = nil }
                Button("确定") { commitProfilePrompt() }
            } message: {
                Text("名称最多 \(GameProfileStore.maxNameLength) 个字符；重名则覆盖。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 弹窗标题：新建看形态，改名看原名。
    private var alertTitle: String {
        guard let p = profPrompt, p.original == nil else { return "重命名预设" }
        return p.kind == .machine ? "存为整机预设" : "存为布局预设"
    }

    private func commitProfilePrompt() {
        guard let p = profPrompt else { return }
        if let old = p.original {
            profNote = profiles.rename(old, to: p.text) ?? ""
        } else {
            let axes = s.axisProfile.isEmpty ? "hotas" : s.axisProfile
            let np: GameProfile
            switch p.kind {
            case .machine:
                // 整机 = 快照当前状态（模式 / 手感 / 布局）
                var m = GameProfile(
                    name: p.text, mode: s.mode, axesPreset: axes,
                    sensX: s.sensX, sensY: s.sensY, dz: s.dz,
                    invX: s.invX, invY: s.invY, invYaw: s.invYaw, invColl: s.invColl,
                    wheelMaxDeg: s.wheelMaxDeg, wheelReturnSpeed: s.wheelReturnSpeed)
                m.widgetsJSON = layout.snapshotWidgetsJSON(mode: s.mode)
                np = m
            case .layout:
                // 布局 = 只快照当前模式的组件（手感一点不记）
                np = GameProfile.layoutOnly(name: p.text, mode: s.mode,
                                            widgetsJSON: layout.snapshotWidgetsJSON(mode: s.mode),
                                            axesPreset: axes)
            }
            var named = np
            named.name = p.text
            profNote = profiles.save(named) ?? (p.kind == .machine ? "已存为整机预设" : "已存为布局预设")
        }
        profPrompt = nil
    }

    // ---- 游戏预设 ----

    @ViewBuilder private var profilesSections: some View {
        Section {
            InfoRow(label: "电脑当前轴表",
                    value: pcAxisProfile,
                    mono: true)
        } header: {
            SettingsHeader("电脑侧")
        } footer: {
            Text("轴表由电脑端决定（App 暂不能远程改）。预设里的「轴表」只是记录你为该游戏选的那个，用来对照是否一致。不一致时到电脑控制台切换。")
        }

        Section {
            ForEach(presetRows) { row in
                Button {
                    applyPreset(row)
                } label: {
                    presetRowView(row)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if case .profile(let p) = row.kind, !profiles.isBuiltin(p) {
                        Button(role: .destructive) {
                            profiles.delete(p.name)
                            profNote = "已删除「\(p.name)」"
                        } label: { Label("删除", systemImage: "trash") }
                        Button {
                            profPrompt = ProfPrompt(original: p.name, text: p.name)
                        } label: { Label("重命名", systemImage: "pencil") }
                            .tint(.orange)
                    }
                }
            }

            Button {
                profPrompt = ProfPrompt(original: nil, text: "", kind: .machine)
            } label: {
                Label("将当前状态存为预设（整机）", systemImage: "plus.circle")
            }
            Button {
                profPrompt = ProfPrompt(original: nil, text: "", kind: .layout)
            } label: {
                Label("将当前布局存为预设（仅布局）", systemImage: "plus.circle")
            }
            .disabled(layout.widgetCount(mode: s.mode) == 0)
        } header: {
            SettingsHeader("预设")
        } footer: {
            if profNote.isEmpty {
                Text("**切游戏请用这里**：点一下就把模式、手感（反转/死区/灵敏度）与布局一起切到位，不会重建虚拟手柄、不会打断游戏。预设只存本机，内置的不可删改。\n\n**整机**（行尾章「整机」）跨模式出现：切模式 + 写手感 + 有布局就换。**仅布局**（「布局」）只装组件、不碰手感，**只在自己那个模式下出现**（它就属于那套面板）。\n\n**内置预设不带布局**：WARDOGS / 欧洲卡车模拟只管模式与手感，不动你摆好的组件。")
            } else {
                Text(profNote).foregroundColor(Theme.orange)
            }
        }
    }

    /// 列表里的一行：一个预设，或内置「默认」（还原点）。
    private struct PresetRow: Identifiable {
        enum Kind { case profile(GameProfile), restoreDefault }
        let id: String
        let kind: Kind
    }

    /// 行顺序：内置整机 → 用户整机 → 当前模式的布局预设 → 内置「默认」。
    /// 「布局」预设只在自己那个模式下出现：它存的是那套面板，在别的模式下没有意义。
    private var presetRows: [PresetRow] {
        let visible = profiles.all.filter { $0.hasShaping || $0.mode == s.mode }
        let machines = visible.filter { $0.hasShaping }.map { PresetRow(id: $0.name, kind: .profile($0)) }
        let layouts = visible.filter { !$0.hasShaping }.map { PresetRow(id: $0.name, kind: .profile($0)) }
        return machines + layouts + [PresetRow(id: LayoutStore.builtinName, kind: .restoreDefault)]
    }

    @ViewBuilder private func presetRowView(_ row: PresetRow) -> some View {
        switch row.kind {
        case .restoreDefault:
            rowBody(title: LayoutStore.builtinName,
                    chips: ["内置", "布局"],
                    detail: "\(s.mode.label) · 出厂布局 · \(LayoutStore.defaults(mode: s.mode).count) 个组件",
                    current: layout.isCurrentDefault(mode: s.mode),
                    warn: false)
        case .profile(let p):
            rowBody(title: p.name,
                    chips: (profiles.isBuiltin(p) ? ["内置"] : []) + [p.kindLabel],
                    detail: detail(p),
                    current: isCurrent(p),
                    warn: !s.axisProfile.isEmpty && s.axisProfile != p.axesPreset)
        }
    }

    private func detail(_ p: GameProfile) -> String {
        if p.hasShaping {
            let layoutText = p.hasLayout ? "含布局" : "仅手感"
            return "\(p.mode.label) · 轴表 \(p.axesPreset) · 死区 \(String(format: "%.2f", p.dz)) · \(layoutText)"
        }
        return "\(p.mode.label) · 只装组件 · \(layout.widgetCount(p.widgetsJSON)) 个组件"
    }

    /// 「当前」标记：整机预设看“最后应用的那个”；布局预设看**内容是否相等**
    /// （它就是一套组件，比形状最直接，且不受“手动改了一个角”以外的影响）。
    private func isCurrent(_ p: GameProfile) -> Bool {
        p.hasShaping ? profiles.activeName == p.name
                     : layout.isCurrentLayout(p.widgetsJSON, mode: p.mode)
    }

    private func rowBody(title: String, chips: [String], detail: String,
                         current: Bool, warn: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                }
                Text(detail)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if current {
                Text("当前")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.cyan)
                    .lineLimit(1)
                    .fixedSize()
            }
            if warn {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.orange)
            }
        }
        .contentShape(Rectangle())
    }

    /// 电脑实际轴表名；未连接时给出提示文案。
    private var pcAxisProfile: String {
        if !s.axisProfile.isEmpty { return s.axisProfile }
        return s.link == .live ? "旧版（未上报）" : "未连接"
    }

    private func applyPreset(_ row: PresetRow) {
        switch row.kind {
        case .restoreDefault:
            layout.applyDefault(mode: s.mode)
            profiles.markActive(nil)
            Haptics.press()
            profNote = "已恢复到「\(LayoutStore.builtinName)」布局"
        case .profile(let p):
            applyProfile(p)
        }
    }

    private func applyProfile(_ p: GameProfile) {
        GameProfileApplier.apply(p, to: s,
                                 setMode: { ctrl.setMode($0) },
                                 replaceLayout: { data, mode in
                                     layout.applyProfile(widgetsJSON: data, mode: mode)
                                 })
        profiles.markActive(p.name)
        Haptics.press()
        if !p.hasShaping {
            profNote = "已应用「\(p.name)」· 只换了布局，手感没动"
        } else {
            profNote = p.hasLayout
                ? "已切换到「\(p.name)」· 布局已换成预设的"
                : "已切换到「\(p.name)」· 布局保持不动"
        }
    }

    // ---- 连接 ----
    @ViewBuilder private var connectionSections: some View {
        Section {
            InfoRow(label: "电脑", value: ctrl.savedHostForUI.isEmpty ? "未设置" : ctrl.savedHostForUI, mono: true)
            HStack {
                Text("状态")
                Spacer()
                LinkStatusPill(state: s.link)
            }
        } header: {
            SettingsHeader("电脑")
        }

        Section {
            if s.link == .live {
                Button(role: .destructive) {
                    ctrl.disconnect(); Haptics.tap()
                } label: {
                    Label("断开连接", systemImage: "wifi.slash")
                }
            } else {
                let list = discovery?.found ?? []
                if !list.isEmpty {
                    ForEach(list, id: \.ip) { d in
                        Button {
                            ctrl.connect(host: d.ip, ws: d.ws, udp: d.udp); Haptics.tap()
                        } label: {
                            Label("连接 \(d.ip)", systemImage: "wifi")
                        }
                    }
                }
                if !ctrl.savedHostForUI.isEmpty,
                   !list.contains(where: { $0.ip == ctrl.savedHostForUI }) {
                    Button {
                        ctrl.connect(host: ctrl.savedHostForUI); Haptics.tap()
                    } label: {
                        Label("连接上次的 \(ctrl.savedHostForUI)", systemImage: "clock.arrow.circlepath")
                    }
                }
                if list.isEmpty && ctrl.savedHostForUI.isEmpty {
                    Text("没搜到电脑。确认电脑端已启动、手机与电脑在同一 Wi-Fi。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
        } header: {
            SettingsHeader("可用电脑")
        }


        Section {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onExit() }
            } label: {
                Label("返回启动页", systemImage: "arrow.uturn.backward")
            }
        } footer: {
            Text("用于更换电脑 IP、重新扫描或再走一遍引导流程。")
        }
    }

    // ---- 布局 ----
    @ViewBuilder private var layoutSections: some View {
        Section {
            Toggle(isOn: $layout.editing) {
                Label("编辑布局", systemImage: "hand.draw")
            }
            .onChange(of: layout.editing) { on in
                // 开 = 记下回滚点（供座舱里的「放弃」用），关 = 当成「完成」
                if on { layout.beginEditing(mode: s.mode) } else { layout.commitEditing(mode: s.mode) }
            }
            if layout.editing {
                Button(role: .destructive) {
                    layout.discardEditing(mode: s.mode)
                    layout.editing = false
                } label: {
                    Label("放弃本次编辑", systemImage: "arrow.uturn.backward")
                }
                .disabled(!layout.canDiscardEditing(mode: s.mode))
            }
        } header: {
            SettingsHeader("模式")
        } footer: {
            Text("三个模式都用同一套通用组件（引擎内不再有固定皮肤）。开启编辑后，顶部出现组件库；拖动移动、拖右下角缩放、✕ 删除、Aa 重命名。按键默认只有中性序号，含义由你在游戏里自己绑。座舱编辑条上的「放弃」可一键回滚到本次编辑开始前。")
        }

        Section {
            Button(role: .destructive) { layout.clear(mode: s.mode) } label: {
                Label("清空当前模式", systemImage: "trash")
            }
        } header: {
            SettingsHeader("清空")
        } footer: {
            Text("清空后画布是空的（会有占位提示）。想回到出厂布局？去「预设」里点内置那一行「\(LayoutStore.builtinName)」；两者都会压一道撤销槽，当场能后悔。")
        }

        undoSection

        Section {
            Button { ctrl.requestLayouts() } label: {
                Label("从电脑拉取布局", systemImage: "arrow.down.circle")
            }
            Button { layout.upload(mode: s.mode, via: ctrl) } label: {
                Label("上传当前模式到电脑", systemImage: "arrow.up.circle")
            }
            .disabled(s.link != .live)
            if !layout.syncMessage.isEmpty {
                Text(layout.syncMessage).font(.footnote).foregroundColor(.secondary)
            }
        } header: {
            SettingsHeader("与电脑同步")
        } footer: {
            Text("上传需要在座舱内已连接电脑；布局保存在电脑的 layouts.json。")
        }
    }

    // ---- 撤销上一次改动（整表操作的回退；命名快照已统一到「预设」） ----

    @ViewBuilder private var undoSection: some View {
        Section {
            Button {
                layout.undoLast(mode: s.mode)
                Haptics.select()
                profNote = "已撤销上一次改动"
            } label: {
                Label("撤销上一次改动", systemImage: "arrow.uturn.backward")
            }
            .disabled(!layout.canUndo(mode: s.mode))
        } footer: {
            Text("回退到上一次**整表操作**之前（应用预设 / 恢复默认 / 清空 / 添加 / 删除）。拖拽与改名不压撤销槽（要保持拖动流畅），这种细粒度反悔用座舱里的「放弃」。")
        }
    }

    // ---- 操纵与手感 ----
    @ViewBuilder private var controlsSections: some View {
        Section {
            Toggle("反转横滚 Roll", isOn: $s.invX)
            Toggle("反转俯仰 Pitch", isOn: $s.invY)
            Toggle("反转方向舵 Yaw", isOn: $s.invYaw)
            Toggle("反转总距 Collective", isOn: $s.invColl)
        } header: {
            SettingsHeader("轴反向 · \(s.mode.label)")
        } footer: {
            Text("与游戏内设置二选一即可，避免双重反转。\n\n**随模式分开保存**：在「\(s.mode.label)」下改，只影响「\(s.mode.label)」。")
        }

        Section {
            Toggle("松手回中", isOn: $s.stickReturn)
        } header: {
            SettingsHeader("摇杆")
        }

        Section {
            SliderRow(title: "横滚灵敏度", value: $s.sensX, range: 0.5...2.0, step: 0.05, unit: "×")
            SliderRow(title: "俯仰灵敏度", value: $s.sensY, range: 0.5...2.0, step: 0.05, unit: "×")
            SliderRow(title: "摇杆死区", value: $s.dz, range: 0...0.2, step: 0.01, unit: "%",
                      format: { String(format: "%.0f", $0 * 100) },
                      parse: { Double($0.replacingOccurrences(of: ",", with: ".")).map { $0 / 100 } })
        } header: {
            SettingsHeader("灵敏度与死区 · \(s.mode.label)")
        } footer: {
            Text("灵敏度 > 1 更跟手（更容易到满舵）；死区滤掉手指微抖。**点数值可直接输入精确值。**\n\n**随模式分开保存**：飞机调出来的死区不会再跟着赛车走 —— 在「\(s.mode.label)」下改，只影响「\(s.mode.label)」。")
        }

        Section {
            HStack(alignment: .top, spacing: 18) {
                curveBlock(title: "横滚 Roll", accent: Theme.cyan,
                           sens: s.sensX, dz: s.dz, inv: s.invX, live: s.roll)
                curveBlock(title: "俯仰 Pitch", accent: Theme.green,
                           sens: s.sensY, dz: s.dz, inv: s.invY, live: s.pitch)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } header: {
            SettingsHeader("响应曲线")
        } footer: {
            Text("虚线＝1:1 参考；阴影带＝死区；实线＝「死区 + 灵敏度 + 反转」后的真实输出曲线（调滑条即实时变化）。")
        }
    }

    /// 一路轴的曲线块（图 + 图例）
    private func curveBlock(title: String, accent: Color, sens: Double, dz: Double,
                            inv: Bool, live: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AxisResponseCurve(sensitivity: sens, deadzone: dz, inverted: inv,
                              accent: accent, live: live)
                .frame(width: 126, height: 126)
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                Text(String(format: "%.2f×", sens))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // ---- 触觉 ----
    @ViewBuilder private var hapticsSections: some View {
        Section {
            Toggle(isOn: $haptics) {
                Label("触觉反馈", systemImage: "hand.tap")
            }
            Button {
                Haptics.press()
            } label: {
                Label("试一下振动", systemImage: "waveform")
            }
            .disabled(!haptics)
        } header: {
            SettingsHeader("反馈")
        } footer: {
            Text("抓住控件、模式切换、总距卡位、过中位等会在支持的机型上触发原生 Taptic 振动。")
        }
    }

    // ---- 方向盘 ----
    @ViewBuilder private var wheelSections: some View {
        Section {
            SliderRow(title: "满舵角度", value: $s.wheelMaxDeg, range: 180...900, step: 90, unit: " 圈",
                      format: { String(format: "%.1f", $0 / 360) },
                      parse: { Double($0.replacingOccurrences(of: ",", with: ".")).map { $0 * 360 } },
                      snapToStep: false)
            SliderRow(title: "回正速度", value: $s.wheelReturnSpeed, range: 0...1440, step: 60, unit: "°/s",
                      format: { String(format: "%.0f", $0) })
        } header: {
            SettingsHeader("参数")
        } footer: {
            Text("回正速度为 0°/s 表示松手后保持当前舵角；点数值可直接输入。")
        }
    }

    // ---- 外观 ----
    @ViewBuilder private var appearanceSections: some View {
        Section {
            Picker("外观模式", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { a in
                    Label(a.label, systemImage: a.symbol).tag(a.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            SettingsHeader("主题")
        } footer: {
            Text("默认浅色；选「深色」适合暗光环境。座舱仪表（姿态球）保持深底亮线，不随主题变。")
        }
    }

    // ---- 帮助 ----
    @ViewBuilder private var helpSections: some View {
        Section {
            Button {
                onShowTutorial()
            } label: {
                Label("查看使用教程", systemImage: "book")
            }
        } header: {
            SettingsHeader("教程")
        }

        Section {
            InfoRow(label: "App 版本", value: appVersion)
            InfoRow(label: "电脑端版本", value: pcVersion, warn: pcVersionMismatch)
            InfoRow(label: "当前模式", value: s.mode.label)
        } header: {
            SettingsHeader("关于")
        } footer: {
            if pcVersionMismatch {
                Text("App 与电脑端主版本号不一致，轴映射或设置项可能对不上，建议一起更新。")
            }
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    /// 电脑端版本（来自 hello 帧）；未连接时为空。
    private var pcVersion: String {
        s.pcVersion.isEmpty ? (s.link == .live ? "旧版（未上报）" : "未连接") : "v\(s.pcVersion)"
    }

    /// 主版本号不一致（只比首段）：只在拿到电脑端版本后判定。
    private var pcVersionMismatch: Bool {
        guard !s.pcVersion.isEmpty else { return false }
        let mine = appVersion.split(separator: ".").first.map(String.init) ?? ""
        let theirs = s.pcVersion.split(separator: ".").first.map(String.init) ?? ""
        return !mine.isEmpty && mine != theirs
    }
}

// MARK: - 复用组件（Apple 设置观感）

/// 彩色圆角图标（Apple 设置同款：29pt 方，圆角 7）。
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.onAccent)
            .frame(width: 29, height: 29)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color)
            )
    }
}

/// 分组小标题（灰、略小、可含图标）。
struct SettingsHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(nil)
    }
}

/// 标签 + 右对齐值。
struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    /// 非空时在值前面画一个感叹号，用于提示「不一致 / 需注意」。
    var warn: Bool = false

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            if warn {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.orange)
            }
            Text(value)
                .foregroundColor(warn ? Theme.orange : .secondary)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// 连接状态胶囊（圆点 + 文案）。
struct LinkStatusPill: View {
    let state: LinkState

    private var text: String {
        switch state {
        case .idle: return "未连接"
        case .connecting: return "连接中…"
        case .live: return "已连接"
        case .lost: return "已断开"
        }
    }

    private var color: Color {
        switch state {
        case .idle: return Color(uiColor: .systemGray)
        case .connecting: return Theme.orange
        case .live: return Theme.green
        case .lost: return Theme.red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundColor(.secondary)
        }
    }
}

/// 滑条行：标题 + **可点击输入的数值** + 滑条。
///
/// 点数值 → 弹出数字键盘精确输入（Apple 设置同款做法）；
/// 输入会夹到 `range`、可选按 `step` 吸附。内部值统一用 `value` 的单位，
/// 展示/解析由 `format` / `parse` 负责（如满舵角度内部是度，展示是圈）。
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var unit: String = ""
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    var parse: (String) -> Double? = { Double($0.replacingOccurrences(of: ",", with: ".")) }
    var snapToStep: Bool = true

    @State private var editing = false
    @State private var draft = ""

    private var display: String { format(value) + unit }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Button {
                    draft = format(value)
                    editing = true
                    Haptics.tap()
                } label: {
                    Text(display)
                        .monospacedDigit()
                        .foregroundColor(Theme.cyan)
                }
                .buttonStyle(.plain)
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
        .alert(title, isPresented: $editing) {
            TextField("数值", text: $draft)
                .keyboardType(.decimalPad)
            Button("取消", role: .cancel) { }
            Button("确定") { commit() }
        } message: {
            Text("可输入 \(format(range.lowerBound) + unit) – \(format(range.upperBound) + unit)")
        }
    }

    private func commit() {
        guard let raw = parse(draft.trimmingCharacters(in: .whitespaces)) else { return }
        var v = min(max(raw, range.lowerBound), range.upperBound)
        if snapToStep && step > 0 {
            v = min(max((v / step).rounded() * step, range.lowerBound), range.upperBound)
            v = (v * 1000).rounded() / 1000   // 抹掉浮点尾数
        }
        value = v
        Haptics.select()
    }
}

/// 响应曲线：把「死区 + 灵敏度 + 反转」的真实整形函数画出来。
///
/// 这里**不复刻公式**，直接调 `AxisCurve.output` —— 和 `ControllerState.tickSmoothing()`、
/// `Packet.pack()` 是同一个函数。复刻过的版本会漂，而骗人的预览比没有预览更糟。
struct AxisResponseCurve: View {
    var sensitivity: Double
    var deadzone: Double
    var inverted: Bool
    var accent: Color
    var live: Double = 0

    /// 与发送路径同一个函数。
    func output(_ v: Double) -> Double {
        AxisCurve.output(v, sensitivity: sensitivity, deadzone: deadzone, inverted: inverted)
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func px(_ x: Double) -> CGFloat { CGFloat((x + 1) / 2) * w }
            func py(_ y: Double) -> CGFloat { CGFloat((1 - y) / 2) * h }

            // 死区带
            let dz = min(max(deadzone, 0), 0.95)
            let band = CGRect(x: px(-dz), y: 0, width: px(dz) - px(-dz), height: h)
            ctx.fill(Path(band), with: .color(accent.opacity(0.12)))

            // 网格
            var grid = Path()
            for i in 1..<4 {
                let t = CGFloat(i) / 4
                grid.move(to: CGPoint(x: w * t, y: 0)); grid.addLine(to: CGPoint(x: w * t, y: h))
                grid.move(to: CGPoint(x: 0, y: h * t)); grid.addLine(to: CGPoint(x: w, y: h * t))
            }
            ctx.stroke(grid, with: .color(Color(uiColor: .separator).opacity(0.45)), lineWidth: 0.5)

            // 中轴
            var axes = Path()
            axes.move(to: CGPoint(x: 0, y: h / 2)); axes.addLine(to: CGPoint(x: w, y: h / 2))
            axes.move(to: CGPoint(x: w / 2, y: 0)); axes.addLine(to: CGPoint(x: w / 2, y: h))
            ctx.stroke(axes, with: .color(Color(uiColor: .separator)), lineWidth: 1)

            // 1:1 参考虚线
            var ref = Path()
            ref.move(to: CGPoint(x: px(-1), y: py(-1)))
            ref.addLine(to: CGPoint(x: px(1), y: py(1)))
            ctx.stroke(ref, with: .color(Color(uiColor: .tertiaryLabel)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // 实际曲线
            var curve = Path()
            let n = 121
            for i in 0..<n {
                let v = -1.0 + 2.0 * Double(i) / Double(n - 1)
                let pt = CGPoint(x: px(v), y: py(output(v)))
                if i == 0 { curve.move(to: pt) } else { curve.addLine(to: pt) }
            }
            ctx.stroke(curve, with: .color(accent),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // 当前输入点
            let lv = max(-1, min(1, live))
            let dot = CGPoint(x: px(lv), y: py(output(lv)))
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 3.5, y: dot.y - 3.5, width: 7, height: 7)),
                     with: .color(accent))
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        )
    }
}
