import Foundation
import Combine
import QuartzCore

/// 座舱大脑：状态 + 网络 + 60Hz 热路径循环。
final class CockpitController: ObservableObject {

    let state = ControllerState()
    private let net = NetClient()
    private var touchActive = false   // 手指正在拖摇杆/轴（体感暂停）
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var lastSend = Date.distantPast
    private var retry = 0
    private var savedHost: String = ""
    private var lastTelem = Date.distantPast

    @Published var pfConnState: String = ""
    @Published var pfMotionState: String = ""
    @Published var readout: String = "R +0.00  P +0.00  Y +0.00  T 35%"

    /// 界面绑定的电脑 IP（持久化到 UserDefaults）
    @Published var savedHostForUI: String = UserDefaults.standard.string(forKey: "palmdeck_host") ?? ""

    /// 若曾保存过地址，自动重连
    func reconnectIfSaved() {
        if !savedHostForUI.isEmpty && state.link != .live {
            connect(host: savedHostForUI)
        }
    }

    init() {
        net.onOpen = { [weak self] in self?.handleOpen() }
        net.onClose = { [weak self] in self?.handleClose() }
        net.onJSON = { [weak self] obj in self?.handleJSON(obj) }
        startLoop()
        Haptics.prepare()
    }

    func setTouchActive(_ v: Bool) { touchActive = v }

    // MARK: - 连接
    func connect(host: String) {
        guard !host.isEmpty else { return }
        savedHost = host
        savedHostForUI = host
        UserDefaults.standard.set(host, forKey: "palmdeck_host")
        state.link = .connecting
        net.connect(host: host)
    }

    func reconnect() {
        guard !savedHost.isEmpty else { return }
        connect(host: savedHost)
    }

    /// 断开连接（保留已保存的 IP）
    func disconnect() {
        net.disconnect()
        state.link = .idle
        Haptics.tap()
    }

    private func handleOpen() {
        retry = 0
        state.link = .live
        Haptics.success()
        pfConnState = "已连接"
        // 上报当前模式
        net.sendJSON(["type": "mode", "name": state.mode.rawValue])
    }

    private func handleClose() {
        state.link = .lost
        state.transport = "idle"
        DispatchQueue.main.asyncAfter(deadline: .now() + min(4.0, 0.6 + Double(retry) * 0.4)) { [weak self] in
            guard let self else { return }
            self.retry += 1
            self.reconnect()
        }
    }

    private func handleJSON(_ obj: [String: Any]) {
        guard let type = obj["type"] as? String else { return }
        switch type {
        case "hello":
            if let u = obj["udp"] as? Int { /* 端口固定 7773，可按需更新 */ _ = u }
        case "status":
            DispatchQueue.main.async {
                self.state.backend = obj["backend"] as? String ?? ""
                self.state.deviceName = obj["device"] as? String ?? ""
                self.state.hz = obj["hz"] as? Double ?? 0
                self.state.transport = obj["transport"] as? String ?? "idle"
                self.state.lastError = obj["error"] as? String ?? ""
                if let cm = obj["cockpit_mode"] as? String,
                   let m = CockpitMode(rawValue: cm) { /* 服务端确认 */ }
                if self.state.backend != "none" {
                    self.pfConnState = "✓ " + self.state.deviceName
                } else {
                    self.pfConnState = self.state.lastError.isEmpty ? "未检测到手柄驱动" : self.state.lastError
                }
            }
        case "attitude":
            let r = (obj["roll"] as? Double) ?? 0
            let p = (obj["pitch"] as? Double) ?? 0
            let y = (obj["yaw"] as? Double) ?? 0
            DispatchQueue.main.async {
                self.state.telemRoll = max(-1, min(1, r))
                self.state.telemPitch = max(-1, min(1, p))
                self.state.telemYaw = max(-1, min(1, y))
                self.state.telemValid = true
                self.lastTelem = Date()
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
        state.mode = m
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

    private var frameCount = 0
    private var atLimit = false
    private func tick() {
        // 遥测超时：>1.5s 无姿态包 → 回退本地杆位（TODO：收不到则回退）
        if state.telemValid && Date().timeIntervalSince(lastTelem) > 1.5 {
            state.telemValid = false
        }
        // 平滑值始终本地更新（驱动 3D 模型），不依赖是否连上电脑
        state.tickSmoothing()
        // 轴到限位：进入满轴时轻震（只在已连接时，避免本地空振）
        let mag = max(abs(state.smRoll), abs(state.smPitch))
        let hit = mag > 0.97
        if hit && !atLimit && state.link == .live { Haptics.bump() }
        atLimit = hit
        // 读数降到 ~10Hz 更新（避免每帧触发 SwiftUI 重绘）
        frameCount += 1
        if frameCount % 6 == 0 {
            // 读数与 3D 直升机/姿态球同源：遥测激活时显示真实姿态
            readout = String(format: "R %+.2f  P %+.2f  Y %+.2f  T %d%%",
                             state.displayRoll, state.displayPitch, state.displayYaw,
                             Int((state.throttle * 100).rounded()))
        }
        // 仅在连接时把杆位发往电脑
        guard state.link == .live else { return }
        net.send(Packet.pack(state))
    }

    // 心跳 ping（5s）
    func ping() { net.sendJSON(["type": "ping", "t": Date().timeIntervalSince1970]) }
}
