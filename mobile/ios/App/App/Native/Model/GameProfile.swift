import Foundation

/// 预设要写入的「手感参数」最小接口。
///
/// 抽出来是为了让 `GameProfileApplier` **不依赖 `ControllerState`**（后者 import Combine）——
/// 于是 `GameProfile.swift` 仍是纯类型，`swiftc` 能单独编译它 + 一个假实现跑应用顺序。
/// `ControllerState` 在 `Model/ControllerState.swift` 里 conformity。
protocol ShapingTarget: AnyObject {
    var sensX: Double { get set }
    var sensY: Double { get set }
    var dz: Double { get set }
    var invX: Bool { get set }
    var invY: Bool { get set }
    var invYaw: Bool { get set }
    var invColl: Bool { get set }
    var wheelMaxDeg: Double { get set }
    var wheelReturnSpeed: Double { get set }
}

/// 游戏预设：把「一份全局轴设置」变成「一套可命名、可一键切换的游戏适配」。
///
/// 一个预设 = 电脑侧轴表名 + App 侧手感参数 + 布局（含按钮标签）。
/// 三层分居两侧、用**同一个预设名**对齐，理由见 `docs/PalmDeck-v4-game-profiles.md` §3.1：
///
/// | 层 | 在哪 | 为什么不能搬 |
/// |---|---|---|
/// | 电脑侧轴表 | 电脑 | `remap_vjoy` 在 HID 写入路径上；22B 热路径字段名是冻的 |
/// | App 侧手感 | App | 整形发生在发送前（`ControllerState.tickSmoothing`） |
/// | App 侧布局 | App | `palmdeck_widgets_v10` 是本地键 |
///
/// **预设只有两种形态**（`docs/PalmDeck-v4-unified-presets.md`）：
///
/// | 形态 | 判据 | 点一下 |
/// |---|---|---|
/// | **整机** | `hasShaping == true` | 切模式 → 写手感 → 有布局就换 |
/// | **布局** | `hasShaping == false` | 只换当前模式的组件，手感一点不动 |
///
/// 从前还有一套平行的“布局模板”（另一个列表、另一个存储键），现已并入本类型：
/// 同一个“存快照、一键切回”的心里动作不该有两个入口。
///
/// **本文件是纯类型**（只 import Foundation），所以 `tests/test_ios_profiles.py`
/// 能用 `swiftc` 直接编译它跑编解码 / 内置定义 / 迁移 / 应用顺序的核心逻辑。
///
/// 布局（`DeckWidget` 数组）以**编码后的 JSON** 存在 `widgetsJSON` 里，而不是
/// 直接放 `[DeckWidget]`：后者会把 `Widgets.swift`（import SwiftUI）拖进测试编译单元。
/// 存取走 `widgets` / `setWidgets`，SwiftUI 侧只管调用，不知道底下是 Data。
struct GameProfile: Codable, Equatable, Identifiable {
    var name: String            // 预设名，如「WARDOGS」
    var mode: CockpitMode       // 套哪个模式的机组布局（三个模式都是通用画布）
    var axesPreset: String      // 电脑侧轴表名，如 "hotas" / "fbw"
    var sensX: Double
    var sensY: Double
    var dz: Double
    var invX: Bool
    var invY: Bool
    var invYaw: Bool
    var invColl: Bool
    /// ETS2 需要 900° 满舵；nil = 不改（沿用该模式当前值）。
    var wheelMaxDeg: Double?
    /// 卡车方向盘不应快速回正；nil = 不改。
    var wheelReturnSpeed: Double?
    /// 编码后的 `[DeckWidget]`；**nil = 这个预设不带布局**。
    ///
    /// nil 的含义是「别碰用户的画布」，不是「把画布清空」——见
    /// `LayoutStore.applyProfile`。内置预设都是 nil（只快照手感）。
    var widgetsJSON: Data?
    /// 这个预设**要不要写手感**。
    ///
    /// - `true`（缺省）= **整机**预设：模式 + 手感 + 布局。
    /// - `false` = **布局**预设：只装布局，上面那串手感字段一律忽略。
    ///
    /// 解码缺省是 `true`：老的 `palmdeck_game_profiles_v1` 里**所有**预设都是整机预设，
    /// 所以旧 JSON 原样解出来就是对的（迁移不用改一个字节）。
    var hasShaping: Bool

