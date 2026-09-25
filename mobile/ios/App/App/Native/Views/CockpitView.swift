import SwiftUI

struct CockpitView: View {
    @ObservedObject var ctrl: CockpitController
    @ObservedObject var s: ControllerState
    @StateObject private var discovery = Discovery()
    @State private var showSettings = false
    @StateObject private var layout = LayoutStore()
    @StateObject private var profiles = GameProfileStore()
    @State private var showLibrary = false
    @State private var showTutorial = false
    @State private var naming = false
    @State private var tplName = ""
    var onExit: () -> Void = {}
    private var stripH: CGFloat { 28 }   // 底部仪表条高度

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
        }
        .background(CockpitBackdrop())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLibrary) { LibrarySheet(store: layout, mode: s.mode) }
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

    /// 库按钮：带绑定的直接加；滑条/按键弹选择
    private func libraryButton(_ title: String, _ kind: WidgetKind, _ defaultBinding: WidgetBinding?) -> some View {
        Button(title) {
            if let b = defaultBinding {
                layout.add(kind: kind, binding: b, mode: s.mode)
            } else {
                showLibrary = true
            }
        }
        .buttonStyle(CardButton(fillWidth: false, height: 28))
    }

    // MARK: 底部仪表条
    private var statusStrip: some View {
        HStack(spacing: 0) {
            HudCell(label: "ROL", value: String(format: "%+.1f°", s.smRoll), accent: axisAccent(s.smRoll))
            divider
            HudCell(label: "PIT", value: String(format: "%+.1f°", s.smPitch), accent: axisAccent(s.smPitch))
            divider
            HudCell(label: "YAW", value: String(format: "%+.1f°", s.smYaw), accent: axisAccent(s.smYaw))
            divider
            HudCell(label: "THR", value: String(format: "%.0f%%", s.throttle * 100), accent: s.throttle > 0.01 ? Theme.green : Theme.textDim)
            divider
            HudCell(label: "LINK", value: s.link == .live ? String(format: "%.0fHz", s.hz) : linkShort,
                    accent: s.link == .live ? Theme.green : (s.link == .connecting ? Theme.orange : Theme.textFaint))
            Spacer(minLength: 0)
            HudCell(label: "MODE", value: s.mode.label, accent: Theme.cyan)
            divider
            HudCell(label: "SRC", value: s.transport == "idle" ? "—" : s.transport.uppercased(),
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

    private func axisAccent(_ v: Double) -> Color {
        abs(v) < 0.01 ? Theme.textDim : Theme.cyan
    }

    // MARK: 顶部
    private func topBar(height: CGFloat) -> some View {
        ZStack {
            // 居中：模式开关（贴顶）
            HStack(spacing: 6) {
                ForEach(CockpitMode.allCases, id: \.self) { m in
                    Button(m.label) { ctrl.setMode(m); Haptics.press() }
                        .buttonStyle(CardButton(active: s.mode == m, accent: Theme.cyan, height: height))
                        .frame(width: 68)
                }
            }
            // 右侧：连接状态 + 齿轮 + 编辑
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                connectionChip(height: height)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 15))
                }
                .buttonStyle(CardButton(fillWidth: false, height: height))
                .frame(width: 40)
                Button {
                    layout.editing.toggle()
                    Haptics.press()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: layout.editing ? "checkmark.circle.fill" : "square.grid.2x2")
                            .font(.system(size: 13))
                        Text(layout.editing ? "完成" : "布局")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(CardButton(active: layout.editing, accent: Theme.orange, fillWidth: false, height: height))
                .frame(width: 64)
                .padding(.leading, 4)
            }
        }
        .frame(height: height)
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
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.green)
                    Text(String(format: "%.0fHz", s.hz))
                        .font(.system(size: 10, design: .monospaced))
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
                            .font(.system(size: 12))
                            .foregroundColor(!discovery.found.isEmpty ? Theme.green : Theme.textFaint)
                    }
                    Text(s.link == .connecting ? "连接中…" : (!discovery.found.isEmpty ? "一键连接" : "连接"))
                        .font(.system(size: 11, weight: .medium))
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
    @ViewBuilder
    private func deckBody(W: CGFloat, H: CGFloat) -> some View {
        ZStack {
            // 应用模板 / 撤销 / 恢复默认是整表替换，用 revision 强制重建画布，
            // 否则 EditableWidget 的 @State dragStart 会残留到新布局上。
            WidgetCanvas(store: layout, mode: s.mode, s: s, ctrl: ctrl)
                .id(layout.revision)
            if layout.editing { editBar }
        }
        .frame(width: W, height: H)
        .hudPanel(corner: 10, accent: Theme.cyan.opacity(0.5))
        .overlay(alignment: .top) { if !layout.editing { notConnectedBanner } }
        .alert("存为模板", isPresented: $naming) {
            TextField("模板名称", text: $tplName)
                .onChange(of: tplName) { v in
                    if v.count > LayoutStore.maxNameLength {
                        tplName = String(v.prefix(LayoutStore.maxNameLength))
                    }
                }
            Button("取消", role: .cancel) { }
            Button("确定") {
                _ = layout.saveTemplate(name: tplName, mode: s.mode)
                Haptics.success()
            }
        } message: {
            Text("快照当前布局（\(layout.widgets(mode: s.mode).count) 个组件），名称最多 \(LayoutStore.maxNameLength) 个字符；可在设置 → 布局里切换。")
        }
    }

    /// 编辑态下的顶部工具条（加组件 / 存模板 / 完成）。
    private var editBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("添加：").font(.system(size: 12)).foregroundColor(Theme.orange)
                libraryButton("按键", .button, nil)
                libraryButton("触摸板", .pad, .look)
                libraryButton("摇杆", .stick, .look)
                libraryButton("方向盘", .wheel, .roll)
                libraryButton("滑条", .slider, nil)
                libraryButton("苦力帽", .hat, .look)
                libraryButton("姿态球", .attitude, .roll)
                Spacer(minLength: 0)
                Button("存为模板") {
                    tplName = "布局 \(layout.customTemplates(mode: s.mode).count + 2)"
                    naming = true
                }
                .buttonStyle(CardButton(accent: Theme.orange, fillWidth: false, height: 30))
                Button("完成") { layout.editing = false; Haptics.press() }
                    .buttonStyle(CardButton(active: true, accent: Theme.cyan, fillWidth: false, height: 30))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.orange.opacity(0.7), lineWidth: 1))
            .padding(.horizontal, 6)
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }

    private var dotColor: Color {
        switch s.link {
        case .live: return .green
        case .connecting: return .orange
        case .lost: return .red
        case .idle: return .gray
        }
    }

    /// 未连接提示横幅（不遮挡控件，顶部居中、半透明、点击可连）
    @ViewBuilder
    private var notConnectedBanner: some View {
        if s.link != .live && s.link != .connecting {
            Button {
                if let d = discovery.found.first { ctrl.connect(host: d.ip, ws: d.ws, udp: d.udp) }
                else if !ctrl.savedHostForUI.isEmpty { ctrl.connect(host: ctrl.savedHostForUI) }
                else { showSettings = true }
                Haptics.tap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: !discovery.found.isEmpty ? "wifi" : "exclamationmark.triangle.fill")
                    Text(!discovery.found.isEmpty ? "点此连接电脑 \(discovery.found.first!.ip)" : "未连接电脑（先在电脑启动 PalmDeck）")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.orange.opacity(0.9)))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

}

