import Foundation
import Darwin

/// 网络：WebSocket（控制面 + 回退热路径）+ UDP（热路径）。
/// 协议与电脑端 bridge.py 对齐：WS :8765 JSON 控制，UDP :7773 收 22 字节 PD 包。
final class NetClient: NSObject {

    private(set) var host: String = ""
    private(set) var udpPort: UInt16 = 7773
    private(set) var wsPort: UInt16 = 8765

    private var ws: URLSessionWebSocketTask?
    private var session: URLSession!
    private var udpFD: Int32 = -1
    private var udpAddr = sockaddr_in()
    private let lock = NSLock()
    /// 当前连接是否已通知过断开（didClose 与 receive 失败可能都触发，去重）
    private var closedNotified = false
    /// 连接超时定时器（8s 没连上就报超时，避免“连接中”卡死）
    private var connectTimeoutWork: DispatchWorkItem?

    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onConnectTimeout: (() -> Void)?
    var onJSON: (([String: Any]) -> Void)?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - 连接
    func connect(host: String, wsPort: UInt16 = 8765, udpPort: UInt16 = 7773) {
        // 先拆旧连接：避免旧任务迟到的回调/重连叠加（重连风暴 → UI 卡死）
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        self.host = host
        self.wsPort = wsPort
        self.udpPort = udpPort
        openUDP()
        closedNotified = false
        let url = URL(string: "ws://\(host):\(wsPort)")!
        let task = session.webSocketTask(with: url)
        ws = task
        task.resume()
        listen()
        // 8 秒连不上 → 超时（多半是电脑防火墙拦了 TCP 8765，而不是没开机）
        connectTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.ws === task else { return }
            self.closedNotified = true
            self.ws?.cancel(with: .goingAway, reason: nil)
            self.onConnectTimeout?()
        }
        connectTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func disconnect() {
        connectTimeoutWork?.cancel()
        connectTimeoutWork = nil
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        closeUDP()
        // 主动断开：标记已通知，迟到的 didClose / receive 失败不再触发 onClose
        closedNotified = true
    }

    // MARK: - 热路径
    func send(_ data: Data) {
        // UDP 优先；UDP 不可用时回退 WS binary
        if udpFD >= 0 {
            var addr = udpAddr
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = withUnsafePointer(to: &addr) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        Darwin.sendto(udpFD, base, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            return
        }
        ws?.send(.data(data)) { _ in }
    }

    // MARK: - 控制面
    func sendJSON(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        ws?.send(.string(s)) { _ in }
    }

    private func listen() {
        guard let task = ws else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                // 迟到的旧任务消息直接丢弃（期间可能已重连）
                guard self.ws === task else { return }
                if case .string(let s) = msg,
                   let d = s.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    self.onJSON?(obj)
                }
                self.listen()
            case .failure:
                guard self.ws === task else { return }
                self.notifyClose()
            }
        }
    }

    private func notifyClose() {
        guard !closedNotified else { return }
        closedNotified = true
        onClose?()
    }

    // MARK: - UDP socket
    private func openUDP() {
        closeUDP()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = udpPort.bigEndian
        _ = host.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        udpFD = fd
        udpAddr = addr
    }

    private func closeUDP() {
        if udpFD >= 0 { Darwin.close(udpFD); udpFD = -1 }
    }
}

extension NetClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        guard webSocketTask === ws else { return }
        connectTimeoutWork?.cancel()
        connectTimeoutWork = nil
        onOpen?()
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === ws else { return }
        notifyClose()
    }
}
