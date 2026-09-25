// PalmDeck G2 纯逻辑测试：游戏预设。
//
// 由 tests/test_ios_profiles.py 用 swiftc 编译并运行：
//   swiftc -o <bin> CockpitMode.swift ShapingKeys.swift GameProfile.swift GameProfileTests.swift
//
// `GameProfile.swift` 是纯类型（只 import Foundation），所以能脱离 App 跑。
// 应用顺序（先切模式再写手感）是这里最重要的断言：写反了预设就白切，
// 而且症状是「切了预设但手感没变」，在真机上很难归因。
//
// 存储走 `DictStore` 替身（同 ShapingKeys 测试），不碰真实 UserDefaults。

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
        failures.append("\(msg)：得到 \(a)，期望 \(b)")
    }
}

final class DictStore: ShapingStore {
    var d: [String: Any]
    init(_ d: [String: Any] = [:]) { self.d = d }
    func object(forKey key: String) -> Any? { d[key] }
    func set(_ value: Any?, forKey key: String) { d[key] = value }
    func removeObject(forKey key: String) { d.removeValue(forKey: key) }
}

/// 假的手感目标 + 假布局槽：记录 `GameProfileApplier` 的调用顺序。
final class FakeTarget: ShapingTarget {
    var sensX = 1.0, sensY = 1.0, dz = 0.06
    var invX = false, invY = false, invYaw = false, invColl = false
    var wheelMaxDeg = 540.0, wheelReturnSpeed = 720.0
}

final class Recorder {
    var events: [String] = []
    var mode: CockpitMode = .heli
    var layoutMode: CockpitMode?
    var layoutJSON: Data?
}

// MARK: - 1. 内置预设定义

func testBuiltins() {
    let all = GameProfileBuiltin.all()
    expect(all.count == 2, "内置两个预设，实际 \(all.count)")
    let names = Set(all.map { $0.name })
    expect(names == [GameProfileBuiltin.wardogs, GameProfileBuiltin.ets2], "内置名对齐规格")

    let w = GameProfileBuiltin.wardogsProfile()
    expect(w.mode == .heli, "WARDOGS 用飞机模式")
    expect(w.axesPreset == "hotas", "WARDOGS 吃 hotas 轴表")
    expectClose(w.dz, 0.06, 1e-12, "WARDOGS 死区保持默认 0.06")
    expect(w.sensX == 1.0 && w.sensY == 1.0, "WARDOGS 灵敏度 1.0")
    expect(!w.invX && !w.invY && !w.invYaw && !w.invColl, "WARDOGS 不反转")

    let e = GameProfileBuiltin.ets2Profile()
    expect(e.mode == .drive, "ETS2 用开车模式")
    expect(e.dz == 0.0, "ETS2 死区必须为 0（ETS2 自带一份，叠上去就是双重死区）")
    expect(e.sensX == 1.0 && e.sensY == 1.0, "ETS2 线性灵敏度（避免非线性叠加）")
    expect(e.wheelMaxDeg == 900, "ETS2 满舵 900°")
    expect(e.wheelReturnSpeed == 720, "ETS2 回正速度沿用默认")
}

// MARK: - 2. 编解码往返 + 缺字段回落

func testCodableRoundTrip() {
    var p = GameProfileBuiltin.ets2Profile()
    p.widgetsJSON = Data([1, 2, 3, 4])
    let data = try! JSONEncoder().encode(p)
    let back = try! JSONDecoder().decode(GameProfile.self, from: data)
    expect(back == p, "编解码往返必须逐字段相等")
    expect(back.widgetsJSON == Data([1, 2, 3, 4]), "布局 JSON 原样往返")
}

