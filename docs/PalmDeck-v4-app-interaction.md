# PalmDeck v4 · App 端功能与交互设计

> 状态：**设计稿 + P7 / G1 实施**（本文档为 iOS App 的权威交互规格）
> 范围：`mobile/ios/App/App/Native/`（纯原生 SwiftUI）。电脑侧见
> `docs/PalmDeck-v3-feature-design.md`；总纲见 `docs/PalmDeck-v4-redesign.md`。
> 原则：**App 是“杆”，不是演示页**——手感、确定性、零误触优先于功能堆砌。

---

## 0. 设计原则

1. **一屏到底**：进座舱后不再跳页；连接、模式、参数、布局全部在座舱内完成（弹层 / 顶栏 / 底栏）。
2. **确定性 > 灵敏度**：所有模拟量控件按“抓取增量”调整（按下不跳值），并带边界/中心吸附。
3. **本地永远可用**：未连电脑也能进座舱、拖动、看反馈；连上后自动生效（`PreflightView` 底部承诺）。
4. **误触零容忍**：切换模式会 park HID；任何会打断游戏的操作都要么可撤销，要么高成本触发。
5. **手感可调且**持久**：轴反向 / 灵敏度 / 死区 / 回中 / 触觉——改一次，重启仍在。
6. **不抢输入**：`gamepad`（手柄）模式轴停发，落地/菜单用电脑键鼠。

---

## 1. 信息架构

```
PalmDeckApp (@main)
├─ PreflightView        启动页：三步引导 + 状态条 + 连接/断开 + 高级(IP/反向)
│   └─ [进入座舱]  ─────────────►  CockpitView（persisted: palmdeck_entered）
└─ CockpitView          座舱：顶栏 + 皮肤 + 底栏
    ├─ 顶栏：模式段(3) · 连接胶囊 · 设置齿轮 · [布局]（仅手柄）
    ├─ 皮肤：
    │   ├─ heli    → FlightDeckView（固定硬件）
    │   ├─ drive   → DriveDeck（固定硬件）
    │   └─ gamepad → GamepadDeck（默认）｜WidgetCanvas（自定义，opt-in）
    ├─ 底栏 statusStrip：ROL/PIT/YAW · THR · LINK(hz) · MODE · SRC
    ├─ ⌘ 设置 → SettingsView（双栏：连接 / 布局 / 操纵与手感 / 触觉 / 方向盘 / 帮助）
    ├─ ⌘ 布局 → LibrarySheet（类型 + 绑定）
    ├─ 首次 → CockpitTutorialView（一次性，可重开）
    └─ 未连接 → notConnectedBanner（顶部胶囊，点击即连）
```

**屏幕状态机**

```
idle ──connect()──► connecting ──open──► live
  ▲                     │ timeout(8s)        │ close(意外)
  │                     ▼                    ▼
  └──disconnect()───  lost ◄─────────────  lost
                        │ 退避自动重连 (0.6→4s)
                        └───────────────► connecting
```

- 手动 `disconnect()` 置 `autoReconnect=false`，**不**自动重连（`CockpitController.swift:73`）。
- 意外断开走指数退避重连（`CockpitController.swift:107`、`:126`）。

---

## 2. 启动与连接交互

### 2.1 PreflightView（启动页）
- 左栏：品牌 + **状态条** + 超大 `[进入座舱]` + 一句承诺。
- 右栏：三步卡片（电脑装好 → 同 Wi-Fi → 进座舱）+ 发现列表 + 「高级设置」折叠。
- 状态条文案由 `s.link` + `discovery.found` 派生（`PreflightView.swift:96-118`）。
- 交互：
  - 点状态条 / 点发现项 / 点「连接」→ `ctrl.connect(host:)`。
  - 点「断开」→ `ctrl.disconnect()`。
  - 「高级」里手动 IP + 四个轴反向按钮（与设置页共享语义）。

### 2.2 发现（Bonjour）
- `Discovery` 解析服务名里的 IP（`PalmDeck-192-168-3-103`）；过滤回环/fake-ip（`Discovery.swift:3`）。
- 服务名带端口时也解析出 `ws/udp`（`DiscoveredHost{ip,ws,udp,name}`）。

### 2.3 连接胶囊 / 未连接横幅（座舱内）
- `live`：绿点 + `IP` + `Hz`，点击 = 断开（`CockpitView.swift:169`）。
- 非 `live`：`连接中…` / `一键连接` / `连接`；有发现则 wifi 图标变绿。
- 皮肤顶部半透明橙胶囊 `notConnectedBanner`：点一下即连最佳主机；不遮挡控件（`CockpitView.swift:262`）。

