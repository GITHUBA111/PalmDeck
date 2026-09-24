import SwiftUI

// MARK: - 分类

/// 设置分类（左栏）。顺序即显示顺序。
enum SettingsCategory: String, CaseIterable, Identifiable {
    case connection, layout, controls, haptics, wheel, help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return "连接"
        case .layout: return "布局"
        case .controls: return "操纵与手感"
        case .haptics: return "触觉"
        case .wheel: return "方向盘"
        case .help: return "帮助"
        }
    }

    /// Apple 设置同款彩色图标
    var symbol: String {
        switch self {
        case .connection: return "wifi"
        case .layout: return "square.grid.2x2.fill"
        case .controls: return "slider.horizontal.3"
        case .haptics: return "hand.tap.fill"
        case .wheel: return "steeringwheel"
        case .help: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .connection: return Color(red: 0.04, green: 0.52, blue: 1.00)   // 蓝
        case .layout: return Color(red: 0.69, green: 0.32, blue: 0.87)       // 紫
        case .controls: return Color(red: 0.20, green: 0.78, blue: 0.35)     // 绿
        case .haptics: return Color(red: 1.00, green: 0.18, blue: 0.33)      // 粉红
        case .wheel: return Color(red: 1.00, green: 0.58, blue: 0.00)        // 橙
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
        case .layout:
            return [
                .init(self, "自定义组件布局", "自定义 custom 组件 widget 布局 layout 手柄"),
                .init(self, "编辑布局", "编辑 edit 拖动 移动 缩放 删除"),
                .init(self, "模板", "模板 template 预设 preset 方案 切换 switch 还原 恢复 快照"),
                .init(self, "将当前布局存为模板", "保存 save 快照 snapshot 模板 template 新增"),
                .init(self, "撤销上一次改动", "撤销 undo 还原 回退 恢复 revert"),
                .init(self, "恢复默认布局", "恢复 reset 默认 default 重置"),
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
        case .help:
            return [
                .init(self, "查看使用教程", "教程 tutorial 帮助 help 说明 引导"),
                .init(self, "App 版本", "版本 version 关于 about build"),
                .init(self, "当前皮肤", "皮肤 skin 模式 mode 飞机 开车 手柄"),
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

/// 模板命名/重命名弹窗状态。`original == nil` 表示新建。
private struct TplPrompt: Identifiable {
    let id = UUID()
    var original: String?
    var text: String
}

/// 设置页：Apple「设置」风格。横屏双栏——左分类、右详情（inset-grouped）。
struct SettingsView: View {
    @ObservedObject var ctrl: CockpitController
    @ObservedObject var s: ControllerState
    @ObservedObject var layout: LayoutStore
    @AppStorage("palmdeck_gamepad_custom") private var gamepadCustom = false
    @AppStorage("palmdeck_haptics") private var haptics = true
    var discovery: Discovery? = nil
    var onExit: () -> Void = {}
    var onShowTutorial: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var sel: SettingsCategory = .connection
    @State private var query = ""
    @State private var tplPrompt: TplPrompt? = nil
    @State private var tplNote = ""

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
        .preferredColorScheme(.dark)
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
        // heli/drive 用固定硬件皮肤，整个「布局」分类下的条目都不存在
        // （面板里只剩一句锁定说明），搜出跳过去却看不到行的死结果不如不给。
        let hiddenCat: SettingsCategory? = s.mode == .gamepad ? nil : .layout
        return SettingsCategory.allCases.compactMap { c in
            guard c != hiddenCat else { return nil }
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
                case .layout:     layoutSections
                case .controls:   controlsSections
                case .haptics:    hapticsSections
                case .wheel:      wheelSections
                case .help:       helpSections
                }
            }
            .listStyle(.insetGrouped)
            .alert(tplPrompt?.original == nil ? "存为模板" : "重命名模板",
                   isPresented: Binding(get: { tplPrompt != nil },
                                        set: { if !$0 { tplPrompt = nil } })) {
                TextField("模板名称", text: Binding(
                    get: { tplPrompt?.text ?? "" },
                    set: { tplPrompt?.text = $0 }))
                    .onChange(of: tplPrompt?.text ?? "") { v in
                        if v.count > LayoutStore.maxNameLength {
                            tplPrompt?.text = String(v.prefix(LayoutStore.maxNameLength))
                        }
                    }
                Button("取消", role: .cancel) { tplPrompt = nil }
                Button("确定") { commitTemplatePrompt() }
            } message: {
                Text("名称最多 \(LayoutStore.maxNameLength) 个字符；重名则覆盖。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func commitTemplatePrompt() {
        guard let p = tplPrompt else { return }
        if let old = p.original {
            tplNote = layout.renameTemplate(old, to: p.text, mode: s.mode) ?? ""
        } else {
            tplNote = layout.saveTemplate(name: p.text, mode: s.mode) ?? ""
        }
        tplPrompt = nil
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
        if s.mode == .gamepad {
            Section {
                Toggle(isOn: $gamepadCustom) {
                    Label("使用自定义组件布局", systemImage: "square.grid.2x2")
                }
                Toggle(isOn: $layout.editing) {
                    Label("编辑布局", systemImage: "hand.draw")
                }
            } header: {
                SettingsHeader("模式")
            } footer: {
                Text("关闭自定义时使用固定 Xbox 手柄皮肤。开启编辑后，顶部出现组件库；拖动移动、拖右下角缩放、✕ 删除。")
            }

            templateSection

            Section {
                Button(role: .destructive) { layout.reset(mode: s.mode) } label: {
                    Label("恢复默认布局", systemImage: "arrow.counterclockwise")
                }
                Button(role: .destructive) { layout.clear(mode: s.mode) } label: {
                    Label("清空当前模式", systemImage: "trash")
                }
            }

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
        } else {
            // heli/drive 用固定硬件皮肤，没有渲染路径：
            // 不提供自定义/同步，否则会让人以为改了却看不到效果。
            Section {
                Label("\(s.mode.label)模式使用固定硬件皮肤，不支持自定义布局。",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                SettingsHeader("模式")
            }
        }
    }

    // ---- 布局模板 ----

    @ViewBuilder private var templateSection: some View {
        Section {
            ForEach(layout.templates(mode: s.mode)) { tpl in
                Button {
                    layout.applyTemplate(tpl, mode: s.mode)
                    Haptics.select()
                    tplNote = "已应用「\(tpl.name)」"
                } label: {
                    HStack(spacing: 10) {
                        Text(tpl.name).foregroundColor(.primary)
                        if layout.isBuiltin(tpl) {
                            Text("内置")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                        }
                        Spacer(minLength: 8)
                        Text("\(tpl.widgets.count)")
                            .font(.system(size: 15)).monospacedDigit()
                            .foregroundColor(.secondary)
                        if layout.isCurrent(tpl, mode: s.mode) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.cyan)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !layout.isBuiltin(tpl) {
                        Button(role: .destructive) {
                            layout.deleteTemplate(tpl.name, mode: s.mode)
                            tplNote = "已删除「\(tpl.name)」"
                        } label: { Label("删除", systemImage: "trash") }
                        Button {
                            tplPrompt = TplPrompt(original: tpl.name, text: tpl.name)
                        } label: { Label("重命名", systemImage: "pencil") }
                            .tint(.orange)
                    }
                }
            }

            Button {
                tplPrompt = TplPrompt(original: nil, text: "")
            } label: {
                Label("将当前布局存为模板", systemImage: "plus.circle")
            }

            if layout.canUndo(mode: s.mode) {
                Button {
                    layout.undoLast(mode: s.mode)
                    Haptics.select()
                    tplNote = "已撤销上一次改动"
                } label: {
                    Label("撤销上一次改动", systemImage: "arrow.uturn.backward")
                }
            }
        } header: {
            SettingsHeader("模板")
        } footer: {
            if tplNote.isEmpty {
                Text("模板只存本机（不上传电脑）。点模板即切换；左滑可重命名/删除；「\(LayoutStore.builtinName)」是内置还原点。")
            } else {
                Text(tplNote).foregroundColor(Theme.orange)
            }
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
            SettingsHeader("轴反向")
        } footer: {
            Text("与游戏内设置二选一即可，避免双重反转。")
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
            SettingsHeader("灵敏度与死区")
        } footer: {
            Text("灵敏度 > 1 更跟手（更容易到满舵）；死区滤掉手指微抖。**点数值可直接输入精确值。**")
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
            InfoRow(label: "当前皮肤", value: s.mode.label)
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
            .foregroundColor(.white)
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
