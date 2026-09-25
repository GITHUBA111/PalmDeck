# 方案：游戏预设（不同游戏的适配）

**状态**：✅ G0–G2 已落地；E1 / E2 已落地；G3 降级为暂不做；G4 待真机验收
**影响范围**：电脑侧（`hotas.py` / `palmdeck_config.py` / `bridge.py`）、
App 侧（`ControllerState.swift` / `Layout.swift` / `SettingsView.swift`）、
协议（**G3 阶段**加一条 WS 文本消息，热路径 22B 包不动）、文档
**一句话**：把「一份全局轴设置」改成「一套可命名、可一键切换的游戏预设」——
预设 = 电脑侧轴映射表 + App 侧手感参数 + 布局（含按钮标签），
换游戏时手动切一次，**不按模式自动切**。

**目标游戏（定稿依据）**：**WARDOGS**（heli）+ **欧洲卡车模拟 / ETS2**（drive）。
两者恰好各占设计的一半——WARDOGS 走 vJoy 轴表，ETS2 走 Xbox 且**完全不吃轴表**（§2.7）。
⇒ **G3（协议 + 电脑侧轴表）对这两个游戏都不需要**，已降级为「暂不做」（§7）。

---

## 1. 目标

### 真实问题：App 现在只有「设备形态」，没有「游戏」这一维

`CockpitMode` 的三个值回答的是「我手里拿的是什么东西」：

| 模式 | 手里是什么 | file:line |
|---|---|---|
| `heli` | 通用模块：仪表盘（只读）+ 周期杆 / 总距 / 脚舵 / 视角 | `Views/Layout.swift` `defaultHeli()` |
| `drive` | 通用模块：方向盘 / 三踏板 / 视角 | `Views/Layout.swift` `defaultDrive()` |
| `gamepad` | 通用模块：双摇杆 / ABXY / 扳机轴 | `Views/Layout.swift` `defaultGamepad()` |

> E2 续起引擎里已无固定皮肤（`FlightDeck.swift` / `DriveDeck.swift` / `GamepadDeck.swift` 已删），
> 三个模式共用一块通用组件画布；上表给出的是各模式的默认模块集。

但**同一个模式下的不同游戏，要求完全相反**。举一个真实冲突：

- **Elite Dangerous** 的社区标准绑定是 `Z = 偏航`（扭杆），油门走单独一根轴。
- **DCS World / MSFS / X-Plane** 的常规绑定是 `Z = 油门`，偏航走 `Rz`。
- **WARDOGS**（本项目现有默认）也是 `Z = 油门`。

这两个游戏都用 `heli` 模式、都该用同一套机身皮肤，但**必须用不同的轴映射**。
而现在 App 里没有任何地方能表达这件事，用户只能：

1. 去电脑控制台开 `web/host.html` 下拉框切 `axis_profile`（`web/host.html:377`），**或者**
2. 去命令行加 `--axis-profile fbw`（`bridge.py:1120`）。

而且切完还得手动去设置页改反转/死区，因为**手感参数也是全局一份**。

### 不做的代价

- **换游戏 = 一套手工流程**：开电脑浏览器改轴预设 → 回手机改反转 → 回手机改死区 → 摆布局。
  任何一个漏了，游戏里就是「舵在动油门」这种故障，而且**用户第一反应是本项目坏了**。
- **手感参数共用是实打实的 bug**：`dz` 只有一个值（`ControllerState.swift:76`），
  飞机要 0.06 压住抖动、赛车要 ≈0 才有线性转向，两者互相污染。
  这个问题**与游戏无关、现在就是错的**，不修只是因为没人同时玩两种模式。
- 反转（`invX/invY/invYaw/invColl`，`ControllerState.swift:79–89`）全局共用 ⇒
  换游戏必须回设置页逐个点，且**极易忘记自己上次改过**。

### 目标（可验证）

1. 从 App 上**两次点击**完成「换游戏」：选预设 → 生效。
2. 预设切换后，电脑侧轴映射表、App 侧反转/死区/灵敏度、布局与按钮标签**同时**到位。
3. 飞机与开车**各自独立**保存死区/灵敏度/反转（不修不改第 2 条也会被卡住）。
4. 切换预设**不重建虚拟设备**，不打断正在运行的游戏。

---

## 2. 现状与证据

### 2.1 电脑侧：轴映射表硬编码两张，且是 `if` 分支

`hotas.py:22 remap_vjoy()` —— 唯一实现，只有两个分支：

```python
def remap_vjoy(profile, roll, pitch, throttle, yaw, left_t, look_x, look_y) -> dict:
    if profile == "fbw":            # hotas.py:33
        return {"x": roll, "y": -pitch, "z": yaw, "rz": 0.0,
                "sl0": throttle * 2 - 1, "rx": look_x, "ry": -look_y}   # :34–42
    return {"x": roll, "y": -pitch, "z": throttle * 2 - 1, "rz": yaw,
            "sl0": left_t * 2 - 1, "rx": look_x, "ry": -look_y}          # :43–51
```

- 未知预设静默回落 `hotas`（`hotas.py:32` 文档字符串 + `:211` 二次兜底）。
- 加第三个游戏 = 改 Python 源码 + 重新打包 exe。**这不是配置，是代码。**
- 枚举被钉死在两处：`palmdeck_config.py:36` `"axis_profile": ("hotas", "fbw")`、
  `bridge.py:1120` argparse `choices=("hotas","fbw")`。三处必须同步改。

### 2.2 电脑侧：vJoy 只有 7 根轴、16 个按钮，已全部用满

`hotas.py:108 _autoconfig_vjoy()` 用固定参数建设备：

```
vJoyConfig.exe 1 -f -a X Y Z Rx Ry Rz Sl0 -b 16 -p 1
```

- 7 根轴：`X Y Z Rx Ry Rz Sl0`。`remap_vjoy` 的返回值**正好用满 7 根**。
- 16 个按钮：`hotas.py:304 VJOY_BTN` 最大 `"b16": 16`（`:321`）；
  `hotas.py:386 release_all_buttons` 的 `range(1, 17)` 印证。
- `-f` = force，重建设备会**打断正在运行的游戏**。
  ⇒ **靠「加轴」适配游戏的路是堵死的**，只能重排 7 根轴的语义。

### 2.3 App 侧：手感参数是全局单例

`ControllerState.swift:6–13` 的 `PKey` —— **没有任何一个键带模式后缀**：

| 键 | 默认 | 行 |
|---|---|---|
| `palmdeck_sens_x` / `palmdeck_sens_y` | 1.0 | `:7–8` |
| `palmdeck_dz` | 0.06 | `:9` |
| `palmdeck_inv_x` / `_y` / `_yaw` / `_coll` | false | `:10–13` |

设置页的滑条直接绑这几个（`SettingsView.swift:589–591`），
曲线预览也读同一份（`SettingsView.swift` 的 `AxisResponseCurve`）。

