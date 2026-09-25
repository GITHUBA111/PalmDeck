# PalmDeck v4 动态字号 + 无障碍标签（走查第 5 条）

> 状态：**已实施**（方案 + 落地记录同文件；实测见 §9）。
> 来源：`docs/TODO.md`「其它」——全 App 固定 `pt` 字号 + 全自绘控件，
> VoiceOver 读不出任何控件、系统调大字号 App 一点不变。一直标为「独立一轮 L」。
> 影响范围：**只在 App 侧 View 层**，不动协议、不动电脑侧、不动任何存储键。

---

## 1. 目标

一句话：**让看不清的人能放大字，让看不见的人能听见每个控件在说什么、值是多少。**

| 现象 | 不修的代价 |
|---|---|
| 全 App `.font(.system(size: N))`（固定 pt，约 130 处） | 系统字号调到最大，App **一个字都不变**；低视力用户无法使用 |
| 方向盘 / 摇杆 / 苦力帽 / 滑条 / 视角板 / 姿态球 / 仪表盘全是自绘 | VoiceOver 只报「按钮」或什么都不报，读不出「现在是几度、满舵没有」 |
| 编辑态 ✕ / `Aa` / 缩放手柄是 SF Symbol 图形 | VoiceOver 读「xmark」「character」，不知道是「删除组件」 |

**不做**：重画任何控件、改配色、改画布数据结构、给画布加 VoiceOver 拖拽重排。

---

## 2. 现状与证据

- 固定字号计数（`grep -r "\.system(size:" Native/Views`）：Settings 23、Preflight 23、
  Cockpit 23、Layout 5、FlightPanel 3、Widgets 2、Theme 2、Controls 2、SteeringWheel 1、AttitudeBall 1。
- `accessibility` 在整个 `Native/` 里出现 **0 次**。
- 自绘控件清单：`Controls.swift` 的 `StickControl` / `BipolarSlider` / `UniSlider` / `HatPad` / `LookPad`，
  `SteeringWheel.swift`，`AttitudeBall.swift`（Canvas），`FlightPanel.swift` 的 `ArcGauge` / `BarGauge` / `FlightPanel`。
- 密集横排（顶栏 68/140/96/64、状态条 `HudCell` 用 `.fixedSize`、编辑条、预设行尾章）——
  最大字号下会不会挤裂，是本轮的重点验收项。

---

## 3. 方案

### 3.1 动态字号（Dynamic Type）

1. `Views/Theme.swift` 新增两件工具：
   - `Font.pd(size:weight:design:)` —— 经 `UIFontMetrics.default.scaledValue(for:)` 缩放，
     **非响应式**，给 `Canvas` / `Text.font()` 这类拿不到 `@ScaledMetric` 的地方用。
   - `.pdFont(size:relativeTo:weight:design:)` —— 内部是 `@ScaledMetric` 的 `ViewModifier`，
     **响应式**（系统字号一变整棵视图重排），视图层统一用它。
     默认字号下 `scaledValue == base`，**外观与改动前完全一致**。
2. 把 View 层所有 `.font(.system(size: N…))` 换成 `.pdFont(N…)`（**几何比例字号除外**：
   方向盘的 `r*0.18`、弧表的 `max(9, d*0.26)`、苦力帽的 `w*0.16` 本来就随控件尺寸走）。
3. 根视图 `.palmDynamicType()` 封顶 `.accessibility2`；**座舱 chrome（顶栏 / 状态条 / 编辑条）
   单独收紧到 `.xxLarge`** —— 它们是固定横排 HUD，放开到无障碍档必挤裂。
   设置 / 首启 / 速览 / 弹窗是文字为主、可滚动，再各自 `.palmDynamicType()` 放开到 `.accessibility2`。
4. 密集横排仍以 `minimumScaleFactor` 兜底：宁可字缩，不裂缝。

### 3.2 无障碍标签（VoiceOver）

给每个自绘控件加 `.accessibilityElement(children: .ignore)` + `label` + `value`：