    var id: String { name }

    /// 行尾章用。`true` 这一支是「整机」，`false` 是「布局」；「内置」由 UI 另加。
    var kindLabel: String { hasShaping ? "整机" : "布局" }

    /// 这个预设带不带布局（`nil` = 不带）。
    var hasLayout: Bool { widgetsJSON != nil }

    /// 该模式是否走通用画布（E2 收尾后恒为 true，保留给“将来可能出现的非画布模式”一个开关）。
    /// 与「预设带不带布局」是两件事：后者看 `widgetsJSON`。
    var usesWidgetCanvas: Bool { mode.usesWidgetCanvas }

    /// 解码布局。**返回空数组 ≠ 空布局**，只表示“这个预设没带布局”：
    /// 调用方据此决定“不碰用户布局”（`LayoutStore.applyProfile`）。
    /// 坏数据也退化成空数组而不是抛错 —— 一个预设的布局坏了
    /// 不该连累「切手感/切模式」这件主功能。
    func widgets<T: Decodable>(_ type: T.Type = T.self) -> [T] {
        guard let d = widgetsJSON else { return [] }
        return (try? JSONDecoder().decode([T].self, from: d)) ?? []
    }

    /// 编码布局。空数组存 nil（省空间、也便于判断「这个预设没有布局」）。
    mutating func setWidgets<T: Encodable>(_ list: [T]) {
        if list.isEmpty { widgetsJSON = nil; return }
        widgetsJSON = try? JSONEncoder().encode(list)
    }

    /// 缺字段时的回落：`Job`/旧格式没有 `widgetsJSON`/`axesPreset` 等也应能解出来。
    /// 手写 `init(from:)` 是唯一能对**单个缺失字段**给默认值的方式
    /// （合成的解码器遇到缺失 key 会直接抛 keyNotFound）。
    init(name: String, mode: CockpitMode, axesPreset: String,
         sensX: Double, sensY: Double, dz: Double,
         invX: Bool, invY: Bool, invYaw: Bool, invColl: Bool,
         wheelMaxDeg: Double? = nil, wheelReturnSpeed: Double? = nil,
         widgetsJSON: Data? = nil, hasShaping: Bool = true) {
        self.name = name
        self.mode = mode
        self.axesPreset = axesPreset
        self.sensX = sensX
        self.sensY = sensY
        self.dz = dz
        self.invX = invX
        self.invY = invY
        self.invYaw = invYaw
        self.invColl = invColl
        self.wheelMaxDeg = wheelMaxDeg
        self.wheelReturnSpeed = wheelReturnSpeed
        self.widgetsJSON = widgetsJSON
        self.hasShaping = hasShaping
    }

    /// 「布局」预设：只装布局（手感字段全给默认值，反正不会被读）。
    static func layoutOnly(name: String, mode: CockpitMode,
                           widgetsJSON: Data?, axesPreset: String = "hotas") -> GameProfile {
        GameProfile(name: name, mode: mode, axesPreset: axesPreset,
                    sensX: 1.0, sensY: 1.0, dz: 0.06,
                    invX: false, invY: false, invYaw: false, invColl: false,
                    widgetsJSON: widgetsJSON, hasShaping: false)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        mode = CockpitMode.parse(try c.decodeIfPresent(String.self, forKey: .mode))
        // 旧格式可能没有轴表名：回落 hotas（内置默认，永不删）
        axesPreset = try c.decodeIfPresent(String.self, forKey: .axesPreset) ?? "hotas"
        sensX = try c.decodeIfPresent(Double.self, forKey: .sensX) ?? 1.0
        sensY = try c.decodeIfPresent(Double.self, forKey: .sensY) ?? 1.0
        dz = try c.decodeIfPresent(Double.self, forKey: .dz) ?? 0.06
        invX = try c.decodeIfPresent(Bool.self, forKey: .invX) ?? false
        invY = try c.decodeIfPresent(Bool.self, forKey: .invY) ?? false
        invYaw = try c.decodeIfPresent(Bool.self, forKey: .invYaw) ?? false
        invColl = try c.decodeIfPresent(Bool.self, forKey: .invColl) ?? false
        wheelMaxDeg = try c.decodeIfPresent(Double.self, forKey: .wheelMaxDeg)
        wheelReturnSpeed = try c.decodeIfPresent(Double.self, forKey: .wheelReturnSpeed)
        widgetsJSON = try c.decodeIfPresent(Data.self, forKey: .widgetsJSON)
        // 缺字段 = 老预设 = 整机预设（v1 里没有「只装布局」这种东西）
        hasShaping = try c.decodeIfPresent(Bool.self, forKey: .hasShaping) ?? true
    }
}

