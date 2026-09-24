# PalmDeck v4 · App 端功能与交互设计

> 状态：**设计稿 + P7 实施**（本文档为 iOS App 的权威交互规格）
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

### 3.2 飞机 heli — `FlightDeckView`（固定硬件）
| 区域 | 控件 | 映射 | 手势/手感 |
|---|---|---|---|
| 左 | 总距杆 `CollectiveLever` | `throttle`(→Z/collective) | 拖动把手；IDLE/FLY/MAX 刻度；抓取增量 |
| 中上 | 仪表面板 | 只读 | COLL/TRQ 弧 + 姿态球 + ROL/PIT/YAW 条 |
| 中下 | 脚舵 `RudderPedals` | `yaw`(→Rz) | 横向拖动 → 偏航；**松手 6/s 回中** |
| 右上 | 周期变距杆 `CyclicControl` | `roll`/`pitch` | 抓取增量 2D；**松手 5/s 回中**；0.95 吸附满值 |
| 右下 | 按键簇 2×3 | vJoy | 开火/投弹/起落架(脉冲 b6)/灯光/悬停/视角 |

### 3.3 开车 drive — `DriveDeck`（固定硬件）
| 区域 | 控件 | 映射 | 手感 |
|---|---|---|---|
| 左上 | `DashPanel` 转速表+档位 | 只读 | 红区红线、油门/刹车/离合/转向条 |
| 中上 | 方向盘 `SteeringWheel` | `roll`(→X) | 多圈（可调满舵 180–900°）；回正速度可调（0=保持） |
| 右 | 视角板 `LookPad` + 3×3 键簇 | `lookX/Y` + vJoy | 视角触碰板；左右转/危险灯/喇叭/手刹/雨刷/大灯/远光 |
| 左下 | 三踏板 `DrivePedals` | 离合 Y / 刹车 Sl0 / 油门 Z&RT | 独立按住，互不影响 |
| 右下 | 序列式档杆 `GearLever` | 脉冲 b6 升 / b5 降 | 拖动选档，每次换位发一次脉冲 |

档杆档位 `R N 1 2 3 4 5 6`，默认 N(=index 2)。**P7 起持久化**（`palmdeck_gear`）。

### 3.4 手柄 gamepad — `GamepadDeck` / `WidgetCanvas`
- 默认硬件皮肤 `GamepadDeck`：左摇杆(roll/pitch) · 右摇杆(look) · 十字键(hat) ·
  ABXY(vjoy1-4) · LB/RB(vjoy5/6) · 视图/菜单(vjoy7/8) · LT/RT(vjoy9/10)。
- 开关 `palmdeck_gamepad_custom`：切到 `WidgetCanvas` 自定义组件布局（P3 同步）。
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
`AxisResponseCurve.output()` **必须**与 `ControllerState.tickSmoothing()` 的
`shape(clampUnit(inv·v·sens), dz)` 逐字一致，否则预览会说谎。

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

## 7. 布局编辑与模板（仅 gamepad）

### 7.1 编辑

- 入口：顶栏 `[布局]`；首次点开自动把 `palmdeck_gamepad_custom=true`（避免“编辑了却看不到”）。
- 组件库条（编辑态顶部）：按键 / 触摸板 / 摇杆 / 方向盘 / 滑条 / 苦力帽 / 姿态球；
  有默认绑定的直接加，滑条/按键弹 `LibrarySheet` 选绑定。
- 画布操作：拖动移动、右下角手柄缩放、`✕` 删除。
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
| G9 | 模式单击即切（误触风险） | `setMode` 无防抖 | 低 | 记录，暂不改 |
| G10 | `LayoutStore` 仍为 heli/drive 生成默认布局（已不用） | `Layout.swift` defaults | 低 | 记录，暂不改 |
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
| `palmdeck_gamepad_custom` | Bool | false | 手柄用自定义布局 |
| `palmdeck_widgets_v10` | Data | defaults | 组件布局 |
| `palmdeck_layout_templates_v1` | Data | `{}` | 布局模板 `{mode: [LayoutTemplate]}`（不含内置「默认」） |
| `palmdeck_layout_undo_v1` | Data | `{}` | 撤销槽 `{mode: [DeckWidget]}`，单格/按模式 |
| `palmdeck_gear` | Int | 2 | 开车档位（P7 新增） |
| `palmdeck_haptics` | Bool | true | 触觉开关（P7 新增） |
| `palmdeck_sens_x/y` | Double | 1.0 | 灵敏度（P7 新增） |
| `palmdeck_dz` | Double | 0.06 | 死区（P7 新增） |
| `palmdeck_inv_x/y/yaw/coll` | Bool | false | 轴反向（P7 新增） |
| `palmdeck_stick_return` | Bool | true | 摇杆回中（P7 新增） |
| `palmdeck_wheel_max_deg` | Double | 540 | 满舵角（P7 新增） |
| `palmdeck_wheel_return` | Double | 720 | 回正速度（P7 新增） |

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

## 12. 不做 / 明确边界

- 不恢复 v3 的“整机倾斜体感”“锁定/校准 HUD”（v4 为触控硬件皮肤）。
- 不做手机端游戏遥测回读（见 `docs/TODO.md`）。
- `gamepad` 之外的模式不做自定义布局（硬件皮肤固定，保证真机手感一致）。
- 不引入第三方依赖 / 不改电脑侧协议。
