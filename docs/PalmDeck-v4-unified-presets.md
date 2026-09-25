# 方案：把「模板」并进「预设」（P1.5）

**状态**：✅ 已采纳并落地（本轮；按 `PalmDeck-proposal-template.md` 骨架写）
**影响范围**：App 侧（`Model/GameProfile.swift`、`Views/SettingsView.swift`、`Views/CockpitView.swift`、
`Views/Layout.swift`）；**不碰协议、不碰电脑侧、不动 `palmdeck_widgets_v10`**
**一句话**：干掉「模板」这个词和那个列表 —— 存快照只有一件事：**预设**；
预设里可以装「整机」（模式+手感+布局）或「只装布局」，行上一眼看得出是哪一种。

---

## 1. 目标

**要解决的真实问题**（来自 UX 走查 P1.5）：同一件心里的事，界面上有两个地方。

「我把现在这套东西存下来，以后一键切回来」——这是**一个**动作。但现在它有两个实现：

| | 设置 → 游戏预设 | 设置 → 布局 → 模板 |
|---|---|---|
| 存了什么 | 模式 + 手感（死区/灵敏度/反转/满舵）+ **布局（可选）** | **只有布局** |
| 作用域 | 跨模式（点了会切模式） | 当前模式 |
| 存储键 | `palmdeck_game_profiles_v1` | `palmdeck_layout_templates_v1` |
| 上限 | 12 | 12 |
| 「存为…」按钮 | 将当前状态存为预设 | 将当前布局存为模板 |

**要付的代价**（都会真实发生）：

- **选错就白存**：想存布局却点了「存为预设」（或反过来），之后「切预设」不换布局 /
  「切模板」不换手感 —— 用户没法从名字上判断该点哪个。
- **切了预设会/不会动布局，事前看不出来**：只能靠行尾一行 11pt 小字「仅手感，不动布局」/「含布局」。
- **两套命名空间**：同一个名字可以在两处各存一份，改的是哪一个要靠记；两个 12 的上限也要分别记。
- **入口重叠**：编辑条「存为模板」、设置 → 布局 → 「恢复默认布局」、编辑条 `⋯` → 「恢复默认布局」
  （同一件事三个入口），而「恢复默认」其实就等价于「应用内置模板『默认』」。

**不做的代价**：这套「我到底该用哪个」的疑问会一直存在，而且每次改布局都要先想一遍。

## 2. 现状与证据

| 事实 | 证据 |
|---|---|
| 两套列表、两套存储 | `GameProfileStore.key = "palmdeck_game_profiles_v1"`；`LayoutStore.templatesByMode` → `palmdeck_layout_templates_v1` |
| 两个「存为」按钮 | `SettingsView.swift` `profilesSections`（将当前状态存为预设）/ `templateSection`（将当前布局存为模板） |
| 预设可以含布局，但要靠小字分辨 | `profileRow`：`p.widgetsJSON == nil ? "仅手感，不动布局" : "含布局"` |
| 编辑条存的是「模板」 | `CockpitView.swift` `editBar`：`Button("存为模板")` → `layout.saveTemplate(...)` |
| 「恢复默认」= 应用内置模板「默认」 | `LayoutStore.templates(mode:)` 第一行就是 `LayoutTemplate(name: builtinName, widgets: defaults(mode:))` |
| 两个上限 | `GameProfileStore.maxProfiles = 12` / `LayoutStore.maxTemplates = 12` |
| 名字校验各写一份 | `GameProfileStore.validate` / `LayoutStore.validate`（后者还要额外拒绝内置名「默认」） |

## 3. 方案

### 3.1 词表：一个概念，两种形态

**预设**（唯一的名词）。一行一个预设，行上标出它装了什么：

| 形态 | 装了什么 | 点一下会发生什么 |
|---|---|---|
| **整机** | 模式 + 手感 + （可选）布局 | 切模式 → 写手感 → 有布局就换布局 |
| **布局** | 只有布局（属于某个模式） | 只换**当前模式**的组件，手感一点不动 |
| 内置「默认」 | 该模式的出厂布局 | 还原点，只读、不可删改 |

- 行尾章：`整机` / `布局` / `内置`。**不再有「模板」这个说法**（源码与 UI 里都不再出现，加守卫）。
- **「布局」预设只在自己那个模式下出现**（与现在「模板」按模式列出的行为一致）：它存的是
  「开车那套滑条」，在飞机模式下没有意义，也就不该出现在列表里。
