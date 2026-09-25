# PalmDeck v4 组件库绑定按类型收敛

> 状态：**已实施，已在 Mac Catalyst 实机逐项看过**（方案 + 落地记录同文件，见 §8；实测见 §9）。
> 来源：`docs/PalmDeck-v4-discoverability.md` §8.4「顺手发现的」——
> 组件库弹窗的绑定下拉**不按组件类型过滤**：类型选「按键」照样能选「油门」这类轴绑定，
> 而 `Views/Widgets.swift` 的 `tapButton` 对轴绑定是空实现，加出来的是**按了没反应的按键**。
> 影响范围：**只在 App 侧两个 View 文件里改**，不动协议、不动电脑侧、不动存储键、不动画布数据结构。

---

## 1. 目标

一句话：**组件库里能选到的绑定，必须是这个组件真的会用的绑定。**

| 现象 | 不修的代价 |
|---|---|
| 类型「按键」的绑定下拉里能选「油门 / 俯仰 / 横滚…」 | 加出来一个**按了没反应**的按键；而且它的标题取的是绑定名，画布上写的是「油门」——像按钮又像标签 |
| 新建组件的默认绑定写死 `.throttle` | **选「按键」→ 直接「添加到画布」一步就能踩到**，不用手滑 |
| 点组件库的「按键 / 滑条」，弹窗都从「滑条」开始 | 想加按键的人先看到的是滑条，得再点一次类型；「按键」入口名不副实 |
| 方向盘 / 触摸板 / 摇杆 / 苦力帽 / 姿态球也显示绑定下拉 | 这些组件渲染时**各走固定通道**，`widget.binding` 被忽略 —— 下拉里选什么都等于选了个不生效的值 |

**不做**：动态类型 / 无障碍（独立的 L 轮，见 `docs/TODO.md`）、改画布数据结构、给组件新增绑定语义。

---

## 2. 现状与证据

### 2.1 绑定下拉列的是全量枚举（`Views/CockpitView.swift:463-470`）

```swift
Section("绑定功能") {
    Picker("绑定", selection: $binding) {
        ForEach(WidgetBinding.allCases, id: \.self) { b in
            Text(b.onlyOnVJoy ? "\(b.label) · 开车/手柄不生效" : b.label).tag(b)
        }
    }
}
```

`WidgetBinding.allCases` = 8 个轴（`roll…look`）+ 16 个 vJoy 键 + `gearUp` / `gearDown` / `fire`。
不管 `kind` 是什么，这一份列表原样给出。

### 2.2 默认绑定写死 `.throttle`（`Views/CockpitView.swift:445-446`）

```swift
@State private var kind: WidgetKind = .slider
@State private var binding: WidgetBinding = .throttle
```

选「按键」后不改 `binding`，所以 `binding` 仍是轴值 `.throttle`；
`tapButton(.throttle)` 走进 `if let idx = b.vjoyIndex`（nil）→ `else if b == .gearUp`（否）
→ `else if b == .gearDown`（否）→ `else if b == .fire`（否）→ **什么都不做**。
（`Views/Widgets.swift:167`）

### 2.3 只有两类组件真的读 `widget.binding`

- **滑条**：`case .slider` 里 `bindAxis(widget.binding)` + `sliderColor`；
  `bindAxis` 只认 `roll / pitch / yaw / throttle / brake / clutch / rt`（`look` 落到 default → roll）。
- **按键**：`case .button` 里 `tapButton(widget.binding)` + `isButtonActive` + 标题。

其余组件的渲染是**写死通道**，`binding` 只被存下来、从不生效：

| 组件 | 渲染实际读的 | `widget.binding` |
|---|---|---|
| 方向盘 `.wheel` | `bindAxis(.roll)` 写死 | 忽略 |
| 触摸板 `.pad` | `lookX` / `lookY` | 忽略 |
| 摇杆 `.stick` | `$s.roll` / `$s.pitch` | 忽略 |
| 苦力帽 `.hat` | `hat` / `lookX` / `lookY` | 忽略 |
| 姿态球 `.attitude` | `smRoll/smPitch/smYaw` | 忽略 |
| 仪表盘 `.panel` | 只读 | 忽略（已由 `isReadOnly` 拦） |