**方向舵死区是例外**：`ControllerState.yawDeadzone = 0.08` 是常量
（刻意不跟 `dz` 走，因为自回中轴死区放大会转不动尾桨）。

### 2.4 已经能按游戏变的部分：布局 + 按钮标签

布局命名快照已落地，**P1.5 后统一叫「预设」**（原「布局模板」这个词已从 UI 与代码里删干净，
见 `docs/PalmDeck-v4-unified-presets.md`）：
每个模式的画布可整表存/取，而按钮的**显示名是每个组件自己的字段**
（`DeckWidget.label`，`Views/Widgets.swift:67`），
且 `Widgets.swift:38–47` 已有「开火/升档/降档」这类语义名。

⇒ **「按钮叫什么」这件事已经能做到按游戏不同了**，只是没有被组织进「预设」。
这是好消息：G2 阶段可以几乎零成本复用它。

### 2.5 协议：新增 WS 消息类型是双向安全的

`bridge.py:766` 的分派是一条 `if/elif` 链，**没有 else**：

```python
kind = msg.get("type")
if kind == "axes": ...        # bridge.py:767
elif kind == "cmd": ...       # :769
elif kind == "btn": ...       # :771
elif kind == "mode": ...      # :773
elif kind == "layouts_get": ...   # :775
elif kind == "layouts_put": ...   # :781
elif kind == "ping": ...      # :791
# 认不出的 type：静默丢弃
```

- **新 App → 老电脑**：老电脑静默忽略 ⇒ 不会崩，但也没生效 ⇒
  App 必须靠 `caps` 判断能不能显示这个开关。
- **老 App → 新电脑**：老 App 根本不发 ⇒ 天然兼容。
- `hello.caps` 已有先例：`bridge.py:749` `caps: ["failsafe","profile","allowlist","layouts"]`
  （另见 `bridge.py:315` 的短版）。

### 2.7 两个真实游戏的取证（定稿依据）

**模式 → 实际驱动的虚拟设备**（`bridge.py:422 live_for_mode`）：

| 模式 | live targets | 代码 |
|---|---|---|
| `heli` | `{vjoy}`（有 vJoy 时） | `bridge.py:426` |
| `drive` | **`{vgamepad}`** | `bridge.py:432` |
| `gamepad` | `set()`（两只都 park） | `bridge.py:438` |

**这直接决定了两个游戏各走哪条路**：

| 游戏 | 模式 | 实际设备 | 吃 `axis_profile` 吗 |
|---|---|---|---|
| **WARDOGS** | `heli` | vJoy | **吃**（`hotas`） |
| **欧洲卡车模拟** | `drive` | **Xbox 360（vgamepad）** | **不吃**（`docs/PalmDeck-v3-feature-design.md:1044`：Remap 只作用于 vJoy） |

#### WARDOGS：现状即最优，一行都不用改

`hotas` 预设 + `docs/PalmDeck-v3-feature-design.md` §7 的绑定说明已经就是为它调好的：

```
vJoy (heli live): X=roll  Y=-pitch  Z=throttle*2-1  Rz=yaw  Sl0=lt*2-1  Rx=look_x  Ry=-look_y
                  rt>0.5 → button 16（开火）
```

⇒ **WARDOGS 的「预设」= 现在跑的东西**。这正是我要证明的那一点：
航空那一半不需要改，需要的是「把它变成一个能被保存和还原的东西」。

#### ETS2：轴表与它无关，全部诉求都在 App 侧

`drive` 走 vgamepad，`remap_vjoy` 根本不参与（`docs/...:1044`）。
它实际收到的是 `hotas.py:236–240` 的 Xbox 写入：

```
Xbox (drive): LS=(roll, -pitch)   RS=(look_x or yaw, -look_y)   LT=lt   RT=rt
```

代入 App 的 drive 真值表（`Model/AxisMap.swift:81` `case .drive`：`pitch: clutch / throttle: throttle / rt: throttle / lt: max(lt,0) / yaw: 0`）：

| 物理控制 | 送到 Xbox | 对应卡车功能 | 判断 |
|---|---|---|---|
| 方向盘 `roll` | LS X | 转向 | ✓ 直连 |
| **离合踏板** | **LS Y（`-clutch`）** | — | ⚠️ **ETS2 默认把 LS Y 当油门/刹车**（见 §3.6） |
| 油门踏板 | RT | 加速 | ✓ |
| 刹车踏板 | LT | 刹车 | ✓ |
| 视角板 `look` | RS | 镜头 | ✓ |
| 档杆升 / 降 | b6 / b5 → RB / LB | 序列式变速箱 | ✓（但被别的按键撞车，见 §3.7） |
| 转灯/危险灯/喇叭/手刹/雨刷/大灯/远光 | b1,b2,b3,b4,b7,b8,b9,b10 → A,B,X,Y,BACK,START,L3,R3 | 对应功能 | ⚠️ 映射合理但**需要游戏内自行绑** |

**结论**：ETS2 的适配清单里**没有一项需要动协议或电脑侧**，
全部落在「手感参数 + 布局 + 标签」——正是 G1/G2 的范围。

### 2.6 与 v3 冻结决定的关系（重要，别踩）

`docs/PalmDeck-v3-feature-design.md:1046` 写着：

> **明确禁止**：按模式自动在 hotas/fbw 间切换；禁止「飞机用 fbw、开车用 hotas」。

**本方案不违反它，且这正是它要防的东西。**

v3 那条禁令防的是**自动**切换（模式一变就换表）——
因为切表会让「游戏内已存好的绑定」突然指向别的物理控制，
玩家在飞行途中模式一变（比如切到步兵再切回来）就会撞上。

本方案的切换是**用户显式动作**，语义是「我现在换了一个游戏」。
游戏内绑定是**每个游戏各存一份**的，所以：

> 预设 A 匹配游戏 A 的绑定，预设 B 匹配游戏 B 的绑定；
> 玩 A 时选 A、玩 B 时选 B，两边的绑定**都不会失效**。

关键事实（也是能给用户的安全承诺）：

> 切预设**只改「App 的哪个控件写到 vJoy 的哪根轴」，不改 vJoy 的设备身份、不改轴编号**。
> 所以 `remap` 是热生效的（`docs/PalmDeck-v3-feature-design.md:627` 已确认「不重建 vJoy」）。

**唯一必须做对的事**：在 UI 上把「切预设」讲清楚是「我换游戏了」，
而不是「调个参数试试」——否则用户会以为调了没副作用。

---

## 3. 方案

### 3.1 三层边界（先定清楚，再谈实现）

「游戏预设」在物理上**必须分居两侧**，因为两半的归属是不可移动的：

| 层 | 内容 | 必须在哪一侧 | 为什么 |
|---|---|---|---|
| **电脑侧轴表** | 7 根 vJoy 轴各自取哪个源、怎么变换 | **电脑** | `remap_vjoy` 在 HID 写入路径上；22B 热路径的字段名（roll/pitch/…）是**冻的**（`docs/PalmDeck-v3-feature-design.md:1048`），不能塞 profile |
| **App 侧手感** | 反转 / 死区 / 灵敏度 | **App** | 整形发生在发送前（`ControllerState.tickSmoothing`）；电脑只收已整形的值 |
| **App 侧布局** | 组件位置、大小、按钮标签 | **App** | `palmdeck_widgets_v10` 是本地键；`layouts.json` 只管自定义画布 |

