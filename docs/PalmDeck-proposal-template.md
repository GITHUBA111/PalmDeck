# PalmDeck 方案模板

> **用途**：任何新功能 / 改造，先按本模板写成方案，评审通过再动代码。
> 目的只有一个——把「想做的」和「已确认的」分开，避免边写边改需求。
>
> 本文件 **§1** 是空白骨架（复制即用），**§2** 是一份已填示例
> （「布局模板：保存 / 切换 / 还原」——已实施，见 §2；本文件同时是该方案的留存记录）。
>
> ⚠️ **P1.5 后「模板」已并进「预设」**（整机 / 布局两种形态，`LayoutTemplate` 类型已删）、
> 见 `docs/PalmDeck-v4-unified-presets.md`。§2 保留当时原文，当写作范本看，不再当现状。

---

## §1 模板骨架

```markdown
### 方案名
### 状态：待评审 / 已采纳 / 已落地 / 仅存档（不做）
### 影响范围：电脑侧 / App 侧 / 协议 / 文档
### 一句话：做什么，给谁用

## 1. 目标
要解决的真实问题。禁止写「提升体验」「更流畅」这类无法验证的目标。
写不出「不做的代价」= 这个方案不该存在。

## 2. 现状与证据
每条结论必须带 file:line 或可复现命令。没有证据的断言直接删。
（本项目尤其：协议 / 常驻服务 / App 三侧都要各自取证。）

## 3. 方案
- 交互：控件行为、状态变化、异常路径（断连 / 越界 / 快速连点）
- 数据：持久化键名 + 默认值 + 取值范围 + 是否同步到电脑
- 接口：REST / WS 报文（若涉及）

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | 不改 / 改（写清新旧兼容与降级） |
| 电脑侧（bridge / pack） | 无 / 文件 + 端点 |
| App 侧 | 文件 + 持久化键 |
| 文档 | 需同步的 md |

## 5. 验证方式
可执行命令 / 可截图画面 / 新增测试用例名。
**写不出验证方式的方案 = 没想清楚。**

## 6. 边界与不做
明确不覆盖什么。防止后续范围蔓延，也防止被当成「顺手也做了吧」。

## 7. 工作量
S / M / L，并拆成可独立验证的步骤。
```

---

## §2 已填示例：布局模板（保存 / 切换 / 还原）

**状态**：✅ 已实施（2026-02；落于 `Layout.swift` / `SettingsView.swift` / `CockpitView.swift`）
**影响范围**：App 侧（`Layout.swift` + `SettingsView.swift` + `CockpitView.swift`）；
**不碰协议、不碰电脑侧、不碰 `layouts.json`**
**一句话**：把当前组件布局存成命名模板，之后一键切换、一键还原。

### 1. 目标

现在**每个模式只有一份布局**，且只有三个破坏性出口：

| 现状出口 | 位置 | 后果 |
|---|---|---|
| 「清空当前模式」 | `SettingsView.swift:419` → `Layout.swift:65` | 布局直接变空，**无备份** |
| 「恢复默认布局」 | `SettingsView.swift:416` → `Layout.swift:67` | 覆盖成内置默认，**原布局找不回** |
| 编辑时拖拽 / 缩放 / ✕ | `Layout.swift:243–285` | 逐次就地覆盖，无历史 |

也就是说：**摆好一套布局后，想再摆第二套 = 必须把第一套毁掉。**
而布局调试是纯手工作业（拖动 + 缩放每一个组件），毁掉一次 = 十几分钟重来。

真实诉求：「空战一套、对地一套」随时切；改坏了能一键还原。
**不做的代价 = 丢手工成果**——这不是"体验优化"，是可逆性问题。

### 2. 现状与证据

**存储：每模式一份，单键**