**规格**
| 状态 | 顶栏 | 皮肤顶部横幅 | 触觉 |
|---|---|---|---|
| idle 未发现 | 「连接」灰 | 「未连接电脑（先在电脑启动 PalmDeck）」 | — |
| idle 已发现 | 「一键连接」绿 | 「点此连接电脑 <ip>」 | tap |
| connecting | 「连接中…」+ 菊花 | 无 | — |
| live | 绿点 ip + Hz | 无 | success |
| lost | 「连接中…」重试 | 橙胶囊（可点重连） | warning |

### 2.4 端口协商（P7 新增）
`hello` 里带 `http/ws/udp`。App 记录服务端实际端口，后续连接用实际端口，
不再假设 7773/8765（`CockpitController.handleJSON` → `NetClient`）。

---

## 3. 模式与皮肤

### 3.1 模式段（顶栏居中）
- 三枚 68pt 卡片：`飞机 / 开车 / 手柄`；激活项为青色实心（`CardButton(active:)`）。
- 点击 → `ctrl.setMode(m)`：
  1. 轻震 `press()`；
  2. 清轴 `resetAxes()`、`hat=255`；
  3. 持久化 `palmdeck_mode`；
  4. 向电脑发 `{"type":"mode","name":m}`（服务端 park 未用 HID 一次）。
- 仅 `手柄` 模式显示右侧 `[布局]` 按钮。

> 遗留议题（见 §10）：v3 曾要求“按住 400ms 防误触”。v4 改为单击；
> 是否恢复长按见 P7 backlog（默认不改，避免影响习惯）。

### 3.2 飞机 heli — 默认通用模块（轴）+ `FlightDeckView`（经典皮肤，可选）

**默认是通用模块布局（`defaultHeli()`），只放轴控件、不放任何按键**：
周期杆（`stick` → roll+pitch）· 总距（`slider` → throttle）· 脚舵（`slider` → yaw）· 视角（`pad` → look）。
按键完全由用户自己添加、命名（见 §12.6）。

下面的 `FlightDeckView` 作为**经典硬件皮肤**保留，但**不是默认**：在编辑态点 `[经典皮肤]` 才切过去。

| 区域 | 控件 | 映射 | 手势/手感 |
|---|---|---|---|
| 左 | 总距杆 `CollectiveLever` | `throttle`(→Z/collective) | 拖动把手；IDLE/FLY/MAX 刻度；抓取增量 |
| 中上 | 仪表面板 | 只读 | COLL/TRQ 弧 + 姿态球 + ROL/PIT/YAW 条 |
| 中下 | 脚舵 `RudderPedals` | `yaw`(→Rz) | 横向拖动 → 偏航；**松手 6/s 回中** |
| 右上 | 周期变距杆 `CyclicControl` | `roll`/`pitch` | 抓取增量 2D；**松手 5/s 回中**；0.95 吸附满值 |
| 右下 | 按键簇 2×3 | vJoy | 开火/投弹/起落架(脉冲 b6)/灯光/悬停/视角 |

> 表中的“按键簇”是**经典皮肤自带**的，与“默认不内置按键”的主张相冲——
> 所以经典皮肤只作为 opt-in，不默认显。

### 3.3 开车 drive — 默认通用模块（轴）+ `DriveDeck`（经典皮肤，可选）

**默认是通用模块布局（`defaultDrive()`），只放轴控件、不放任何按键**：
方向盘（`wheel` → roll）· 三踏板（`slider` → clutch/brake/throttle）· 视角（`pad` → look）。
换档/转向灯……由用户自己加按键、在游戏里自己绑。

下面的 `DriveDeck` 作为**经典硬件皮肤**保留，但**不是默认**：在编辑态点 `[经典皮肤]` 才切过去。

| 区域 | 控件 | 映射 | 手感 |
|---|---|---|---|
| 左上 | `DashPanel` 转速表+档位 | 只读 | 红区红线、油门/刹车/离合/转向条 |
| 中上 | 方向盘 `SteeringWheel` | `roll`(→X) | 多圈（可调满舵 180–900°）；回正速度可调（0=保持） |
| 右 | 视角板 `LookPad` + 3×3 键簇 + 3 个十字键 | `lookX/Y` + vJoy + `hat` | 视角触碰板；左右转/危险灯/喇叭/手刹/雨刷/大灯/远光；**视角 ↑/左视 ←/右视 →** 走 `hat`（按下生效，松手回中） |
| 左下 | 三踏板 `DrivePedals` | 离合 Y / 刹车 Sl0 / 油门 Z&RT | 独立按住，互不影响 |
| 右下 | 序列式档杆 `GearLever` | 脉冲 b6 升 / b5 降 | 拖动选档，每次换位发一次脉冲 |