⇒ **预设名是唯一的关联键**。两侧各存自己的那一半，用同一个名字对齐。

### 3.2 电脑侧：把 `remap_vjoy` 从代码改成声明式表

**不用 `eval`、不用表达式字符串**（那等于把配置文件变成远程代码执行面）。
用「源 + 变换」两段枚举，覆盖现有两张表且不引入图灵完备：

```python
# 可用源：8 个，正是热路径字段名 + 零（hotas.py:22 形参）
SOURCES = ("roll", "pitch", "yaw", "throttle", "lt", "look_x", "look_y", "zero")
# 可用变换：4 个，语义自明
#   same     v
#   neg      -v
#   uni      2v-1     （0..1 的单极量 → -1..1，油门/刹车用）
#   uni_neg  1-2v
AXIS_TABLE_KEYS = ("x", "y", "z", "rx", "ry", "rz", "sl0")
```

现有两张表原样表达得出来（**这是"不破坏兼容"的证明**，不是巧合）：

| 轴 | `hotas` | `fbw` |
|---|---|---|
| `x` | roll / same | roll / same |
| `y` | pitch / neg | pitch / neg |
| `z` | **throttle / uni** | **yaw / same** |
| `rz` | **yaw / same** | **zero** |
| `sl0` | **lt / uni** | **throttle / uni** |
| `rx` | look_x / same | look_x / same |
| `ry` | look_y / neg | look_y / neg |

新增第三张表就变成**配置**：在 `palmdeck_config.py` 加一个 `axes_presets` 字典，
`remap_vjoy` 缩成「查表 + 套变换」约 15 行。

**兼容性**：`axis_profile` 键保留原义（= 当前生效的预设名），
`hotas` / `fbw` 作为内置预设名**永不删除**（老用户 `config.json` 里写着的值继续work）。

### 3.3 App 侧：手感参数按模式分离（**已实施：G1**）

键名加模式后缀，启动时一次性迁移：

```
palmdeck_sens_x            →  palmdeck_sens_x.heli / .drive / .gamepad
palmdeck_dz                →  palmdeck_dz.<mode>
palmdeck_inv_x/_y/_yaw/_coll →  palmdeck_inv_*.<mode>
```

迁移规则：**读不到带后缀的键时，回落读旧键**（老用户升级后参数不丢），
把旧值写到**三个模式**各自的键上，然后删旧键（已有新键的不覆盖）。
`ControllerState.yawDeadzone` 常量不动。

实现：`Model/ShapingKeys.swift`（纯逻辑）+ `ControllerState(shapingStore:)`
（存储可注入，测试不碰真实偏好设置）。

> 这一条**不依赖预设也能单独成立**，且它是「飞机 0.06 死区污染赛车」的直接修复。
> 所以它排在 G1，可以独立验收。
> 完整说明见 `docs/PalmDeck-v4-app-interaction.md` §12。

### 3.4 App 侧：预设 = 布局 + 手感 + 轴表名（G2，已落地）

复用已落地的布局快照机制（P1.5 后二者合并，统一叫「预设」），把它扩成整机预设：

```swift
struct GameProfile: Codable, Equatable {  // Model/GameProfile.swift（纯类型）
    var name: String                    // 预设名，如「WARDOGS」
    var mode: CockpitMode               // 用哪套机身皮肤
    var axesPreset: String              // 电脑侧轴表名，如 "hotas"
    var sensX, sensY, dz: Double
    var invX, invY, invYaw, invColl: Bool
    var wheelMaxDeg: Double?            // nil = 不改（ETS2 才需要 900）
    var wheelReturnSpeed: Double?       // nil = 不改
    var hasShaping: Bool                // 见下「两种形态」；decode 默认 true（老 v1 JSON 全是整机）
    var widgetsJSON: Data?              // 布局（编码后的 [DeckWidget]）；nil = 预设不带布局
}
```

> **实现与原设计的差异（有意）**：布局存 **编码后的 `Data`** 而不是 `[DeckWidget]`。
> `DeckWidget` 定义在 `Widgets.swift`（import SwiftUI），直接放数组会把整个视图层
> 拖进 `swiftc` 纯逻辑测试的编译单元；`GameProfile` 保持只 import Foundation。
> 存取走 `widgets()` / `setWidgets(_:)`，布局解码在 `LayoutStore.applyProfile` 里做。
> 又：`GameProfileApplier` 不直接吃 `ControllerState`，而是吃一个 `ShapingTarget` 协议
> （`ControllerState` 在 `ControllerState.swift` 里 conformity）—— 同样是为了测试可注入替身。

- 存储：`palmdeck_game_profiles_v2`（本地，**不进 `layouts.json`、不进配置导出包**）；
  生效名另存 `palmdeck_active_game_profile`（仅 UI 标记）。
  旧键 `palmdeck_game_profiles_v1` / `palmdeck_layout_templates_v1` 只在 v2 不存在时被合并一次，
  之后**只读不写**（`GameProfileMigration`，见下）。
- 切换动作 = 一次性写入，**顺序固定**（`GameProfileApplier.apply`）：
  先切模式（`setMode` → `applyMode` 读本模式手感）→ 再写手感参数（键跟着新模式走）
  → 最后布局整表替换。写反的症状是“切了预设但手感没变”。
- 切换后 **`layout.revision += 1`**（`applyProfile` 沿用 `applyTemplate` 的语义，
  因为这是整表替换，`WidgetCanvas` 靠 `.id(revision)` 强制重绘）；同时压撤销槽。
- **`widgetsJSON == nil` 时不动用户布局**（实测坑，见 `tests/test_deck_bindings.py` 的
  `TestProfileDoesNotBlankTheCanvas`）。`nil` 的含义是「这个预设不带布局」，
  不是「把画布清空」——内置预设（WARDOGS / ETS2）都是 nil，它们只是**手感快照**。
  空数组 / 坏 JSON 也一律当成“不带”。唯一例外：该模式**当前就是空表**
  （用户清空过，或踩过这个坑）→ 铺回该模式默认模块，绝不留一块白板。
- 上限 **24**（原预设 12 + 模板 12，合并后不再按类型各分一半）；内置不可删不可改名。

**UI 位置**：设置页新增分类「游戏预设」（放在「布局」上方），
一行一个预设，显示 `名字 · 模式 · 轴表名 · 死区` + 第二行说明 `仅手感，不动布局` / `含布局`，
选中行标「当前」。顶部只读显示**电脑实际**的 `axis_profile`（来自 `hello`，`bridge.py:744`）；
选中预设的 `axesPreset` 与它不一致时给黄标提示。
切换后的反馈文案会把“布局到底动没动”写出来（`已切换到「X」· 布局保持不动`），
因为旧版“切了预设面板变白板”很难让人分清是 bug 还是设计。

