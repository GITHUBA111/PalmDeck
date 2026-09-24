# 方案：游戏预设（不同游戏的适配）

**状态**：📝 待评审
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
| `heli` | 总距 + 脚舵 + 周期变距杆 | `Views/FlightDeck.swift` |
| `drive` | 方向盘 + 三踏板 + 档杆 | `Views/DriveDeck.swift` |
| `gamepad` | 双摇杆手柄 | `Views/GamepadDeck.swift` |

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

「布局模板」已落地（`docs/PalmDeck-proposal-template.md` §2）：
每模式 12 个命名快照，可切换/重命名/删除/还原。
而按钮的**显示名是每个组件自己的字段**（`DeckWidget.label`，`Views/Widgets.swift:67`），
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

### 3.3 App 侧：手感参数按模式分离（**独立于预设，先修**）

键名加模式后缀，一次性迁移：

```
palmdeck_sens_x            →  palmdeck_sens_x.heli / .drive / .gamepad
palmdeck_dz                →  palmdeck_dz.<mode>
palmdeck_inv_x/_y/_yaw/_coll →  palmdeck_inv_*.<mode>
```

迁移规则：**读不到带后缀的键时，回落读旧键**（老用户升级后参数不丢），
然后写回新键、删旧键。`ControllerState.yawDeadzone` 常量不动。

> 这一条**不依赖预设也能单独成立**，且它是「飞机 0.06 死区污染赛车」的直接修复。
> 所以它排在 G1，可以独立验收。

### 3.4 App 侧：预设 = 布局 + 手感 + 轴表名（G2）

复用已落地的布局模板机制，把它扩成预设：

```swift
struct GameProfile: Codable, Equatable {
    var name: String                    // 预设名，如「DCS 直升机」
    var mode: CockpitMode               // 用哪套机身皮肤
    var axesPreset: String              // 电脑侧轴表名，如 "hotas"
    var sensX, sensY, dz: Double
    var invX, invY, invYaw, invColl: Bool
    var widgets: [DeckWidget]           // 布局 + 每个按钮的 label
}
```

- 存储：`palmdeck_game_profiles_v1`（本地，**不进 `layouts.json`、不进配置导出包**）。
- 切换动作 = 一次性写入：`layouts[mode] = widgets` → 手感参数 → 模式。
- 切换后 **`layout.revision += 1`**（沿用 `applyTemplate` 的语义，
  因为这是整表替换，`WidgetCanvas` 靠 `.id(revision)` 强制重绘）。
- 上限沿用模板的 12 个；内置「默认」不可删不可改名（同模板的规则）。

**UI 位置**：设置页新增 Section「游戏预设」（放在「布局」上方），
一行一个预设，显示 `名字 · 模式 · 轴表名 · 电脑当前是否匹配`。
最顶部一行是「当前」——显示**电脑实际**的 `axis_profile`（来自 `hello`/`status`，`bridge.py:744`）。

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
| 布局 | 现状 `FlightDeck`（固定布局） | |

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
| 布局 | `DriveDeck`（固定布局） | 已有转灯/危险灯/喇叭/手刹/雨刷/大灯/远光/视角，**本来就是按卡车做的** |
| 按钮标签 | 沿用 `DriveDeck.swift:316–324` 的中文名 | |

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

> 这两条都是「按常规」写的，**不是在本项目里验证过的**（我没有 ETS2 环境）。
> 请你在游戏里对一遍，有出入告诉我改。

### 3.7 取证时顺带发现的三个 App 侧缺陷

这三个都不是「游戏适配」，是现在就错的。ETS2 恰好会踩到第 1 个。

#### (1) drive 模式：视角键与降档撞同一个按钮（b5 = LB）

`DriveDeck.swift:324` 视角键用 `.vjoy5` ⇒ `vjoyIndex = 4` ⇒ 发 **b5**；
`DriveDeck.swift` `shift(-1)` ⇒ `pulse(4)` ⇒ 也发 **b5**。
PC 侧两者都映射到 `X360["b5"] = LEFT_SHOULDER = LB`（`hotas.py:293`）。

⇒ **按降档会同时触发镜头。**
卡车里降档是高频操作（上坡/减速），而镜头跳一下是直接干扰驾驶的。

#### (2) 手柄模式下 b11–b16 是死按钮

`hotas.py X360` 字典到 `b10` 为止，**没有 `b11`–`b16`**；
但 `Widgets.swift:32` 的组件库提供 `vjoy11`–`vjoy16` 可选。
在 flight（vJoy）下它们是好的（`VJOY_BTN` 有 `:321`），在 drive/gamepad（Xbox）下按下去**没有任何反应**。

⇒ 组件库里用户能选到一个「什么都不做」的绑定。

#### (3) `defaultGamepad()` 的 LB/RB 标签反了

`Layout.swift:299` 把 `.gearUp` 标成 `"LB"`，`:300` 把 `.gearDown` 标成 `"RB"`。
但 `Widgets.swift:157` `gearUp → pulse(5) → b6 → X360["b6"] = RIGHT_SHOULDER`（`hotas.py:294`），
`gearDown → pulse(4) → b5 → LEFT_SHOULDER`。
**标签与真实按键正好相反。**

（同一张表里 `.vjoy7` 标 `"视图"`、`.vjoy8` 标 `"菜单"`，而 `b7`/`b8` 是 BACK/START，
这个偏离是合理的，不算缺陷。）

> 这三条**建议单独成 commit（E1）**，不混进预设功能——
> 它们是修复，与「游戏预设」这个新功能无因果关系。

### 3.8 顺手删掉的两个 Capacitor 残骸（G0）