- **「整机」预设跨模式出现**：它的价值就是「一键切到另一个游戏」，隐藏它等于废掉这个功能。

### 3.2 数据模型：一个布尔把两种形态装进同一个类型

`GameProfile` 已经很接近了：`widgetsJSON == nil` 表示「不动布局」。缺的是反向的那半 ——
「这个预设**不带手感**」。加一个字段即可：

```swift
struct GameProfile {           // Model/GameProfile.swift（纯类型，只 import Foundation）
    var name: String
    var mode: CockpitMode
    …
    var hasShaping: Bool        // false = 只装布局，手感字段一律忽略
    var widgetsJSON: Data?      // nil = 这个预设不带布局
}
```

- **解码缺省 = `true`**：`palmdeck_game_profiles_v1` 里**所有**老预设都是整机预设，
  所以老的 JSON 原样解出来就是对的 —— 不需要迁移代码，也不需要新键。
- `GameProfileApplier.apply` 里手感那一段加 `if p.hasShaping { … }`；
  布局那一段不变（`nil` 依然 = 不碰）。
- 内置 WARDOGS / 欧洲卡车模拟：`hasShaping = true`、`widgetsJSON = nil`（现状不变）。

### 3.3 迁移：v1 预设 + v1 模板 → v2（一次、幂等）

新键 `palmdeck_game_profiles_v2`。`GameProfileStore.load()`：

1. **有 v2 → 直接读，迁移永不重跑**（幂等；也让「用户删掉某个预设」不会被下次启动复活）。
2. 没有 v2 → `soup = 解码(palmdeck_game_profiles_v1) + 展开(palmdeck_layout_templates_v1)`
   写入 v2。**旧键一律留着不删**（同仓库一贯做法：只读不写、留着兜底）。

模板那半边（`[mode: [{name, widgets}]]`）的展开规则：

- 每个模板 → 一个 `hasShaping = false`、`mode = 它所属模式`、`widgetsJSON = 重新编码后的 widgets`
  的预设。
- 重名（和已有的整机预设，或两个模式下的同名模板）→ 加后缀「·布局」，还冲突就加序号。
- 名字叫「默认」的跳过（内置还原点，从不入库；万一有人手写过就忽略）。
- 重编码走 **`JSONSerialization`** 而不是 `JSONDecoder`：`widgets` 里面是 `DeckWidget`
  （定义在 `Widgets.swift`，import SwiftUI），`GameProfile.swift` 是纯类型，
  不能把它拖进 `swiftc` 的编译单元。`JSONSerialization` 只是搬字节，不关心里面是什么。

上限：`maxProfiles` 12 → **24**（= 老的 12 预设 + 12 模板）。迁移**不受上限约束**：
宁可列表长一点，也不能静默丢掉用户的快照。

### 3.4 UI：一个列表

**设置 → 预设**（原「游戏预设」分类，一行没挪）：

```
电脑侧      电脑当前轴表        hotas
预设        欧洲卡车模拟  [内置]              [当前]
            开车 · 死区 0.00 · 900° · 仅手感
            WARDOGS      [内置]
            飞机 · 死区 0.06 · 仅手感
            默认          [内置]
            布局 · 开车 · 8 个组件                    ✓
            我摆的卡车台  [布局]              ✓
            布局 · 开车 · 6 个组件
            我的整机       [整机]
            开车 · 死区 0.02 · 含布局
            ＋ 将当前状态存为预设（整机）
            ＋ 将当前布局存为预设（仅布局）
```

- 排序：内置整机 → 用户整机 → 当前模式的布局预设 → 内置「默认」（还原点排最后，它是兜底）。
- 两类「存为」按钮**都在这**，名字里就把差别写出来（整机 / 仅布局），
  弹窗标题也跟着变（「存为整机预设」/「存为布局预设」）。
- 行尾：`内置` / `整机` / `布局` 章 + `当前`（整机看 `activeName`；布局与「默认」看**内容是否相等**，
  复用 `sameShape`）。删除/重命名走原来的左滑（内置不可）。
- 脚注一段话说清三件事：整机跨模式、布局只在本模式可见、内置不可改。

**设置 → 布局**：删掉整个「模板」段；「恢复默认布局」按钮也删掉（它 = 列表里的「默认」行），
只留「清空当前模式」＋脚注指路。**编辑条「存为模板」→「存为预设」**，存的是**布局预设**
（人在摆布局，手感不在这件事的范围里），默认名沿用「布局 N」。

### 3.5 应用语义与撤销

