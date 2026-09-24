import Foundation

/// G1：把「手感参数」从全局单键搬成**按模式分键**。
///
/// 升级前 `palmdeck_dz` 是三个模式共用的一份值，于是为飞机调出来的 0.06 死区
/// 会一直跟着赛车走 —— 开车本来就不需要死区（ETS2 自己有一份），叠加之后
/// 方向盘中位会多出一段死行程。
///
/// 这个文件只做两件事：**键名怎么拼**、**旧值怎么搬**。
/// 纯逻辑（不依赖 UIKit / Combine），所以 `tests/test_ios_axis.py` 能直接
/// 编译它跑迁移测试。
enum ShapingKeys {
    // 旧键名（无后缀）。迁移之后它们不再被读取，也不再被写入。
    static let sensX = "palmdeck_sens_x"
    static let sensY = "palmdeck_sens_y"
    static let dz = "palmdeck_dz"
    static let invX = "palmdeck_inv_x"
    static let invY = "palmdeck_inv_y"
    static let invYaw = "palmdeck_inv_yaw"
    static let invColl = "palmdeck_inv_coll"

    static let legacyDoubles = [sensX, sensY, dz]
    static let legacyBools = [invX, invY, invYaw, invColl]

    /// 受模式影响的全部旧键。迁移和测试共用这一份清单，防止漏掉某个键。
    static let legacyKeys = legacyDoubles + legacyBools

    /// `palmdeck_dz` + `heli` → `palmdeck_dz.heli`
    static func scoped(_ legacy: String, _ mode: CockpitMode) -> String {
        legacy + "." + mode.rawValue
    }
}

/// 迁移与读取需要的最小存储接口。
///
/// `UserDefaults` 天然满足（它的 `set(_:forKey:)` 正好收 `Any?`）；
/// 测试用一个字典替身，这样迁移逻辑可以不碰真实 UserDefaults 地验证。
protocol ShapingStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: ShapingStore {}

enum ShapingMigration {
    /// 把旧的全局键搬到**每个模式各自的键**上，然后删掉旧键。
    ///
    /// 关键性质：**迁移本身不改变任何手感** —— 升级前三个模式共用一个值，
    /// 迁移后三个模式各自拿到同一个值，行为逐位相同。
    /// 这条一旦被破坏，迁移就不再安全，所以它有专门的测试。
    ///
    /// 已经存在的新键不覆盖 —— 用户可能已经在新版本里调过；旧键仍然删掉，
    /// 否则「删旧键」这件事永远做不完。
    @discardableResult
    static func run(_ store: ShapingStore,
                    modes: [CockpitMode] = CockpitMode.allCases) -> [String] {
        var moved: [String] = []
        for legacy in ShapingKeys.legacyKeys {
            guard let value = store.object(forKey: legacy) else { continue }
            for mode in modes {
                let key = ShapingKeys.scoped(legacy, mode)
                if store.object(forKey: key) == nil {
                    store.set(value, forKey: key)
                }
            }
            store.removeObject(forKey: legacy)
            moved.append(legacy)
        }
        return moved
    }
}

/// 按模式读 / 写一个手感参数。读不到就回落 `fallback`（不是回落旧键 ——
/// 旧键的回落只在 `ControllerState` 的初始读取里做一次，之后旧键就没了）。
enum ShapingParams {
    static func double(_ store: ShapingStore, _ legacy: String,
                       _ mode: CockpitMode, _ fallback: Double) -> Double {
        (store.object(forKey: ShapingKeys.scoped(legacy, mode)) as? Double) ?? fallback
    }

    static func bool(_ store: ShapingStore, _ legacy: String,
                     _ mode: CockpitMode, _ fallback: Bool) -> Bool {
        (store.object(forKey: ShapingKeys.scoped(legacy, mode)) as? Bool) ?? fallback
    }

    static func set(_ store: ShapingStore, _ value: Any,
                    _ legacy: String, _ mode: CockpitMode) {
        store.set(value, forKey: ShapingKeys.scoped(legacy, mode))
    }
}