档杆档位 `R N 1 2 3 4 5 6`，默认 N(=index 2)。**P7 起持久化**（`palmdeck_gear`）。

> 本表描述的是 **opt-in 的经典皮肤** `DriveDeck`。默认走通用模块（`defaultDrive()`），
> 只给轴、不给按键。


**开车默认就是通用模块**（见 §12.6）：`palmdeck_drive_custom` 默认 true，
皮肤即 `WidgetCanvas`，默认布局 `defaultDrive()` = **方向盘 / 三踏板 / 视角（只有轴，没有任何按键）**。
在编辑态点 `[经典皮肤]` 可切回 `DriveDeck` 卡车皮肤（opt-in）。

> 为何不再把「左转/降档」这类字硬编码进按钮：同一只虚拟手柄在不同游戏里默认占用完全不同，
> App 替用户拍板的每一条语义都可能与游戏默认撞车（如欧卡2 默认 LB=向左看）。
> 具体症状与修法见 §12.6。

### 3.4 手柄 gamepad — `GamepadDeck` / `WidgetCanvas`
- 默认硬件皮肤 `GamepadDeck`：左摇杆(roll/pitch) · 右摇杆(look) · 十字键(hat) ·
  ABXY(vjoy1-4) · LB/RB(vjoy5/6) · 视图/菜单(vjoy7/8) · L3/R3(vjoy9/10)。
  （**不是 LT/RT**：Xbox 的 LT/RT 是模拟轴 `lt`/`rt`，不在按键表里；
  `X360["b9"] = LEFT_THUMB`、`X360["b10"] = RIGHT_THUMB`。）
- 开关 `palmdeck_gamepad_custom`：切到 `WidgetCanvas` 自定义组件布局（P3 同步）。
  飞机 / 开车同构地用 `palmdeck_heli_custom` / `palmdeck_drive_custom`，且**两者默认 true**
  （默认就是通用模块，经典皮肤需手动切回；见 §3.2 / §3.3 / §12.6）。
- 服务端在 gamepad 停 `thr/lt/rt`，App 停发轴 → **不抢电脑键鼠**。

---

## 4. 触摸与手感模型

### 4.1 抓取增量（所有模拟量通用）
按下瞬间记录 `(基准值, 手指起点)`，之后仅按**位移增量**改值——避免“一触摸就跳到手指位置”。
实现见 `StickControl`、`BipolarSlider`、`CyclicControl`、`CollectiveLever`、`DeckPedal`。

### 4.2 回中
- 摇杆 / 周期杆 / 脚舵：松手后用 60Hz 定时器按指数逼近 0（不是瞬跳），到 `|v|<0.004` 归零并停表。
- 方向盘：按 `wheelReturnSpeed`（°/s）回正；0 = 松手保持。
- 摇杆是否回中由 `stickReturn` 决定（仅手柄左摇杆可关）。

### 4.3 死区 / 曲线 / 灵敏度
发送前统一经 `ControllerState.tickSmoothing()`：
`sm = lerp(sm, shape(±sens·raw), k)`，`shape` = 死区内归零 + `^1.35` 曲线；
`k`：XY 0.45 / Yaw 0.5（`ControllerState.swift:88`）。

- **死区 `dz`**：默认 0.06，舵 0.08，视角 0.05。
- **灵敏度 `sensX/sensY`**：P7 起接入发送曲线（此前为死变量）。
- 轴反向 `invX/invY/invYaw/invColl` 在 `tickSmoothing` / `collective` 应用。

### 4.4 多指与并发
- 所有控件用独立 `DragGesture`，支持多指同时操作（总距 + 周期 + 脚舵可三指同时）。
- `ctrl.setTouchActive(true/false)` 仅用于统计“手在杆上”，不阻塞热路径。

---

## 5. 触觉词汇表（Taptic）

| 事件 | API | 强度 |
|---|---|---|
| 抓住控件 / 点按 | `tap()` | light |
| 模式切换 / 主操作 | `press()` | medium |
| 轴到满行程（仅已连接） | `bump()` | heavy |
| 开火 | `rigidTap()` | rigid |
| 列表选择 | `select()` | selection |
| 连接成功 | `success()` | notification |
| 连接失败 / 无效地址 | `warning()` | notification |

**P7 新增**：总距越过 IDLE/FLY/MAX 卡位 → `tap()`；脚舵/方向盘过中位 → `select()`。
**P7 新增**：设置里「触觉反馈」总开关（`palmdeck_haptics`，默认开），关后全部静默。

---

## 6. 设置（SettingsView）