| 东西 | 体积 | 证据 | 结论 |
|---|---|---|---|
| `mobile/ios/App/App/public/` | **84 KB**（打进 App 包） | `project.pbxproj:18,56,158,236` 作为 folder 资源；内容是 Capacitor 期 `host.html` + `qrcode.js` + 空 `cordova.js` | v4 是纯 SwiftUI（`@main`），**全 App 无 WebView**，从不读它 |
| `mobile/ios/App/App/PalmDeckUdpPlugin.swift` | 118 行 | 仅被 `capacitor.config.json:16` 的 `packageClassList` 提及；`Haptics.swift` 直接用 UIKit | Capacitor 插件残骸。注释还写着「iOS WKWebView 不支持 navigate.vibrate」——WebView 早没了 |

建议单独一个 commit 删掉（**不混进本方案**）。

---

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改**。字段名 roll/pitch/yaw/thr 保持冻结 |
| 协议 WS 文本 | **暂不改**。原计划 G3 新增 `{"type":"profile"}` + `caps: profile_select`，但§2.7 证明两个目标游戏都不需要，已降级（§7） |
| 电脑侧 | **G0+G1+G2 不改电脑侧任何文件**。（若将来做 G3：`hotas.py` `remap_vjoy` 改查表、`palmdeck_config.py` 新 `axes_presets`、`bridge.py` WS 分支 + `caps`） |
| App 侧 | `ControllerState.swift`（PKey 加模式后缀 + 迁移、`wheelMaxDeg` 默认）、`Model/GameProfile.swift`（新）、`Layout.swift`（模板 → 预设）、`SettingsView.swift`（新 Section）、`project.pbxproj`（手动登记新文件）；**E1**：`DriveDeck.swift` / `GamepadDeck.swift` / `Layout.swift` 的按钮绑定 |
| 文档 | 本文件、`docs/PalmDeck-v4-app-interaction.md`（持久化键表 + 预设交互）、`docs/PalmDeck-v4-redesign.md`（P8）、`docs/README.md` |

---

## 5. 验证方式

**电脑侧（Python）**
- **G1/G2 不碰电脑侧文件**，所以这一层在 G3 之前**一条测试都不需要加**。
  这是降级 G3 的直接好处：本轮改动的回归面只剩 App 侧。
- （若将来做 G3）扩 `tests/test_profile_remap.py`：两张内置表**逐轴**与改造前的字面值一致
  （「重构 vs 改行为」的分界线）、未知预设回落 `hotas`、
  `tests/test_game_profiles.py`：已知名/未知名/`caps`；`tests/test_config.py`：`axes_presets` 往返。

**App 侧（`swiftc` + `python3 -m unittest`，沿用 `tests/test_ios_axis.py` 的路子）**
- `GameProfile` 编解码往返；旧格式缺字段时的回落。
- 手感参数迁移：先写旧键 → 初始化 → 断言新键拿到旧值、旧键被清。
- 预设应用后 `layouts[mode]` 等于预设里的 `widgets`、`revision` 自增。
- **E1 回归**：断言 `GamepadDeck` / `DriveDeck` 的每个按钮绑定的 `vjoyIndex`
  在本模式下**互不重复**（这是那个 b5 撞车的直接守卫——
  手工数按键不可靠，要机器数）。

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
- **不做跨设备预设同步**（与「布局模板」相同的边界，见 `docs/PalmDeck-proposal-template.md` §2 边界）。
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
| **G0** | 删 Capacitor 残骸（84 KB + 118 行） | **XS** | 无 | ✅ App 包不再含 `public/` |
| **E1** | 修 §3.7 的三个 App 侧缺陷（b5 撞车 / b11–16 死键 / LB-RB 标签反） | **S** | 无 | ✅ 新增「绑定不重复」测试 |
| **G1** | 手感参数按模式分离 + 迁移 | **S** | 无 | ✅ ETS2 与 WARDOGS 参数互不污染 |
| **G2** | `GameProfile` + 预设 UI | **M** | G1 | ✅ 两个预设一键来回切 |
| **G4** | 两个预设的**具体值**（§3.6） | **XS** | G2 | ✅ 打开即有「WARDOGS」「欧洲卡车模拟」 |
| ~~G3~~ | ~~电脑侧声明式轴表 + WS `profile`~~ | ~~M~~ | — | **暂不做**（§2.7 证明用不上） |

建议顺序 **G0 → E1 → G1 → G2 → G4**，每个阶段一个 commit。
- G0 纯删除，不带任何功能。
- E1 是 bug 修复，和预设功能**没有因果关系**，必须能单独回滚。
- G1 也是「当前就是错的」（飞机/赛车共用一个死区），不是新功能。
- G2 是唯一一个真正的功能 commit。
- G4 只是把两个预设的默认值填进去，几乎不写逻辑。

---

## 附：明确被本方案否决的备选

| 备选 | 否决理由 |
|---|---|
| 把预设定义成表达式字符串，电脑 `eval` 求值 | 配置文件 = 远程代码执行面。7 根轴的排列组合用枚举足够，不需要图灵完备 |
| 让 App 下发完整轴表给电脑 | HID 语义跑到手机上；断线/版本错配直接表现为「杆乱动」，且无法在电脑侧校验 |
| 按模式自动切轴表 | v3 明令禁止（`:1046`）。切表会让游戏内已存绑定突然指向别的物理控制 |
| 用 `vJoyConfig -f` 按游戏重建不同轴数的设备 | 打断运行中的游戏；且 `-f` 是强制，会顶掉用户自己配的设备 |
| 每个游戏一个独立 App 界面（多套 skin） | 已经有三套皮肤覆盖设备形态了；游戏之间的差异 90% 是**参数**不是**形态**，加皮肤是重复造轮子 |
