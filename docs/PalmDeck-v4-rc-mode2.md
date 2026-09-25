# 方案：遥控器双杆（Mode 2）布局

> **方案名**：遥控器双杆（Mode 2）布局
> **状态**：✅ 已落地（按 §3.2 **方案 A**；改动落于 `Views/Widgets.swift` `Views/Controls.swift`
> `Views/Layout.swift` `Views/SettingsView.swift`）
> **影响范围**：App 侧（`Views/Widgets.swift` `Views/Controls.swift` `Views/Layout.swift`
> `Views/SettingsView.swift`）+ 文档
> **一句话**：给飞过航模遥控器的人一套「左杆=总距+尾桨、右杆=副翼+升降」的布局，
> 一键切换，不动协议、不动电脑侧。

## 0. 起因（更正）

最初把这件事记成「**零代码**：官方出一个布局预设即可」。**这是错的**。查了代码：
`stick` 组件的通道是**写死**的（`Widgets.swift:185` `StickControl(x: $s.roll, y: $s.pitch)`），
仓库里**没有任何**控件能同时写「方向舵 + 总距」。所以 Mode 2 不是布局，是**缺一个控件**。
本方案就是要补它。

## 1. 目标

让「手上有遥控器肌肉记忆」的玩家（飞 WARDOGS / 无人机模拟）能**不脱手**地用双杆飞，
而不是被迫用 PalmDeck 的「真机座舱」布局（总距滑条 + 脚舵滑条 + 周期杆）。

**不做的代价**：这部分玩家进来第一眼找不到自己会的杆型，直接卸载；而「双杆」是
模拟飞行圈里比「真机座舱手」更主流的默认。这不是锦上添花，是**一类玩家的准入门槛**。

## 2. 现状与证据

| 结论 | 证据 |
|---|---|
| `stick` **写死**发 roll + pitch，绑定被忽略 | `Views/Widgets.swift:185` `StickControl(x: $s.roll, y: $s.pitch, ...)` |
| 于是 `stick` 不给绑定下拉，只有一行说明 | `Views/Widgets.swift:52` `case .stick: return "固定发「横滚 + 俯仰」"`；`:39` `bindingOptions` 默认 `[]` |
| 松手回中把 **x 和 y 一起**拉回 0，不能只回一轴 | `Views/Controls.swift:29-30` `x += (0 - x) * k; y += (0 - y) * k`，由单一 `returnToCenter` 控制（`:106`） |
| 摇杆的无障碍读数写死「横滚/俯仰」 | `Views/Controls.swift:116` |
| heli 已经在读 `yaw` 与 `collective`，**协议不用改** | `Model/AxisMap.swift:77` `o.yaw = cYaw`；`thr` = `collective`（= 熄火锁处理过的 `throttle`） |
| 内置「布局」预设 = 一行硬编码 + 一个 `LayoutStore` 工厂 | `Views/SettingsView.swift:472` `enum Kind { case profile, restoreDefault }`；`:488` 渲染；`:586` 应用 |
| 「固定通道组件不给下拉」是**被文档与测试锁死**的既有决策 | `docs/PalmDeck-v4-binding-filter.md`；`tests/test_deck_bindings.py:420` `test_only_slider_and_button_have_binding_options` |

**协议侧**：`PKT`（22B）与电脑侧**完全不动** —— Mode 2 只是换「哪只手写哪个已有的轴」。

## 3. 方案

### 3.1 两轴共存的摇杆

新增一个控件类型（下面 A/B 二选一），X 写 `s.yaw`、Y 写**单极** `s.throttle`（Y ∈ [-1,1] → 0..1），
且 **Y 不回中**（对位遥控器左杆：尾桨松手回中、总距保持）。

`StickControl` 加三个参数（都有默认值，老调用点不动）：

```swift
var centerY: Bool = true      // 只有这个杆给 false：松手只把 X 拉回 0
var xLabel: String = "横滚"    // 无障碍读数用词
var yLabel: String = "俯仰"
```

- `startReturn()` 里 `if centerY { y += (0 - y) * k }`；收尾条件也跟着只判 X。
- 中位咔哒那一声只在 `centerY` 时对 Y 生效（总距没有「中位」）。
- `accessibilityValue` 用 `xLabel/yLabel`。

### 3.2 方案 A（推荐）：新增 `WidgetKind`

`WidgetKind` 加一档 `.collective`，显示名「**总距/尾桨杆**」，渲染走上面的双轴逻辑。

- **不动** `docs/PalmDeck-v4-binding-filter.md` 的合同：新 kind 的 `bindingOptions` 仍是 `[]`
  （它照样写死通道），`fixedBindingNote` 加一条「固定发「方向舵 + 总距（松手保持）」」。
- 老布局零影响（没人用过这个 kind）。
- 代价：`WidgetKind` 从 8 档变 9 档，要同步 `docs/README.md` 的「8 类组件」与交互文档的枚举。

### 3.3 方案 B：让 `stick` 读 `binding`

`stick.bindingOptions = [.roll, .yaw]`：`.yaw` → 上面的双轴，其余 → 现状 roll/pitch。

- 优点：不加枚举，更通用（将来 `.pitch+yaw` 之类也能长）。
- 代价：**重开** `binding-filter` 的既有决策 —— 要改 `docs/PalmDeck-v4-binding-filter.md`
  与 `tests/test_deck_bindings.py:420`，得说清「这里为什么可以给下拉」（因为两个选项都真生效）。

> 两个方案都**不引入假下拉**。区别只是「新控件」还是「老控件多一个真选项」。
> 倾向 A：它把「一个控件 = 一对固定通道」的模型保持住了，改动面更小、回归风险更低。

### 3.4 布局与入口

`LayoutStore` 加工厂 `defaultRCMode2()`（heli 模式，0..1 坐标）：