**版式**：Apple「设置」风格 —— 横屏双栏（左分类 / 右详情），右栏 `insetGrouped` 分组卡片；
彩色圆角图标瓦片（29pt，圆角 7）、分组小标题、右对齐值、选中行灰底高亮、顶部「设置 / 完成」栏。
左栏各行右侧显示关键值（连接 → 电脑 IP；触觉 → 开/关）。

**搜索**：左栏顶部胶囊搜索框（Apple 设置同款），跨全部分类搜标题 + 中英关键词
（`SettingsCategory.entries` 索引，如搜 “死区 / deadzone / dead” 均中）；
有词时左栏换成按分类分组的结果列表，空词时回到分类列表；点结果 → 跳到该分类并清空搜索；
无匹配显示空态。

**滑条值可直接输入**：`SliderRow` 的数值是可点的青色字段，点开 → `alert` + 数字键盘精确输入；
提交时夹到 `range`、按 `step` 吸附（可关）、抹浮点尾数。内部值与展示值单位不同时靠
`format`/`parse` 转换（如满舵角度内部是度、展示是圈：`parse(s) = s × 360`）。

**响应曲线**（操纵与手感 → 响应曲线）：把真实整形函数画出来——横轴＝原始输入（含反转），
纵轴＝实际输出；叠了 1:1 参考虚线、死区阴影带、当前输入点；拖灵敏度/死区滑条曲线实时变。
`AxisResponseCurve.output()` **必须**与发送路径逐字一致，否则预览会说谎。
**实现方式（不能退回到「复刻公式」）**：预览不再自己写一遍数学，而是直接调
`Model/AxisCurve.swift` 的 `AxisCurve.output(v, sensitivity:deadzone:inverted:)` ——
`ControllerState.tickSmoothing()`（平滑）与 `Packet.pack()`（发送）调的是同一个函数。
`tests/test_ios_axis.py::TestCurveHasSingleImplementation` 会在任何别的 Swift 文件里
再出现 `pow(` 或 `func shape(` 时直接失败。

曲线定义（`AxisCurve.swift` 为唯一出处）：

```
y = sign(x) · ((|x| − dz) / (1 − dz)) ^ 1.35      |x| >= dz
y = 0                                              |x| <  dz
```

顺序不能反：**先乘灵敏度 → 夹到 [-1,1] → 再进死区/曲线**（`AxisCurve.output`）。
`dz` 被夹到 `[0, 0.95]`，杜绝 `dz >= 1` 的除零；方向舵用固定死区 `0.08`
（自回中轴，死区跟着滑条放大会转不动尾桨）。

> 实现：不用 `NavigationView`（横屏下会挤压两栏内容），改用自绘标题栏 + `HStack` 双栏，
> 见 `Views/SettingsView.swift`（`SettingsCategory` / `SettingsIcon` / `SettingsHeader` /
> `InfoRow` / `LinkStatusPill` / `SliderRow`）。

| 分类 | 分组 | 项 | 持久化（P7） |
|---|---|---|---|
| 连接 | 电脑 / 可用电脑 / — | 电脑、状态胶囊、断开连接、发现列表、上次主机、返回启动页 | — |
| 布局 | 模式 / 与电脑同步 | 自定义开关(手柄) / 编辑 / 恢复默认 / 清空 / 拉取 / 上传 | `palmdeck_gamepad_custom` |
| 操纵与手感 | 轴反向 / 摇杆 / 灵敏度与死区 / 响应曲线 | 横滚 / 俯仰 / 方向舵 / 总距；松手回中；灵敏度 X / Y、死区（点值精确输入）；双轴响应曲线预览 | ✅ `invX/invY/invYaw/invColl`、`stickReturn`、`sensX/sensY/dz` |
| 触觉 | 反馈 | 触觉反馈总开关 + 「试一下振动」 | ✅ `palmdeck_haptics` |
| 方向盘 | 参数 | 满舵角度 / 回正速度（点值精确输入） | ✅ `wheelMaxDeg/wheelReturnSpeed` |
| 帮助 | 教程 / 关于 | 查看使用教程；App 版本、当前皮肤 | `palmdeck_tutored` |

> 历史问题（已修）：轴反向/摇杆/方向盘这些参数此前是**普通 `var`，既不 `@Published` 也不落盘**，
> 重启即丢、开关可能不刷新。P7 统一改为持久化（见 §11）。

---

## 7. 布局编辑与模板（全部模式）

### 7.1 编辑

- 入口：顶栏 `[布局]`（`LayoutStore.supportsCustom(mode:)` 对三个模式都为 true）；
  首次点开自动把该模式的自定义开关置 true（`palmdeck_gamepad_custom` / `palmdeck_heli_custom` /
  `palmdeck_drive_custom`），避免“编辑了却看不到”。
