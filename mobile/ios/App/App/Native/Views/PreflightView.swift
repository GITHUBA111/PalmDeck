import SwiftUI

/// 首次引导（座舱前一屏）：三步卡片 + 状态条 + 超大主按钮。
struct PreflightView: View {
    @ObservedObject var ctrl: CockpitController
    @ObservedObject var s: ControllerState
    @State private var host: String = ""
    @State private var showAdvanced = false
    @StateObject private var discovery = Discovery()
    @FocusState private var ipFocused: Bool
    var onEnter: () -> Void

    init(ctrl: CockpitController, onEnter: @escaping () -> Void) {
        self.ctrl = ctrl
        self._s = ObservedObject(wrappedValue: ctrl.state)
        self.onEnter = onEnter
        _host = State(initialValue: ctrl.savedHostForUI)
    }

    var body: some View {
        ZStack {
            CockpitBackdrop()

            HStack(spacing: 0) {
                // ── 左：品牌 + 主按钮
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 30))
                            .foregroundColor(Theme.cyan)
                            .rotationEffect(.degrees(-45))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PalmDeck").font(.system(size: 28, weight: .heavy)).foregroundColor(Theme.text)
                            Text("手机就是摇杆 / 方向盘").font(.system(size: 13)).foregroundColor(Theme.cyan.opacity(0.85))
                        }
                    }
                    Text("零硬件 · 可自定义 · 随身携带").font(.system(size: 11)).foregroundColor(Theme.textDim)
                        .padding(.top, 6)

                    Spacer()

                    statusBar

                    Button {
                        Haptics.press()
                        onEnter()
                    } label: {
                        HStack(spacing: 8) {
                            Text("进入座舱").font(.system(size: 19, weight: .bold))
                            Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(PrimaryButton())
                    .padding(.top, 12)

                    Text("不连电脑也能先进 → 连上后自动生效")
                        .font(.system(size: 11)).foregroundColor(Theme.textFaint)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(width: 300)

                // 分隔线
                Rectangle().fill(Theme.glass).frame(width: 1)
                    .padding(.vertical, 30)

                // ── 右：三步卡片
                VStack(alignment: .leading, spacing: 12) {
                    Spacer(minLength: 0)
                    Text("三步开始").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    stepCard(1, "desktopcomputer", "电脑装好 PalmDeck",
                             "Windows 双击 start.bat · Mac 运行 python3 bridge.py")
                    stepCard(2, "wifi", "手机连同一 Wi-Fi",
                             !discovery.found.isEmpty ? "已发现 \(discovery.found.count) 台电脑 ✓" : "和电脑连同一个路由器")
                    stepCard(3, "gamecontroller", "进座舱直接玩",
                             "在游戏里把 PalmDeck 当虚拟手柄绑一次即可")
                    if !discovery.found.isEmpty { discoveredList }
                    advanced
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .palmAppearance()
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { ipFocused = false }
            }
        }
    }

    // MARK: - 状态条
    private var statusDotColor: Color {
        if s.link == .live { return .green }
        if s.link == .connecting { return .orange }
        if s.link == .lost { return .red }
        if !discovery.found.isEmpty { return .cyan }
        return .gray
    }

    private var statusTitle: String {
        if s.link == .live { return "已连接  \(ctrl.savedHostForUI)" }
        if s.link == .connecting { return "正在连接…" }
        if s.link == .lost { return "连接失败" }
        if !discovery.found.isEmpty { return "发现 \(discovery.found.count) 台电脑" }
        return "正在搜索电脑…"
    }

    private var statusSub: String {
        if s.link == .live { return "\(String(format: "%.0f", s.hz)) Hz · 可以开始玩了" }
        if !ctrl.pfConnState.isEmpty { return ctrl.pfConnState }
        if !discovery.found.isEmpty { return "点下方电脑即可连接" }
        return "确保电脑端已启动、手机在同一 Wi-Fi"
    }

    private var statusTitleColor: Color {
        if s.link == .live { return .green }
        if s.link == .connecting { return .orange }
        if s.link == .lost { return .red }
        if !discovery.found.isEmpty { return .cyan }
        return .gray
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle().fill(statusDotColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(statusTitleColor)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(statusSub).font(.system(size: 10)).foregroundColor(Theme.textDim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            statusButton
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.glassBorder, lineWidth: 1))
        .onTapGesture {
            if s.link != .live, let d = discovery.best {
                ctrl.connect(host: d.ip, ws: d.ws, udp: d.udp); Haptics.tap()
            }
        }
    }

    private var statusButton: some View {
        Button(s.link == .live ? "断开" : (s.link == .connecting ? "…" : "连接")) {
            if s.link == .live { ctrl.disconnect() }
            else if s.link != .connecting {
                if let d = discovery.best { ctrl.connect(host: d.ip, ws: d.ws, udp: d.udp) }
                else { ctrl.connect(host: host) }
            }
            Haptics.tap()
        }
        .buttonStyle(CardButton(active: false,
                                accent: s.link == .live ? Theme.red : Theme.cyan,
                                fillWidth: false, height: 34))
        .frame(width: 76)
    }

    // MARK: - 三步卡片
    private func stepCard(_ n: Int, _ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.cyan.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17)).foregroundColor(Theme.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(n)").font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.cyan)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Theme.cyan.opacity(0.2)))
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                }
                Text(sub).font(.system(size: 11)).foregroundColor(Theme.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.glassBorder, lineWidth: 1))
    }

    // MARK: - 高级（手动 IP / 轴反向）
    private var advanced: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { showAdvanced.toggle() }
                if !showAdvanced { ipFocused = false }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                    Text("高级设置").font(.system(size: 12))
                }
                .foregroundColor(Theme.textDim)
            }
            .buttonStyle(.plain)

            if showAdvanced {
                HStack(spacing: 8) {
                    TextField("电脑 IP", text: $host)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelHi))
                        .foregroundColor(Theme.text)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($ipFocused)
                        .submitLabel(.done)
                        .onSubmit { connectManual() }
                    Button("连接") { connectManual() }
                        .buttonStyle(CardButton(active: false, accent: Theme.cyan, fillWidth: false, height: 34))
                        .frame(width: 70)
                }
                // 手动连接反馈：成功/失败/无效地址一目了然
                if !ctrl.pfConnState.isEmpty && s.link != .live {
                    Text(ctrl.pfConnState)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ctrl.pfConnState.contains("无效") || ctrl.pfConnState.contains("断开") ? Theme.red : Theme.orange)
                        .lineLimit(2)
                }
                // 反向开关是**按模式**保存的（G1）—— 不标出当前模式就会让用户以为
                // 自己改的是全局，实际改的是「现在这个模式」的那一份。
                HStack(spacing: 6) {
                    Text("轴反向 · \(s.mode.label)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textDim)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    invBtn("反转横滚", $s.invX)
                    invBtn("反转俯仰", $s.invY)
                    invBtn("反转舵", $s.invYaw)
                    invBtn("反转总距", $s.invColl)
                }
            }
        }
    }

    private func connectManual() {
        ipFocused = false
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        ctrl.connect(host: h)
        Haptics.tap()
    }

    /// 扫描到的所有电脑（点一下连接）
    private var discoveredList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("发现的电脑（点一下连接）").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textDim)
            ForEach(discovery.found, id: \.ip) { d in
                let isCurrent = s.link == .live && ctrl.savedHostForUI == d.ip
                Button {
                    ctrl.connect(host: d.ip, ws: d.ws, udp: d.udp); Haptics.tap()
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(isCurrent ? Theme.green : Theme.cyan).frame(width: 7, height: 7)
                        Image(systemName: "desktopcomputer").font(.system(size: 12)).foregroundColor(Theme.cyan)
                        Text(d.ip).font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.text)
                        Spacer()
                        Text(isCurrent ? "已连 ✓" : "连接")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isCurrent ? Theme.green : Theme.cyan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.glass))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isCurrent ? Theme.green.opacity(0.6) : Theme.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func invBtn(_ title: String, _ b: Binding<Bool>) -> some View {
        Button(title) { b.wrappedValue.toggle(); Haptics.tap() }
            .buttonStyle(CardButton(active: b.wrappedValue,
                                    accent: Theme.orange, fillWidth: false, height: 32))
    }
}

/// 大主按钮样式
struct PrimaryButton: ButtonStyle {
    var accent: Color = .green
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Theme.onAccent)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(configuration.isPressed ? accent.opacity(0.75) : accent)
                    .shadow(color: accent.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 10, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
