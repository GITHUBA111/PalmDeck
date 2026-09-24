import Foundation

/// 二进制热路径包，与电脑端 `PKT = struct.Struct("<2sBB8hH")` 完全对齐。
/// 布局：magic 'PD' | ver u8 | hat u8 | roll,pitch,yaw,look_x,look_y,thr,lt,rt i16 | buttons u16 (22 字节)
enum Packet {
    static let size = 22

    static func pack(_ s: ControllerState) -> Data {
        var data = Data(capacity: size)
        data.append(0x50) // 'P'
        data.append(0x44) // 'D'
        data.append(1)    // ver
        data.append(s.hat) // hat

        // 真值表（与 JS packState 一致）；直升机油门 = 总距（可反转），开车油门不反转
        let coll: Double = s.mode == .heli ? s.collective : s.throttle
        let rtOut: Double = s.mode == .drive ? s.throttle
                          : s.mode == .gamepad ? 0
                          : s.rt
        let thrOut: Double = s.mode == .gamepad ? 0 : coll
        let ltOut: Double = s.mode == .gamepad ? 0 : max(s.lt, 0)

        // 开车时 Rz 不输出（离合改走左摇杆 Y），飞行时 Rz = 方向舵
        let rzOut: Double = s.mode == .drive ? 0 : s.smYaw
        // 开车时左摇杆 Y = 离合（滑条 0 → 中位，1 → -1 到底）；飞行时 Y = 俯仰
        let yOut: Double = s.mode == .drive ? s.clutch : s.smPitch
        appendI16(&data, s.smRoll)
        appendI16(&data, yOut)
        appendI16(&data, rzOut)
        appendI16(&data, shape(s.lookX, dz: 0.05))
        appendI16(&data, shape(s.lookY, dz: 0.05))
        appendI16(&data, thrOut)
        appendI16(&data, ltOut)
        appendI16(&data, rtOut)
        appendU16(&data, s.btnMask)
        return data
    }

    private static func appendI16(_ d: inout Data, _ v: Double) {
        let clamped = max(-1.0, min(1.0, v))
        let i = Int((clamped * 32767.0).rounded())
        var le = Int16(max(-32767, min(32767, i))).littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    private static func appendU16(_ d: inout Data, _ v: UInt16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    private static func shape(_ v: Double, dz: Double) -> Double {
        let s = v < 0 ? -1.0 : 1.0
        let a = abs(v)
        if a < dz { return 0 }
        return s * pow((a - dz) / (1 - dz), 1.35)
    }
}