**测试**：`tests/ios/GameProfileTests.swift` + `tests/test_ios_profiles.py`
（内置定义 / 编解码往返 / 缺字段回落 / 存储增删改与上限 / **应用顺序** / pbxproj 登记守卫）。

#### 3.4.1 P1.5 落地：一个概念，两种形态（整机 / 布局）

原来「游戏预设」（整机）与「布局模板」（只装组件）是两套类型、两个键、两个 UI 分类，
用户要在两处找「我上次存的那套」。现在合并成一种类型 + 一个开关：

- **`hasShaping: Bool`** 决定形态。`true` = **整机**（模式 + 手感 + 有布局就换）；
  `false` = **布局**（只装组件、不碰手感，模式只是归属）。
  同一个 `GameProfile`、同一个 store（不引入子类，也不搞两个 store）。
- **decode 默认 `true`**：老 v1 JSON 里没有这个字段，解出来全是「整机」——正是它们本来的语义。
- **`GameProfileApplier.apply` 里所有手感写入都包在 `if p.hasShaping` 内**：
  一个「布局」预设点下去只换面板，死区/灵敏度/反转一个都不碰
  （`GameProfileTests.testApplyLayoutOnlyDoesNotTouchShaping` 钉死）。
- **「布局」预设只在自己那个模式下出现**（`$0.hasShaping || $0.mode == s.mode`）：
  它存的就是那套面板，拿到别的模式里既没有对等的轴也没有对等的组件。
- **内置「默认」不是类型，是列表里一行只读的「布局」预设**：点了走
  `LayoutStore.applyDefault(mode:)`（直接取 `defaults(mode:)`，不入库、不占 24 个名额）。
- **空预设两级拦截**：`save` 兵底（`既没手感也没布局` 直接返回错误文案）
  + UI 把两个存按钮置灰。
- **迁移幂等且旧键只读**：只有 v2 不存在时才 `GameProfileMigration.merge(profilesV1:templatesV1:)`；
  否则用户删掉的预设下次启动会复活。重名加「·布局」后缀（内置名也算重名）。

细节、验证方式与实测记录：`docs/PalmDeck-v4-unified-presets.md`。

### 3.5 协议：一条 WS 文本消息（G3）

**只在 App 需要改电脑侧轴表时才加**，报文：

```json
// App → 电脑
{"type": "profile", "name": "dcs_heli"}

// 电脑 → App（回执，也用于校验）
{"type": "profile", "ok": true, "name": "dcs_heli", "known": ["hotas","fbw","dcs_heli"]}
// 未知名字：ok:false，不改动任何状态
{"type": "profile", "ok": false, "reason": "unknown", "known": [...]}
```

- `hello.caps` 追加 `"profile_select"`（`bridge.py:749`）。
- App 只有在 `caps` 含 `profile_select` 时才允许从手机切轴表；
  否则该行变成只读提示 + 文案「请到电脑控制台切换」（并给出手势/按钮跳转说明）。
  **这正是 §2.5 的降级路径，必须有，不能省。**
- 生效沿用现有热路径：`bridge.py:916–918` 那套（改 `HUB.axis_profile` → 写 `status` → 广播）。  不重建 vJoy（`docs/PalmDeck-v3-feature-design.md:627`）。
- **每模式自动 park 逻辑不受影响**：`bridge.py:609` 用的是 `self.axis_profile`，
  换一个值即可。

### 3.6 两个游戏的预设定义（G4）

#### 预设一：「WARDOGS」（现状原样固化）

| 字段 | 值 | 理由 |
|---|---|---|
| 模式 | `heli` | `bridge.py:426` |
| 轴表 | `hotas` | 已是默认，`docs/...:1036` |
| 死区 `dz` | 0.06（默认） | 现有值 |
| 灵敏度 | 1.0 / 1.0 | 现有值 |
| 反转 | 全 false | 总距不要开 self-centering（`docs/.../§7`） |
| 布局 | 不绑定（`widgetsJSON = nil`） | 走 `defaultHeli()` 通用模块（仪表盘（只读）/周期杆/总距/脚舵/视角，**只有轴**）；预设不覆盖用户布局 |

**这个预设的价值不是「改了参数」，而是「它是一个可保存、可还原、不会被下一个游戏的调整污染的快照」。**

#### 预设二：「欧洲卡车模拟」（新）

| 字段 | 值 | 理由 |
|---|---|---|
| 模式 | `drive` | `bridge.py:432` |
| 轴表 | `hotas`（**无意义，仅供参考**） | ETS2 走 vgamepad，不吃轴表 |
| **死区 `dz`** | **0** | **关键**。ETS2 自带 steering deadzone/sensitivity/non-linearity 三项设置，App 再加死区 = **双重死区**，中心区会变成一段死行程 |
| **灵敏度** | **1.0 / 1.0（线性）** | 同上：ETS2 会在自己那侧再压一条曲线。两边都压 = 转向非线性叠加，高速微调会变得不可控 |
| **反转 `invX`** | **视游戏而定** | ETS2 有 Steering Axis 反向开关，两边只能开一个 |
| **方向盘转角 `wheelMaxDeg`** | **900**（默认 540） | 默认 540 是 `ControllerState.swift:97` 定的；真实卡车/ETS2 的 lock-to-lock 是 900°，触发点不对齐时「打满」感觉会怪 |
| 回正速度 `wheelReturnSpeed` | 720（默认） | 卡车方向盘不应快速回正，可再调低 |
| 布局 | **不绑定**（`widgetsJSON = nil`） | E2 起开车默认走 `defaultDrive()` 通用模块（方向盘/三踏板/视角，**只有轴**）；预设不强行覆盖用户布局 |
| 按钮标签 | 用户自定（默认不内置按键） | App 不再硬编码「降档」这类语义（见 §3.9 / E2） |

ETS2 里建议的键位对应（都是 Xbox 手柄侧）：

| 皮肤上的键 | 发出去的键 | ETS2 里绑什么 |
|---|---|---|
| 左转 / 右转 | b1 / b2 | 左转向灯 / 右转向灯 |
| 危险灯 | b3 | 危险警示灯 |
| 喇叭 | b4 | 喇叭 |
| 手刹 | b7 | 驻车制动 |
| 雨刷 | b8 | 雨刮 |
| 大灯 | b9 | 近光/大灯 |
| 远光 | b10 | 远光闪 |
| 视角 ↑ / 左视 ← / 右视 → | D-pad 上/左/右 | 车内视角上/左/右看（**按住才看，松手回正**） |
| 档杆上推 / 下拉 | b6 = RB / b5 = LB | Shift Up / Shift Down |

> 视角走 D-pad 是修复后（E1 第 1 条）的行为；修复前「视角键」占的是 LB，
> 和降档撞在一起。

#### ETS2 的两条必须在游戏内确认的事