- `Layout.swift:16` `final class LayoutStore: ObservableObject`
- `Layout.swift:19` `@Published private var layouts: [String: [DeckWidget]]`（key = 模式 rawValue）
- `Layout.swift:23` `private let key = "palmdeck_widgets_v10"` —— **全 App 唯一的布局键**
- `Layout.swift:77–81` `save()` 整体编码写回该键（无版本、无槽位、无历史）

**写入口（全部"就地覆盖"）**

| 方法 | 行 | 行为 |
|---|---|---|
| `add` | `Layout.swift:39` | append |
| `remove` | `Layout.swift:56` | filter |
| `update` | `Layout.swift:60` | 替换同 id 项 —— 拖拽/缩放每次 `onChanged` 都调 |
| `clear` | `Layout.swift:65` | `setWidgets([])` |
| `reset` | `Layout.swift:67` | `setWidgets(defaults(mode:))` |

`setWidgets`（`Layout.swift:34–37`）只有 `layouts[mode] = list; save()` —— **旧值不留存**，
这就是"不可还原"的根因；改它一处即可让所有破坏性操作变成可撤销。

**内置默认布局（可直接当只读模板）**

- `Layout.swift:107–113` `defaults(mode:)` → `defaultFlight()`（`:114`）/ `defaultDrive()`（`:141`）/ `defaultGamepad()`（`:164`）

**组件数据模型（已是值类型 + Codable，深拷贝零成本）**

- `Widgets.swift:67` `struct DeckWidget: Codable, Identifiable, Equatable { id, kind, binding, rect, label }`
- `WRect`（`Layout.swift:4`）同为 `Codable` 值类型

→ 模板存储**几乎零成本**：`[DeckWidget]` 本身就是可编码值，深拷贝 = 直接赋值。

**电脑侧是另一套，且 App 只渲染 gamepad**

- 电脑侧 `palmdeck_layouts.py:4` `{schema:1, layouts:{mode:[...]}}`；`:141/:151/:162/:178`
  同样只有"一份/模式"，无槽位
- App 仅 gamepad 走可编辑画布：`CockpitView.swift:219` `WidgetCanvas`；
  `SettingsView.swift:399–421` 只在 `s.mode == .gamepad` 显示布局编辑，heli/drive 显示"固定硬件皮肤"锁
- 同步通道：WS `layouts_get`/`layouts_put`（`bridge.py:771`/`:778`），REST `/api/layouts`（`bridge.py:991/1029/1063`）

### 3. 方案

**概念**：模板 = `(name, [DeckWidget])` 命名快照，**按模式归类**。
「默认」是内置只读模板（直接取 `LayoutStore.defaults(mode:)`，不占存储、不入库）。

**存储**（新增 1 键，**不动** `palmdeck_widgets_v10`）

```
UserDefaults["palmdeck_layout_templates_v1"]
{
  "gamepad": [
    { "name": "空战", "widgets": [ ...DeckWidget... ] },
    { "name": "对地", "widgets": [ ... ] }
  ]
}
```

- 每模式上限 **12 个**（UserDefaults 不是数据库，防手滑存爆）
- 名称：去首尾空白、≤16 字符、非空、**同模式内唯一**
- 空布局**允许**存（"空白板"是有用的起点）

**操作语义**

| 操作 | 语义 |
|---|---|
| 存为模板 | 快照当前 `widgets(mode:)` 追加；重名则覆盖并提示 |
| 应用 | `setWidgets(tpl.widgets, mode:)`；**应用前把当前布局压入撤销槽** |
| 重命名 / 删除 | 直接改数组；删除不二次确认（模板可重建，避免确认疲劳） |
| 还原 | = 应用内置「默认」模板（走同一路径，因此**也可撤销**） |

**撤销槽**：单槽、按模式、与模板一起持久化：
`UserDefaults["palmdeck_layout_undo_v1"] = {mode: [DeckWidget]}`。
`clear` / `reset` / `applyTemplate` **执行前**写入该槽。

**UI（Apple 设置风格，接进现有「布局」分类）**