> 结论：全 App **真正有意义的绑定** = `{roll, pitch, yaw, throttle, brake, clutch, rt}`（滑条）
> ∪ `{vjoy1…vjoy16, gearUp, gearDown, fire}`（按键）。`look` 虽然有 `isAxis == true`，
> 但没有任何一个「读 `widget.binding`」的组件会处理它（触摸板/摇杆/苦力帽都是写死通道），
> 所以它也不该出现在下拉里。

### 2.4 点「按键 / 滑条」弹窗不传类型（`Views/CockpitView.swift:60-68`）

```swift
private func libraryButton(_ title: String, _ kind: WidgetKind, _ defaultBinding: WidgetBinding?) -> some View {
    Button(title) {
        if let b = defaultBinding {
            layout.add(kind: kind, binding: b, mode: s.mode)
        } else {
            showLibrary = true          // ← kind 丢了
        }
    }
}
```

`LibrarySheet(store:mode:)` 没有 `kind` 参数，`@State kind` 永远从 `.slider` 起。

---

## 3. 方案

### 3.1 模型层：把「这个组件吃什么绑定」写在枚举上（`Views/Widgets.swift`）

```swift
extension WidgetBinding {
    /// 滑条真正会用的轴（与 `WidgetView.bindAxis` 的 case 一一对应，不含 `look`）。
    static let axes: [WidgetBinding] = [.roll, .pitch, .yaw, .throttle, .brake, .clutch, .rt]
    /// 按键真正会发的键（与 `WidgetView.tapButton` 的分支一一对应）。
    static let buttons: [WidgetBinding] = [.vjoy1, … , .vjoy16, .gearUp, .gearDown, .fire]
}

extension WidgetKind {
    /// 组件库里「绑定」下拉该给哪些选项。空 = 这个组件不读 `widget.binding`
    /// （方向盘/触摸板/摇杆/苦力帽/姿态球走固定通道；仪表盘只读）。
    var bindingOptions: [WidgetBinding] {
        switch self {
        case .slider: return WidgetBinding.axes
        case .button: return WidgetBinding.buttons
        default:      return []
        }
    }

    /// 绑定被忽略时，说清它到底发什么（给下拉的替身文案用）。
    var fixedBindingNote: String {
        switch self {
        case .wheel:    return "固定发「横滚/转向」"
        case .pad:      return "固定发「视角」"
        case .stick:    return "固定发「横滚 + 俯仰」"
        case .hat:      return "固定发「苦力帽 + 视角」"
        case .attitude: return "只显示本机杆位"
        case .panel:    return "只读显示，不绑定"
        default:        return ""
        }
    }
}
```

> `buttons` 用 `WidgetBinding.allCases` 里非轴项拼，避免以后加键漏一处；
> `axes` 用**显式 7 项**，因为它必须与 `bindAxis` 的 case 同步 —— 用 `filter(isAxis)`
> 会把 `look` 带进来，而 `look` 恰恰是那个「选了等于没选」的值。

### 3.2 弹窗：按类型给选项，换类型把绑定归到第一个（`Views/CockpitView.swift`）

- `LibrarySheet` 增加 `let initialKind: WidgetKind`：
  `@State kind` / `@State binding` 的初值都从它推（`binding = initialKind.bindingOptions.first ?? .roll`）。
- 绑定区块改成三选一：
  1. `kind.isReadOnly`（仪表盘）→ 原只读说明；
  2. `kind.bindingOptions.isEmpty`（固定通道组件）→ 不显示 `Picker`，显示
     「「方向盘」**固定发「横滚/转向」**，这里不用选绑定」；
  3. 否则 → `ForEach(kind.bindingOptions, …)`，`onlyOnVJoy` 的 ⚠️ 段照旧。
- `.onChange(of: kind)`：只要新类型有绑定，就把 `binding` 置为 `bindingOptions.first`
  （换回滑条默认 `roll`、换到按键默认 `vjoy1`）。
