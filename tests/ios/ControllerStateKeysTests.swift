// PalmDeck G1 集成测试：真的 `ControllerState`，注入的字典存储。
//
// 由 `tests/test_ios_state_keys.py` 编译并运行。它和 `AxisCoreTests.swift` 的分工：
//   - AxisCoreTests  → 迁移算法本身（纯函数，字典替身）
//   - 本文件         → 接线是否正确（`ControllerState` 有没有真的调迁移、
//                      `applyMode` 有没有真的换一套、写入有没有落到当前模式的键上）
//
// 后一类才是「改了 A 模式、B 模式跟着变」这种 bug 的真实藏身处：
// 算法对、接线错，一切照旧。
//
// 存储是注入的（`ControllerState(shapingStore:)`），所以跑测试不会往真实
// `UserDefaults` 里写一个字节 —— 「真实 `UserDefaults` 能不能当 store」
// 由 `extension UserDefaults: ShapingStore` 在**编译期**保证。

import Foundation

var checks = 0
var failures: [String] = []

func expect(_ cond: Bool, _ msg: String) {
    checks += 1
    if !cond { failures.append(msg) }
}

/// 字典替身：和 `tests/ios/AxisCoreTests.swift` 里的同名类型刻意保持一致。
final class DictStore: ShapingStore {
    var d: [String: Any]
    init(_ d: [String: Any] = [:]) { self.d = d }
    func object(forKey key: String) -> Any? { d[key] }
    func set(_ value: Any?, forKey key: String) { d[key] = value }
    func removeObject(forKey key: String) { d.removeValue(forKey: key) }
}

func scoped(_ store: ShapingStore, _ legacy: String, _ m: CockpitMode) -> Any? {
    store.object(forKey: ShapingKeys.scoped(legacy, m))
}

// MARK: - 1. 迁移在真对象上跑起来了

let store = DictStore()
store.set(0.09, forKey: ShapingKeys.dz)          // 老版本留下的全局键
store.set(true, forKey: ShapingKeys.invY)
let migrated = ControllerState(shapingStore: store)   // ← 真实初始化路径

expect(migrated.mode == .heli, "无 palmdeck_mode 时默认飞机，实际 \(migrated.mode.rawValue)")
expect(abs(migrated.dz - 0.09) < 1e-12, "迁移后当前模式应读到旧值 0.09，实际 \(migrated.dz)")
expect(migrated.invY == true, "迁移后当前模式应读到旧的反转开关")
expect(store.object(forKey: ShapingKeys.dz) == nil, "旧键 palmdeck_dz 必须删掉")
expect(store.object(forKey: ShapingKeys.invY) == nil, "旧键 palmdeck_inv_y 必须删掉")
for m in CockpitMode.allCases {
    expect(abs((scoped(store, ShapingKeys.dz, m) as? Double ?? -1) - 0.09) < 1e-12,
           "迁移必须覆盖 \(m.rawValue)，而不是只搬到当前模式")
    expect((scoped(store, ShapingKeys.invY, m) as? Bool) == true,
           "迁移必须覆盖 \(m.rawValue)（Bool 类型也不能丢）")
}

// MARK: - 2. 切模式 = 换一整套参数，且互不污染

migrated.applyMode(.drive)
expect(abs(migrated.dz - 0.09) < 1e-12, "迁移后开车也应是 0.09（迁移不改手感）")
migrated.dz = 0.0                              // 开车调成 0（ETS2 预设将来就是这么写的）
migrated.applyMode(.heli)
expect(abs(migrated.dz - 0.09) < 1e-12,
       "切回飞机必须还是 0.09 —— 这就是 G1 要修的 bug，实际 \(migrated.dz)")
migrated.applyMode(.drive)
expect(migrated.dz == 0.0, "切回开车必须还是 0，实际 \(migrated.dz)")
expect(abs((scoped(store, ShapingKeys.dz, .heli) as? Double ?? -1) - 0.09) < 1e-12, "飞机的值写在 heli 键上")
expect((scoped(store, ShapingKeys.dz, .drive) as? Double) == 0.0, "开车的值写在 drive 键上")

// MARK: - 3. 改一个参数只落当前模式的键

migrated.applyMode(.gamepad)
migrated.sensX = 1.7
migrated.invYaw = true
expect((scoped(store, ShapingKeys.sensX, .gamepad) as? Double) == 1.7, "灵敏度写到 gamepad 键上")
expect((scoped(store, ShapingKeys.invYaw, .gamepad) as? Bool) == true, "反转航向写到 gamepad 键上")
expect((scoped(store, ShapingKeys.sensX, .heli) as? Double) == 1.0, "飞机灵敏度不得被动")
expect((scoped(store, ShapingKeys.sensX, .drive) as? Double) == 1.0, "开车灵敏度不得被动")
expect((scoped(store, ShapingKeys.invYaw, .heli) as? Bool) == false, "飞机反转航向不得被动")
expect(store.object(forKey: ShapingKeys.sensX) == nil, "不得写出无后缀的全局键")
for k in ShapingKeys.legacyKeys {
    expect(store.object(forKey: k) == nil, "全流程结束后不应再有旧键 \(k)")
}

// MARK: - 4. 干净安装：默认值也落成显式值（读的时候不必再想兜底）

let clean = DictStore()
let fresh = ControllerState(shapingStore: clean)
expect(fresh.dz == 0.06, "干净安装的默认死区 0.06，实际 \(fresh.dz)")
expect(fresh.sensX == 1.0 && fresh.sensY == 1.0, "干净安装的默认灵敏度")
expect(fresh.invX == false && fresh.invY == false && fresh.invYaw == false && fresh.invColl == false,
       "干净安装的默认反转")
for k in ShapingKeys.legacyDoubles {
    expect((scoped(clean, k, .heli) as? Double) != nil, "干净安装也要把 \(k).heli 写出来")
}
for k in ShapingKeys.legacyBools {
    expect((scoped(clean, k, .heli) as? Bool) != nil, "干净安装也要把 \(k).heli 写出来")
}
expect(scoped(clean, ShapingKeys.dz, .gamepad) == nil, "没进过的模式不写——默认值由属性兜底")

// MARK: - 跑

if failures.isEmpty {
    print("OK  \(checks) checks passed")
    exit(0)
} else {
    print("FAILED  \(failures.count)/\(checks)")
    for f in failures.prefix(40) { print("  ✗ \(f)") }
    exit(1)
}
