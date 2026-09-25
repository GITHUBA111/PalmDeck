# PalmDeck v4 · 未连接提示横幅不该“顶”一下画布

> 现象（用户）：**点「点此连接电脑」的提示，其它组件会闪一下。**
> 本文只修这一个 View 层的布局抖动，不动状态机 / 协议 / 存储。

---

## 1. 目标

- 点按未连接横幅（`idle → connecting`）时，**画布上的组件不允许移动 / 跳动**。
- 其它会改动「画布上方那一行」的连接事件（连上 `live`、断线 `lost`）尽量平滑，不“啪”一下。
- 只动 `Views/CockpitView.swift`。

## 2. 现状与证据（源码）

`CockpitView.deckBody` 是（节选）：

```swift
VStack(spacing: 0) {
    if layout.editing { editBar }
    else { notConnectedBanner }      // ← 这一行会随连接状态 出现 / 消失
    presetNoteRow
    WidgetCanvas(store: layout, mode: s.mode, s: s, ctrl: ctrl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
.frame(width: W, height: H)          // 整块高度固定
```

`WidgetCanvas` 内部是 `GeometryReader`，组件坐标是**归一化**的：

```swift
ForEach(store.widgets(mode: mode)) { w in
    EditableWidget(..., canvas: CGSize(width: W, height: H), ...)   // x/y/w/h ∈ 0~1
}
```

横幅的出现条件（改前）：

```swift
if s.link != .live && s.link != .connecting { … }   // connecting 时也收起
```

于是点按横幅：

1. `ctrl.connect(...)` → `s.link = .connecting`；
2. 横幅**整行消失**（因为它把 `.connecting` 也排除了）；
3. `deckBody` 的总高 H 不变，于是 `WidgetCanvas` 的 `GeometryReader` **变高**（多出横幅那一行）；
4. 所有组件按归一化坐标重排 ⇒ 视觉上就是“点一下，其它组件全闪了”。

同理，`connecting → live`、`live → lost` 也会各跳一次。

> 这不是本轮引入的问题，是「横幅占位」方案从一开始就带的：横幅用占位（而不是 overlay）本身是对的
> （见 `deckBody` 上方的注释：overlay 会让被盖住的组件点不动），但它**没有把高度锚住**。

## 3. 方案

把「画布上方那一行」的高度与连接状态**解耦**：

1. **`connecting` 不再收起横幅**：把条件从
   `s.link != .live && s.link != .connecting` 改成 `s.link != .live`，
   连接中显示「正在连接…」（同一条胶囊、同一套 padding），只是不可再点。
   → 点按瞬间行高不变，画布不动。
2. **行高固定**：`deckTopRowH: CGFloat = 32`，胶囊放在 `.frame(height: deckTopRowH)` 里。
   文字 / 图标 / 发现的 IP 变化都不再影响高度；文字 `.lineLimit(1)` + `minimumScaleFactor(0.8)`。
3. **`live` 时才收成 0 行**，并给 `deckBody` 的 `VStack` 挂
   `.animation(.easeInOut(duration: 0.22), value: s.link)`：
   连上 / 断线时画布是**平滑展开 / 收起**，不是瞬跳。
4. 连接中 `.disabled(true)`：避免重复点。

```
idle        → [ 点此连接电脑 192.168.3.103 ]   行高 32
connecting  → [ 正在连接… ]                    行高 32   ← 点按不改变画布
live        → （0 高，动画展开画布）
lost        → [ 点此连接电脑 … ]               行高 32
```

## 4. 影响面

| 文件 | 改动 |
|---|---|
| `Views/CockpitView.swift` | `notConnectedBanner` → `connectionBannerRow`（含 connecting 态 + 固定行高 + live 收回 + 动画） |
| `tests/test_deck_bindings.py` | 新增 `TestConnectBanner` 守卫 |
| 文档 | 本文件 + `README.md` + `PalmDeck-v4-app-interaction.md` |

**不动**：`ControllerState` / `LinkState` / `CockpitController.connect` / 协议 / 存储键 / 画布坐标。

## 5. 验证方式

- 源码守卫 `TestConnectBanner`：横幅条件含 `connecting`、固定 `deckTopRowH`、`live` 才收 0、
  有 `.animation(..., value: s.link)`、文字 `lineLimit(1)`、connecting 时 `disabled`。
- `xcodebuild -scheme App`（Catalyst + iOS Simulator）零警告；`python3 -m unittest` 全绿。
- 行为：`idle` 与 `connecting` 的行高**同为 32**（源码上是同一个 `.frame`），
  所以点按前后 `WidgetCanvas` 拿到的 `geo.size` 不变 ⇒ 组件不位移。

## 6. 边界与不做

- **编辑条 ↔ 横幅** 的行高仍不同（编辑条更高），所以进 / 出「布局」模式画布仍会变一次 ——
  那是用户主动操作，且编辑条本身就要那块高度，本轮不动。
- **「存为预设」回执**（`presetNoteRow`，编辑态里出现 / 消失）也会让画布动一下；
  场景小（编辑中存模板），本轮不动，记在这里。
- 不给横幅加进度动画 / 转圈（连接通常一瞬间完成，反而更闪）。