- `libraryButton` 把 `kind` 带进弹窗：`showLibrary` 旁加 `@State libraryKind`，
  调 `LibrarySheet(store:mode:initialKind:)`。

### 3.3 文案

| 位置 | 之前 | 之后 |
|---|---|---|
| 组件库入口 | 点「按键」「滑条」都从「滑条」弹 | 点哪个就从哪个开始 |
| 绑定下拉（滑条） | 8 轴 + 20 键全列 | 7 个轴：横滚/转向、俯仰、方向舵、油门、刹车（LT）、离合、右扳机（RT） |
| 绑定下拉（按键） | 同上 | 19 个键：按钮 1–16、升档、降档、开火（vJoy 16） |
| 固定组件（方向盘等） | 给一个不生效的下拉 | 一行说明它固定发什么 |
| 仪表盘 | 只读说明 | 不变 |

---

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT | **不改** |
| 电脑侧 | **无** |
| App 侧 | `Views/Widgets.swift`（`WidgetBinding` / `WidgetKind` 各加只读派生）、`Views/CockpitView.swift`（`libraryButton`、`LibrarySheet`） |
| 画布数据结构 / 存储键 | **一个不动**（`DeckWidget.binding` 字段保留，老布局照常解码） |
| 文档 | 本文件 + `docs/TODO.md` + `docs/README.md`（测试项数） |

**兼容性**：已存在的布局里若正好有「按键 + 轴绑定」这种历史死组件，**本轮不迁移** ——
它仍然照原样加载（字段没变），只是以后在弹窗里不会再选到这种组合；
要改就删掉重加。若以后要清，应另开一条一次性迁移。

---

## 5. 验证方式

- **源码守卫**（`tests/test_deck_bindings.py::TestBindingOptions`）：
  `BindingOptions` 只列 7 个轴、`buttons` 含 16 键 + 升降档 + 开火；
  `WidgetKind.bindingOptions` 只对 `.slider` / `.button` 非空；
  弹窗用 `kind.bindingOptions` 而不是 `WidgetBinding.allCases`；
  `initialKind` 从 `libraryButton` 传进来；`binding` 初值由 `bindingOptions.first` 推。
- 全量 `python3 -m unittest discover -s tests -t .` 全绿。
- `xcodebuild -destination "platform=macOS,variant=Mac Catalyst"` → `BUILD SUCCEEDED`，零警告。
- **Mac Catalyst 截图**：点「按键」弹窗直接是「按键」+「按钮 1」；下拉里没有轴项；
  点「滑条」弹窗是 7 个轴；切到方向盘后下拉消失、出现「固定发…」；
  仪表盘仍是只读说明。

---

## 6. 边界与不做

- **不做历史死组件的自动迁移**：字段没变，加载不受影响；自动改绑定属于行为变更，
  收益（老布局里极少数、且用户自己知道是坏的）小于风险（误改用户自定义）。
- **不给方向盘/触摸板等加「可选绑定」**：它们本来就是固定通道，加可配置性＝新功能，不是本轮。
- **不动动态类型 / 无障碍标签**：独立的 L 轮，见 `docs/TODO.md`。
- **不改 `libraryButton` 里「有默认绑定就直接加」的快捷路径**（方向盘/触摸板等一键加），
  那是刻意的：它们没有可选参数。

---

## 7. 工作量

**S**：`Widgets.swift` 两个 extension（约 30 行）；`CockpitView.swift` 的
`libraryButton` + `LibrarySheet` 结构小改（约 25 行）；测试 1 个类。

---

## 8. 落地记录（已实施）

### 8.1 改动清单