| 控件 | label | value |
|---|---|---|
| `StickControl` | 摇杆 | 横滚 / 俯仰 百分比 |
| `BipolarSlider` | 轴名（如「脚舵」） | ±百分比 |
| `UniSlider` | 油门 | 百分比 |
| `HatPad` | 苦力帽 | 中立 / 上 / 右 / 下 / 左 |
| `LookPad` | 视角触摸板 | 视角左右 / 上下 百分比 |
| `SteeringWheel` | 方向盘 | 角度 + 满舵刻度 |
| `AttitudeBall` | 姿态球（只读） | 横滚 / 俯仰 / 航向 |
| `ArcGauge` / `BarGauge` | 表名 | 百分比 / ±百分比 |
| `FlightPanel` | 飞行仪表盘（只读） | 总距 / 扭矩 / 三轴 |
| 画布 ✕ / `Aa` / 缩放手柄 | 删除组件 / 重命名组件 / 缩放组件 | — |
| 按键组件 | 标题（已是 `Button`） | 按下 / 松开 |

### 3.3 交互 / 数据

- **不改任何持久化键**，不改画布结构，不改包格式。
- 纯展示层：字号与可访问性都只影响本机渲染。

---

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT | 不改 |
| 电脑侧 | 无 |
| App 侧 | `Theme.swift`（工具 + 封顶）、`Controls/SteeringWheel/AttitudeBall/FlightPanel/Widgets/Layout`（标签）、`CockpitView/SettingsView/PreflightView`（字号 + 封顶），零新增存储键 |
| 文档 | 本文件 + `docs/README.md` + `docs/TODO.md` + `PalmDeck-v4-app-interaction.md §12.18` |

---

## 5. 验证方式

1. **源码守卫**：`python3 -m unittest discover -s tests -t .` → **216 项 OK**（新增 `TestAccessibility` 8 条）：
   - 根视图挂了 `.palmDynamicType()`；座舱 chrome 收了口；设置/首启/速览放开口。
   - `Theme.swift` 定义了 `Font.pd` / `.pdFont` / `@ScaledMetric`。
   - View 层不再有裸 `.font(.system(size: <数字`（几何比例表达式白名单）。
   - 摇杆/滑条/苦力帽/视角板/方向盘/姿态球/弧表杆位条 都有 `accessibilityLabel` + `accessibilityValue`；编辑态 ✕/`Aa` 有名。
2. **构建**：Mac Catalyst 与 iOS Simulator 均 `** BUILD SUCCEEDED **`，零警告。
3. **真机字号实测**（`xcrun simctl`，iPhone 18 Pro 模拟器）：见 §8。

---

## 8. 实测（9 月 25 日 17:39 / iPhone 18 Pro 模拟器）

用 `xcrun simctl ui <udid> content_size <档>` 切换系统字号、重启 App 后截图：

| 界面 | 字号 | 结果 |
|---|---|---|
| 座舱（`.palmCockpitType()`，收口 `.xxLarge`） | 默认 `large` | 与改造前逐像素一致（`pdFont` 在基准字号下等于原 `pt`） |
| 座舱 | `accessibility-extra-extra-large` | 字变大；仍不裂缝 |
| 座舱 | `accessibility-extra-extra-extra-large` | **与上一行截图字节完全相同** → 已夹在 `.xxLarge`，不会继续膨胀 |
| 首启（`.palmDynamicType()`，放开 `.accessibility2`） | 默认 `large` | 与改造前一致 |
| 首启 | `accessibility-extra-extra-extra-large` | 字号明显放大，`PalmDeck` 换行、步骤卡文案自动省略（`…`）、整体重排，不重叠 |

**结论**：两类表面行为符合设计——座舱在固定横排里自适应但设了天花板；
首启/设置这类可滚动文字页真正跟随系统字号。

> 说明：模拟器 GUI（`Simulator.app`）在本机不可用、也无点击注入，
> 因此「设置弹窗」本身未在超大字号下单独截图；它与「首启」同用 `.pdFont` + `.palmDynamicType()`，
> 行为由同一套代码路径决定。

---

## 6. 边界与不做

- 不改控件视觉、不复刻系统字号档位表。
- 画布上的 **拖拽 / 缩放不给 VoiceOver 替代手势**（要 `accessibilityAction` 做像素级拖动，
  是另一套「无障碍编辑布局」的活，超出本轮）。
- 不引入第三方库、不做 Localization。

---

## 7. 工作量

**L**，拆成可独立验证的步骤：
① Theme 工具 + 封顶 → ② 机械换字号（`pdFont`）→ ③ 自绘控件补标签 →
④ 密集横排兜底 → ⑤ 测试 + 构建 + 两种字号截图。