- 编辑条最左 `[经典皮肤]`：把该模式切回固定硬件皮肤（opt-in），退出编辑。
- 组件库条（编辑态顶部）：按键 / 触摸板 / 摇杆 / 方向盘 / 滑条 / 苦力帽 / 姿态球；
  有默认绑定的直接加，滑条/按键弹 `LibrarySheet` 选绑定。
- 画布操作：拖动移动、右下角手柄缩放、左上 `✕` 删除、右上 `Aa` **重命名**
  （名称留空回落绑定的默认名，如「按钮 3」；名称只存本机，不改变发出去的键位）。
- **组件库条右侧**：`存为模板`（快照当前布局，弹命名框）／ `完成`。
- 同步：`layouts_get` / `layouts_put`（WS 控制面）；服务端下发 → `LayoutStore.applyServer`。
- 存储键 `palmdeck_widgets_v10`（`{mode: [DeckWidget]}`）。

> ⚠️ 曾在 `WidgetCanvas` 的 `.overlay(.topTrailing)` 里放过「完成 / 清空 / 存为模板」。
> 那是**死 UI**：`CockpitView` 的组件库条是 ZStack 后绘制的兄弟节点，会把它整个盖住。
> 编辑类按钮一律放组件库条里。

### 7.2 模板（保存 / 切换 / 还原）

问题：每个模式只有一份布局，`清空` / `恢复默认` 都是不可逆覆盖。
模板 = `(name, [DeckWidget])` 命名快照，**按模式归类**。

- 内置「默认」**不入库**，直接取 `LayoutStore.defaults(mode:)` → 它同时是「还原点」。
- 「还原」= 应用内置「默认」模板（与普通应用同一条路径，所以**也可撤销**）。
- 撤销槽：`清空` / `恢复默认` / `应用模板` 执行前压入，满足条件时设置页出现「撤销上一次改动」。
- 上限：每模式 12 个；名称 ≤16 字符、非空、同模式内唯一（重名覆盖）。
- 入口：设置 → 布局 → **模板**段（点行即切换；左滑重命名/删除；`✓` = 当前布局）。

**判定形状用 `isCurrent`，不能直接 `==`**：`DeckWidget.make`（`Widgets.swift:76`）每次生成新 `UUID`，
而 `Equatable` 是合成实现、包含 `id`——内置默认回回重建都是新 id，用 `==` 永远比不等。
`isCurrent` 只比 `kind / binding / rect / label`（顺序敏感），因此「默认」和内容相同的自建模板会**同时**打 `✓`，这是对的。

**整表替换必须重建画布**：`applyTemplate` / `undoLast` / `clear` / `reset` 走 `replaceWidgets`，
递增 `revision`，画布用 `.id(layout.revision)` 强制重建——否则 `EditableWidget` 的 `@State dragStart`
会残留到新布局上。`add` / `remove` / `update`（拖拽中高频调用）**不得**递增 `revision`，否则手势会断。

**初始化只补不存在的模式**：`init` 用 `layouts[mode] == nil`（而非 `isEmpty`）播种默认布局，
否则用户主动「清空」的空白布局会在重启后被默认布局盖掉。

---

## 8. 教程与帮助

- 首次进座舱延迟 0.3s 弹 `CockpitTutorialView`（`palmdeck_tutored` 标记）。
- 内容：顶部 / 飞机 / 开车 / 手柄 / 自定义布局 / 三步上手。
- 设置 → 帮助可重开（关闭设置后 0.4s 再弹，避免叠层）。

---

## 9. 现状差距清单（P7 backlog）

| # | 问题 | 证据 | 严重 | 处置 |
|---|---|---|---|---|
| G1 | 设置参数不持久化（反向/回中/方向盘） | `ControllerState.swift` 普通 var | **高** | ✅ P7.1 落盘 |
| G2 | `sensX/sensY` 未接入，无 UI | 仅定义，无引用 | 高 | ✅ P7.2 接入 + UI |
| G3 | 触觉无开关 | `Haptics.enabled` 无处设置 | 中 | ✅ P7.3 UI |
| G4 | `ping()` 死代码，无心跳 | 无调用 | 中 | ✅ P7.4 5s 心跳 |
| G5 | 忽略 `hello` 端口 | `hello` 分支空实现 | 中 | ✅ P7.4 协商 |
| G6 | `Discovery.found.ws/udp` 未用 | 只取 `.ip` | 中 | ✅ P7.4 TXT + 传递 |
| G7 | 总距卡位无触觉 | `CollectiveLever` 无 detent 反馈 | 中 | ✅ P7.3 卡位震 |
| G8 | 档位不持久化，切模式归零 | `DriveDeck` `@State gearIndex` | 中 | ✅ P7.5 落盘 |
| G9 | 手感参数三模式共用一份 | `ControllerState` 全局键 | **高** | ✅ **G1** 按模式分键 |
| G9 | 模式单击即切（误触风险） | `setMode` 无防抖 | 低 | 记录，暂不改 |
| G10 | `LayoutStore` 仍为 heli 生成默认布局（heli 无自定义布局） | `Layout.swift` defaults | 低 | 记录，暂不改 |
| G11 | `haveCenter/paused` 已删，无校准流程 | — | — | 已解决 |

