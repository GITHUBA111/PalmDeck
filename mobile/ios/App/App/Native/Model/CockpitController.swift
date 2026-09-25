import Foundation
import Combine
import QuartzCore

/// 座舱大脑：状态 + 网络 + 60Hz 热路径循环。
final class CockpitController: ObservableObject {

    let state = ControllerState()
    private let net = NetClient()
    private var touchActive = false   // 手指正在拖动手柄/踏板
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var lastSend = Date.distantPast
    private var retry = 0
    private let maxAttempts = 6         // 连不上最多试 6 次就停；不再无限重连
    private var savedHost: String = ""
    private var autoReconnect = false   // 仅「意外断线」才自动重连；手动断开不重连
    private var wsPort: UInt16 = 8765   // 服务端实际端口（hello 时分商）
    private var udpPort: UInt16 = 7773
    private var lastPing = Date.distantPast

    @Published var pfConnState: String = ""
    /// true = 自动重连已用尽尝试次数而放弃，界面上给「重试」。
    @Published var connectFailed = false

    /// 界面靠 `ControllerState.smRoll/smPitch/smYaw` 刷新（那三个是 @Published，
    /// 且在 tickSmoothing 里做了等值去重）。这里**不要**再放一个每帧赋值的
    /// @Published 字段当“心跳”：@Published 不去重，闲置时会把整棵树重绘 60 次/秒。

    /// 界面绑定的电脑 IP（持久化到 UserDefaults）
    @Published var savedHostForUI: String = {
        let h = UserDefaults.standard.string(forKey: "palmdeck_host") ?? ""
        return isBogusIP(h) ? "" : h
    }()

    init() {
        net.onOpen = { [weak self] in self?.handleOpen() }
        net.onClose = { [weak self] in self?.handleClose() }
        net.onConnectTimeout = { [weak self] in self?.handleConnectTimeout() }
        net.onJSON = { [weak self] obj in self?.handleJSON(obj) }
        startLoop()
        Haptics.prepare()
    }

    func setTouchActive(_ v: Bool) { touchActive = v }

    // MARK: - 连接
    func connect(host: String) { connect(host: host, ws: wsPort, udp: udpPort) }

