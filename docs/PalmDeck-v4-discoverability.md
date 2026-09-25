# PalmDeck v4 可发现性补完（P2 残留）

> 状态：**已实施，已在 Mac Catalyst 实机逐张看一遍**（方案 + 落地记录同文件，见 §8；实测见 §9）。
> 来源：UX 走查第 P2 组剩下的四条 —— 上一轮 `docs/PalmDeck-v4-consistency.md`
> 做掉的是「命名 / 分组一致性」，这一轮做**看得见、点得到、说人话**。
> 影响范围：**只在 App 侧的三个 View 文件里改**，不动协议、不动电脑侧、不动存储键。

---

## 1. 目标

四件事，各自都有「不做的代价」：

| # | 目标 | 不做的代价 |
|---|---|---|
| a | 顶栏三个入口看起来是**同一类控件** | 「齿轮」是唯一没有字的入口：新用户不知道它是什么，也不会去点它 |
| b | 预设的**改名 / 删除**要看得见 | 现在**只有左滑**，footer 里提了一句但没人看 footer；用户以为预设存下去就改不了 |
| c | **已连接时切模式**要说清代价 | 飞机↔开车＝电脑侧从 vJoy 切成虚拟 Xbox，游戏里手柄会掉；用户以为 App 卡了 |
| d | 状态条与绑定列表**说人话** | `SRC` / `仅飞行` 这类词，普通玩家读完不知道是什么 |

**不做**：Dynamic Type / 无障碍标签（理由见 §6）、动画、配色。

---

## 2. 现状与证据

### 2.1 顶栏三个入口不等权（`Views/CockpitView.swift:124-150`）

```
connectionChip  →  带图标 + 文字（「连接」/「一键连接」/ IP+Hz），强调色，宽 96 / 140
齿轮            →  Image(systemName: "gearshape.fill")，字号 15，**没有文字**，宽 40
布局            →  图标 + 文字（「布局」/「完成」），宽 64
```

三个并排，其中一个是纯图标 —— 高度/圆角/底色同一套 `CardButton`，**唯独少了标签**，
于是它读起来像「另一个东西」。教程里也只能绕开它说「齿轮设置」（`CockpitView.swift:485`）。