/// 卡片式按钮样式（灰底 / 灰字，激活变绿）
struct CardButton: ButtonStyle {
    var active: Bool = false
    var accent: Color = Theme.cyan
    var fillWidth: Bool = true
    var height: CGFloat = 0   // 0 = 自适应父容器高度

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = (active || pressed) ? accent : Theme.panel
        let base = configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(active ? .white : (pressed ? accent : Theme.textDim))
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
            return AnyView(base.frame(height: height))
        } else {
            return AnyView(base.frame(maxHeight: .infinity))
        }
    }
}

/// 组件库：选类型 + 绑定，加到画布
struct LibrarySheet: View {
    @ObservedObject var store: LayoutStore
    let mode: CockpitMode
    @Environment(\.dismiss) private var dismiss

    @State private var kind: WidgetKind = .slider
    @State private var binding: WidgetBinding = .throttle

    var body: some View {
        NavigationView {
            Form {
                Section("组件类型") {
                    Picker("类型", selection: $kind) {
                        ForEach(WidgetKind.allCases, id: \.self) { k in Text(k.label).tag(k) }
                    }.pickerStyle(.segmented)
                }
                Section("绑定功能") {
                    Picker("绑定", selection: $binding) {
                        ForEach(WidgetBinding.allCases, id: \.self) { b in
                            Text(b.onlyOnVJoy ? "\(b.label) · 仅飞行" : b.label).tag(b)
                        }
                    }
                }
                if binding.onlyOnVJoy {
                    Section {
                        Label("第 11–16 号键只存在于 vJoy。Xbox 虚拟手柄只有 A/B/X/Y、LB/RB、视图/菜单、L3/R3 十个键，开车和手柄模式里选它不会生效。",
                              systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.amber)
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
        }
    }
}

/// 首次使用速览（一次性，可在设置「帮助」里重新打开）
struct CockpitTutorialView: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.22),
                                    Color(red: 0.06, green: 0.09, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        section(icon: "switch.2", title: "顶部",
                                text: "中间切「飞机 / 开车 / 手柄」；右侧是连接状态 + 齿轮设置（手柄模式多一个「布局」按钮）")
                        section(icon: "airplane", title: "飞机模式",
                                text: "硬件飞行甲板：总距杆（IDLE/FLY/MAX 止动）+ 脚舵 + 周期变距杆 + 仪表板（姿态球 / 扭矩 / 滚转俯仰）；按键簇：开火/投弹/起落架/灯光/悬停/视角")
                        section(icon: "car", title: "开车模式",
                                text: "方向盘（多圈、可调回正速度）+ 离合/刹车/油门三踏板 + 序列式档杆 + 转速表与仪表盘 + 视角板 + 按键簇")
                        section(icon: "gamepad", title: "手柄模式",
                                text: "Xbox 硬件皮肤：双摇杆 / 十字键 / ABXY / LB·RB / LT·RT / 视图·菜单；轴停发、不抢电脑键鼠。设置里可切回「自定义组件布局」")
                        section(icon: "square.grid.2x2", title: "自定义布局（仅手柄）",
                                text: "手柄模式点右上角「布局」：拖动移动、拖右下角缩放、✕ 删除；顶部组件库可加方向盘/滑条/触摸板/摇杆/苦力帽/姿态球/按键，可从电脑拉取 / 上传")
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
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(PrimaryButton())
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 24)).foregroundColor(.cyan)
                    .rotationEffect(.degrees(-45))
                Text("PalmDeck 座舱速览")
                    .font(.system(size: 24, weight: .heavy)).foregroundColor(.white)
            }
            Text("60 秒看懂每个区域，第一次上手不抓瞎")
                .font(.system(size: 13)).foregroundColor(.gray)
        }
        .padding(.bottom, 4)
    }

    private func section(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundColor(.cyan)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.cyan.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(text).font(.system(size: 12)).foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
