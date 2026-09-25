# 方案：画布拖拽吸附与对齐线（P1.7）

**状态**：✅ 已采纳并落地（本轮；按 `PalmDeck-proposal-template.md` 骨架写）
**影响范围**：App 侧（`Model/Snap.swift` 新增、`Views/Layout.swift` 接线）；**不碰协议、不碰电脑侧**
**一句话**：拖组件时吸最近的边/中线并画出对齐线，顺手保证组件不会拖出画布找不回来。

---

## 1. 目标

**要解决的真实问题**（来自 UX 走查 P1.7）：现在拖组件是「纯自由拖动」，没有任何参考。

- 两个滑条要**对齐**，只能靠肉眼看像素；手一抖就差 3~5pt，摆出来是歪的，而且**看不出来歪**。
- 想「居中」，得目测画布中线在哪；滑条和方向盘的中心对不上是常态。
- 更糟的是**可以把组件拖出画布**：`WRect` 是 0~1 的归一化坐标，但代码里**没有任何夹取**
  （`Layout.swift` `EditableWidget` 拖动分支只做 `st.x + translation.width / W`）。
  拖到画布外之后，`✕` / `Aa` / 缩放手柄可能都不在可视区里，**只能靠「取消编辑」或整表回滚**救。

**不做的代价**：布局永远摆不整齐（这是**唯一**的「手工活」，值得给参考线）；
以及「组件拖丢」这个死胡同状态会一直存在。

## 2. 现状与证据

| 事实 | 证据 |
|---|---|
| 拖动只做线性位移、无吸附无夹取 | `Views/Layout.swift` `EditableWidget`：`nw.rect = WRect(x: st.x + g.translation.width / W, …)` |
| 缩放手柄同为线性 | 同上：`w: max(0.04, st.w + g.translation.width / W)` |
| 归一化坐标 | `Views/Layout.swift:4` `struct WRect { x, y, w, h: Double }`（相对可用画布 0~1） |
| 画布尺寸在编辑态已知 | `WidgetCanvas` 用 `GeometryReader` 拿 `W/H`，已经传给每个 `EditableWidget` 的 `canvas: CGSize` |
| 高频落盘不能打断手势 | 同文件注释：`add`/`remove`/`update`（拖拽中高频调用）**不得**递增 `revision` |

（另：`WidgetCanvas` 不裁剪，越界组件会画到画布满框之外 —— 更难被发现。）

## 3. 方案

### 3.1 吸附：只吸「边」和「中线」

拖动时把「正在拖的框」与候选线比较，**每个轴各吸一条最近的**：

| 轴 | 同类 | 候选线 | 被吸附锚点 |
|---|---|---|---|
| x | 边缘 ↔ 边缘 | 画布 `0` / `W`，其它每个组件的 `left` / `right` | 本组件的 `left` / `right` |
| x | 中心 ↔ 中心 | 画布 `W/2`，其它组件的 `centerX` | 本组件的 `centerX` |
| y | 边缘 ↔ 边缘 | 画布 `0` / `H`，其它组件的 `top` / `bottom` | 本组件的 `top` / `bottom` |
| y | 中心 ↔ 中心 | 画布 `H/2`，其它组件的 `centerY` | 本组件的 `centerY` |

**边缘与中心不交叉**（`center` 不会吸到别人的 `left` 上）。这不是洁癖：
实际摆两个同宽滑条想「左对齐」时，本框中心到对方右边缘的距离比边缘差更小，
于是被「中心-右边缘」抢走 —— 屏幕上看着就是歪的。跨类对齐在人眼里不是对齐。

- **阈值 7pt**（手指尺度；小于 7pt 才吸，避免「怎么拖都动不了」）。
- 每个轴只在阈值内吸**一条**（最近者）；平手时按「组序 → 候选序 → 锚点序」取先到的 → 结果稳定可复现。
- 吸附基于**本次拖动的起点 + 位移**（`dragStart`），不是「上一次吸附后的位置」——
  所以往回拖会自然脱吸，不会越吸越粘。
- 两个轴独立：x 吸住、y 照样自由（反之亦然）。
- **夹取改掉落点时会撤掉该轴的线** —— 否则屏幕上会出现「线在一边、组件在另一边」的假对齐。

### 3.2 对齐线（视觉反馈）

吸住时画一条**贯穿画布**的线（灰青色 1pt）：竖线画在吸附到的 x，横线画在 y。
没吸住就不画 —— 只在真吸上的时候出现，线条本身才是信息。

### 3.3 夹取：不许拖丢（`minVisible = 40pt`）

不管有没有吸附，落点都夹到「至少 40pt 留在画布里」：

```
lo = -max(0, pw - 40)          // 左侧最多出去 (宽 - 40)
hi = W - min(pw, 40)           // 右侧同理；小件则要求整个在画布里
```

- 40pt ≈ 一根手指，够抓住它拖回来；也够点到 `✕`。
- 宽/高比画布还大的组件：仍在 `lo…hi` 区间内可拖，不会「怎么拖都一样」。
- **缩放不夹取**（本次不做）：缩放到超出画布时，`✕` 与拖动面仍在可视区里，出得来；
  要拦的话规则更多（要不要允许 w>1 表达「占满」？），留到有真实需求再说。

### 3.4 数据与接口

**不新增持久化键、不改结构**：吸附只是「拖动这一瞬间」的落点计算，落盘还是那个 `palmdeck_widgets_v10`。

- 新增纯逻辑 `Model/Snap.swift`（**只 import Foundation**，能被 `swiftc` 单独编译测试）：