### 2.2 预设行的改名 / 删除只能左滑（`Views/SettingsView.swift:443-452`）

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) { profiles.delete(p.name) } …
    Button { profPrompt = … } label: { Label("重命名", …) }
}
```

`swipeActions` 在 iPad + 触控笔 / 鼠标（Catalyst）上是**最难发现**的手势之一，
而行里的 footer 只提到「预设只存本机，内置的不可删改」。**界面上没有任何可点的入口。**

### 2.3 已连接时切模式没有预告（`Views/CockpitView.swift:113-120`）

```swift
Button(m.label) { ctrl.setMode(m); Haptics.press() }
```

`ctrl.setMode` → 电脑侧 `bridge.py` 在 `hotas` 与 `gamepad` 之间**换后端**（`vjoy.py` / `vgamepad`），
游戏里那只手柄会消失再出现（`docs/PalmDeck-v4-app-interaction.md` §12.6 已写明这个约束）。
当前是**一点就切**，没有任何提示 —— 掉手柄的现象会被归因成「App 卡了」。

### 2.4 术语

| 位置 | 现在 | 问题 |
|---|---|---|
| 状态条 `CockpitView.swift:79-88` | `LINK` / `MODE` / `SRC`，值为 `UDP` / `WS` | 同一行里轴标签是中文（横滚/俯仰…），这三个是英文；`SRC`+`UDP` 玩家读不懂 |
| 绑定列表 `CockpitView.swift:442` | `按钮 11 · 仅飞行` | 「仅飞行」= 只在 vJoy 上有：开车/手柄模式用的是 Xbox 虚拟手柄，这些键不存在。措辞太省，且没说「为什么」 |
| 绑定列表 footer `CockpitView.swift:448` | 解释里直接写 `vJoy` / `Xbox` 型号名 | 需要保留（要在游戏里对照），但应当先说人话再给型号 |

---

## 3. 方案

### 3.1 顶栏：三个入口都「图标 + 文字」，等宽等高

| 入口 | 之前 | 之后 |
|---|---|---|
| 连接 | 图标 + 文字，宽 96（已连 140） | 不变（它的宽度是状态决定：`IP` + `Hz`） |
| 设置 | 纯齿轮，宽 40 | **齿轮 + 「设置」**，宽 64 |
| 布局 | 图标 + 文字，宽 64 | 不变 |

统一细节：图标 `.font(.system(size: 13))`、文字 `.font(.system(size: 11, weight: .medium))`、
`HStack(spacing: 4)`、`CardButton(…, fillWidth: false, height:)`、宽度 64。
教程文案同步：「右侧是连接状态 + **「设置」** + 「布局」按钮」。
**不改**三个模式的胶囊、不改连接胶囊的配色（绿/蓝是状态语义，不是层级）。

### 3.2 预设行：行尾给一个 `⋯`（重命名 / 删除），左滑保留

- 行**不再整行当 Button**：改成 `contentShape(Rectangle()) + onTapGesture` 应用预设，
  这样行尾的 `Menu` 才能独立吃掉自己的点击（Button 套 Button 在 SwiftUI 里点不动）。
- 行尾新增 `Menu`（`ellipsis.circle`，32×32 命中区）：**重命名** / **删除**（红色）。
  内置预设与「默认」行**不显示**这个菜单 —— 顺带把「哪些能改」画出来了。
- `swipeActions` **保留**（左滑更快，老用户已经会了）。
- 删除后回执（`profNote`）保持：`已删除「X」`。

### 3.3 切模式：只在**已连接**时问一句

```
if s.link == .live && m != s.mode → 弹确认；否则直接切
```

- 标题：「切换到「开车」？」
- 正文：「电脑端要从 vJoy 换成虚拟 Xbox 手柄，游戏里这只手柄会掉一下（重进或重连即可）。
  当前这套布局会先保存下来。」
- 按钮：**切换**（默认）/ 取消。
- 确认后才做原来那两步：`layout.commitEditing(mode:)`（若在编辑态）+ `ctrl.setMode(m)`。
- **未连接时一声不吭**（本机切模式没有代价，多一层弹窗只会变慢）。

### 3.4 术语

| 位置 | 之前 | 之后 |
|---|---|---|
| 状态条 | `LINK` / `MODE` / `SRC` | **`链路` / `模式` / `通道`**（值仍是 `UDP` / `WS`，它们是协议名，改不了也别瞎改） |
| 状态条帮助（教程） | — | 补一句：「状态条最右的**通道**：UDP 是轴的快速通道，WS 是 WebSocket 控制通道」 |
| 绑定列表 | `按钮 11 · 仅飞行` | **`按钮 11 · 开车/手柄不生效`** |
| 绑定列表 footer | 「第 11–16 号键只存在于 vJoy。Xbox 虚拟手柄只有……」 | 「**第 11–16 号键只在飞行模式存在**（电脑侧那只 vJoy 手柄）。开车与手柄模式用的是 Xbox 虚拟手柄，只有 A/B/X/Y、LB/RB、视图/菜单、L3/R3 十个键，选它不会生效。」 |

### 3.5 顺带：教程里「齿轮」的说法跟着改

`CockpitView.swift:485` 的教程文案改成与顶栏一致（「设置」）。

---

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改** |
| 电脑侧（bridge / pack） | **无** |
| App 侧 | `Views/CockpitView.swift`（顶栏、状态条标签、绑定列表文案、教程文案、切模式确认）、`Views/SettingsView.swift`（预设行结构 + 行尾菜单） |
| 存储键 | **一个不动** |
| 文档 | 本文件 + `PalmDeck-v4-app-interaction.md`（§12.16）+ `README`/`TODO` 各一处 |

---

## 5. 验证方式

- **源码守卫**（`tests/test_deck_bindings.py::TestDiscoverability`）：
  顶栏「设置」带文字；预设行有 `Menu`/`ellipsis.circle` 且仍保留 `swipeActions`；
  切模式有确认（`pendingMode` + `alert`）且只在 `link == .live` 时弹；
  源码里不再出现 `HudCell(label: "SRC"` / `"仅飞行"`；状态条三个标签是中文。
- 全量 `python3 -m unittest discover -s tests -t .` 全绿。
- `xcodebuild -destination "platform=macOS,variant=Mac Catalyst"` → `BUILD SUCCEEDED`，零警告。
- **Mac Catalyst 截图**：顶栏三个入口都带字；预设行尾有 `⋯`、点开有重命名/删除；
  已连接时点另一个模式出确认框；状态条最右两格是「模式 / 通道」；
  组件库绑定列表里是「开车/手柄不生效」。

## 6. 边界与不做

- **Dynamic Type 与无障碍标签**（走查里的第 5 条）：本轮不做，另起一轮落地，
  见 `docs/PalmDeck-v4-accessibility.md`（视图层 `.pdFont` + 自绘控件补
  `accessibilityLabel` / `accessibilityValue`，座舱 chrome 收口）。
- **不改模式胶囊的样式**（它是「当前模式」，不是入口）。
- **不给内置预设加菜单**（内置不可删改，菜单只会引导用户点进去发现点不动）。
- **不动 `swipeActions`**（老路径保留）。
- **不改 `UDP` / `WS` 的值**（协议事实，改了反而搜不到、对不上）。

## 7. 工作量

**S–M**：`CockpitView.swift` 四处小改 + 一个 `@State pendingMode`；
`SettingsView.swift` 一处结构调整；测试 1 个类（实施时写了 **11 条**）；文档 3 处。
拆成三步：**a+d（纯文案/样式）→ b（行结构）→ c（行为）**，每步都能单独构建验证。

---

## 8. 落地记录（已实施）

### 8.1 改动清单

| 文件 | 改动 |
|---|---|
| `Views/CockpitView.swift` | 顶栏齿轮 → 齿轮 + 「设置」（宽 64，图标 13 / 字 11 medium，与「布局」同一套）；状态条 `LINK`/`MODE`/`SRC` → `链路`/`模式`/`通道`；切模式改为 `requestMode(_:)`：已连接且不是当前模式时弹确认（`pendingMode` + `.alert`），未连接直接切，确认后仍在编辑态就 `commitEditing`；绑定列表 `· 仅飞行` → `· 开车/手柄不生效` + footer 改写；教程文案「齿轮设置」→「「设置」」 |
| `Views/SettingsView.swift` | 预设行从「整行 Button」改为 `contentShape + onTapGesture`（否则行尾 `Menu` 点不动），行尾加 `Menu`（`ellipsis.circle`：重命名 / 删除），内置与「默认」行不显示；`swipeActions` 保留 |
| `tests/test_deck_bindings.py` | 新增 `TestDiscoverability`（**11 条**守卫） |
| 文档 | 本文件 + `PalmDeck-v4-app-interaction.md` §12.16 + `README`（测试项数）+ `TODO` |

教程那两节的具体文案（`CockpitTutorialView`）：

- **换模式**（`arrow.triangle.2.circlepath`）：「已连接时换模式会问一句：电脑端要换手柄后端
  （vJoy ≠ 虚拟 Xbox），游戏里这只手柄会掉一下，重连或重进就行。」
- **底部状态条**（`chart.bar`）：「最左边是横滚 …… 后面依次是「链路」「模式」「通道」：
  「通道」是电脑实际用的传输通道 —— UDP 是轴的快速通道，WS 是 WebSocket 控制通道。」

### 8.2 机器验证

1. `python3 -m unittest discover -s tests -t .` → **`Ran 199 tests … OK`**（新增 11 条之前是 188）。
2. `xcodebuild … -destination "platform=macOS,variant=Mac Catalyst" build` →
   **`** BUILD SUCCEEDED **`**，`grep -E "error:|warning: [^M]"` 无匹配（零警告）。
3. 源码守卫 `TestDiscoverability` 全绿（见 §5）。

### 8.3 未做 / 风险

- **Dynamic Type 与无障碍标签**（走查第 5 条）：见 §6；已由
  `docs/PalmDeck-v4-accessibility.md` 落地。
- **内置预设的 `⋯` 菜单**：故意不给（不可删改，给了菜单只会引导用户点进去发现点不动）。
- **未连接时切模式不提醒**：这是刻意的（本机切模式没有代价）。代价是：**正好没连上**时
  用户也收不到任何提示，若他以为连上了，就会觉得「切了没反应」。

### 8.4 顺手发现的（本轮不改，记 `docs/TODO.md`）

组件库弹窗的**绑定下拉不按组件类型过滤**：类型选「按键」，绑定里照样能选「油门」这类**轴**绑定；
而 `tapButton` 对轴绑定是空实现（`Views/Widgets.swift:167` 的 `if/else` 链里没有轴分支），
于是加出来的是**一个按了没反应的按键**。更糟的是新建组件的默认绑定就写死 `@State binding = .throttle`，
**选「按键」→ 直接「添加到画布」就能踩到**。改法（按类型过滤选项 + 换类型时把绑定改成该类的第一个）
属于**行为变更**，按仓库规矩得先出方案，故本轮只记录。

---

## 9. 实测记录（Mac Catalyst，2026-09-25，逐张截图）

前提：`App.app` 从 DerivedData 直接 `open`（Mac Catalyst），电脑侧 `bridge.py` **未跑** → 未连接；
先删掉 `palmdeck_widgets_v10` 让三个模式回到出厂布局，避免旧数据干扰读数
（`LayoutStore` 只在**改布局时**才落盘，所以删除后启动内存里是出厂布局、键是空的）。

| 看哪 | 结果 |
|---|---|
| 顶栏 | 「一键连接」/「⚙ 设置」/「▦ 布局」**三个入口都带字、等宽等高**；进编辑态时「布局」变橙色「完成」 |
| 状态条 | 未连：`链路 未连 · 模式 开车 · 通道 —`；连上后：`链路 192.168.3.103 ● · 模式 开车 · 通道 udp`（值仍是 `UDP`/`WS`） |
| 预设页行尾 | 用户布局预设（`卡车台`）行尾有 `⋯`；内置 `WARDOGS` / `欧洲卡车模拟` 与内置「默认」行**没有** `⋯` |
| 点行体本身 | 仍然一键应用（行从整行 `Button` 改成 `onTapGesture` 后没坏：点完该行显示「当前」） |
| `⋯` 菜单 | 展开是「✎ 重命名 / 🗑 删除」（删除红色）；`swipeActions` 左滑仍在 |
| **已连接**时切模式 | 点「飞机」→ 弹「切换到「飞机」？电脑端要从 vJoy 换成虚拟 Xbox 手柄（或换回来），游戏里这只手柄会掉一下，重连或重进即可。当前的布局会先保存。」+「取消 / 切换」；点「切换」后 `palmdeck_mode` 立刻变 `heli`，控制台 `模式 heli / Hz 58.6` |
| **未连接**时切模式 | 点「手柄」→ **不弹窗**，`palmdeck_mode` 直接变 `gamepad`（若弹窗，得先点「切换」才会变） |
| 组件库绑定列表 | 类型选「按键」→ 绑定下拉里出现 `按钮 11 · 开车/手柄不生效`；选中后弹出 ⚠️ 段：「第 11–16 号键只在飞行模式里存在（电脑侧那只 vJoy 手柄）。开车与手柄模式用的是 Xbox 虚拟手柄，只有 A/B/X/Y、LB/RB、视图/菜单、L3/R3 十个键，选它不会生效。」 |
| 教程（设置 → 帮助 → 查看使用教程） | 顶部那条已改成「右侧是连接状态 +「设置」+「布局」」；新增「**换模式**」（vJoy ≠ 虚拟 Xbox，手柄会掉一下）与「**底部状态条**」（链路 / 模式 / 通道，并说明 UDP 与 WS 各是什么）两节 |

> 这一轮在 Catalyst 上又踩到三个坑，已同步进 `~/.pi/agent/skills/shot/SKILL.md` 之外、也记在这里：
> ① **`sips -c/--cropOffset` 的落点会漂**：同一张 2940×1912 原图上请求 `(Y=480, X=1760)`，
> 实际落点约 `(Y≈898, X≈1865)`。**不能**用请求的 offset 反算逻辑坐标；
> 要么只做**同图内**的相对测量（把光标当参照物），要么先用一个已知控件校准一次。
> ② **Catalyst 的 `Picker`（Form 行）**：点**左边的标签不展开**，必须点**右边的值**；
> 展开后方向键是**从第一项往下数**（而不是从当前选中项继续），`↓×N + Enter` = 选第 N+1 项 —— 比算坐标稳得多。
> ③ **弹出菜单（NSMenu）是独立窗口**：`scroll.py` 要先把鼠标移到菜单**里面**再滚才有效。