> 图例：✅ 表示已在 P7 落地（构建通过）。

---

## 10. 状态持久化总表

| key | 类型 | 默认 | 说明 |
|---|---|---|---|
| `palmdeck_entered` | Bool | false | 是否已进过座舱 |
| `palmdeck_tutored` | Bool | false | 是否看过速览 |
| `palmdeck_host` | String | "" | 上次电脑 IP |
| `palmdeck_mode` | String | heli | 上次模式 |
| `palmdeck_gamepad_custom` | Bool | false | 手柄用自定义模块布局（经典皮肤 opt-in） |
| `palmdeck_heli_custom` | Bool | **true** | 飞机用通用模块布局（**§12.6 新增**） |
| `palmdeck_drive_custom` | Bool | **true** | 开车用通用模块布局（**§12.6 新增**） |
| `palmdeck_widgets_v10` | Data | defaults | 组件布局 |
| `palmdeck_layout_templates_v1` | Data | `{}` | 布局模板 `{mode: [LayoutTemplate]}`（不含内置「默认」） |
| `palmdeck_layout_undo_v1` | Data | `{}` | 撤销槽 `{mode: [DeckWidget]}`，单格/按模式 |
| `palmdeck_gear` | Int | 2 | 开车档位（P7 新增） |
| `palmdeck_haptics` | Bool | true | 触觉开关（P7 新增） |
| `palmdeck_sens_x/y` | Double | 1.0 | 灵敏度（P7 新增；**G1 起带模式后缀**） |
| `palmdeck_dz` | Double | 0.06 | 死区（P7 新增；**G1 起带模式后缀**） |
| `palmdeck_inv_x/y/yaw/coll` | Bool | false | 轴反向（P7 新增；**G1 起带模式后缀**） |
| `palmdeck_stick_return` | Bool | true | 摇杆回中（P7 新增） |
| `palmdeck_wheel_max_deg` | Double | 540 | 满舵角（P7 新增） |
| `palmdeck_wheel_return` | Double | 720 | 回正速度（P7 新增） |
| `palmdeck_game_profiles_v1` | Data | `[]` | 用户自建游戏预设 `[GameProfile]`（**G2 新增**；内置两个不入库） |
| `palmdeck_active_game_profile` | String | 无 | 当前生效的预设名（**G2 新增**；仅 UI 标记） |

> **G1：手感参数按模式分键。** 上表里带 *(G1)* 标记的键实际存为
> `palmdeck_dz.heli` / `palmdeck_dz.drive` / `palmdeck_dz.gamepad`（其余同理），
> 见 §12。旧的无后缀键在启动时**一次性迁移**到三个模式并删除。

---

## 11. P7 实施计划（App 交互加固）

> 目标：把手感参数变成“可调 + 可存 + 有反馈”，消除死代码与端口假设。**不改协议、不改电脑侧。**

- **P7.1 参数持久化**：`ControllerState` 参数改为 `@Published` + `UserDefaults` 读写；
  新增 `palmdeck_*` 键（§10）。
- **P7.2 手感面板**：设置新增「手感」分组——灵敏度 X/Y、死区滑条；`sensX/sensY` 接入发送曲线。
- **P7.3 触觉开关 + 卡位反馈**：设置「触觉反馈」开关；总距 IDLE/FLY/MAX 过位震；
  脚舵/方向盘过中位 `select()`。
- **P7.4 连接加固**：5s `ping` 心跳；`hello` 端口协商；发现端口透传。
- **P7.5 档位持久化**：`DriveDeck` 档位写 `palmdeck_gear`，重启/切模式保留。

**验收**：改灵敏度/死区/回中/反向 → 杀进程重开仍在；关触觉 → 全程无震动；
总距过卡位有感；切模式再切回，档位不变；`xcodebuild` 通过。

---

## 12. G1 实施：手感参数按模式分键

**要修的 bug**：上述七个手感参数（灵敏度 X/Y、死区、四个反向）此前是**三个模式共用一份**。
为飞机调出的 `dz=0.06` 会一直跟着赛车走 —— 开车本来不需要死区（ETS2 自带一份），
叠上去就是中位多一段死行程。反过来在赛车下调的参数也会污染飞机。

