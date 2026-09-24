import Foundation

/// 热路径包的**字节布局**（纯函数，可单测）。
///
/// 与电脑端 `bridge.py` 的 `PKT = struct.Struct("<2sBB8hH")` 一一对应：
///
/// ```
/// 偏移  长度  字段
///  0     2    magic 'P','D'
///  2     1    ver = 1
///  3     1    hat（0 = 中位；见 Controls.swift 的 HAT_* 约定）
///  4     2    roll     i16 LE
///  6     2    pitch    i16 LE
///  8     2    yaw      i16 LE
/// 10     2    look_x   i16 LE
/// 12     2    look_y   i16 LE
/// 14     2    thr      i16 LE
/// 16     2    lt       i16 LE
/// 18     2    rt       i16 LE
/// 20     2    buttons  u16 LE
///             合计 22
/// ```
///
/// 轴标度：`[-1, 1] → [-32767, 32767]`，四舍五入。**不是** `-32768`——
/// 与电脑端 `_vjoy_axis` 的 `[1, 0x8000]` 标度对应，负满量程留 1 个刻度的余量。
///
/// 抽出来的理由：这段原来内联在 `Packet.pack()`，而它需要 `ControllerState`
/// （SwiftUI ObservableObject）才能编译，于是字节序/偏移这种最容易错、
/// 错了又最难查的东西一个测试都没有。现在它只依赖 `AxisOutputs`。
enum PacketFormat {

    /// 包总长。改这个值等于改协议。
    static let size = 22

    static let magic: [UInt8] = [0x50, 0x44]  // 'P','D'
    static let version: UInt8 = 1

    static func encode(hat: UInt8, axes: AxisOutputs, buttons: UInt16) -> Data {
        var d = Data(capacity: size)
        d.append(contentsOf: magic)
        d.append(version)
        d.append(hat)
        appendI16(&d, axes.roll)
        appendI16(&d, axes.pitch)
        appendI16(&d, axes.yaw)
        appendI16(&d, axes.lookX)
        appendI16(&d, axes.lookY)
        appendI16(&d, axes.thr)
        appendI16(&d, axes.lt)
        appendI16(&d, axes.rt)
        appendU16(&d, buttons)
        return d
    }

    /// 夹到 [-1,1] → ×32767 → 四舍五入 → 再夹到 i16 安全范围。
    static func quantize(_ v: Double) -> Int16 {
        let clamped = max(-1.0, min(1.0, v))
        let i = Int((clamped * 32767.0).rounded())
        return Int16(max(-32767, min(32767, i)))
    }

    static func appendI16(_ d: inout Data, _ v: Double) {
        var le = quantize(v).littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    static func appendU16(_ d: inout Data, _ v: UInt16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    // MARK: 解码（测试与排查用；电脑端也有一份等价的 struct.unpack）

    static func readI16(_ d: Data, at offset: Int) -> Int16 {
        let lo = UInt16(d[d.startIndex + offset])
        let hi = UInt16(d[d.startIndex + offset + 1])
        return Int16(bitPattern: lo | (hi << 8))
    }

    static func readU16(_ d: Data, at offset: Int) -> UInt16 {
        let lo = UInt16(d[d.startIndex + offset])
        let hi = UInt16(d[d.startIndex + offset + 1])
        return lo | (hi << 8)
    }
}