/// 老存储 → 新存储的一次性合并（`palmdeck_game_profiles_v2`）。
///
/// 两个老键：
/// - `palmdeck_game_profiles_v1`：整机预设，**原样搬**（`hasShaping` 缺省 true，解码即对）；
/// - `palmdeck_layout_templates_v1`：`{mode: [{name, widgets}]}`，展开成「布局」预设。
///
/// 模板的 `widgets` 里是 `DeckWidget`（定义在 `Widgets.swift`，import SwiftUI），
/// 本文件是纯类型、**不能解它** —— 所以用 `JSONSerialization` 原样搬字节：
/// 我们不需要知道里面是什么，只需要保证 `LayoutStore.applyProfile` 之后能解回来。
///
/// 迁移是**幂等**的：`GameProfileStore.load()` 只在 v2 键不存在时调它。
/// 否则「用户删掉一个迁移来的预设」会在下次启动被复活。
enum GameProfileMigration {
    static func merge(profilesV1: Data?, templatesV1: Data?) -> [GameProfile] {
        var out: [GameProfile] = []
        if let d = profilesV1,
           let list = try? JSONDecoder().decode([GameProfile].self, from: d) {
            out = list
        }
        out.append(contentsOf: layoutPresets(fromLegacyTemplates: templatesV1,
                                             taken: out.map { $0.name }
                                                 + GameProfileBuiltin.all().map { $0.name }
                                                 + [GameProfileBuiltin.reservedLayoutName]))
        return out
    }

    /// 老「布局模板」→「布局」预设。坏数据一律跳过（迁移不能把 App 拖崩）。
    static func layoutPresets(fromLegacyTemplates data: Data?,
                              taken: [String]) -> [GameProfile] {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var used = Set(taken)
        var out: [GameProfile] = []
        // 字典顺序不稳定，排一下让迁移结果可复现（测试要断言名字后缀）
        for (modeRaw, value) in obj.sorted(by: { $0.key < $1.key }) {
            guard let rows = value as? [[String: Any]] else { continue }
            let mode = CockpitMode.parse(modeRaw)
            for row in rows {
                guard let raw = row["name"] as? String, !raw.isEmpty,
                      raw != GameProfileBuiltin.reservedLayoutName,
                      let widgets = row["widgets"] as? [Any], !widgets.isEmpty,
                      let json = try? JSONSerialization.data(withJSONObject: widgets)
                else { continue }
                let name = uniqueName(raw, taken: &used)
                out.append(GameProfile.layoutOnly(name: name, mode: mode, widgetsJSON: json))
            }
        }
        return out
    }

    /// 重名就加「·布局」后缀（还冲突就加序号）。
    static func uniqueName(_ base: String, taken: inout Set<String>) -> String {
        var name = base
        var i = 2
        while taken.contains(name) {
            name = i == 2 ? "\(base)·布局" : "\(base)·布局\(i)"
            i += 1
        }
        taken.insert(name)
        return name
    }
}
enum GameProfileBuiltin {
    static let wardogs = "WARDOGS"
    static let ets2 = "欧洲卡车模拟"
    /// 内置「布局」预设（还原点）：该模式的出厂布局。
    /// **不入库**，只读呈现，应用时走 `LayoutStore.applyDefault(mode:)`。
    /// 用户预设不得叫这个名字（`GameProfileStore.validate` 拦）。
    static let reservedLayoutName = "默认"