**键名**：`palmdeck_dz` → `palmdeck_dz.heli` / `.drive` / `.gamepad`（其余同理）。
后缀用 `CockpitMode.rawValue`（英文），不用 `label`（中文文案会变）。

**迁移**（`ShapingMigration.run`，启动时跑一次）：

1. 读到旧的无后缀键 → 把**它的值写到三个模式各自的键上**，然后删掉旧键；
2. 已经存在的新键不覆盖（用户可能已在新版里调过），旧键仍删。

> 迁移**不改变任何手感**：升级前三个模式共用一个值，迁移后三个模式各拿一份同一个值，
> 行为逐位相同。这条是迁移能安全上线的全部理由，所以它有专门的测试。

**切模式**：`CockpitController.setMode` 走 `state.applyMode(m)` —— 先换 `mode`，
再 `reloadShaping()` 读本模式那一份。`didSet` 的保存键跟着 `mode` 走，
所以写回去的就是刚读出来的那个键，不会把旧模式的参数写进新模式。

**实现位置**：`Model/ShapingKeys.swift`（纯逻辑：键名拼接、迁移、读写）、
`ControllerState.shapingStore`（**可注入**，默认 `UserDefaults.standard`；
测试注入字典替身，跑测试不碰真实偏好设置）。

**测试**（两层，缺一不可 —— 只测算法抳不住“接线错”）：

| 层 | 文件 | 测什么 |
| --- | --- | --- |
| 算法 | `tests/ios/AxisCoreTests.swift` | 键名拼接、每个旧键都搬家、不覆盖已有值、幂等、不碰无关键 |
| 接线 | `tests/ios/ControllerStateKeysTests.swift` | 真的 `ControllerState`：真跑了迁移、`applyMode` 真的换一套、写入只落当前模式的键 |
| 守卫 | `tests/test_ios_axis.py` | 全仓库不得再出现无后缀的全局手感键；`setMode` 不得绕过 `applyMode` |

---

## 12.5 G2 实施：游戏预设

**要解决的问题**：`CockpitMode` 只回答“手里拿的是什么”，不回答“在玩哪个游戏”。
同一个 `heli` 模式下，WARDOGS 要 `Z=油门`，而别的竞品要 `Z=偏航`；
ETS2 又要求**死区 0 / 线性灵敏度 / 900° 满舵**，与飞机的 0.06 死区正好相反。
换游戏原本是一套手工流程（改电脑轴表 → 回手机改反转 → 改死区 → 摆布局），漏一步就是故障。

**预设 = 电脑侧轴表名 + App 侧手感 + 布局（含按钮标签）**，用**同一个名字**把两侧对齐
（三层为何分居两侧见 `docs/PalmDeck-v4-game-profiles.md` §3.1）。

**类型与存储**（`Model/GameProfile.swift`，纯类型，只 import Foundation）：

- `GameProfile`：`name / mode / axesPreset / sensX,Y / dz / invX,Y,Yaw,Coll /
  wheelMaxDeg? / wheelReturnSpeed? / widgetsJSON?`。
  `wheel*` 为 nil 表示“不改”（WARDOGS 不动方向盘；ETS2 改成 900°）。
- 布局以**编码后的 JSON** 存在 `widgetsJSON` 里，而不是 `[DeckWidget]`：
  后者会把 `Widgets.swift`（import SwiftUI）拖进 `swiftc` 测试编译单元。
  存取走 `widgets()` / `setWidgets(_:)`。坏数据退化成空布局（不抛错）。
- `GameProfileStore`：`palmdeck_game_profiles_v1`，上限 12，内置不可删改，重名覆盖用户自建。
- 内置（`GameProfileBuiltin`）：**WARDOGS**（heli / hotas / dz 0.06，即现状固化）、
  **欧洲卡车模拟**（drive / hotas / **dz 0** / 线性 / **900°** / 720°/s）。

**应用顺序**（`GameProfileApplier.apply`，**这是本功能唯一容易写错的地方**）：

1. **先切模式**（`setMode` → `state.applyMode`，把该模式那一份手感读进来）；
2. 再写手感参数（`didSet` 的保存键跟着**新的** `mode` 走，落对键）；
3. 最后布局整表替换（`revision++` 强制画布重建，同 `applyTemplate`）。

> 写反（先手感后模式）的症状是“切了预设但手感没变”——`applyMode` 会把刚写的值覆盖回去。
> 所以顺序有专门的断言（`tests/ios/GameProfileTests.swift`）。

