import SwiftUI

struct CockpitView: View {
    @ObservedObject var ctrl: CockpitController
    @ObservedObject var s: ControllerState
    @StateObject private var discovery = Discovery()
    @State private var showSettings = false
    @StateObject private var layout = LayoutStore()
    @State private var showLibrary = false
    @State private var showTutorial = false
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
                if s.mode == .infantry {
                    infantryBody(W: W, H: bodyH)
                        .hudPanel(corner: 10, accent: Theme.cyan.opacity(0.5))
                } else {
                    ZStack {
                        WidgetCanvas(store: layout, mode: s.mode, s: s, ctrl: ctrl)
                        // 飞行模式的中心 3D 直升机（固定）
                        if s.mode == .heli {
                            HelicopterSceneView(state: s)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                                .frame(width: W * 0.22, height: bodyH * 0.42)
                                .position(x: W * 0.62, y: bodyH * 0.26)
                                .allowsHitTesting(false)
                        }
                        // 编辑时：组件库条（悬浮在顶部，半透明，不挤压布局）
                        if layout.editing {
                            VStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Text("添加：")
                                        .font(.system(size: 12)).foregroundColor(Theme.orange)
                                    libraryButton("方向盘", .wheel, .roll)
                                    libraryButton("滑条", .slider, nil)
                                    libraryButton("触摸板", .pad, .look)
                                    libraryButton("摇杆", .stick, .roll)
                                    libraryButton("苦力帽", .hat, .look)
                                    libraryButton("姿态球", .attitude, .roll)
                                    libraryButton("按键", .button, nil)
                                    Spacer(minLength: 0)
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
                    }
                    .frame(width: W, height: bodyH)
                    .hudPanel(corner: 10, accent: Theme.cyan.opacity(0.5))
                    .overlay(alignment: .top) { if !layout.editing { notConnectedBanner } }
                }
                telemetryStrip
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
            // 首次进入座舱自动弹一次速览（可在设置里重新打开）；延迟一帧确保能正常弹出
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
    private var telemetryStrip: some View {
        HStack(spacing: 0) {
            HudCell(label: "ROL", value: String(format: "%+.1f°", s.displayRoll), accent: axisAccent(s.displayRoll))
            divider
            HudCell(label: "PIT", value: String(format: "%+.1f°", s.displayPitch), accent: axisAccent(s.displayPitch))
            divider
            HudCell(label: "YAW", value: String(format: "%+.1f°", s.displayYaw), accent: axisAccent(s.displayYaw))
            divider
            HudCell(label: "THR", value: String(format: "%.0f%%", s.throttle * 100), accent: s.throttle > 0.01 ? Theme.green : Theme.textDim)
            divider
            HudCell(label: "LINK", value: s.link == .live ? String(format: "%.0fHz", s.hz) : linkShort,
                    accent: s.link == .live ? Theme.green : (s.link == .connecting ? Theme.orange : Theme.textFaint))
            Spacer(minLength: 0)
            HudCell(label: "MODE", value: s.mode.label, accent: Theme.cyan)
            divider
            HudCell(label: "SRC", value: s.displaySource == .telemetry ? (s.telemValid ? "遥测" : "等待") : "杆位",
                    accent: s.displaySource == .telemetry ? (s.telemValid ? Theme.orange : Theme.textFaint) : Theme.textDim)
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
        .sheet(isPresented: $showSettings) { SettingsSheet(ctrl: ctrl, s: s, layout: layout, discovery: discovery, onExit: onExit, onShowTutorial: {
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
                let target = discovery.found?.ip ?? ctrl.savedHostForUI
                if target.isEmpty { showSettings = true } else { ctrl.connect(host: target) }
                Haptics.tap()
            } label: {
                HStack(spacing: 5) {
                    if s.link == .connecting { ProgressView().scaleEffect(0.6).tint(Theme.cyan) }
                    else {
                        Image(systemName: discovery.found != nil ? "wifi" : "wifi.slash")
                            .font(.system(size: 12))
                            .foregroundColor(discovery.found != nil ? Theme.green : Theme.textFaint)
                    }
                    Text(s.link == .connecting ? "连接中…" : (discovery.found != nil ? "一键连接" : "连接"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(discovery.found != nil ? Theme.green : Theme.textFaint)
                }
            }
            .buttonStyle(CardButton(active: false, accent: Theme.cyan, fillWidth: false, height: height))
            .frame(width: 96)
        }
    }

    // MARK: 步兵模式（休息屏）
    private func infantryBody(W: CGFloat, H: CGFloat) -> some View {
        ZStack {
            // 步兵模式也支持自定义组件（给开火/投弹/地图等加触控键）
            WidgetCanvas(store: layout, mode: s.mode, s: s, ctrl: ctrl)

            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "figure.walk")
                    .font(.system(size: 34)).foregroundColor(Theme.cyan)
                Text("步兵模式")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(Theme.cyan)
                Text("键鼠操作中 · 轴已停（不会干扰鼠标）")
                    .font(.system(size: 14)).foregroundColor(Theme.textDim)
                Text("点右上角「布局」可加开火/投弹/地图等触控键")
                    .font(.system(size: 12)).foregroundColor(Theme.textFaint)
                Spacer()
            }
            .allowsHitTesting(false)

            // 编辑时：组件库条
            if layout.editing {
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
        }
        .frame(width: W, height: H)
        .overlay(alignment: .top) { if !layout.editing { notConnectedBanner } }
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
                let target = discovery.found?.ip ?? ctrl.savedHostForUI
                if target.isEmpty { showSettings = true } else { ctrl.connect(host: target) }
                Haptics.tap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: discovery.found != nil ? "wifi" : "exclamationmark.triangle.fill")
                    Text(discovery.found != nil ? "点此连接电脑 \(discovery.found!.ip)" : "未连接电脑（先在电脑启动 PalmDeck）")
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

/// 设置面板（从座舱齿轮进入）
struct SettingsSheet: View {
    @ObservedObject var ctrl: CockpitController
    @ObservedObject var s: ControllerState
    @ObservedObject var layout: LayoutStore
    var discovery: Discovery? = nil
    var onExit: () -> Void = {}
    var onShowTutorial: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("连接") {
                    HStack {
                        Text("电脑")
                        Spacer()
                        Text(ctrl.savedHostForUI.isEmpty ? "未设置" : ctrl.savedHostForUI)
                            .foregroundColor(.gray)
                    }
                    if let d = discovery?.found {
                        Button("连接已发现的 \(d.ip)") { ctrl.connect(host: d.ip) }
                    }
                    Button(s.link == .live ? "断开连接" : "连接") {
                        if s.link == .live { ctrl.disconnect() }
                        else { ctrl.connect(host: discovery?.found?.ip ?? ctrl.savedHostForUI) }
                    }
                    Button("返回启动页（换 IP / 重新引导）") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onExit() }
                    }
                }
                Section("布局") {
                    Toggle("编辑布局（拖动移动 · 拖右下角缩放）", isOn: $layout.editing)
                    Text("开启后顶部出现组件库：方向盘/滑条/触摸板/摇杆/苦力帽/姿态球/按键；拖动移动、拖右下角缩放、✕ 删除")
                        .font(.footnote).foregroundColor(.gray)
                    Button("恢复默认布局") { layout.reset(mode: s.mode) }
                    Button("清空当前模式") { layout.clear(mode: s.mode) }
                }
                Section("轴反向（游戏里也能改，两边二选一即可）") {
                    Toggle("反转横滚 Roll", isOn: $s.invX)
                    Toggle("反转俯仰 Pitch", isOn: $s.invY)
                    Toggle("反转方向舵 Yaw", isOn: $s.invYaw)
                    Toggle("反转总距 Collective", isOn: $s.invColl)
                }
                Section("摇杆") {
                    Toggle("松手回中", isOn: $s.stickReturn)
                }
                Section("方向盘（开车）") {
                    HStack {
                        Text("满舵角度")
                        Slider(value: $s.wheelMaxDeg, in: 180...900, step: 90)
                        Text(String(format: "%.1f圈", s.wheelMaxDeg/360)).frame(width: 48)
                    }
                    HStack {
                        Text("回正速度")
                        Slider(value: $s.wheelReturnSpeed, in: 0...1440, step: 60)
                        Text(s.wheelReturnSpeed == 0 ? "不回" : String(format: "%.0f°/s", s.wheelReturnSpeed)).frame(width: 56)
                    }
                    Text("回正速度 0 = 松手保持（不回正）")
                        .font(.footnote).foregroundColor(.gray)
                }
                Section("3D 显示源") {
                    Picker("姿态来源", selection: $s.displaySource) {
                        ForEach(DisplaySource.allCases, id: \.self) { src in
                            Text(src.label).tag(src)
                        }
                    }
                    if s.displaySource == .telemetry {
                        Text(s.telemValid ? "已收到游戏遥测 ✓" : "等待遥测…（电脑端需开启 --telemetry）")
                            .font(.footnote).foregroundColor(s.telemValid ? .green : .gray)
                    }
                }
                Section("帮助") {
                    Button("查看使用教程") { onShowTutorial() }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
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
                        ForEach(WidgetBinding.allCases, id: \.self) { b in Text(b.label).tag(b) }
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
                                text: "中间切「飞机 / 开车 / 步兵」；右侧是连接状态 + 齿轮设置 + 布局")
                        section(icon: "airplane", title: "飞机模式",
                                text: "姿态球（左）+ 3D 直升机（右）实时显示杆位/游戏姿态；左列油门/横滚/俯仰 + 苦力帽视角；右列摇杆（松手回中）/开火/方向舵 + 武器键")
                        section(icon: "car", title: "开车模式",
                                text: "触摸方向盘（多圈、可调回正速度）+ 油门/刹车/离合滑条 + 升/降档 + 视角触摸板")
                        section(icon: "figure.walk", title: "步兵模式",
                                text: "键鼠休息屏，轴不发，不干扰鼠标；仍可布局加开火/投弹等触控键")
                        section(icon: "square.grid.2x2", title: "自定义布局",
                                text: "点右上角「布局」：拖动移动、拖右下角缩放、✕ 删除；顶部组件库可加方向盘/滑条/触摸板/摇杆/苦力帽/姿态球/按键")
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