    /// 内置预设定义（`docs/PalmDeck-v4-game-profiles.md` §3.6）。
    ///
    /// WARDOGS 的「价值不是改了参数，而是它是一个可保存、可还原、
    /// 不会被下一个游戏的调整污染的快照」—— 所以它就是现状原样固化。
    ///
    /// ETS2 的关键项是 **死区 0 / 线性灵敏度 / 900° 满舵**：
    /// ETS2 自带 steering deadzone / sensitivity / non-linearity，
    /// 两边都压 = 中位多一段死行程 + 转向非线性叠加。
    static func all() -> [GameProfile] {
        [wardogsProfile(), ets2Profile()]
    }

    static func wardogsProfile() -> GameProfile {
        GameProfile(
            name: wardogs,
            mode: .heli,
            axesPreset: "hotas",          // WARDOGS 走 vJoy，吃轴表（§2.7）
            sensX: 1.0, sensY: 1.0,
            dz: 0.06,                     // 现有默认，别动
            invX: false, invY: false, invYaw: false, invColl: false)
    }

    static func ets2Profile() -> GameProfile {
        GameProfile(
            name: ets2,
            mode: .drive,
            axesPreset: "hotas",          // ETS2 走 vgamepad，**不吃轴表**（仅参考）
            sensX: 1.0, sensY: 1.0,
            dz: 0.0,                      // 关键：别叠死区
            invX: false, invY: false, invYaw: false, invColl: false,
            wheelMaxDeg: 900,             // 真实卡车 lock-to-lock
            wheelReturnSpeed: 720)        // 卡车方向盘不应快速回正（沿用默认）
    }
}

/// 预设存储与增删改（本地，**不进 `layouts.json`、不进配置导出包**）。
///
/// 存储键 `palmdeck_game_profiles_v2`（编码后的 `[GameProfile]`）。
/// 上限 24（= 老的 12 预设 + 12 模板，合并后不能因为上限变紧而丢东西）。
/// 内置「WARDOGS / 欧洲卡车模拟 / 默认」不入库、只读。
final class GameProfileStore: ObservableObject {
    static let maxProfiles = 24
    static let maxNameLength = 16
    static let key = "palmdeck_game_profiles_v2"
    /// 迁移源：**只读**，永不写、永不删（回滚 App 版本时不丢数据）。
    static let legacyProfilesKey = "palmdeck_game_profiles_v1"
    static let legacyTemplatesKey = "palmdeck_layout_templates_v1"
    static let activeKey = "palmdeck_active_game_profile"

    /// 用户自建预设（不含内置）。
    @Published private(set) var custom: [GameProfile] = []
    /// 当前生效的预设名（仅本地 UI 标记；权威状态是手感参数本身）。
    @Published private(set) var activeName: String?
    /// 操作反馈文案。
    @Published var note = ""

    private let store: ShapingStore

    init(store: ShapingStore = UserDefaults.standard) {
        self.store = store
        load()
        activeName = store.object(forKey: GameProfileStore.activeKey) as? String
    }

    /// 全部预设：内置在前、用户自建在后。
    var all: [GameProfile] { GameProfileBuiltin.all() + custom }

    func isBuiltin(_ p: GameProfile) -> Bool {
        GameProfileBuiltin.all().contains { $0.name == p.name }
    }

    func find(_ name: String) -> GameProfile? { all.first { $0.name == name } }

    /// 存为预设。重名覆盖**用户自建**；内置名拒绝。返回错误文案，nil = 成功。
    @discardableResult
    func save(_ profile: GameProfile) -> String? {
        var p = profile
        p.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let err = GameProfileStore.validate(name: p.name) { return err }
        if isBuiltin(p) { return "「\(p.name)」是内置预设，换个名字" }
        // 两样都不装的预设点下去什么也不会发生（连模式都不会切），存它只是制造困惑。
        // UI 已经把这种按钮置灰了，这里是兵底。
        if !p.hasShaping && p.widgetsJSON == nil { return "这个预设是空的（既没手感也没布局）" }
        var list = custom
        if let i = list.firstIndex(where: { $0.name == p.name }) {
            list[i] = p                                       // 覆盖
        } else {
            guard list.count < GameProfileStore.maxProfiles else {
                return "最多 \(GameProfileStore.maxProfiles) 个预设，请先删掉一个"
            }
            list.append(p)
        }
        custom = list
        saveToDisk()
        return nil
    }

