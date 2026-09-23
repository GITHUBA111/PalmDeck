import Foundation
import UIKit
import Capacitor
import Darwin

@objc(PalmDeckUdpPlugin)
public class PalmDeckUdpPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PalmDeckUdpPlugin"
    public let jsName = "PalmDeckUdp"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "close", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "haptic", returnType: CAPPluginReturnPromise)
    ]

    private var sock: Int32 = -1
    private var dest = sockaddr_in()
    private let lock = NSLock()

    @objc func open(_ call: CAPPluginCall) {
        let host = call.getString("host") ?? ""
        let port = UInt16(call.getInt("port") ?? 7773)
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            call.reject("udp socket failed")
            return
        }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        _ = host.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        sock = fd
        dest = addr
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
        call.resolve()
    }

    @objc func send(_ call: CAPPluginCall) {
        guard let b64 = call.getString("data"), let data = Data(base64Encoded: b64) else {
            call.resolve()
            return
        }
        lock.lock()
        let fd = sock
        var addr = dest
        lock.unlock()
        guard fd >= 0 else {
            call.resolve()
            return
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.sendto(fd, base, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        call.resolve()
    }

    @objc func close(_ call: CAPPluginCall) {
        lock.lock()
        closeLocked()
        lock.unlock()
        call.resolve()
    }

    private func closeLocked() {
        if sock >= 0 {
            Darwin.close(sock)
            sock = -1
        }
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // 原生触觉反馈：iOS WKWebView 不支持 navigator.vibrate，
    // 座舱通过 Capacitor.Plugins.PalmDeckUdp.haptic({ style }) 触发 Taptic Engine。
    @objc func haptic(_ call: CAPPluginCall) {
        let style = call.getString("style") ?? "light"
        DispatchQueue.main.async {
            switch style {
            case "light":
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case "medium":
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "heavy":
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case "rigid":
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            case "soft":
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            case "success":
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "warning":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case "error":
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case "selection":
                UISelectionFeedbackGenerator().selectionChanged()
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        call.resolve()
    }

    deinit {
        lock.lock()
        closeLocked()
        lock.unlock()
    }
}
