import Foundation

/// 局域网自动发现（用 NetService，最兼容）。
/// PC 端 Bonjour 注册 `_palmdeck._udp`，服务名形如 `PalmDeck-192-168-3-103`。
/// 直接解析服务名里的 IP，无需 address resolve（最稳）。
final class Discovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published private(set) var found: DiscoveredHost?
    @Published private(set) var statusText = "搜索中…"

    struct DiscoveredHost: Equatable {
        var ip: String
        var ws: UInt16
        var udp: UInt16
        var name: String
    }

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        statusText = "搜索中…"
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_palmdeck._udp.", inDomain: "local.")
        browser = b
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.found == nil else { return }
            self.statusText = "没搜到电脑（需同一 Wi-Fi / 已授权本地网络）"
        }
    }

    func stop() {
        running = false
        browser?.stop()
        browser = nil
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async { [weak self] in self?.statusText = "开始搜索…(权限?)" }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "搜到服务：\(service.name)"
        }
        services.append(service)
        service.delegate = self
        // 从服务名直接提取 IP：PalmDeck-192-168-3-103
        let name = service.name
        if name.hasPrefix("PalmDeck-") {
            let ip = String(name.dropFirst("PalmDeck-".count)).replacingOccurrences(of: "-", with: ".")
            if ip.filter({ $0 == "." }).count == 3 {
                publish(ip: ip, name: "电脑")
                return
            }
        }
        // 兜底：resolve 拿地址
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addrs = sender.addresses else { return }
        for data in addrs {
            let ip = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> String? in
                guard let sa = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
                if sa.pointee.sa_family == sa_family_t(AF_INET) {
                    var sin = ptr.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
                    return String(cString: buf)
                }
                return nil
            }
            if let ip, !ip.isEmpty, ip != "127.0.0.1" {
                publish(ip: ip, name: sender.name)
                return
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "搜索失败：\(errorDict)"
        }
    }

    private func publish(ip: String, name: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.found?.ip != ip else { return }
            self.found = DiscoveredHost(ip: ip, ws: 8765, udp: 7773, name: name)
            self.statusText = "已发现 \(ip)"
            Haptics.tap()
        }
    }
}