**1. LS Y 的归属（最可能出问题的地方）**
PalmDeck 的 drive 把**离合踏板送到 LS Y**（§2.7）。
如果 ETS2 保留默认的「LS Y = 油门/刹车」（手柄默认预设），
那么**踩离合会让车加速或刹车**。

两个修法，选一个：
- (a) ETS2 里把 `Clutch` 绑到 LS Y（左摇杆 Y），油门/刹车只用 RT/LT—— **推荐**，
  这样车不动时踩离合才真的分离。
- (b) 完全不用离合踏板（不买带离合的变速箱）。PalmDeck 侧不动。

**2. 序列式变速箱**
`DriveDeck` 的档杆是「R / N / 1–6」八位置，但事实上发的是
**升档 / 降档**两个脉冲（`DriveDeck.swift` `shift()` → `pulse(5/4)` → b6/b5 → RB/LB）。
所以 ETS2 里必须把变速箱设为 **Sequential（序列式）**，把 `Shift Up` 绑到 RB、`Shift Down` 绑到 LB。
ETS2 的 H-pattern（H 档）**本方案不支持**——那需要 6 个独立按钮 + 离合搭配，
而且档杆 UI 的「八位置」会变成谎话。

> **E2 起 App 不再规定「哪个键是降档」**：默认开车布局只有轴、没有按键，
> 你在编辑态自己加两个按键、在 ETS2 里绑成 Shift Up / Shift Down 就行，想用哪两个键都行。
> 这样就避开了「降档键与欧卡2 默认的 LB/RB 看镜头撞车」这个报障（§3.9）。
> 下表的 b5/b6 → RB/LB 是**旧版固定卡车皮肤**的行为，仅作参考。

> 这两条都是「按常规」写的，**不是在本项目里验证过的**（我没有 ETS2 环境）。
> 请你在游戏里对一遍，有出入告诉我改。

### 3.7 取证时顺带发现的 App 侧缺陷（E1，实际是 5 条不是 3 条）

这几条都不是「游戏适配」，是**现在就错的**——皮肤上写的是一个键，实际发出去的是另一个。
ETS2 恰好会踩到第 1 条。

#### (1) drive 模式：视角键与降档撞同一个按钮（b5 = LB）

`DriveDeck.swift` 视角键用 `.vjoy5` ⇒ `vjoyIndex = 4` ⇒ 发 **b5**；
`DriveDeck.swift` `shift(-1)` ⇒ `pulse(4)` ⇒ 也发 **b5**。
PC 侧两者都映射到 `X360["b5"] = LEFT_SHOULDER = LB`（`hotas.py:293`）。

⇒ **按降档会同时触发镜头。**
卡车里降档是高频操作（上坡/减速），而镜头跳一下是直接干扰驾驶的。

**修法**：视角不走按钮位，改走 **十字键**（`hat`）。

理由：22 字节包里**本来就有 `hat` 字段**（`bridge.py:224` `PKT = struct.Struct("<2sBB8hH")`，
偏移 3），PC 侧 `HAT_NAME = {0:"hat_up",1:"hat_right",2:"hat_down",3:"hat_left"}`（`bridge.py:227`）
→ `tap_button(...)` → `X360["hat_left"] = DPAD_LEFT`（`hotas.py:301`）。**全程零协议改动、零电脑侧改动。**

而且十字键本来就是「看」的键位：开车时按住左/右看一眼后视镜，比一个 toggle 的「视角键」更接近真车。
换档留在 LB/RB：那是**两个独立的键位 bit**，可以重叠脉冲；
`hat` 是**单值**，快速上下拨档时先发的脉冲会被后发的覆盖 —— 手感上不能接受。

落地：`DriveDeck.swift` 新增 `DeckHoldButton`（按住生效 / 松手复位，`DeckButton` 是 toggle 不合适），
按键簇变成 8 个 toggle + 3 个 D-pad（视角 ↑ / 左视 ← / 右视 →）。

#### (2) 手柄模式的 b11–b16 在 Xbox 侧是死键

`hotas.py X360` 字典到 `b10` 为止，**没有 `b11`–`b16`**；
但 `Widgets.swift:32` 的组件库提供 `vjoy11`–`vjoy16` 可选。
在 flight（vJoy）下它们是好的（`VJOY_BTN`），在 drive/gamepad（Xbox）下按下去**没有任何反应**。

**修法**：留着能用（vJoy 侧确实有人用），但不让用户闷声踩坑——
`WidgetBinding.onlyOnVJoy`（阈值由 `hotas.py` 实际键数推出，不是写死的魔法数），
`LibrarySheet` 在选中时把 `仅飞行` 写进标题并给一条黄字警告。

#### (3) `defaultGamepad()` 的 LB/RB 标签反了

`Layout.swift` 把 `.gearUp` 标成 `"LB"`、`.gearDown` 标成 `"RB"`。
但 `Widgets.swift:157` `gearUp → pulse(5) → b6 → X360["b6"] = RIGHT_SHOULDER`（`hotas.py:294`），
`gearDown → pulse(4) → b5 → LEFT_SHOULDER`。**标签与真实按键正好相反。**

（同一张表里 `.vjoy7` 标 `"视图"`、`.vjoy8` 标 `"菜单"`，而 `b7`/`b8` 是 BACK/START，
这个偏离是合理的，不算缺陷。）

#### (4) `GamepadDeck` 把 b9/b10 标成了 LT/RT —— 实际是 L3/R3

`GamepadDeck.swift` 左右两列顶上标 `"LT"`/`"RT"`，绑的是 `.vjoy9`/`.vjoy10`。
但 `X360["b9"] = LEFT_THUMB`、`X360["b10"] = RIGHT_THUMB`（`hotas.py:296-297`）
—— **摇杆按下**，不是扳机。Xbox 的 LT/RT 是**模拟轴**（`hotas.py:240` `left_trigger_float` / `right_trigger_float`），
根本不在按键表里。

⇒ 一个 Xbox 皮肤，写的字和按下去的效果是两回事。**改成 `L3`/`R3`。**

#### (5) `defaultGamepad()` 的 RT 滑条绑到了一个 Xbox 不读的轴

同一张默认布局里 `.make(.slider, .throttle, ... label: "RT")`。
但 Xbox 写轴路径（`hotas.py:236-240`）是
`LS=(roll,-pitch) RS=(look_x or yaw,-look_y) LT=lt RT=rt` —— **`throttle` 根本没用上**
（只在 heli 降级时才被当作 RT，见 `hotas.py:216` `xbox_rt = throttle if heli_degraded else right_t`）。

⇒ 手柄模式下拖「RT」滑条没有任何反应。而且 `WidgetBinding` 里**压根没有 `rt` 这个轴**，
想绑也绑不了。

**修法**：`WidgetBinding` 增加 `case rt`（`$s.rt`，单极滑条），默认布局的 RT 改用 `.rt`。
轴字段 `rt` 本来就在包里（偏移 18），**不加协议、不加电脑侧代码**。

#### 顺手修掉的编译警告（不算缺陷）