    func connect(host: String, ws: UInt16, udp: UInt16) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        // 拒绝回环/假地址（如 127.0.0.1），否则会连到手机自己
        guard !isBogusIP(h) else {
            if h == savedHostForUI {
                savedHostForUI = ""
                UserDefaults.standard.removeObject(forKey: "palmdeck_host")
            }
            pfConnState = "无效地址：\(h)"
            state.link = .idle
            Haptics.warning()
            return
        }
        wsPort = ws
        udpPort = udp
        savedHost = h
        savedHostForUI = h
        UserDefaults.standard.set(h, forKey: "palmdeck_host")
        autoReconnect = true
        connectFailed = false
        retry = 0
        state.link = .connecting
        pfConnState = "正在连接 \(h)…"
        net.connect(host: h, wsPort: ws, udpPort: udp)
    }

    func reconnect() {
        guard !savedHost.isEmpty else { return }
        connect(host: savedHost)
    }

    /// 断开连接（保留已保存的 IP；手动断开后不再自动重连）
    func disconnect() {
        autoReconnect = false
        connectFailed = false
        net.disconnect()
        state.link = .idle
        state.transport = "idle"
        pfConnState = "已断开"
        Haptics.tap()
    }

    /// 取消正在进行的连接 / 停止自动重连（「连接中」点「取消」走这里）。
    /// 不丢已保存的 IP：下次点「连接」还是它。
    func cancelConnect() {
        autoReconnect = false
        connectFailed = false
        net.disconnect()
        state.link = .idle
        state.transport = "idle"
        pfConnState = "已取消连接"
        Haptics.tap()
    }

    private func handleOpen() {
        // 回调来自 URLSession 后台队列，切回主线程改状态（否则 SwiftUI 竞态/卡死）
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retry = 0
            self.connectFailed = false
            self.lastPing = Date()
            self.state.link = .live
            Haptics.success()
            self.pfConnState = "已连接"
            // 上报当前模式
            self.net.sendJSON(["type": "mode", "name": self.state.mode.rawValue])
            // 拉取电脑端保存的布局（没有则由 App 用内置默认）
            self.net.sendJSON(["type": "layouts_get"])
        }
    }

    // MARK: - 布局同步（P3）
    /// 服务端下发布局时回调（在 UI 层接到 LayoutStore）
    var onLayouts: (([String: Any]) -> Void)?

    func requestLayouts() { net.sendJSON(["type": "layouts_get"]) }

    func sendLayoutPut(mode: String, layout: [[String: Any]]) {
        net.sendJSON(["type": "layouts_put", "mode": mode, "layout": layout])
    }

    private func handleClose() {
        // 后台队列回调：切主线程改状态；仅在「意外断线」时按退避自动重连
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.link = .lost
            self.state.transport = "idle"
            self.pfConnState = self.autoReconnect ? "连接断开，重连中…" : "连接断开"
            // 意外断线才震：手动断开（autoReconnect=false）不吓人。
            // 对位航模遥控器的「信号丢失」蜂鸣。
            if self.autoReconnect { Haptics.warning() }
            self.scheduleReconnect(base: 0.6, step: 0.4, cap: 4.0)
        }
    }

    private func handleConnectTimeout() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.link = .lost
            self.state.transport = "idle"
            self.pfConnState = "连接超时：请检查电脑防火墙（放行 8765）"
            Haptics.warning()
            self.scheduleReconnect(base: 1.0, step: 0.5, cap: 8.0)
        }
    }

    /// 退避重连，但**有上限**：连不上就停，绝不无限重连。
    /// 用户也可以在「连接中」点「取消」（`cancelConnect()`）随时中断。
    private func scheduleReconnect(base: Double, step: Double, cap: Double) {
        guard autoReconnect else { return }
        guard retry < maxAttempts else {
            autoReconnect = false
            connectFailed = true
            state.link = .lost
            pfConnState = "连不上 \(savedHost)（已试 \(retry) 次），点「重试」"
            Haptics.warning()
            return
        }
        let delay = min(cap, base + Double(retry) * step)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.autoReconnect else { return }
            self.retry += 1
            self.reconnect()
        }
    }

    private func handleJSON(_ obj: [String: Any]) {
        guard let type = obj["type"] as? String else { return }
        switch type {
        case "hello":
            // 协商服务端实际端口（配置可改）；下次连接/重连使用
            DispatchQueue.main.async {
                if let w = obj["ws"] as? Int, w > 0, w <= 65535 { self.wsPort = UInt16(w) }
                if let u = obj["udp"] as? Int, u > 0, u <= 65535 { self.udpPort = UInt16(u) }
                // 记下电脑端版本，设置 → 关于里显示；主版本不一致时告警
                self.state.pcVersion = obj["version"] as? String ?? ""
                // 游戏预设用：记住电脑实际生效的轴表名（G3 之前只读显示）
                self.state.axisProfile = obj["axis_profile"] as? String ?? ""
            }
        case "status":
            DispatchQueue.main.async {
                self.state.backend = obj["backend"] as? String ?? ""
                self.state.deviceName = obj["device"] as? String ?? ""
                self.state.hz = obj["hz"] as? Double ?? 0
                self.state.transport = obj["transport"] as? String ?? "idle"
                self.state.lastError = obj["error"] as? String ?? ""
                // 注：服务端 hello 里的 `cockpit_mode` 只是回显，不采纳 ——
                // 模式是 App 本地选择（见 docs/PalmDeck-v4-app-interaction.md §3）。
                if self.state.backend != "none" {
                    self.pfConnState = "✓ " + self.state.deviceName
                } else {
                    self.pfConnState = self.state.lastError.isEmpty ? "未检测到手柄驱动" : self.state.lastError
                }
            }
        case "layouts":
            if let raw = obj["layouts"] as? [String: Any] {
                DispatchQueue.main.async { [weak self] in self?.onLayouts?(raw) }
            }
        case "pong":
            break
        default:
            break
        }
    }

    // MARK: - 模式
    func setMode(_ m: CockpitMode) {
        if m != state.mode { Haptics.press() }
        // G1：手感参数按模式分开存，切模式要把本模式那一份读回来
        state.applyMode(m)
        UserDefaults.standard.set(m.rawValue, forKey: "palmdeck_mode")
        state.resetAxes()
        state.hat = 255
        net.sendJSON(["type": "mode", "name": m.rawValue])
    }

    // MARK: - 60Hz 热路径
    private func startLoop() {
        // CADisplayLink：与屏幕刷新同步（60/120Hz），比 Timer 稳定不抖
        let link = CADisplayLink(target: self, selector: #selector(frameTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        // 限制到 ~60Hz（120Hz 屏上隔帧跑），发送与平滑都稳定
        let now = link.timestamp
        if now - lastFrameTime < 1.0 / 75.0 { return }
        lastFrameTime = now
        tick()
    }

    private var atLimit = false
    private func tick() {
        // 平滑值始终本地更新（驱动姿态球），不依赖是否连上电脑；
        // 界面刷新由 sm* 的 @Published 带动（没变就不发布，见 applySm）
        state.tickSmoothing()
        // 轴到限位：进入满轴时轻震（只在已连接时，避免本地空振）
        let mag = max(abs(state.smRoll), abs(state.smPitch))
        let hit = mag > 0.97
        if hit && !atLimit && state.link == .live { Haptics.bump() }
        atLimit = hit
        // 仅在连接时把杆位发往电脑
        guard state.link == .live else { return }
        // 5s 心跳：保活 WS / NAT
        let nowD = Date()
        if nowD.timeIntervalSince(lastPing) >= 5 { lastPing = nowD; ping() }
        net.send(Packet.pack(state))
    }

    // 心跳 ping（5s）
    func ping() { net.sendJSON(["type": "ping", "t": Date().timeIntervalSince1970]) }
}