| 形态 | setMode | 写手感 | 换布局 | 撤销槽 |
|---|---|---|---|---|
| 整机 | 总是 | `hasShaping` 时 | 有布局时（`nil` 不碰） | `applyProfile` 换布局时压一道 |
| 布局 | 总是（= 自己那个模式，实际是 no-op） | **不写** | 总是 | 压一道 |
| 默认 | — | — | 总是（铺 `defaults(mode:)`） | 压一道 |

「整机且不带布局」在**当前模式是空表**时仍铺回默认模块 —— 这是原来那个「选预设变白板」
的修复，保留（`applyProfile` 的三分支逻辑原样不动）。

### 3.6 异常路径

| 情况 | 行为 |
|---|---|
| v1 预设 JSON 坏了 | 当成没有（不迁移那半边），模板那半边照迁 |
| v1 模板 JSON 坏了 / 不是字典 | 跳过，不抛错 |
| 模板的 `mode` 认不出来 | `CockpitMode.parse` 的既有回落（未知 → 沿用默认模式），不丢数据 |
| 迁移后超过 24 个 | 全部保留；上限只拦**新建** |
| 用户删掉迁移来的预设 | v2 已存在 → 不重跑迁移，不会复活 |
| 布局预设被判「当前」 | 比形状（`sameShape`），不比 `UUID`（每次重建都变） |

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B） | **不改** |
| 电脑侧（bridge / `layouts.json`） | **无**（预设一直只存本机） |
| 持久化键 | 新增 `palmdeck_game_profiles_v2`；`…_v1` 与 `palmdeck_layout_templates_v1` 变成**只读**（迁移源） |
| `LayoutStore` | **净减**：`LayoutTemplate` / `templates(mode:)` / `customTemplates` / `saveTemplate` / `renameTemplate` / `deleteTemplate` / `applyTemplate` / `isBuiltin` / `templatesByMode` / `loadTemplates` / `saveTemplates` / `validate` / `maxTemplates` / `maxNameLength` 全删；新增 `applyDefault(mode:)` / `isCurrentDefault(mode:)` / `isCurrentLayout(_:mode:)` |
| `GameProfileStore` | 新键 + 迁移 + 保留名「默认」 |
| 文档 | 本文件 + `PalmDeck-v4-game-profiles.md` §3.4（改为指向本文件）+ `PalmDeck-v4-app-interaction.md` §7.2 + §12.14 + `README` + `TODO` |

## 5. 验证方式

- **纯逻辑**（`tests/ios/GameProfileTests.swift`，`swiftc` 直跑）：
  `hasShaping` 缺省为 true（老 JSON 原样解出）；往返；**迁移**（v1 预设 + v1 模板 → 合并后的
  条数/形态/模式/重名后缀；模板 payload 的字节能被 `JSONDecoder` 解回来且与原 JSON 深等）；
  迁移幂等（v2 存在时不再跑）；`apply` 对 `hasShaping = false` 的预设**一个手感字段都不碰**但
  仍然 `setMode` + 换布局；保留名「默认」被拒。
- **源码守卫**（`tests/test_deck_bindings.py`）：`GameProfile.swift` 仍只 `import Foundation`；
  App 源码里不再出现 `LayoutTemplate`；旧键只读（`set(` 不写它们）；编辑条的保存走 `profiles.save`。
- **真机/截图**（Mac Catalyst）：设置 → 预设里同时看到整机/布局/默认三种行 → 存一个「布局」预设
  → 切一下（组件换、手感不变）→ 切内置 WARDOGS（模式+手感变、布局不动）→ 「默认」还原。
- `python3 -m unittest discover -s tests -t .` 全绿；`xcodebuild -scheme App` `BUILD SUCCEEDED`。

## 6. 边界与不做

- **不做跨设备同步**（与预设/模板的既有边界一致）。
- **不把「布局预设」做成可跨模式套用**（同一个布局套到另一个模式是另一件事，且模式间的
  可用轴/组件并不对等）。
- **不做「只切模式」的第三种形态**：模型允许（`hasShaping = false` 且无布局），但不给新建入口 ——
  两个按钮已经够用，第三种只会重新制造「该点哪个」。
- **不迁移旧键的删除**（旧键留着不删，避免回滚 App 版本时丢数据）。
- **不改 `palmdeck_widgets_v10`**（当前布局的存储与同步路径完全不动）。

## 7. 工作量

**M（约 250 行净改动 + 迁移测试）**，拆 4 步：