`CockpitView.swift` 的 `ctrl.onLayouts = { [weak layout] raw in ... }` 报
`'weak' ownership of capture 'layout' differs from implicitly-captured strong reference`
—— 同一个闭包里 `discovery` / `showSettings` 把 `self` 强引用住了。
改成先落局部变量再弱引用。

#### E1 的回归测试

这些都是**源码级对应关系**，XCTest 表达不了（要编译整个 SwiftUI 视图层），
所以 `tests/test_deck_bindings.py` 直接读 Swift 源码 + 读 `hotas.py` 的 `X360` 表对账：

- 手柄皮肤每个标签 → `X360[bN]` 必须等于标准 Xbox 键名；
- 同一皮肤内不能有两个标签撞同一个键；
- 开车模式「按键簇 toggle 的键号」与「换档 pulse 的键号」必须不相交；
- 开车模式所有键号必须 ≤ 10（Xbox 只有 b1–b10）。

再加 `tests/test_hotas_hat.py`（hat → Xbox `DPAD_*`）和 `tests/test_pack_state.py`
（22 字节包里的 `hat` 端到端派发/回中）两条运行期验证。

> 这五条**单独成 commit（E1）**，不混进预设功能——
> 它们是修复，与「游戏预设」这个新功能无因果关系，必须能单独回滚。

### 3.8 Capacitor 残骸（G0）—— 比预想的大，而且是个阻塞项

本来以为只是「删 84 KB 死文件」，实际查下来是**整个 Capacitor 壳子只删了一半**。

| 东西 | 体积 | 证据 |
|---|---|---|
| `App/App/public/` | **84 KB**（打进 App 包） | pbxproj 作为 folder 资源；内容是 `cap sync` 从 `webDir: "../web"` 拷来的网页座舱 |
| `App/App/PalmDeckUdpPlugin.swift` | 118 行 | 全仓库**唯一** `import Capacitor` 的地方 |
| `App/App/Base.lproj/Main.storyboard` | 1 KB | 里面是 **`customClass="CAPBridgeViewController" customModule="Capacitor"`** |
| `App/App/SceneDelegate.swift` | 6 行 | 空占位（“保留占位以免工程引用报错”） |
| `App/App/capacitor.config.json` / `config.xml` | 小 | `cap sync` 生成物，pbxproj 当资源拷进包 |

**为什么这些能活到现在**：它们都没有 `UIMainStoryboardFile` 引用，
所以只是「打进包的死资源」，跑起来看不出问题。

#### 真正的阻塞项：干净克隆根本构建不了

```
Podfile:12   pod 'Capacitor', :path => '../../node_modules/@capacitor/ios'
Podfile:13   pod 'CapacitorCordova', :path => '../../node_modules/@capacitor/ios'
.gitignore:10   mobile/node_modules/
```

CocoaPods 用的是**本地路径 pod**，指向 `mobile/node_modules/@capacitor/ios`；
而 `mobile/node_modules/` 是 gitignored 的。
⇒ **新克隆的仓库里 `pod install` 必定失败**（本地能构建只因为
`mobile/node_modules/` 和 `Pods/` 这两份未入库的东西还在）。

而且 `project.pbxproj` 是**完整接入** CocoaPods 的：
`Pods_App.framework`、`baseConfigurationReference = Pods-App.debug.xcconfig`、
`[CP] Check Pods Manifest.lock` / `[CP] Embed Pods Frameworks` 两个构建阶段。
所以不能只删 Podfile —— 会把工程拆坏。

#### 拆成两个 commit

| | 内容 | 验证 |
|---|---|---|
| **G0a** | 删上表 5 个残骸 + pbxproj 里对应的 24 行引用 + 1 个 VariantGroup 块；清掉 iOS `.gitignore` 的 Capacitor 规则。**Pods 先不动** | 模拟器构建 + 启动截图 + 新增 3 条防腐测试 |
| **G0b** | 摘掉 CocoaPods：删 `Podfile`/`Podfile.lock`/`App.xcworkspace/`/`Pods/`，摘 pbxproj 的 framework/xcconfig/两个 CP 阶段，构建命令由 `-workspace` 改 `-project`（`deploy_wifi.sh:124`、`mac.sh:14,19,24`） | 构建 + 真机安装 |

分成两步是因为 G0b 会改构建方式（`-workspace` → `-project`），
万一 pbxproj 手术出错，G0a 已经是一个能独立回滚的干净状态。

建议单独一个 commit 删掉（**不混进本方案**）。

### 3.9 通用模块化（E2）：App 不再替游戏拍板按钮语义

**用户报的 bug**：欧卡2 里 **4→3 降档会亮“视角键”**。

**排查结论（复现 + 源码对账，**不是 App 内部代码 bug**）**：

- App 降档 = `pulse(4)` → `X360["b5"] = LEFT_SHOULDER`（LB）；升档 = `pulse(5)` → `b6 = RB`；
- **欧卡2 默认就把 LB/RB 绑成“向左/右看”**；所以降档与切镜头共用一个物理键；
- E1 已把 App 自己的“视角”从 `vjoy5` 改走 `hat`（D-pad），App 内部不再撞键；
  剩下的冲突**纯粹来自 App 替你决定了 LB=降档**。

**更深的问题**：`DriveDeck` 把“左转/右转/危险灯/喇叭……”这类语义硬编码进按钮。
但同一只虚拟手柄在不同游戏里默认占用完全不同——App 替用户拍板的**每一条语义都可能撞车**，
而且每换一个游戏就得改一份 App 代码。

**设计修正（E2）**：App **只提供通用模块**，含义与绑定由用户在游戏里完成；
**飞机与开车默认只给轴控件、不放任何按键**（按键由用户自己添加、`Aa` 命名）。

| 项 | 之前 | 现在 |
|---|---|---|
| 按钮标签 | 「降档」「危险灯」 | 默认不内置按键；用户加的按键默认叫「按钮 N」，可 `Aa` 改名 |
| 可用模式 | 仅 gamepad | **三个模式都行**（不再有「模式是否支持自定义」这一说） |
| 飞机默认 | `FlightDeckView` 硬编码（含 6 个内部按键） | `defaultHeli()` = 仪表盘（只读）/周期杆/总距/脚舵/视角（**只有轴、无按键**） |
| 开车默认 | `DriveDeck` 硬编码 | `defaultDrive()` = 方向盘/三踏板/视角（**只有轴**） |
| 固定皮肤 | 唯一外观 | **整份删除**（`FlightDeck.swift` / `DriveDeck.swift` / `GamepadDeck.swift`） |

核心代码：`LayoutStore.defaultHeli()` / `defaultDrive()`、`CockpitView.deckBody`（直接渲染
`WidgetCanvas`）、`EditableWidget` 重命名；删除了 `supportsCustom` 与三个
`palmdeck_*_custom` 开关。详见 `docs/PalmDeck-v4-app-interaction.md` §12.6。

