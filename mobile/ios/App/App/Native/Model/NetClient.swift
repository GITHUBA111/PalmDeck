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

    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onJSON: (([String: Any]) -> Void)?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - 连接
    func connect(host: String, wsPort: UInt16 = 8765, udpPort: UInt16 = 7773) {
        self.host = host
        self.wsPort = wsPort
        self.udpPort = udpPort
        openUDP()
        let url = URL(string: "ws://\(host):\(wsPort)")!
        let task = session.webSocketTask(with: url)
        ws = task
        task.resume()
        listen()
    }

    func disconnect() {
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        closeUDP()
        onClose?()
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
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let s) = msg,
                   let d = s.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    self.onJSON?(obj)
                }
                self.listen()
            case .failure:
                self.onClose?()
            }
        }
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
        onOpen?()
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose?()
    }
}