**UI**：设置新增分类「游戏预设」（放在「布局」上方）。顶部一行只读显示**电脑实际轴表**
（取自 `hello.axis_profile`）；下面是预设列表，点行即切换，左滑重命名/删除，
底部「将当前状态存为预设」（快照模式+手感+布局）。
**G3 之前 App 不改电脑轴表**：选中预设的 `axesPreset` 与电脑实际值不一致时给黄标提示，
文案指向“请到电脑控制台切换”——这正是降级路径，不能省。

**测试**：`tests/ios/GameProfileTests.swift`（内置定义、编解码往返、缺字段回落、
存储增删改/内置保护/上限、**应用顺序**）+ `tests/test_ios_profiles.py`（跑它，
并守卫 `GameProfile.swift` 已登记进 `project.pbxproj`）。

---

## 12.6 通用模块化：App 不再替游戏拍板按钮语义

**触发 bug**：欧卡2 里 **4→3 降档会连带亮“视角键”**。排查结论（见 `docs/PalmDeck-v4-game-profiles.md` §3.8）：

- App 侧降档 = `pulse(4)` → `X360["b5"] = LEFT_SHOULDER`（LB），升档 = `pulse(5)` → `b6 = RB`；
- 欧卡2 **默认就把 LB/RB 绑成“向左/右看”**；于是降档与切镜头共用一个物理键；
- E1 已把 App 的“视角”从 `vjoy5` 改走 `hat`（D-pad），App 内部不再撞键；
  **剩下的冲突纯粹来自“App 替用户决定了 LB=降档”**。

**设计修正（本版）**：App **只提供通用模块**（滑块 / 按键 / 摇杆 / 方向盘 / 触摸板……），
飞机与开车 **默认只有轴控件、不放任何按键**（`defaultHeli()` / `defaultDrive()`）；
按键由用户在编辑态自己添加（默认名就是中性序号「按钮 N」）、自己 `Aa` 重命名，
要发哪个键由用户在 `LibrarySheet` 里选。于是“撞键”从“App 的 bug”变成“用户的选择”，
且任何新游戏都无需改 App。

**落地范围**：

- `LayoutStore.supportsCustom(mode:)`：**三个模式都为 true**。
- `LayoutStore.defaultHeli()` / `defaultDrive()`：**只有轴、没有任何按键**。
- `CockpitView`：`gamepadBody` → `deckBody` + 通用 `moduleBody(mode:custom:fixed:)`，
  经典皮肤与画布共用编辑条 / 存模板 / 未连接横幅；顶栏 `[布局]` 按 `supportsCustom` 显示，
  编辑条里的 `[经典皮肤]` 可切回硬件皮肤（opt-in）。
- `EditableWidget`：编辑态新增 `Aa` 重命名（存 `DeckWidget.label`，留空回落默认名）。
- 新增持久化键 `palmdeck_heli_custom`（默认 **true**）、`palmdeck_drive_custom`（默认 **true**）（§10）。

**不改的部分**：`FlightDeckView` / `DriveDeck` / `GamepadDeck` 经典皮肤仍在，
作为 **opt-in**（不是默认外观）；`WidgetBinding` 与发出去的键位不变；电脑侧协议一字未动。

**回归守则**（`tests/test_deck_bindings.py`）：

- `TestDefaultHeliLayout` / `TestDefaultDriveLayout`：默认布局不得出现 `.make(.button,`，
 且不得出现“开火/投弹/起落架/…”或“左转/右转/危险灯/喇叭/手刹/雨刷/大灯/远光/换挡/升档/降档”等词；
 必须包含基本轴模块（heli：stick / slider.throttle / slider.yaw / pad；drive：wheel / slider×3 / pad）。
- `TestLayoutModuleWiring`：三个模式都支持自定义、`defaults(mode:)` 都对、`init` 都播种。
- `func_body()` 把 `defaultGamepad()` / `defaultHeli()` / `defaultDrive()` 的断言隔开。

---

## 13. 不做 / 明确边界

- 不恢复 v3 的“整机倾斜体感”“锁定/校准 HUD”（v4 为触控硬件皮肤）。
- 不做手机端游戏遥测回读（见 `docs/TODO.md`）。
- **三个模式都支持自定义模块布局**（`LayoutStore.supportsCustom(mode:)` 恒 true）。
  飞机 / 开车默认就是通用模块（只有轴、无按键）；`FlightDeckView` / `DriveDeck` / `GamepadDeck`
  作为经典皮肤 opt-in。**App 不为任何游戏硬编码按钮语义**——只提供通用模块 + 中性序号，
  含义与绑定由用户在游戏内完成（见 §12.6）。
- 不引入第三方依赖 / 不改电脑侧协议。