**为何不直接把换档换成 X/B 这种“安全键”**：没有任何一组键对**所有**游戏安全
（欧卡2 的 X/B 是别的功能）。一旦 App 重新拍板，就又把 App 和游戏默认绑死了。
把选择权交给用户，才是“一套模块适配所有游戏”的唯一自洽做法。

**测试**：`tests/test_deck_bindings.py::TestDefaultHeliLayout` /
`TestDefaultDriveLayout`——默认布局不得出现 `.make(.button,`、不得出现游戏语义词;
`TestNoFixedSkins` 守卫三个皮肤文件已删、`CockpitView` 只渲染 `WidgetCanvas`；
`TestLayoutModuleWiring` 守卫三模式的 `defaults` / 播种接线。

---

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改**。字段名 roll/pitch/yaw/thr 保持冻结 |
| 协议 WS 文本 | **暂不改**。原计划 G3 新增 `{"type":"profile"}` + `caps: profile_select`，但§2.7 证明两个目标游戏都不需要，已降级（§7） |
| 电脑侧 | **G0+G1+G2 不改电脑侧任何文件**。（若将来做 G3：`hotas.py` `remap_vjoy` 改查表、`palmdeck_config.py` 新 `axes_presets`、`bridge.py` WS 分支 + `caps`） |
| App 侧 | **G1**：`Model/ShapingKeys.swift`（新：键名 + 迁移）、`ControllerState.swift`（`shapingStore` 可注入 + `applyMode`）、`CockpitController.swift`（`setMode` 走 `applyMode`）、`SettingsView.swift`（分组头带当前模式 + 按模式保存说明）；G2：`Model/GameProfile.swift`（新）、`Layout.swift`（复用布局快照机制）、`SettingsView.swift`（预设 Section）、`project.pbxproj`（手动登记新文件）——**注：G2 里那套「模板」已在 P1.5 并进预设，`LayoutTemplate` 类型已删除**；**E1**：`DriveDeck.swift`（视角改走 D-pad + 新增 `DeckHoldButton`）/ `GamepadDeck.swift`（L3·R3）/ `Layout.swift`（gear 标签 + RT 轴）/ `Widgets.swift`（新增 `rt` 轴 + `onlyOnVJoy`）/ `CockpitView.swift`（组件库提示 + 弱引用警告）——**注：E1 涉及的两个皮肤文件已在 E2 续中整份删除** |
| 文档 | 本文件、`docs/PalmDeck-v4-app-interaction.md`（持久化键表 + 预设交互）、`docs/PalmDeck-v4-redesign.md`（P8）、`docs/README.md` |
| App 侧（E2） | `Layout.swift`（`defaultHeli()` / `defaultDrive()` 只留轴 + `EditableWidget` 重命名）、`CockpitView.swift`（`deckBody` 直接渲染 `WidgetCanvas`）、`SettingsView.swift`（布局分类三模式统一）、删除 `FlightDeck.swift` / `DriveDeck.swift` / `GamepadDeck.swift`、`project.pbxproj` 去登记；`tests/test_deck_bindings.py`（`TestDefaultHeliLayout` / `TestDefaultDriveLayout` / `TestNoFixedSkins`） |

---

## 5. 验证方式

**电脑侧（Python）**
- **G1/G2 不碰电脑侧文件**，所以这一层在 G3 之前**一条测试都不需要加**。
  这是降级 G3 的直接好处：本轮改动的回归面只剩 App 侧。
- （若将来做 G3）扩 `tests/test_profile_remap.py`：两张内置表**逐轴**与改造前的字面值一致
  （「重构 vs 改行为」的分界线）、未知预设回落 `hotas`、
  `tests/test_game_profiles.py`：已知名/未知名/`caps`；`tests/test_config.py`：`axes_presets` 往返。

**App 侧（`swiftc` + `python3 -m unittest`，沿用 `tests/test_ios_axis.py` 的路子）**
- **G2 回归（已实现）**：`tests/ios/GameProfileTests.swift` + `tests/test_ios_profiles.py` ——
  `GameProfile` 编解码往返、旧格式缺字段时的回落（缺 `axesPreset` 回落 `hotas`、
  `infantry` 兼容成 `gamepad`）、内置两个预设的值与 §3.6 一致、
  存储增删改/内置保护/上限（P1.5 起 24）、**应用顺序**（先切模式→写手感→换布局）、
  布局 `nil` 时不碰 `wheel*`；另守卫 `GameProfile.swift` 已登记进 `project.pbxproj`。
- **P1.5 迁移（已实现）**：`hasShaping` 缺省 true（老 v1 JSON 原样解出）、
  两个老键合并（条数/形态/重名后缀）、**幂等**（v2 存在时不重跑，删掉的预设不会复活）、
  垃圾 JSON 不抛错；源码级守卫在 `TestUnifiedPresets`（「模板」词已删干净、旧键只读、
  迁移只在 v2 缺位时跑、内置「默认」是一行不是按钮、布局预设按模式展示）。
- 预设应用后 `layouts[mode]` 等于预设里的 `widgets`、`revision` 自增（`applyProfile` 里保证；
  布局解码在 `LayoutStore`，单测覆盖编解码层）。
- **预设不得擦掉画布（已实现）**：`tests/test_deck_bindings.py::TestProfileDoesNotBlankTheCanvas`——
  内置预设不得夹带 `widgetsJSON`；`LayoutStore.applyProfile` 必须先判空再 `pushUndo`；
  空数组也算“不带布局”；当前是空表时要铺回 `LayoutStore.defaults(mode:)`；
  设置行要标出“仅手感，不动布局” / “含布局”。
  （这一条是**源码级**守卫：`LayoutStore` 在 `Views/` 里，`swiftc` 编不了。）
- **G1 回归（已实现，两层）**：
  - **算法层** `tests/ios/AxisCoreTests.swift`：键名拼接用 `rawValue` 不用 `label`；
    七个旧键**逐个**都被搬家（每个键给不同值，防「只搬了一个也能过」）；
    迁移**不改手感**（三个模式都拿到旧的那一份值）；不覆盖已有的新键、幂等、不碰无关键。
  - **接线层** `tests/ios/ControllerStateKeysTests.swift`：用真的 `ControllerState`
    （存储注入字典替身），验证它真的调了迁移、`applyMode` 真的换一套、
    写入只落当前模式的键、干净安装也把默认值落成显式值。
    只测算法抳不住「算法对、接线错」——而那正是这类 bug 的形状。
  - **守卫** `tests/test_ios_axis.py`：全仓库不得再出现无后缀的全局手感键；
    `setMode` 不得绕过 `applyMode`。
  - **真机/模拟器**：旧容器的 `palmdeck_dz=0.09` + `palmdeck_inv_y=true` → 启动一次后
    `palmdeck_dz.{heli,drive,gamepad} = 0.09`、`palmdeck_inv_y.* = true`，旧键消失（实测）。