func testDecodeMissingFieldsFallBack() {
    // 旧格式：只有 name/mode + 部分手感字段，其余缺失
    let legacy = #"{"name":"老预设","mode":"drive","dz":0.03}"#
    let p = try! JSONDecoder().decode(GameProfile.self, from: Data(legacy.utf8))
    expect(p.name == "老预设", "name 解出来")
    expect(p.mode == .drive, "mode 解出来")
    expectClose(p.dz, 0.03, 1e-12, "显式给的 dz 保留")
    expectClose(p.sensX, 1.0, 1e-12, "缺 sensX 回落 1.0")
    expect(p.axesPreset == "hotas", "缺 axesPreset 回落 hotas（内置默认，永不删）")
    expect(!p.invX, "缺布尔回落 false")
    expect(p.widgetsJSON == nil, "缺 widgetsJSON 回落 nil")
    expect(p.wheelMaxDeg == nil, "缺 wheelMaxDeg 回落 nil（= 不改）")
}

func testModeLegacyValue() {
    // v3 遗留的 infantry 必须映射到 gamepad（CockpitMode.parse 的职责）
    let legacy = #"{"name":"步兵","mode":"infantry"}"#
    let p = try! JSONDecoder().decode(GameProfile.self, from: Data(legacy.utf8))
    expect(p.mode == .gamepad, "infantry 兼容成 gamepad")
}

func testWidgetsHelpers() {
    var p = GameProfileBuiltin.wardogsProfile()
    expect(p.widgetsJSON == nil, "新建预设默认无布局")
    p.setWidgets([1, 2, 3])                       // [Int] 也能编（泛型）
    expect(p.widgetsJSON != nil, "非空布局被编码")
    let ints: [Int] = p.widgets()
    expect(ints == [1, 2, 3], "泛型解码")
    p.setWidgets([Int]())                        // 空数组 → nil（省空间）
    expect(p.widgetsJSON == nil, "空布局存 nil")
    // 坏数据退化成空，不抛错（一个预设的布局坏了不能连累主功能）
    var bad = GameProfileBuiltin.wardogsProfile()
    bad.widgetsJSON = Data([0xFF, 0x00, 0x12])
    let empty: [Int] = bad.widgets()
    expect(empty.isEmpty, "坏布局退化成空数组")
}

// MARK: - 3. 存储：增删改 / 内置保护 / 上限

func testStoreCRUD() {
    let store = DictStore()
    let ps = GameProfileStore(store: store)
    expect(ps.all.count == 2, "初始只有两个内置")

    var mine = GameProfileBuiltin.ets2Profile()
    mine.name = "我的卡车"
    expect(ps.save(mine) == nil, "存用户预设成功")
    expect(ps.all.count == 3, "多了一个")
    expect(ps.find("我的卡车") != nil, "能查到")

    // 重名覆盖
    mine.dz = 0.05
    expect(ps.save(mine) == nil, "重名覆盖成功")
    expectClose(ps.find("我的卡车")!.dz, 0.05, 1e-12, "覆盖后的值生效")
    expect(ps.all.count == 3, "覆盖不新增")

    // 内置名不可存
    var dupBuiltin = GameProfileBuiltin.wardogsProfile()
    dupBuiltin.dz = 0.5
    expect(ps.save(dupBuiltin) != nil, "不得用内置名存用户预设")

    // 重命名
    expect(ps.rename("我的卡车", to: "卡车2") == nil, "重命名成功")
    expect(ps.find("卡车2") != nil && ps.find("我的卡车") == nil, "名字换了")
    expect(ps.rename("卡车2", to: GameProfileBuiltin.ets2) != nil, "不得改成内置名")

    // 删除
    ps.delete("卡车2")
    expect(ps.find("卡车2") == nil, "删掉了")

    // 上限
    for i in 0..<GameProfileStore.maxProfiles {
        var p = GameProfileBuiltin.ets2Profile()
        p.name = "p\(i)"
        _ = ps.save(p)
    }
    var overflow = GameProfileBuiltin.ets2Profile()
    overflow.name = "overflow"
    expect(ps.save(overflow) != nil, "超过 \(GameProfileStore.maxProfiles) 个必须拒绝")
}

