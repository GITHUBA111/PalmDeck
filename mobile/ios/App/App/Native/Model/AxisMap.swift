import Foundation

/// 一次发送里 8 个 i16 轴的最终取值（[-1, 1]）。
///
/// 顺序与电脑端 `PKT = struct.Struct("<2sBB8hH")` 一致：
/// `roll, pitch, yaw, look_x, look_y, thr, lt, rt`。
struct AxisOutputs: Equatable {
    var roll = 0.0
    var pitch = 0.0
    var yaw = 0.0
    var lookX = 0.0
    var lookY = 0.0
    var thr = 0.0
    var lt = 0.0
    var rt = 0.0
}

/// 模式 → 轴的**真值表**。
///
/// 为什么单独一个文件：这套映射原来内联在 `Packet.pack()` 里，
/// 只能靠读代码确认「开车时 Rz 到底给不给」。抽出来后既是唯一实现，也能被单测覆盖
/// （`AxisCoreTests`）。改这里等于改协议语义，必须同步 `docs/PalmDeck-v3-feature-design.md` §6。
///
/// 规则（与电脑端 `hotas.remap_vjoy` 对齐）：
///
/// | 模式 | roll(X) | pitch(Y) | yaw(Rz) | lookX(Rx) | lookY(Ry) | thr(Z) | lt | rt |
/// |---|---|---|---|---|---|---|---|---|
/// | heli | smRoll | smPitch | smYaw | 视角X | 视角Y | 总距 | max(lt,0) | rt |
/// | drive | smRoll | 离合 | **0** | 视角X | 视角Y | 油门 | max(lt,0) | 油门 |
/// | gamepad | smRoll | smPitch | smYaw | 视角X | 视角Y | **0** | **0** | **0** |
///
/// 三个模式在开车上的差异值得记住：
/// - **Rz 恒为 0**：离合改走左摇杆 Y（`pitch` 槽），不再占 Rz。
/// - **thr 与 rt 同时给油门**：Z 轴与右扳机都代表油门，游戏里任选一个绑。
/// - **rt 不再等于 `rt` 输入**：开车时右扳机的原始值被忽略。
///
/// gamepad 模式把 thr/lt/rt 全部清零，是因为手柄模式只发按键与摇杆，
/// 不动油门/刹车，避免误触游戏里的油门。
///
/// 本函数是全函数：所有入参先夹到 [-1, 1]，输出必然在 [-1, 1] 内。
enum AxisMap {

    /// 视角轴（look）固定死区。不改灵敏度：视角是速率控制，不是位置控制。
    static let lookDeadzone = 0.05

    static func resolve(
        mode: CockpitMode,
        collective: Double,
        throttle: Double,
        clutch: Double,
        smRoll: Double,
        smPitch: Double,
        smYaw: Double,
        lookX: Double,
        lookY: Double,
        rt: Double,
        lt: Double
    ) -> AxisOutputs {
        // 入参一律先夹到 [-1,1]：让本函数成为**全函数**，任何输入都给出合法输出。
        // 下游 `PacketFormat.quantize` 也会夹，但「真值表本身保证输出在范围内」
        // 比「靠调用方或下游兜底」可靠得多（实测过：不夹的话 shape 会把
        // 超范围视角输入放大到 1.77）。
        let c = AxisCurve.clampUnit
        let cRoll = c(smRoll), cPitch = c(smPitch), cYaw = c(smYaw)
        let cColl = c(collective), cThr = c(throttle), cClutch = c(clutch)
        let cLt = c(lt), cRt = c(rt)

        var o = AxisOutputs()
        o.roll = cRoll
        // 视角：输入已是单位区间，这里只做死区/曲线
        o.lookX = AxisCurve.shape(c(lookX), dz: lookDeadzone)
        o.lookY = AxisCurve.shape(c(lookY), dz: lookDeadzone)

        switch mode {
        case .heli:
            o.pitch = cPitch
            o.yaw = cYaw
            o.thr = cColl
            o.lt = max(cLt, 0)
            o.rt = cRt
        case .drive:
            o.pitch = cClutch          // 左摇杆 Y = 离合
            o.yaw = 0                  // Rz 不输出
            o.thr = cThr
            o.lt = max(cLt, 0)
            o.rt = cThr                // 油门同时走 Z 与右扳机
        case .gamepad:
            o.pitch = cPitch
            o.yaw = cYaw
            // thr / lt / rt 保持 0
        }
        return o
    }
}