```swift
enum Snap {
    struct Rect: Equatable { var x, y, w, h: Double }      // 归一化
    struct Outcome: Equatable { var rect: Rect; var guideX: Double?; var guideY: Double? }
    static let threshold = 7.0, minVisible = 40.0
    static func drag(_ moving: Rect, others: [Rect], canvas: (w: Double, h: Double)) -> Outcome
}
```

- `LayoutStore` 增加**瞬时**的对齐线状态（不落盘）：
  `@Published private(set) var guidesX/guidesY: [Double]` + `setGuides(x:y:)` / `clearGuides()`；
  `editing` 变 false 时自动清空（避免退出编辑后留一条线）。
  赋值前比一下，值没变就不发布（同 §12.8 的「变了才发布」）。

### 3.5 异常路径

| 情况 | 行为 |
|---|---|
| 画布尺寸为 0（还没布局出来） | `Snap.drag` 里 `guard W > 0, H > 0 else` 原样返回（不算，**不能算出 NaN** —— NaN 归一化坐标会被 `JSONEncoder` 拒掉，整个布局就丢了） |
| 排序/单选拖动 | 每次只有一个组件在拖（手势独占），不存在多组件互吸 |
| 拖动中切模式/退出编辑 | 手势 `onEnded` 没来也会因 `editing=false` 清线；`revision` 机制重建画布 |
| 阈值内但没有「其它组件」 | 仍可吸画布三条线（居中/贴边） |

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改** |
| 电脑侧（bridge / `layouts.json`） | **无** |
| App 侧 | 新增 `Model/Snap.swift`；`Views/Layout.swift`（拖动分支接 `Snap.drag`、`WidgetCanvas` 画线、store 清线） |
| 持久化键 | **无新增** |
| 文档 | 本文件 + `PalmDeck-v4-app-interaction.md`（画布操作与 §12.13）、`README`、`TODO` |

## 5. 验证方式

- **纯逻辑**：`tests/ios/SnapTests.swift`（`swiftc` 直跑，`tests/test_ios_snap.py`）——
  边缘对边缘、中心对中心、**中心不吸别人的边**、7pt 边界、最近者优先、阈值外不动、
  夹取的三种尺寸关系、只吸一个轴时另一个轴 `guide == nil`、`w/h` 不被吸附改动、
  夹取改掉落点后撤线、画布尺寸为 0 时原样返回（不能变 NaN）。
- **源码守卫**：`tests/test_deck_bindings.py` —— `Snap.swift` 不得 `import SwiftUI`；
  `Snap.drag(` 只允许在拖动分支出现一次；`onEnded` 必须 `clearGuides()`；
  缩放手势**不得**调 `Snap`。
- **真机/截图**：Mac Catalyst 里把两个滑条拖到「左边缘对齐」看是否出竖线并停在同一 x；
  故意把方向盘拖出左边界，确认停住时仍有 40pt 留在画布内。
- `python3 -m unittest discover -s tests -t .` 全绿；`xcodebuild -scheme App` `BUILD SUCCEEDED`。

### 落地记录（本轮实测）

Mac Catalyst（`palmdeck_widgets_v10` 逐次落盘后读回来比对；画布 ≈ 998×756pt，
阈值 7pt，滑条 w = 0.2 → 205pt）：

| 场景 | 算出来的落点 | 实际落点 | 结论 |
|---|---|---|---|
| 「刹车」中心离画布中线差 10pt（> 阈值） | 0.4098 | **0.4098** | 不吸 ✓ 且是纯算术值 |
| 「油门」左边缘离「刹车」左边缘差 3pt | 0.4127 | **0.4098** | 吸住 ✓（与「刹车」x **完全相等**） |
| 「视角」中心离画布中线差 4pt | 0.4260 | **0.4300** | 吸住 ✓（中心 = 0.5000） |
| 「视角」中心离「刹车」右边缘差 4pt（跨类） | 0.5098 | **0.5133** | 没吸 ✓（差的是合成鼠标事件本身的十几 px 误差） |

对齐线的**可见性**也在同一拖动的**按住状态**截屏里核过：吸附时画布正中水平位置
出现一条贯穿的细实线（与虚线选中框明显不同），松手后消失。

> 注：夹取「拖出画布仍留 40pt」用纯逻辑测试钉死（综合拖拽在合成事件下有十几 px 误差，
> 不如直接测函数）。另：合成鼠标在少数几次拖动里没被 App 收到（`cliclick` 的鼠标事件
> 有丢失），属于测试工具问题，不是产品行为 —— 同一场景重跑即出结果。

`python3 -m unittest discover -s tests -t .` → **168 项全绿**；`xcodebuild -scheme App`（Mac
Catalyst）→ `** BUILD SUCCEEDED **`（零警告）。

## 6. 边界与不做

- 不做网格吸附（固定栅格会把「手摆的自由度」收窄，且和归一化坐标一起会随画布尺寸漂）。
- 不做等间距分布 / 智能排布（那是另一套「自动布局」，不套在拖拽里）。
- 不做缩放的吸附与夹取（见 3.3）。
- 不做撤销的粒度调整（仍是一次拖动 = 一次落盘，靠「放弃」回滚）。
- 不做多选 / 成组拖动（现在没有多选概念）。

## 7. 工作量

**S~M（约 120 行实现 + 2 个测试文件）**，拆 3 步：

1. `Model/Snap.swift` + `tests/ios/SnapTests.swift` + `tests/test_ios_snap.py`（纯逻辑先绿）
2. `Views/Layout.swift` 接线（拖动分支 + 对齐线渲染 + `editing` 清线）+ pbxproj 注册
3. 源码守卫 + 截图核对 + 文档（本文件 §5 的产物）