| 组件 | 通道 | 位置（x, y, w, h） |
|---|---|---|
| 左杆「总距/尾桨杆」 | X=yaw，Y=throttle（保持） | `0.04, 0.24, 0.30, 0.52` |
| 右杆「摇杆」（= 现有周期杆） | roll + pitch | `0.40, 0.30, 0.28, 0.48`（右手拇指位） |
| 视角 | lookX/lookY | `0.78, 0.12, 0.18, 0.28` |

入口照抄内置「默认」行的写法（`SettingsView.swift:472/488/586`）：`PresetRow.Kind` 加一档
`rcMode2`，应用时 `layout.applyRC()`。它出现在**飞机**模式下的预设列表里，行尾章「内置 / 布局」。

**数据**：不新增持久化键。布局仍进 `palmdeck_widgets_v10`。
**兼容**：新 kind 写进 `widgetsJSON` 后，被**旧版 App** 读到会解码失败 →
`applyProfile` 的 `try?` 退化成「不碰布局」（静默不动），不会崩。属可接受降级，写进文档。

### 3.5 异常路径

- 熄火锁（`throttleHold` 默认锁上）：Mode 2 左杆 Y 推满也**发不出去**，直到解锁 —— 与既定安全一致。
- 切到开车/手柄模式：这套布局只挂在 heli 下（「布局」预设按模式过滤，`SettingsView.swift:480`）。
- 快速连点左杆：Y 是保持型，不需要防抖；X 沿用既有回中定时器。

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改** |
| 电脑侧（bridge / pack） | **无** |
| App 侧 | `Widgets.swift`（新 kind / 渲染 / note）、`Controls.swift`（`StickControl` 三参数）、`Layout.swift`（`defaultRCMode2`）、`SettingsView.swift`（预设行） |
| 持久化键 | 无新增 |
| 文档 | `docs/README.md`（组件数）、`docs/PalmDeck-v4-app-interaction.md`（kind 枚举 + 触觉）、`docs/PalmDeck-v4-binding-filter.md`（仅方案 B） |

## 5. 验证方式

- **新测试**（沿用 `tests/test_deck_bindings.py` 的源码守卫风格）：
  - `TestRCMode2`：`WidgetKind` 有该档且 `bindingOptions == []`；`StickControl` 有 `centerY`；
    渲染分支写 `$s.yaw` 与 `s.throttle`（且是 `(y+1)/2` 单极映射）；`LayoutStore.defaultRCMode2()`
    存在且只含 3 个组件；`SettingsView` 有该内置行。
  - `TestAccessibility` 不回归：新控件用 `.pdFont`、带 `accessibilityValue`。
  - `tests/test_ios_axis.py`：heli 真值表不变（不用改，跑通即证明协议没动）。
- **截图**（Mac Catalyst）：飞机模式下预设列表出现「遥控器双杆」→ 点一下 → 左杆推 Y，
  底栏「总距」跟着涨、松手不回、X 松手回中；熄火锁不解锁则「总距」恒 0。
- 全套 `python3 -m unittest discover -s tests -q` 绿；`./mac.sh build` 通过。

## 6. 边界与不做

- **不做**舵机微调 / 曲线（expo）—— 那是另一件（见 §「可调 expo」），且要等 G4 真机飞过再调。
- **不做**混控（CCPM / 尾桨补偿）—— 交给游戏。
- **不改** heli 出厂默认布局 —— Mode 2 是**可选项**，不动既有的「真机座舱手」。
- **不做** Mode 1 / Mode 3（换个通道指派即可，等有人要再说）。

## 7. 工作量

**M**，拆两步各自可验证：

1. **控件**：`StickControl` 三参数 + `WidgetKind` 新档 + 渲染 + 守卫测试。（半天）
2. **布局 + 入口**：`defaultRCMode2()` + 内置预设行 + 截图走查 + 文档同步。（半天）

---

## 8. 落地记录（2026-09，Mac Catalyst 实机走查）

按 **方案 A** 实施：新增 `WidgetKind.collective`，**未**动 `docs/PalmDeck-v4-binding-filter.md` 的合同
（新 kind 的 `bindingOptions` 依旧为 `[]`，只有一行 `fixedBindingNote`）。

| 改动 | 落点 |
|---|---|
| 双轴摇杆可只回一轴 + 可定制读数用词 | `Controls.swift` `StickControl`：`centerY` / `xLabel` / `yLabel` |
| 新控件 + 渲染 | `Widgets.swift`：`case collective`、`StickControl(x: $s.yaw, y: Binding(get: { s.throttle*2-1 }, set: { s.throttle = ($0+1)/2 }), centerY: false, …)` |
| 内置还原点 | `Layout.swift`：`rcMode2Name` / `defaultRCMode2()` / `applyRCMode2` / `isCurrentRCMode2`；`add(kind:)` 补尺寸分支 |
| 预设行（仅飞机模式） | `SettingsView.swift`：`Kind.rcMode2` + `presetRows` 里的 `s.mode == .heli ?` 门控 |

**实测**（Catalyst，预设列表点「遥控器双杆」）：左杆 Y 上推 → 底栏「总距 83%」，**松手保持 83%**；
左杆 X 右推 → 「方向舵 +1.00」，**松手回 0.00，总距仍 83%**（Mode 2 左杆语义）。
熄火锁锁上时总距输出 0%、解锁后回到 83%（与既定安全一致）。右杆仍写 roll/pitch、两轴都回中（无回归）。

**测试**：新增 `TestRCMode2Layout`（9 条），全套 278 → **287** 绿；`./mac.sh build` 通过。

**未做**（保持 §6 边界）：没给 `collective` 加绑定下拉；没动 `defaultHeli()`；没碰协议与电脑侧。
