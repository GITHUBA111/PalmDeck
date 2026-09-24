// PalmDeck iOS 纯逻辑测试（不依赖 XCTest / 宿主 App / CocoaPods）
//
// 由 tests/test_ios_axis.py 用 swiftc 编译并运行：
//   swiftc -O -o <bin> AxisCurve.swift AxisMap.swift CockpitMode.swift AxisCoreTests.swift
//
// 覆盖对象都是「改错不会崩、只会悄悄发错轴」的代码 —— 这类错误在真机上极难发现，
// 所以必须在这里钉死。断言里出现的 0.3922920… 这类常量是用 Python 独立算出来
// 再硬编码的（见下方注释），不复用被测代码，避免自证。

import Foundation

var checks = 0
var failures: [String] = []

func expect(_ cond: Bool, _ msg: String) {
    checks += 1
    if !cond { failures.append(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ tol: Double = 1e-9, _ msg: String) {
    checks += 1
    if !(abs(a - b) <= tol) {
        failures.append("\(msg)：得到 \(a)，期望 \(b)（容差 \(tol)）")
    }
}

// MARK: - AxisCurve：整形曲线

// 常量来源：Python 独立计算 ((0.5-0)/1)**1.35
let HALF_NO_DZ = 0.3922920489483753
// ((0.5-0.1)/0.9)**1.35
let HALF_DZ10 = 0.33462131420943864
// ((0.5-0.05)/0.95)**1.35
let HALF_DZ05 = 0.3646783880430707

func testClampUnit() {
    expectClose(AxisCurve.clampUnit(0.5), 0.5, 1e-12, "clampUnit 不动区间内的值")
    expectClose(AxisCurve.clampUnit(1.5), 1.0, 1e-12, "clampUnit 上夹")
    expectClose(AxisCurve.clampUnit(-1.5), -1.0, 1e-12, "clampUnit 下夹")
    expectClose(AxisCurve.clampUnit(0), 0, 1e-12, "clampUnit 零点")
}

func testShapeBasics() {
    expectClose(AxisCurve.shape(0.5, dz: 0), HALF_NO_DZ, 1e-12, "shape 无死区取 0.5^1.35")
    expectClose(AxisCurve.shape(0.5, dz: 0.1), HALF_DZ10, 1e-12, "shape 带 0.1 死区")
    expectClose(AxisCurve.shape(0.5, dz: 0.05), HALF_DZ05, 1e-12, "shape 带 0.05 死区")
    expectClose(AxisCurve.shape(1, dz: 0), 1.0, 1e-12, "满输入映射到满输出")
    expectClose(AxisCurve.shape(1, dz: 0.5), 1.0, 1e-12, "死区不影响满输入")
    expectClose(AxisCurve.shape(-1, dz: 0.3), -1.0, 1e-12, "负满输入")
}

func testShapeSignAndSymmetry() {
    for dz in [0.0, 0.05, 0.12, 0.2] {
        for v in [0.3, 0.55, 0.8, 1.0] {
            expectClose(AxisCurve.shape(-v, dz: dz), -AxisCurve.shape(v, dz: dz), 1e-12,
                        "shape 关于原点对称 v=\(v) dz=\(dz)")
        }
    }
    // 符号必须跟随输入（-0.0 的处理）
    expect(AxisCurve.shape(-0.0, dz: 0) == 0, "shape(-0) 为 0")
}

func testShapeDeadzone() {
    // 死区内恒为 0，且边界（|v| == dz）也是 0
    expectClose(AxisCurve.shape(0.099, dz: 0.1), 0, 1e-12, "死区内为 0")
    expectClose(AxisCurve.shape(0.1, dz: 0.1), 0, 1e-12, "死区边界为 0")
    expectClose(AxisCurve.shape(-0.1, dz: 0.1), 0, 1e-12, "负侧死区边界为 0")
    expectClose(AxisCurve.shape(0, dz: 0.3), 0, 1e-12, "零点")
    // 刚出死区：连续（不能跳变）
    expect(AxisCurve.shape(0.100001, dz: 0.1) < 0.001, "出死区处连续、不跳变")
}

func testShapeDeadzoneClamped() {
    // dz 被夹到 [0, 0.95]：dz>=1 会导致除零，必须不崩且给出有限值
    let a = AxisCurve.shape(1.0, dz: 1.5)
    expect(a.isFinite, "dz=1.5 不产生 NaN/Inf")
    expectClose(a, 1.0, 1e-12, "dz 被夹到 0.95，满输入仍是 1")
    let b = AxisCurve.shape(0.5, dz: 5.0)
    expect(b.isFinite && b >= 0, "超大 dz 仍有限")
    let n = AxisCurve.shape(0.5, dz: -1.0)
    expectClose(n, HALF_NO_DZ, 1e-12, "负 dz 被夹到 0")
}

func testShapeMonotonic() {
    let dz = 0.08
    var prev = -1.0
    var x = -1.0
    while x <= 1.0001 {
        let y = AxisCurve.shape(x, dz: dz)
        expect(y >= prev - 1e-12, "shape 单调不减 @ x=\(x)")
        prev = y
        x += 0.01
    }
}

func testShapeScurve() {
    // 指数 > 1 → 中段低于 1:1（更细腻），且恒在 [-1,1] 内
    expect(AxisCurve.shape(0.5, dz: 0) < 0.5, "1.35 次幂 → 中段低于 1:1")
    for v in stride(from: -1.0, through: 1.0, by: 0.05) {
        let y = AxisCurve.shape(v, dz: 0.1)
        expect(y >= -1.0000001 && y <= 1.0000001, "shape 输出不越界 @ v=\(v)")
    }
}

func testOutputCombinesAll() {
    // 无灵敏度/死区/反转 → 与 shape 相同
    expectClose(AxisCurve.output(0.5), HALF_NO_DZ, 1e-12, "output 默认参数")
    // 反转
    expectClose(AxisCurve.output(0.5, inverted: true), -HALF_NO_DZ, 1e-12, "反转取负")
    // 灵敏度乘在进死区之前
    expectClose(AxisCurve.output(0.5, sensitivity: 0.5), AxisCurve.shape(0.25, dz: 0),
                1e-12, "灵敏度先乘")
    // 灵敏度放大后夹到 1
    expectClose(AxisCurve.output(0.6, sensitivity: 2.0), 1.0, 1e-12, "灵敏度放大后夹紧")
    // 组合：0.6*2=1.2→夹到1→dz .1 → 1
    expectClose(AxisCurve.output(0.6, sensitivity: 2.0, deadzone: 0.1), 1.0, 1e-12,
                "夹紧发生在死区之前")
    // 灵敏度把输入压进死区 → 0（顺序反了就不是 0）
    expectClose(AxisCurve.output(0.3, sensitivity: 0.2, deadzone: 0.1), 0, 1e-12,
                "灵敏度可在死区前把输入压回死区")
    // 反转 + 灵敏度 + 死区一起
    expectClose(AxisCurve.output(0.5, sensitivity: 1.0, deadzone: 0.1, inverted: true),
                -HALF_DZ10, 1e-12, "三者组合")
}

// MARK: - AxisMap：模式 → 轴的真值表

func outputs(_ mode: CockpitMode) -> AxisOutputs {
    AxisMap.resolve(mode: mode, collective: 0.7, throttle: 0.9, clutch: 0.4,
                    smRoll: 0.11, smPitch: 0.22, smYaw: 0.33,
                    lookX: 0.5, lookY: -0.5, rt: 0.66, lt: 0.55)
}

func testHeliTruthTable() {
    let o = outputs(.heli)
    expectClose(o.roll, 0.11, 1e-12, "heli roll = smRoll")
    expectClose(o.pitch, 0.22, 1e-12, "heli pitch = smPitch")
    expectClose(o.yaw, 0.33, 1e-12, "heli yaw = smYaw")
    expectClose(o.thr, 0.7, 1e-12, "heli thr = 总距")
    expectClose(o.lt, 0.55, 1e-12, "heli lt = lt")
    expectClose(o.rt, 0.66, 1e-12, "heli rt = rt")
    expectClose(o.lookX, HALF_DZ05, 1e-12, "heli lookX 过 0.05 死区")
    expectClose(o.lookY, -HALF_DZ05, 1e-12, "heli lookY 过 0.05 死区")
}

func testDriveTruthTable() {
    let o = outputs(.drive)
    expectClose(o.roll, 0.11, 1e-12, "drive roll = smRoll")
    expectClose(o.pitch, 0.4, 1e-12, "drive pitch = 离合（不是 smPitch）")
    expectClose(o.yaw, 0.0, 1e-12, "drive Rz 恒为 0")
    expectClose(o.thr, 0.9, 1e-12, "drive thr = 油门")
    expectClose(o.rt, 0.9, 1e-12, "drive rt 也 = 油门")
    expectClose(o.lt, 0.55, 1e-12, "drive lt 正常")
}

func testGamepadTruthTable() {
    let o = outputs(.gamepad)
    expectClose(o.thr, 0.0, 1e-12, "gamepad thr 必须为 0")
    expectClose(o.lt, 0.0, 1e-12, "gamepad lt 必须为 0")
    expectClose(o.rt, 0.0, 1e-12, "gamepad rt 必须为 0")
    expectClose(o.pitch, 0.22, 1e-12, "gamepad pitch = smPitch")
    expectClose(o.yaw, 0.33, 1e-12, "gamepad yaw = smYaw")
    expectClose(o.roll, 0.11, 1e-12, "gamepad roll = smRoll")
}

func testDriveIgnoresRawRt() {
    // 开车时右扳机原始值必须被忽略：rt 输入 0 / 1 都不改变输出
    let a = AxisMap.resolve(mode: .drive, collective: 0, throttle: 0.5, clutch: 0,
                            smRoll: 0, smPitch: 0, smYaw: 0, lookX: 0, lookY: 0, rt: 0, lt: 0)
    let b = AxisMap.resolve(mode: .drive, collective: 0, throttle: 0.5, clutch: 0,
                            smRoll: 0, smPitch: 0, smYaw: 0, lookX: 0, lookY: 0, rt: 1, lt: 0)
    expect(a == b, "drive 的 rt 输出只由油门决定，与原始 rt 无关")
    expectClose(a.rt, 0.5, 1e-12, "drive rt = 油门")
}

func testNegativeLtClamped() {
    for mode in CockpitMode.allCases {
        let o = AxisMap.resolve(mode: mode, collective: 0.5, throttle: 0.5, clutch: 0.5,
                                smRoll: 0, smPitch: 0, smYaw: 0, lookX: 0, lookY: 0,
                                rt: 0, lt: -0.8)
        expect(o.lt >= 0, "\(mode.rawValue)：负 lt 被夹到 0（得到 \(o.lt)）")
    }
}

func testLookDeadzone() {
    // 视角死区 0.05：小于它直接 0
    let o = AxisMap.resolve(mode: .heli, collective: 0, throttle: 0, clutch: 0,
                            smRoll: 0, smPitch: 0, smYaw: 0,
                            lookX: 0.04, lookY: -0.04, rt: 0, lt: 0)
    expectClose(o.lookX, 0, 1e-12, "视角死区内为 0")
    expectClose(o.lookY, 0, 1e-12, "视角死区内为 0（负）")
    expectClose(AxisMap.lookDeadzone, 0.05, 1e-12, "视角死区常量")
}

func testAllOutputsInRange() {
    // 三个模式 × 极端输入：所有轴必须在 [-1,1]
    for mode in CockpitMode.allCases {
        for v in stride(from: -1.5, through: 1.5, by: 0.25) {
            let o = AxisMap.resolve(mode: mode, collective: v, throttle: v, clutch: v,
                                    smRoll: v, smPitch: v, smYaw: v,
                                    lookX: v, lookY: v, rt: v, lt: v)
            for (name, x) in [("roll", o.roll), ("pitch", o.pitch), ("yaw", o.yaw),
                              ("lookX", o.lookX), ("lookY", o.lookY),
                              ("thr", o.thr), ("lt", o.lt), ("rt", o.rt)] {
                expect(x >= -1.0000001 && x <= 1.0000001,
                       "\(mode.rawValue).\(name) 越界：\(x) @ \(v)")
                expect(x.isFinite, "\(mode.rawValue).\(name) 非有限：\(x)")
            }
        }
    }
}

// MARK: - CockpitMode：兼容层

func testModeParse() {
    expect(CockpitMode.parse("heli") == .heli, "parse heli")
    expect(CockpitMode.parse("drive") == .drive, "parse drive")
    expect(CockpitMode.parse("gamepad") == .gamepad, "parse gamepad")
    expect(CockpitMode.parse("infantry") == .gamepad, "legacy infantry → gamepad")
    expect(CockpitMode.parse("nonsense") == .heli, "未知值回落 heli")
    expect(CockpitMode.parse(nil) == .heli, "nil 回落 heli")
    expect(CockpitMode.parse("") == .heli, "空串回落 heli")
    expect(CockpitMode.allCases.count == 3, "只有三个模式")
    expect(CockpitMode.gamepad.usesWidgetCanvas, "只有 gamepad 用组件画布")
    expect(!CockpitMode.heli.usesWidgetCanvas && !CockpitMode.drive.usesWidgetCanvas,
           "heli/drive 不用组件画布")
}

// MARK: - PacketFormat：字节布局（最容易错、最难查的一块）

func testPacketLayout() {
    // PKT = struct.Struct("<2sBB8hH") = 2+1+1+16+2 = 22 字节
    expect(PacketFormat.size == 22, "热路径包必须 22 字节")

    var a = AxisOutputs()
    a.roll = 0.5; a.pitch = -0.25; a.yaw = 1.0; a.lookX = -1.0
    a.lookY = 0.0; a.thr = 0.75; a.lt = -0.5; a.rt = 0.1
    let d = PacketFormat.encode(hat: 3, axes: a, buttons: 0x8001)

    expect(d.count == PacketFormat.size, "编码后长度必须是 22（得到 \(d.count)）")
    expect(Array(d[0..<2]) == [0x50, 0x44], "magic 必须是 'PD'")
    expect(d[2] == 1, "ver 必须是 1")
    expect(d[3] == 3, "hat 在第 3 字节")
    // 小端序实证：roll = 0.5 → 16384 → 0x4000 → 字节 [0x00, 0x40]
    expect(d[4] == 0x00 && d[5] == 0x40, "roll 在偏移 4 且为小端序（得到 \(d[4]),\(d[5])）")

    // 偏移 4..19 = 8 个 i16，顺序 roll,pitch,yaw,look_x,look_y,thr,lt,rt
    let want = [0.5, -0.25, 1.0, -1.0, 0.0, 0.75, -0.5, 0.1]
    for (i, v) in want.enumerated() {
        let off = 4 + i * 2
        let got = PacketFormat.readI16(d, at: off)
        let exp = PacketFormat.quantize(v)
        expect(got == exp, "偏移 \(off) 应为 \(exp)，得到 \(got)")
    }
    expect(PacketFormat.readU16(d, at: 20) == 0x8001, "buttons 在偏移 20")
    expect(d[20] == 0x01 && d[21] == 0x80, "buttons 为小端序（得到 \(d[20]),\(d[21])）")
}

func testQuantize() {
    expect(PacketFormat.quantize(0) == 0, "0 → 0")
    expect(PacketFormat.quantize(1) == 32767, "+1 → 32767（不是 32768）")
    expect(PacketFormat.quantize(-1) == -32767, "-1 → -32767")
    expect(PacketFormat.quantize(2) == 32767, "越界上夹")
    expect(PacketFormat.quantize(-2) == -32767, "越界下夹")
    // 四舍五入
    expect(PacketFormat.quantize(0.5) == Int16((0.5 * 32767.0).rounded()), "0.5 四舍五入")
    // 永远不产生 Int16.min（电脑端按 -32767..32767 处理）
    for v in stride(from: -3.0, through: 3.0, by: 0.017) {
        let q = PacketFormat.quantize(v)
        expect(q >= -32767 && q <= 32767, "quantize 越界：\(v) → \(q)")
    }
}

func testPacketIsDeterministicAndZeroed() {
    // 全零姿态 → 只有 magic/ver/hat 非零，轴全 0
    let z = PacketFormat.encode(hat: 0, axes: AxisOutputs(), buttons: 0)
    expect(z.count == 22, "零包长度")
    for off in stride(from: 4, through: 19, by: 2) {
        expect(PacketFormat.readI16(z, at: off) == 0, "零包偏移 \(off) 应为 0")
    }
    expect(PacketFormat.readU16(z, at: 20) == 0, "零包按钮")
    expect(z == PacketFormat.encode(hat: 0, axes: AxisOutputs(), buttons: 0), "同输入同输出")
}

// MARK: - 跑

testClampUnit()
testShapeBasics()
testShapeSignAndSymmetry()
testShapeDeadzone()
testShapeDeadzoneClamped()
testShapeMonotonic()
testShapeScurve()
testOutputCombinesAll()
testHeliTruthTable()
testDriveTruthTable()
testGamepadTruthTable()
testDriveIgnoresRawRt()
testNegativeLtClamped()
testLookDeadzone()
testAllOutputsInRange()
testModeParse()
testPacketLayout()
testQuantize()
testPacketIsDeterministicAndZeroed()

if failures.isEmpty {
    print("OK  \(checks) checks passed")
    exit(0)
} else {
    print("FAILED  \(failures.count)/\(checks)")
    for f in failures.prefix(40) { print("  ✗ \(f)") }
    exit(1)
}
