import Foundation

/// 是否是可用的局域网 IPv4（排除回环 / 0.x / link-local / Clash fake-ip / 组播广播）
func usableLanIP(_ ip: String) -> Bool {
    let parts = ip.split(separator: ".")
    guard parts.count == 4 else { return false }
    guard let a = Int(parts[0]), let b = Int(parts[1]) else { return false }
    if a == 0 || a == 127 { return false }
    if a == 169 && b == 254 { return false }
    if a == 198 && (18...19).contains(b) { return false }
    if a >= 224 { return false }
    return true
}

/// 连接前的轻校验：只拦明显连不上的回环/假地址；主机名等非 IPv4 放行
func isBogusIP(_ host: String) -> Bool {
    let parts = host.split(separator: ".")
    guard parts.count == 4, let a = Int(parts[0]) else { return false }
    if a == 0 || a == 127 { return true }
    if let b = Int(parts[1]) {
        if a == 169 && b == 254 { return true }
        if a == 198 && (18...19).contains(b) { return true }
    }
    if a >= 224 { return true }
    return false
}

/// 局域网自动发现（用 NetService，最兼容）。
/// PC 端 Bonjour 注册 `_palmdeck._udp`，服务名形如 `PalmDeck-192-168-3-103`。
/// 直接解析服务名里的 IP，无需 address resolve（最稳）。
final class Discovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    /// 所有可连接的电脑（已按发现顺序排列，过滤掉回环/假地址）
    @Published private(set) var found: [DiscoveredHost] = []
    @Published private(set) var statusText = "搜索中…"

    /// 最优先的一台（列表第一项）
    var best: DiscoveredHost? { found.first }

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
            guard let self, self.found.isEmpty else { return }
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
            // 名称已编码 IP；无效（如回环 127）不发布，也无需 resolve
            if usableLanIP(ip) {
                publish(ip: ip, name: "电脑")
            }
            return
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
            if let ip, usableLanIP(ip) {
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
            guard let self else { return }
            guard usableLanIP(ip) else { return }      // 忽略回环/假地址
            guard !self.found.contains(where: { $0.ip == ip }) else { return }
            self.found.append(DiscoveredHost(ip: ip, ws: 8765, udp: 7773, name: name))
            self.statusText = "已发现 \(ip)"
            Haptics.tap()
        }
    }
}