| 文件 | 改动 |
|---|---|
| `Views/Widgets.swift` | `WidgetBinding` 加 `axes` / `buttons` 两个静态清单；`WidgetKind` 加 `bindingOptions`（`.slider`→轴、`.button`→键、其余为空）、`fixedBindingNote`、`defaultBinding`，并加 `Identifiable`（`id = rawValue`，给 `.sheet(item:)` 用） |
| `Views/CockpitView.swift` | `libraryButton` 记住点的是哪个 `kind`：`@State libraryKind: WidgetKind?` + **`.sheet(item: $libraryKind)`**（见 §8.3 的时序坑）；`LibrarySheet` 新增 `init(store:mode:initialKind:)`，`binding` 初值取 `bindingOptions.first`；绑定区块按 `bindingOptions` 三选一（只读 / 固定通道说明 / 下拉）；`.onChange(of: kind)` 把绑定归到该类型第一个 |
| `tests/test_deck_bindings.py` | 新增 `TestBindingOptions`（**9 条**守卫） |
| 文档 | 本文件 + `docs/TODO.md`（把「小坑」移进已完成）+ `docs/README.md`（测试项数） |

### 8.2 机器验证

1. `python3 -m unittest discover -s tests -t .` → **`Ran 208 tests … OK`**（新增 9 条之前是 199）。
2. `xcodebuild … -destination "platform=macOS,variant=Mac Catalyst" build` →
   **`** BUILD SUCCEEDED **`**，`grep -E "error:|warning: [^M]"` 无匹配（零警告）。
3. 源码守卫 `TestBindingOptions` 全绿（见 §5）。

### 8.3 落地时踩到的坑（SwiftUI 时序）

第一版用的是 `@State showLibrary = false` + `.sheet(isPresented: $showLibrary)`，
在同一个 action 里先 `libraryKind = kind` 再 `showLibrary = true`。
源码/测试都对，但**实机点「按键」弹出来的是「滑条」** —— `isPresented` 触发的
sheet 内容闭包读到了更新前的 `libraryKind`。

改成把类型本身当弹窗输入：`WidgetKind: Identifiable` + `.sheet(item: $libraryKind)`，
内容用 `initialKind: kind`。实机复测：点「按键」→ 弹窗类型选中「按键」、绑定「按钮 1」。
（守卫里加了 `assertNotIn("showLibrary", …)`，防止有人改回去。）

### 8.4 未做 / 风险

- **老布局里的历史死组件不迁移**（见 §4、§6）：仍能加载，但用户若在弹窗里改它，
  会先被归到该类第一个。可接受。
- **`WidgetBinding.look` 仍留在枚举里**：方向盘等写死通道内部仍以它作默认 `binding` 占位；
  只是不再作为任何下拉选项出现。删除它要动默认布局与老数据解码，不在本轮。

---

## 9. 实测记录（Mac Catalyst，2026-09-25，逐张截图）

前提与应用方式同 `docs/PalmDeck-v4-discoverability.md` §9（DerivedData 直接 `open`；
先删 `palmdeck_widgets_v10` 回出厂布局）。

| 看哪 | 结果 |
|---|---|
| 组件库点「按键」 | 弹窗里类型直接选中「**按键**」，绑定是「**按钮 1**」（第一版点出来是滑条，改用 `.sheet(item:)` 后修正，见 §8.3） |
| 「按键」的绑定下拉 | 只有 `按钮 1…16`、`升档`、`降档`、`开火（vJoy 16）`；**没有**「油门/俯仰/横滚」 |
| 选「按钮 11」 | 出现 ⚠️「第 11–16 号键只在飞行模式里存在……」；加到画布是**真按键**，按下有回弹 |
| 组件库点「滑条」 | 弹窗类型选中「**滑条**」，绑定是「横滚/转向」 |
| 「滑条」的绑定下拉 | 只有 7 个轴：横滚/转向、俯仰、方向舵、油门、刹车（LT）、离合、右扳机（RT）；**没有**「按钮 N」、**没有**「视角」 |
| 弹窗里把类型切到「方向盘」 | 绑定下拉**消失**，显示「「方向盘」固定发「横滚/转向」，这里不用选绑定」 |
| 弹窗里把类型切到「仪表盘」 | 显示只读说明（与原一致） |
| 加到画布 | 按键标题为「按钮 11」、滑条标题为所选轴名；都是会响应的控件 |