- 预设应用后 `layouts[mode]` 等于预设里的 `widgets`、`revision` 自增。
- **E1 回归**（已实现）：`tests/test_deck_bindings.py` 把 Swift 源码和 `hotas.py` 的
  `X360` 表**对账** —— 手柄皮肤每个 `title:` 旁的 `.vjoyN` → `X360[bN]` 必须等于该标签的
  标准 Xbox 键名；同一皮肤内不能有两个标签撞同一个键号；开车模式「按键簇 `toggle` 的键号」
  与「换档 `pulse` 的键号」必须**不相交**（这就是 b5 撞车的直接守卫）；开车模式所有键号 ≤ 10；
  `defaultGamepad()` 的 gear 标签与实际 pulse 下标一致、RT 滑条绑 `.rt`。
  另加两条运行期验证：`tests/test_hotas_hat.py`（`hat_left` → `XUSB_GAMEPAD_DPAD_LEFT`）、
  `tests/test_pack_state.py::DriveHatTests`（22 字节包里的 `hat` 端到端派发/回中）。

**手工（两个游戏各跑一遍）**
1. WARDOGS（heli）：确认与**改动前一致的杆感**——这是「G1 可逆」的回归线。
2. **切到 ETS2 预设**：确认死区/灵敏度/方向盘转角一起变，**且 WARDOGS 的参数不被污染**
   （往回切要回到原值）。这是 G1 的核心验收点。
3. ETS2 内：转向中位不虚、离合不蹿车、降档不同时跳镜头（E1 验收点）。
4. 跑一次 `--open-udp` + 真机，确认切换时**没有**「手机已离线」类 failsafe 误报。

---

## 6. 边界与不做

- **不做按模式自动切轴表**。这是 v3 明令禁止的（`docs/PalmDeck-v3-feature-design.md:1046`），
  本方案也不打算翻案。切换永远是用户显式动作。
- **不给 vJoy 加轴/加按钮**。7 轴 16 键是 `vJoyConfig -f` 建出来的（`hotas.py:112`），
  重建会打断运行中的游戏。真实 HOTAS 需要 30+ 键的需求**本方案解决不了**，要单独立项。
- **不做组合轴（combined axis）**、不做油门 detent/卡位曲线。
  `remap_vjoy` 的 `uni` 是纯线性 `2v-1`（`hotas.py:39,46,48`），
  带 detent 的映射需要在游戏里设，或另立方案。
- **不做 App → 电脑的轴表下发**（即 App 自己定义新轴表并推给电脑）。
  那等于把 HID 语义交给手机，一旦断线/版本错配就是「杆乱动」。
  轴表**只能在电脑侧定义**，App 只能**选**。
- **不做跨设备预设同步**（与命名快照一直以来的边界一致，见 `docs/PalmDeck-v4-unified-presets.md` §6）。
- **不把预设塞进 `layouts.json` / 配置导出包**，除非你明确要求（那就升级 `BUNDLE_VERSION`）。
- **G3（协议 + 电脑侧轴表）暂不做**。立论已写在 §2.7：两个目标游戏里，
  WARDOGS 用 `hotas`（已是默认）且 ETS2 根本不吃轴表。
  为一个用不上的功能去改协议、改打包、改控制台，**收益为零而回归面最大**。
  机制与验收方式保留在 §3.2/§3.5，将来真玩到需要换轴的模拟器再开。
- **⚠️ 需要你确认的两件事**（不是「补信息」，是请你对一遍）：
  1. §3.6 里 ETS2 的两条游戏内设置（LS Y 归属、序列式变速箱）——
     我是按常规写的，**没在本项目里验证过**。
  2. `wheelMaxDeg` 是否真的要从 540 改 900（默认值定在 `ControllerState.swift:97`）。

---

## 7. 工作量

**修订**：拿到真实游戏清单后，原计划的 G3 被降级为「暂不做」，G4 从「编一张表」
变成「写两个具体预设」。新增了取证时发现的 E1。

| 阶段 | 内容 | 规模 | 依赖 | 可独立验收 |
|---|---|---|---|---|
| **G0a** | 删 Capacitor 残骸（`public/` 84 KB、插件、`Main.storyboard`、`SceneDelegate`、`config.xml`） | **S** | 无 | ✅ 新增 3 条防腐测试 |
| **G0b** | 摘掉 CocoaPods（含构建命令 `-workspace` → `-project`） | **S** | G0a | ✅ 干净克隆能直接构建 |
| **E1** | 修 §3.7 的 **5 条** App 侧缺陷（b5 撞车 / b11–16 死键 / LB·RB 标签反 / b9·b10 假 LT·RT / RT 滑条绑空轴） | **S** | 无 | ✅ 新增 `tests/test_deck_bindings.py`（13 条）+ hat 链路 2 条 |
| **G1** | 手感参数按模式分离 + 迁移（修「飞机 0.06 死区污染赛车」） | **S** | 无 | ✅ 算法 58 + 接线 33 条断言 + 4 条守卫；模拟器迁移实测 |
| **G2** | `GameProfile` + 预设 UI | **M** | G1 | ✅ 已落地：两个预设一键来回切 |
| **G4** | 两个预设的**具体值**（§3.6） | **XS** | G2 | ✅ 值已填入 `GameProfileBuiltin`；**剩下真机验收**（游戏内绑定/参数对账） |
| ~~G3~~ | ~~电脑侧声明式轴表 + WS `profile`~~ | ~~M~~ | — | **暂不做**（§2.7 证明用不上） |

建议顺序 **G0a → G0b → E1 → G1 → G2 → G4**，每个阶段一个 commit。
- G0a/G0b 纯删除，不带任何功能；拆两步是为了让 pbxproj 手术失败时可回滚。
- E1 是 bug 修复，和预设功能**没有因果关系**，必须能单独回滚。
- G1 也是「当前就是错的」（飞机/赛车共用一个死区），不是新功能。
- G2 是唯一一个真正的功能 commit。
- G4 的代码部分已随 G2 完成（内置两个预设就写在 `GameProfileBuiltin` 里）；
  剩下的只是**真机验收**：拿 WARDOGS/ETS2 对一遍游戏内绑定与参数，有出入才改值。

---

## 附：明确被本方案否决的备选

| 备选 | 否决理由 |
|---|---|
| 把预设定义成表达式字符串，电脑 `eval` 求值 | 配置文件 = 远程代码执行面。7 根轴的排列组合用枚举足够，不需要图灵完备 |
| 让 App 下发完整轴表给电脑 | HID 语义跑到手机上；断线/版本错配直接表现为「杆乱动」，且无法在电脑侧校验 |
| 按模式自动切轴表 | v3 明令禁止（`:1046`）。切表会让游戏内已存绑定突然指向别的物理控制 |
| 用 `vJoyConfig -f` 按游戏重建不同轴数的设备 | 打断运行中的游戏；且 `-f` 是强制，会顶掉用户自己配的设备 |
| 每个游戏一个独立 App 界面（多套 skin） | 已经有三套皮肤覆盖设备形态了；游戏之间的差异 90% 是**参数**不是**形态**，加皮肤是重复造轮子 |