    @discardableResult
    func rename(_ old: String, to raw: String) -> String? {
        let new = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let err = GameProfileStore.validate(name: new) { return err }
        if GameProfileBuiltin.all().contains(where: { $0.name == new }) {
            return "「\(new)」是内置预设，换个名字"
        }
        var list = custom
        guard let i = list.firstIndex(where: { $0.name == old }) else { return "预设不存在" }
        if new != old, all.contains(where: { $0.name == new }) { return "已有同名预设" }
        list[i].name = new
        custom = list
        if activeName == old { markActive(new) }
        saveToDisk()
        return nil
    }

    func delete(_ name: String) {
        custom.removeAll { $0.name == name }
        if activeName == name { markActive(nil) }
        saveToDisk()
    }

    /// 记下当前生效的预设名。
    func markActive(_ name: String?) {
        activeName = name
        if let n = name {
            store.set(n, forKey: GameProfileStore.activeKey)
        } else {
            store.removeObject(forKey: GameProfileStore.activeKey)
        }
    }

    private static func validate(name: String) -> String? {
        if name.isEmpty { return "名称不能为空" }
        if name.count > maxNameLength { return "名称最多 \(maxNameLength) 个字符" }
        if name == GameProfileBuiltin.reservedLayoutName {
            return "「\(name)」是内置预设，换个名字"
        }
        return nil
    }

    /// 读 v2；没有 v2 就把两个老键合并进来（`GameProfileMigration`），写进 v2。
    ///
    /// **只在 v2 不存在时迁移**：否则用户删掉的预设会在下次启动复活。
    private func load() {
        if let data = store.object(forKey: GameProfileStore.key) as? Data,
           let obj = try? JSONDecoder().decode([GameProfile].self, from: data) {
            custom = obj
            return
        }
        let merged = GameProfileMigration.merge(
            profilesV1: store.object(forKey: GameProfileStore.legacyProfilesKey) as? Data,
            templatesV1: store.object(forKey: GameProfileStore.legacyTemplatesKey) as? Data)
        guard !merged.isEmpty else { return }
        custom = merged
        saveToDisk()
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(custom) {
            store.set(data, forKey: GameProfileStore.key)
        }
    }
}

/// 把预设写进「布局 + 手感 + 模式」。
///
/// **顺序很关键**（也是这个函数值得单独存在、单独测的原因）：
/// 1. **先切模式** —— `applyMode` 会把该模式那一份手感读进来；
/// 2. 再写手感参数 —— `didSet` 的保存键跟着**新的** `mode` 走，落对键；
///    **`hasShaping == false` 的「布局」预设整段跳过**（它只管布局）；
/// 3. 布局：**仅当预设自带布局（`widgetsJSON != nil`）时**才整表替换；
///    内置预设不带布局，于是这一步是空操作，用户摆好的画布不被擦掉。
///
/// 若先写手感再切模式，`applyMode` 会把刚写的手感覆盖回该模式原来的值，预设等于白切。
enum GameProfileApplier {
    /// - Parameters:
    ///   - setMode: 切模式（UI 传 `ctrl.setMode`，它内部会 `state.applyMode`）。
    ///   - replaceLayout: 应用预设布局（UI 传 `layout.applyProfile`；
    ///     `widgetsJSON` 为 nil 时它自己会判空跳过，所以这里无条件转发）。
    static func apply(_ p: GameProfile,
                      to state: ShapingTarget,
                      setMode: (CockpitMode) -> Void,
                      replaceLayout: (Data?, CockpitMode) -> Void) {
        // 1. 切模式
        setMode(p.mode)
        // 2. 手感参数（按 p.mode 落键）；「布局」预设不碰手感
        if p.hasShaping {
            state.sensX = p.sensX
            state.sensY = p.sensY
            state.dz = p.dz
            state.invX = p.invX
            state.invY = p.invY
            state.invYaw = p.invYaw
            state.invColl = p.invColl
            if let w = p.wheelMaxDeg { state.wheelMaxDeg = w }
            if let r = p.wheelReturnSpeed { state.wheelReturnSpeed = r }
        }
        // 3. 布局（预设不带布局时 LayoutStore 会自己跳过）
        replaceLayout(p.widgetsJSON, p.mode)
    }
}
