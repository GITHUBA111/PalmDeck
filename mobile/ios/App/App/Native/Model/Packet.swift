import Foundation

/// 二进制热路径包，与电脑端 `PKT = struct.Struct("<2sBB8hH")` 完全对齐。
/// 布局：magic 'PD' | ver u8 | hat u8 | roll,pitch,yaw,look_x,look_y,thr,lt,rt i16 | buttons u16 (22 字节)
///
/// 这里只做「状态 → 纯数据」的适配：
/// 轴的真值表在 `AxisMap`，字节布局在 `PacketFormat`，两者都是可单测的纯函数。
enum Packet {
    static let size = PacketFormat.size

    static func pack(_ s: ControllerState) -> Data {
        PacketFormat.encode(
            hat: s.hat,
            axes: AxisMap.resolve(
                mode: s.mode,
                collective: s.collective,
                throttle: s.throttle,
                clutch: s.clutch,
                smRoll: s.smRoll,
                smPitch: s.smPitch,
                smYaw: s.smYaw,
                lookX: s.lookX,
                lookY: s.lookY,
                rt: s.rt,
                lt: s.lt
            ),
            buttons: s.btnMask
        )
    }
}