func testStorePersistence() {
    let store = DictStore()
    do {
        let ps = GameProfileStore(store: store)
        var mine = GameProfileBuiltin.wardogsProfile()
        mine.name = "留存"
        mine.dz = 0.0123
        _ = ps.save(mine)
        ps.markActive("留存")
    }
    // 新开一个 store（模拟重启）——数据必须还在
    let ps2 = GameProfileStore(store: store)
    expect(ps2.find("留存") != nil, "重启后用户预设还在")
    expectClose(ps2.find("留存")!.dz, 0.0123, 1e-12, "重启后参数没变")
    expect(ps2.activeName == "留存", "重启后 activeName 保留")

    // activeName 清空时键要删掉
    ps2.markActive(nil)
    expect(store.object(forKey: GameProfileStore.activeKey) == nil, "清空 active 时删键")
}

func testStoreRejectsEmptyAndLong() {
    let ps = GameProfileStore(store: DictStore())
    var p = GameProfileBuiltin.wardogsProfile()
    p.name = "   "
    expect(ps.save(p) != nil, "空白名拒绝")
    p.name = String(repeating: "长", count: GameProfileStore.maxNameLength + 1)
    expect(ps.save(p) != nil, "超长名拒绝")
    p.name = String(repeating: "长", count: GameProfileStore.maxNameLength)
    expect(ps.save(p) == nil, "刚好到上限允许")
}

// MARK: - 4. 应用顺序（最关键）

func testApplyOrderModeBeforeShaping() {
    let rec = Recorder()
    let t = FakeTarget()
    t.dz = 0.06

    // 模拟真机：setMode 会把状态的手感读成该模式那一份（这里用一个标记表示）
    let setMode: (CockpitMode) -> Void = { m in
        rec.events.append("mode:\(m.rawValue)")
        rec.mode = m
    }
    var applied = false
    let replaceLayout: (Data?, CockpitMode) -> Void = { data, m in
        rec.events.append("layout:\(m.rawValue)")
        rec.layoutMode = m
        rec.layoutJSON = data
        applied = true
        _ = t
    }

    GameProfileApplier.apply(GameProfileBuiltin.ets2Profile(), to: t,
                             setMode: setMode, replaceLayout: replaceLayout)

    expect(rec.events == ["mode:drive", "layout:drive"],
           "先切模式、后换布局，实际 \(rec.events)")
    expect(rec.mode == .drive, "模式切到 drive")
    expect(rec.layoutMode == .drive, "布局替换发生在同一个模式上")
    expect(applied, "布局替换被调用了")
    expectClose(t.dz, 0.0, 1e-12, "ETS2 死区写进去了")
    expectClose(t.sensX, 1.0, 1e-12, "灵敏度写进去了")
    expect(t.wheelMaxDeg == 900, "满舵写进去了")
}

func testApplyDoesNotTouchWheelWhenNil() {
    let t = FakeTarget()
    t.wheelMaxDeg = 540
    t.wheelReturnSpeed = 500
    GameProfileApplier.apply(GameProfileBuiltin.wardogsProfile(), to: t,
                             setMode: { _ in }, replaceLayout: { _, _ in })
    expect(t.wheelMaxDeg == 540, "WARDOGS 的 wheelMaxDeg 为 nil，不得改动原值")
    expect(t.wheelReturnSpeed == 500, "WARDOGS 的 wheelReturnSpeed 为 nil，不得改动原值")
    expectClose(t.dz, 0.06, 1e-12, "但死区必须写成 0.06")
}

// MARK: - 跑

testBuiltins()
testCodableRoundTrip()
testDecodeMissingFieldsFallBack()
testModeLegacyValue()
testWidgetsHelpers()
testStoreCRUD()
testStorePersistence()
testStoreRejectsEmptyAndLong()
testApplyOrderModeBeforeShaping()
testApplyDoesNotTouchWheelWhenNil()

if failures.isEmpty {
    print("OK  \(checks) checks passed")
    exit(0)
} else {
    print("FAILED  \(failures.count)/\(checks)")
    for f in failures.prefix(40) { print("  ✗ \(f)") }
    exit(1)
}