1. `GameProfile.swift`：`hasShaping` + 迁移函数 + `apply` 分支 + 保留名
2. `Layout.swift`：删模板那一段，补 `applyDefault` / `isCurrent*`
3. `SettingsView` 一个列表 + `CockpitView` 编辑条按钮
4. 测试（纯逻辑 + 守卫）+ 截图核对 + 文档

## 8. 落地记录（已实施）

### 8.1 改了什么

| 文件 | 改动 |
|---|---|
| `Model/GameProfile.swift` | `hasShaping`（decode 默认 true）；`kindLabel` / `hasLayout`；`layoutOnly(name:mode:widgetsJSON:axesPreset:)`；`GameProfileBuiltin.reservedLayoutName = "默认"`；`enum GameProfileMigration`；`key` → `palmdeck_game_profiles_v2` + 两个 `legacy…Key`；`load()` 只在 v2 不存在时迁移；`validate` 拒「默认」；`save` 兵底拦空预设；`apply` 把写手感包在 `if p.hasShaping` 里 |
| `Views/Layout.swift` | 删 `LayoutTemplate` 及整段模板 API（净减 ~90 行）；新增 `builtinName` / `applyDefault(mode:)` / `isCurrentDefault(mode:)` / `isCurrentLayout(_:mode:)` / `widgetCount(_:)` / `widgetCount(mode:)` |
| `Views/SettingsView.swift` | `TplPrompt` 删除；`ProfPrompt.NewKind { machine, layout }`；预设列表改成 `presetRows` / `PresetRow`（含 `restoreDefault`）；两个存按钮；撤销段独立；搜索索引改写 |
| `Views/CockpitView.swift` | `存为预设`（存布局预设，空画布置灰）+ 回执行 + 默认名从 1 数 + `⋯` / 放弃 / 完成会清回执 |
| 测试 | `GameProfileTests.swift` 新增 7 个（含迁移 4 个）；`test_deck_bindings.py` 新增 `TestUnifiedPresets`（6 个）+ 保存回执 2 个 |

**净变化**：类型少一个（`LayoutTemplate`）、存储键少一个（合二为一）、UI 分类少一个（少一处找「我存的那套」）。

### 8.2 机器验证（不是「应该没问题」）

1. **迁移**：先 `defaults write … palmdeck_game_profiles_v1 -data <hex>`（2 个整机）
   + `palmdeck_layout_templates_v1 -data <hex>`（drive `卡车台`、heli `WARDOGS`），
   删 `palmdeck_game_profiles_v2`，启动 App，然后 `defaults export com.palmdeck.yoke - | plistlib.loads`
   读回：v2 正好 4 条 —— `我的飞机`(heli/整机) / `我的卡车`(drive/整机) /
   `卡车台`(drive/布局) / `WARDOGS·布局`(heli/布局)。重名后缀按设计生效。
2. **应用布局预设**：drive 模式下点 `卡车台` → `palmdeck_widgets_v10` 的 drive 变成那 1 个滑条，
   同时 `palmdeck_dz.drive` 保持 `0.0`（手感一点没动）。
3. **应用「默认」行**：heli 下点「默认」→ 回到出厂 5 个组件。
4. **编辑条存预设**：存出 `机舱台`（heli / `hasShaping=false` / 带 widgets）。
5. **保留名**：名字填「默认」→ 出现回执「「默认」是内置预设，换个名字」，库里没有新记录。
6. **空画布**：「存为预设」置灰且点不动。
7. **迁移空转**：v1 = `[]` + 2 个模板 → v2 只有 2 条（不会凭空造整机预设）。

### 8.3 顺手修掉的两个显示问题（截图里看到的）

- 预设名与章（「内置 / 整机 / 当前」）挤一行时名字被折行（`WARDOGS·` / `布局`）：
  标题 `lineLimit(1)` + `layoutPriority(1)`，章 `fixedSize()`，详情行 `lineLimit(2)`。
- 「存为预设」以前是 `_ = profiles.save(p)`：失败静默。现在一行回执就写在编辑条下面
  （占位，不盖画布）。

### 8.4 未做 / 风险

- **Catalyst 上带 `swipeActions` 的列表行对合成点击时灵时不灵**（同一 List 里的普通按钮正常）：
  「点行应用预设」只成功了那一次，真机上请再手点一下确认手感。
- **旧键不删**（可回滚），已被 `test_store_key_is_v2_and_old_keys_are_read_only` 钉住「只读」。
- 预设仍只存本机，不进 `layouts.json` / 配置导出包。