设置 → 布局，在「模式」段之后、破坏性按钮段之前插入：

```
模板
┌────────────────────────────────┐
│  默认                 使用中 ✓  │   ← 内置只读，无滑动删除
│  空战                           │
│  对地                           │
│  ＋ 将当前布局存为模板           │
└────────────────────────────────┘
        撤销上一次                  ← 仅撤销槽非空时出现
```

- 右侧 `checkmark` = `isCurrent(tpl, mode:)`（逐项 `==` 比较，`DeckWidget: Equatable` 已具备）
- 左滑 = 重命名 / 删除（`List` 原生 `.swipeActions`，iOS 15 可用）
- 画布编辑栏（`Layout.swift:201–211`，现有「完成 / 清空」）加「存为模板」
- 命名弹窗复用 `SettingsView.swift` 里 `SliderRow` 那套 `alert + TextField`（已落地、已验证）

**id 与视图复用**：模板保留原 `id`；应用时整表替换，表内 id 天然唯一。
但 `EditableWidget` 的 `@State dragStart`（`Layout.swift:224`）在整表替换后可能残留 →
应用模板时给画布加一次性 `.id(revision)`（`revision` 为 `@Published` 递增计数）强制重建。

### 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改** |
| 电脑侧（bridge / pack / `layouts.json`） | **无**。模板不参与 `layouts_get/put`，也不进 `/api/config/export` |
| App 侧 | `Layout.swift`（模板存储 + 撤销槽 + `LayoutTemplate`）；`SettingsView.swift`（模板 Section + 搜索索引 `entries`）；`CockpitView.swift`（画布 revision） |
| 新增持久化键 | `palmdeck_layout_templates_v1`、`palmdeck_layout_undo_v1` |
| 文档 | `PalmDeck-v4-app-interaction.md` §7 布局编辑 + §10 持久化总表 |

### 5. 验证方式

- 模拟器截图 4 张：空模板段 / 存 2 个模板 / 应用后「使用中 ✓」位移 / 撤销后回原布局
- 手工回归：存模板 → 清空 → 应用模板 → 与存之前**逐项全等**（id/kind/binding/rect/label）
- 重启 App 后模板仍在（UserDefaults 往返）
- 破坏性检查：清空 → 撤销应恢复；重启后撤销槽仍在
- `python3 -m unittest discover -s tests -t .` 仍 61 OK（本方案无 Python 改动）
- 真机：`cd mobile/ios && ./deploy_wifi.sh --wifi-only hui`

### 6. 边界与不做

- **模板只存手机本地**（UserDefaults），不上电脑、不随 `/api/config/export` 配置包走
  → 换手机 / 重装会丢。跨设备迁移是**另一个方案**（要 `bundle` 升版 + 电脑侧新端点）。
- 只在 `gamepad` 自定义布局暴露入口（heli/drive 是固定硬件皮肤，`SettingsView.swift:422` 起有锁）
- 不做模板缩略图预览（画布是活的，静态图没意义）
- 不做自动版本历史（撤销槽只 1 格；要历史 = 另一个方案）
- 不重排组件 z 序（现在没有 z 概念）
- 不改 `palmdeck_widgets_v10` 结构，不迁移旧数据

### 7. 工作量

**M（约 180–240 行 / 3 文件）**，拆 4 步，每步可独立验证：

1. **存储层**（`Layout.swift`）：`LayoutTemplate` 值类型 + `templates/saveTemplate/applyTemplate/
   renameTemplate/deleteTemplate/isCurrent` + 撤销槽 + `revision`
2. **设置页**（`SettingsView.swift`）：模板 Section + 滑动重命名/删除 + 「存为模板」弹窗
3. **画布**（`Layout.swift:201` + `CockpitView.swift`）：编辑栏「存为模板」+ `.id(revision)`
4. **验证 + 文档**：4 张截图 + 真机部署 + 两处 md 同步
