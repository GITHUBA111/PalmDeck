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
    ├─ 顶栏：模式段(3) · 连接胶囊 · 设置齿轮 · [布局]
    ├─ 皮肤：三个模式**共用一块通用组件画布** `WidgetCanvas`（引擎内无任何固定皮肤）
    ├─ 底栏 statusStrip：`HudReadout` 按模式取字段（飞机 横滚/俯仰/方向/总距，开车 转向/离合/油门/刹车，手柄 摇杆X/摇杆Y/视角X/视角Y）· LINK(hz) · MODE · SRC
    ├─ ⌘ 设置 → SettingsView（双栏：连接 / 预设 / 布局 / 操纵与手感 / 触觉 / 外观 / 帮助）
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
- 右栏：三步卡片（电脑装好 → 同 Wi-Fi → 进座舱）+「可用电脑（点一下连接）」列表 + 「设置」折叠。
  （P2 前文案是「发现的电脑」「高级设置」，见 §12.15。）
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
- 橙色胶囊 `connectionBannerRow`：点一下即连最佳主机。
  它现在是**画布上方的一行**（VStack 占位），不是浮层 —— 浮层会盖住下面的组件，
  那些组件既点不动也拖不动（画布还在浮层下面接着手势）。详见 §12.10。

**规格**
| 状态 | 顶栏 | 画布上方横幅 | 触觉 |
|---|---|---|---|
| idle 未发现 | 「连接」灰 | 「未连接电脑（先在电脑启动 PalmDeck）」 | — |
| idle 已发现 | 「一键连接」绿 | 「点此连接电脑 <ip>」 | tap |
| connecting | 「连接中…」+ 菊花 | 青色「正在连接…」（同行高，不可点） | — |
| live | 绿点 ip + Hz | 无（画布**平滑**变高） | success |
| lost | 「连接中…」重试 | 橙胶囊（可点重连） | warning |

> **行高恒定**：横幅整行高度钉死在 `deckTopRowH`（32pt），`idle` 与 `connecting`
> 完全一致；只有 `live` 才收成 0（带 0.22s 动画）。否则「点按 → connecting → 横幅消失 →
> 画布变高 → 组件按归一化坐标重排」会看成「点一下其它组件全闪了」。
> 详见 §12.19 与 `PalmDeck-v4-connect-banner-stable.md`。

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
- 三个模式都显示右侧 `[布局]` 按钮（引擎里已无固定皮肤）。

> 遗留议题（见 §10）：v3 曾要求“按住 400ms 防误触”。v4 改为单击；
> 是否恢复长按见 P7 backlog（默认不改，避免影响习惯）。

### 3.2 飞机 heli — 通用模块（只有轴）

默认布局 `defaultHeli()`：**只放轴控件、不放任何按键**。

| 组件 | 绑定 | 说明 |
|---|---|---|
| 仪表盘 `panel` | 无（只读） | COLL/TRQ 弧表 + 姿态球 + ROL/PIT/YAW 杆位条；读本机平滑杆位，不读游戏遥测、不绑定任何键 |
| 周期杆 `stick` | `roll` / `pitch` | 2D 摇杆，抓取增量，松手回中 |
| 总距 `slider` | `throttle` | 单极滑条 |
| 脚舵 `slider` | `yaw` | 双极滑条 |
| 视角 `pad` | `look` | 触摸板 |

按键完全由用户自己添加、命名、绑定（见 §12.6）。仪表盘是**只读显示**，不带任何游戏语义，
所以默认留下；不想要就 `✕` 删掉。

### 3.3 开车 drive — 通用模块（只有轴）

默认布局 `defaultDrive()`：**只放轴控件、不放任何按键**。

| 组件 | 绑定 | 说明 |
|---|---|---|
| 方向盘 `wheel` | `roll` | 多圈（可调满舵 180–900°）；回正速度可调（0 = 保持） |
| 三踏板 `slider` | `clutch` / `brake` / `throttle` | 三根单极滑条 |
| 视角 `pad` | `look` | 触摸板 |

换档 / 转向灯 / 危险灯……由用户自己加按键、在游戏内自己绑。

> 为何不内置「左转/降档」这类按钮：同一只虚拟手柄在不同游戏里默认占用完全不同，
> App 替用户拍板的每一条语义都可能与游戏默认撞车（如欧卡2 默认 LB = 向左看）。
> 症状与修法见 §12.6。

### 3.4 手柄 gamepad — 通用模块 + Xbox 起步布局

默认布局 `defaultGamepad()` 给出一套 Xbox 手柄起步布局：
左摇杆(`roll`/`pitch`) · 右摇杆(`look`) · LT/RT 滑条 · ABXY(`vjoy1`-`4`) · LB/RB(`vjoy5`/`6`) ·
视图/菜单(`vjoy7`/`8`) · L3/R3(`vjoy9`/`10`) · 十字键(`hat`)。
全部可在编辑态拖动 / 改名 / 改绑（`vjoy9`/`10` **不是** LT/RT：Xbox 的 LT/RT 是模拟轴
`lt`/`rt`；`X360["b9"]=LEFT_THUMB`、`X360["b10"]=RIGHT_THUMB`）。
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
| 连接 | 电脑 / 可用电脑 / — | 电脑、状态胶囊、断开连接、当前电脑高亮、上次主机、返回启动页 | — |
| 预设 | 电脑 / 预设 | 电脑当前轴表（只读）；预设列表（内置「默认」一行 + 整机 / 布局）+ 存为整机预设 / 存为布局预设 | ✅ `palmdeck_game_profiles_v2`（P1.5 起） |
| 布局 | 编辑 / 重置 / 撤销 / 与电脑同步 | 编辑布局开关 + 放弃本次编辑；清空画布；撤销上一次改动；从电脑拉取 / 上传当前模式 | — |
| 操纵与手感 | 轴反向 / 摇杆 / 灵敏度与死区 / 响应曲线 / **方向盘（全局项）** | 横滚 / 俯仰 / 方向舵 / 总距；松手回中；灵敏度 X / Y、死区（点值精确输入）；双轴响应曲线预览；满舵角度 / 回正速度（点值精确输入） | ✅ `invX/invY/invYaw/invColl`、`stickReturn`、`sensX/sensY/dz`、`wheelMaxDeg/wheelReturnSpeed` |
| 触觉 | 触觉反馈 | 开启振动 + 「试一下振动」 | ✅ `palmdeck_haptics` |
| 外观 | 主题 | 外观模式（跟随系统 / 浅色 / 深色） | ✅ `palmdeck_appearance`（默认浅色） |
| 帮助 | 教程 / 关于 | 查看使用教程；App 版本、当前模式 | `palmdeck_tutored` |

> 历史问题（已修）：轴反向/摇杆/方向盘这些参数此前是**普通 `var`，既不 `@Published` 也不落盘**，
> 重启即丢、开关可能不刷新。P7 统一改为持久化（见 §11）。

---

## 7. 布局编辑与模板（全部模式）

### 7.1 编辑

- 入口：顶栏 `[布局]`（三个模式都有）。
- 组件库条（编辑态顶部）：按键 / 触摸板 / 摇杆 / 方向盘 / 滑条 / 苦力帽 / 姿态球 / 仪表盘；
  有默认绑定的直接加，滑条/按键弹 `LibrarySheet` 选绑定（只读的「仪表盘」跳过绑定选择）。
  弹窗里的绑定下拉**只列该类型真正会用的项**（滑条→轴、按键→vJoy 键），且从被点的类型起，
  见 §12.17。
- 画布操作：拖动移动、右下角手柄缩放、左上 `✕` 删除、右上 `Aa` **重命名**
  （名称留空回落绑定的默认名，如「按钮 3」；名称只存本机，不改变发出去的键位）。
  两个手势都写在 `DragGesture(coordinateSpace: .global)` 上 —— 组件自己会跟着手指跑，
  在 `.local` 里量位移会被抵掉一半（组件总追不上手指），详见 §12.11。
- **拖动会吸附并画出对齐线**：靠近画布的边/中线、或别的组件的边/中心（7pt 以内）时自动吸住，
  并在吸住的位置画一条细线（松手即消失）；中心只吸中心、边只吸边，不跨类。
  同时**不许把组件拖出画布**：任何方向至少留 40pt 在画布里，`✕` / `Aa` 永远够得着。详见 §12.13。
- **组件库条右侧**：`存为预设`（快照当前布局成一个「布局」预设，弹命名框）／ `⋯`（恢复默认布局 / 清空画布 /
  撤销上一次改动）／ `放弃` ／ `完成`。
  三个整表操作以前只在设置里，现在编辑条上就够得着（见 §12.12）。
- **编辑会话与「放弃」**：进入编辑（顶栏 `[布局]` 或设置里的「编辑布局」）时把当前布局
  快照成 `editBaseline[mode]`（只存内存）；编辑是立刻落盘的，所以只靠「撤销槽」反悔不了
  （它只覆盖 `清空`/`恢复默认`/`应用预设`/`添加`/`删除` 这类整表操作；拖动与改名不压槽）。
  - `放弃`（红，`Theme.red`）= 整表回滚到进入编辑前 + 退出编辑，**不进撤销槽**
    （它本身就是一次回退，再叠一层「撤销放弃」只会绕）。
  - 没动过东西时 `canDiscardEditing` 为 false，按钮变淡（0.35）不可点。
  - `完成` / 顶栏 `[完成]` / 换模式 = `commitEditing`，只丢掉回滚点，改动保留。
  - 「有没有改过」用 `sameShape`（比 `kind/binding/rect/label`）——`DeckWidget` 的合成
    `Equatable` 含 `UUID`，每次重建都变，不能用 `==`。
- 组件库条左侧的「添加」一行是横向 `ScrollView`：组件越加越多，窄屏（iPhone 竖屏）也不会挤成一团；
  `存为预设/⋯/放弃/完成` 四个动作按钮固定在右侧不参与滚动。
- **空画布不是白板**：当前模式一个组件都没有时，画布中间显示「画布是空的」+ 下一步提示
  （编辑态指上方「添加：」，非编辑态指顶栏「布局」/`⋯`）。该层 `allowsHitTesting(false)`。
- 同步：`layouts_get` / `layouts_put`（WS 控制面）；服务端下发 → `LayoutStore.applyServer`。
- 存储键 `palmdeck_widgets_v10`（`{mode: [DeckWidget]}`）。
- `CardButton` 读 `@Environment(\.isEnabled)`（不可用时 `opacity 0.35`）——编辑条上的 `放弃` 靠它表达状态。

> ⚠️ 曾在 `WidgetCanvas` 的 `.overlay(.topTrailing)` 里放过「完成 / 清空 / 存为模板」。
> 那是**死 UI**：`CockpitView` 的组件库条是 ZStack 后绘制的兄弟节点，会把它整个盖住。
> 编辑类按钮一律放组件库条里。

### 7.2 命名快照：统一到「预设」（原「模板」已并进来）

问题：每个模式只有一份布局，`清空` / `恢复默认` 都是不可逆覆盖 → 需要命名快照。
原来有**两套**：设置 → 游戏预设（模式 + 手感 + 可选布局）与
设置 → 布局 → 模板（`(name, [DeckWidget])`，按模式归类）。两套都是「命名快照」，
却各存各的键、各有一套 UI —— 用户得在两个分类里找「我上次存的那套」。

**现在只有一处：设置 → 预设**。一个概念两种形态（`: 整机 / 布局`），
「模板」这个词从 UI 与代码里删干净（`LayoutTemplate` 类型已不存在）。
完整方案与迁移见 `docs/PalmDeck-v4-unified-presets.md`；结论如下：

- **内置「默认」不再是一个类型**，而是列表里一行只读的「布局」预设，
  点了走 `LayoutStore.applyDefault(mode:)`（直接取 `defaults(mode:)`，不入库）。
- **「布局」预设只在自己那个模式下出现**（它存的就是那套面板，模式间可用轴/组件并不对等）；
  所以它**不**算进跨模式切换的候选。
- 撤销槽：`清空` / `应用预设的布局` / `恢复默认` 执行前压入；设置页与编辑条 `⋯` 里的「撤销」都能回退。
- 上限：24 个（原预设 12 + 模板 12），名称 ≤16 字符、非空、不得叫「默认」（内置还原点保留名），
  不得用内置预设名；重名覆盖。
- **旧键只读**：`palmdeck_game_profiles_v1` + `palmdeck_layout_templates_v1` 在 v2 不存在时
  一次性合并进 `palmdeck_game_profiles_v2`（幂等：v2 一旦存在就不再跑，否则删掉的会复活）。

**判定形状用 `sameShape`（`isCurrentLayout` 与编辑会话共用一份实现），不能直接 `==`**：`DeckWidget.make`（`Widgets.swift:76`）每次生成新 `UUID`，
而 `Equatable` 是合成实现、包含 `id`——内置默认回回重建都是新 id，用 `==` 永远比不等。
`sameShape` 只比 `kind / binding / rect / label`（顺序敏感），因此「默认」和内容相同的自建布局预设会**同时**打「当前」，这是对的。

**整表替换必须重建画布**：`applyDefault` / `applyProfile`（换布局时）/ `undoLast` / `clear` 走 `replaceWidgets`，
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
| G8 | 档位不持久化，切模式归零 | `DriveDeck` `@State gearIndex` | 中 | ✅ P7.5 落盘；**E2 起 `DriveDeck` 已删，档杆由用户自组** |
| G9 | 手感参数三模式共用一份 | `ControllerState` 全局键 | **高** | ✅ **G1** 按模式分键 |
| G9 | 模式单击即切（误触风险） | `setMode` 无防抖 | 低 | 记录，暂不改 |
| G10 | `LayoutStore` 仍为 heli 生成默认布局（heli 无自定义布局） | `Layout.swift` defaults | 低 | ✅ **E2** 三模式统一为通用模块 |
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
| `palmdeck_widgets_v10` | Data | defaults | 组件布局 |
| `palmdeck_layout_templates_v1` | Data | `{}` | ~~布局模板~~ **已废弃（只读）**：一次性迁进 `palmdeck_game_profiles_v2`，见 `docs/PalmDeck-v4-unified-presets.md` |
| `palmdeck_game_profiles_v1` | Data | `[]` | ~~游戏预设~~ **已废弃（只读）**：同上 |
| `palmdeck_game_profiles_v2` | Data | `[]` | 预设（整机 / 布局两种形态）`[GameProfile]` |
| `palmdeck_layout_undo_v1` | Data | `{}` | 撤销槽 `{mode: [DeckWidget]}`，单格/按模式 |
| ~~`palmdeck_gear`~~ | ~~Int~~ | — | 已废弃：`DriveDeck` 随 E2 删除，档位改由用户自组 |
| `palmdeck_haptics` | Bool | true | 触觉开关（P7 新增） |
| `palmdeck_sens_x/y` | Double | 1.0 | 灵敏度（P7 新增；**G1 起带模式后缀**） |
| `palmdeck_dz` | Double | 0.06 | 死区（P7 新增；**G1 起带模式后缀**） |
| `palmdeck_inv_x/y/yaw/coll` | Bool | false | 轴反向（P7 新增；**G1 起带模式后缀**） |
| `palmdeck_stick_return` | Bool | true | 摇杆回中（P7 新增） |
| `palmdeck_wheel_max_deg` | Double | 540 | 满舵角（P7 新增） |
| `palmdeck_wheel_return` | Double | 720 | 回正速度（P7 新增） |
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
- **P7.5 档位持久化**：~~`DriveDeck` 档位写 `palmdeck_gear`~~（E2 起该皮肤已删，不再适用）。

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
- `GameProfileStore`：`palmdeck_game_profiles_v2`，上限 24，内置与保留名「默认」不可用，重名覆盖用户自建。
- 内置（`GameProfileBuiltin`）：**WARDOGS**（heli / hotas / dz 0.06，即现状固化）、
  **欧洲卡车模拟**（drive / hotas / **dz 0** / 线性 / **900°** / 720°/s）。

**应用顺序**（`GameProfileApplier.apply`，**这是本功能唯一容易写错的地方**）：

1. **先切模式**（`setMode` → `state.applyMode`，把该模式那一份手感读进来）；
2. 再写手感参数（`didSet` 的保存键跟着**新的** `mode` 走，落对键）；
3. 最后布局整表替换（`revision++` 强制画布重建，同 `applyTemplate`）。

> 写反（先手感后模式）的症状是“切了预设但手感没变”——`applyMode` 会把刚写的值覆盖回去。
> 所以顺序有专门的断言（`tests/ios/GameProfileTests.swift`）。

**UI**：设置新增分类「游戏预设」（放在「布局」上方）——**P1.5 起该分类改名「预设」**（它同时装整机与布局预设），
**P2 起侧栏固定 7 项**（`连接 / 预设 / 布局 / 操纵与手感 / 触觉 / 外观 / 帮助`，见 §12.15）。
顶部一行只读显示**电脑实际轴表**
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

**落地范围**（分两步：E2 → E2 续）：

- `LayoutStore.defaultHeli()` / `defaultDrive()`：**只有轴、没有任何按键**；
  飞机额外带一块**只读**仪表盘 `panel`（`Views/FlightPanel.swift`，
  纯显示、无手势、无绑定）；
  `defaultGamepad()` 保留一套 Xbox 起步布局（ABXY/LB-RB/摇杆/扳机轴）。
- `LayoutStore.supportsCustom(mode:)`：**已删除**——引擎里不再有「固定皮肤」可供切换。
- `Views/FlightDeck.swift` / `DriveDeck.swift` / `GamepadDeck.swift`：**整份删除**。
  仍然需要的仪具（姿态球 / 苦力帽 / 方向盘 / 摇杆……）以组件形式留在
  `Widgets.swift` / `Controls.swift` / `AttitudeBall.swift` / `SteeringWheel.swift`。
- `CockpitView`：`deckBody` 直接渲染 `WidgetCanvas`，不再有「皮肤 ⇄ 画布」分支；
  编辑条里的 `[经典皮肤]` 按钮也一并移除。
- `SettingsView`：布局分类不再区分模式，不再有「使用自定义组件布局」开关与
  heli/drive 的「不支持自定义布局」锁定提示。
- `EditableWidget`：编辑态 `Aa` 重命名（存 `DeckWidget.label`，留空回落默认名）。
- 删除持久化键 `palmdeck_gamepad_custom` / `palmdeck_heli_custom` / `palmdeck_drive_custom`
  以及随皮肤删除而失效的 `palmdeck_gear`。

**不改的部分**：`WidgetBinding` 与发出去的键位不变；电脑侧协议一字未动。

**回归守则**（`tests/test_deck_bindings.py`）：

- `TestDefaultHeliLayout` / `TestDefaultDriveLayout`：默认布局不得出现 `.make(.button,`，
 且不得出现“开火/投弹/起落架/…”或“左转/右转/危险灯/喇叭/手刹/雨刷/大灯/远光/换挡/升档/降档”等词；
 必须包含基本轴模块（heli：stick / slider.throttle / slider.yaw / pad；drive：wheel / slider×3 / pad）。
- `TestNoFixedSkins`：三个皮肤文件不得存在；`CockpitView` 必须渲染 `WidgetCanvas`，
  且不得再出现 `FlightDeckView` / `DriveDeck` / `GamepadDeck` / `经典皮肤`；
  代码里不得残留 `palmdeck_*_custom` 开关。
- `TestInstrumentPanel`：`WidgetKind.panel` 存在且 `isReadOnly`；`FlightPanel.swift`
  必须有 `ArcGauge` / `BarGauge` / `FlightPanel`，且**不得**出现 `DragGesture` / `@Binding` /
  `onButton?(` / `btnMask`（只读）；组件库有入口；`project.pbxproj` 有登记。
- `TestDefaultHeliLayout::test_keeps_the_readonly_instrument_panel`：飞机默认布局必须含
  `.make(.panel, .roll, ...)`。
- `TestEditSession`：`LayoutStore` 有 `beginEditing` / `canDiscardEditing` / `discardEditing` / `commitEditing`；
  `beginEditing` 记 `editBaseline[mode.rawValue]`；`discardEditing` 走 `replaceWidgets` 且**不得**调 `pushUndo`；
  `commitEditing` 不得 `replaceWidgets`；`canDiscardEditing` 用 `sameShape`；座舱编辑条有 `Button("放弃")`
  与 `.disabled(!layout.canDiscardEditing(mode: s.mode))`；顶栏与设置两个入口都 `beginEditing`；
  离开编辑态的路径（完成 / 顶栏 [完成] / 换模式）至少 3 处 `commitEditing`。
- `TestLayoutModuleWiring`：`defaults(mode:)` 三个模式都对、`init` 都播种。
- `TestThemeAppearance`：`Theme` 必须有 `Color.pd(浅,深)` 动态色助手且 18 个主题色都给了两套值；
  视图层不得出现 `preferredColorScheme(.dark)` / `(.light)`；`AppAppearance` + `palmAppearance()`
  必须同时落在根视图与三个 presentation（sheet/cover 不一定继承窗口 override）；
  外观分类要进 `SettingsCategory` 与搜索索引；仪表固定色（`instr*`/`hud*`）不得用 `Color.pd(`。
- `func_body()` 把 `defaultGamepad()` / `defaultHeli()` / `defaultDrive()` 的断言隔开。

---

## 12.7 浅色 / 深色双主题（默认浅色）

**背景**：整套界面原来只有一套写死的暗色调色板，再加 4 处 `.preferredColorScheme(.dark)`，
在亮环境（户外、白天开车）下反光严重。改为**双主题 + 可切换**。

**做法**：把「主题」做成一次查表，而不是往 120 个引用点里插 `@Environment(\.colorScheme)`。

```swift
enum Theme {
    static let panel = Color.pd(Color(red: 1, green: 1, blue: 1),        // 浅色：白卡片
                                Color(red: 0.11, green: 0.15, blue: 0.21)) // 深色：原值
}
```

`Color.pd(_:_:)` 走 `UIColor(dynamicProvider:)`（`#if canImport(UIKit)` 守，iOS + Mac Catalyst 都适用），
系统按 `traitCollection.userInterfaceStyle` 自动解析——**视图层一行都不用改**，主题切换也不需要
任何全局可变状态。浅色侧的强调色整体压深一档（否则白底对比度不够）：

| 语义 | 浅色 | 深色 |
|---|---|---|
| cyan（主强调） | `#007AB0` | `#33D1FF` |
| green（连接/确认） | `#0E8B4A` | `#4DDB80` |
| orange（编辑/注意） | `#CD6F00` | `#FF9E33` |
| red（危险） | `#CD2928` | `#FF5C5C` |
| panel / panelHi / border | `#FFFFFF` / `#F2F6FA` / `#BDC9D7` | 原值 |
| text / textDim / textFaint | `#0E1724` / `#47556B` / `#5F6D80` | 原值 |

**外观开关**：`AppAppearance`（`system` / `light` / `dark`，键 `palmdeck_appearance`，
**默认 `.light`**），设置新增分类「外观」（靖蓝图标，排在「方向盘」后）→ 内联 `Picker`；
搜索词「外观 / appearance / 主题 / theme / 深色 / 浅色 / 夜间」都能命中。

**落到哪里**：`.palmAppearance()` 是个读 `@AppStorage` 的 `ViewModifier`，只抛 `preferredColorScheme`。
它必须挂在**根视图**（`PalmDeckApp` 的 `WindowGroup` 内容包一层 `Group`）**以及**
`CockpitView` / `PreflightView` / `SettingsView` 三处——sheet / `fullScreenCover` 不保证
继承窗口的 override，漏一处就会出现“外面浅色、弹窗黑底”。

**仪表是例外（故意不跟随）**：姿态球是真仪表，白底上放一块黑表盘反而更像真机也更清楚，
所以它用一组**固定色**（`Theme.instrBg` 天/地渐变、`instrLine`、`hudAmber`、`hudOrange`）。
`ArcGauge` / `BarGauge` 不在此列——它们只读 `Theme.border` / `panelHi` / 强调色，跟着主题走反而更好看。

**未动**：`Model/` 一层与电脑侧协议完全没碰（`swiftc` 单测也只编 `Model/`，所以主题改动不影响纯逻辑层）。

---

## 12.8 刷新策略：变了才发布（待机不烧 CPU）

**背景**：座舱里「姿态球 / 仪表盘 / 状态条」的数值只有一个来源——手机**本地平滑后的杆位**
`smRoll/smPitch/smYaw`。它们由 `CADisplayLink`（60~75Hz）在 `tickSmoothing()` 里逐帧更新。

坑在于 SwiftUI 的 `@Published` **不做等值去重**：赋一次值就让所有观察者重建一次视图。
热路径上无脑写一个 `@Published` 字段，等于把「什么都没发生」也变成每秒几十次全树重绘。
原来的代码正是如此：`CockpitController` 里有个每 6 帧写一次的 `readout` 字符串
（**全工程没有任何地方读它**，是 v3 留下的死字段），它实际充当了刷新心跳。

实测（Mac Catalyst，未连接、手不碰）：

| 状态 | 修前 | 修后 |
|---|---|---|
| 启动页 | 12~13% CPU | 1.2~1.3% |
| 座舱（默认布局） | 13~15% | 1.3~1.7% |
| 座舱 · 按住方向不动（= 开车保持角度） | — | 1.3~1.4% |
| 座舱 · 持续拖动方向盘 | — | 24~35% |

**规则（改热路径前先读这条）**：

1. `sm*` 是 `@Published`（界面唯一数据源），但**只经 `applySm()` 写回**，
   变化小于 `smEpsilon = 1e-4`（满量程比，姿态球上 0.036°）就不赋值。
   收敛尾巴不值得继续重绘。
2. 热路径上**禁止**再引入「每帧赋值的 `@Published`」当心跳——要发布就发布真值本身，
   并且发布前先和旧值比一比。
3. 代价**只跟「有没有在动」成正比**：手没碰 = 0 次发布；手在拖 = 满帧率。
   这比「固定 10Hz 心跳」两头都更好：待机不发热，动起来反而更顺（原来是 10Hz）。

**副作用**：`readout` / `pfMotionState` 两个死字段随本次一并删除。
若以后真要在界面上显示数字读数，请直接读 `state.smRoll` 等，别再另开一个字符串心跳。

**已知后续（未做）**：持续拖动时 24~35% 的成因是「整棵座舱视图树（含画布上所有组件）
都在观察 `ControllerState`」。想再压一半，得把姿态拆成独立的小 `ObservableObject`，
只让姿态球 / 仪表盘 / 状态条观察它——需要改动每个组件的传入方式，等真有热感再说。

---

## 12.9 状态条按模式取字段：显示的就是发出去的

**背景**：底栏原来三个模式共用一套写死的 `ROL/PIT/YAW/THR`，可它显示的并不是同一件事：

- **开车模式 `Rz` 恒为 0**（离合改走左摇杆 Y），状态条却照旧写着「方向」；
- **手柄模式 `thr/lt/rt` 全清零**（防误触油门），状态条却照旧写着「油门」；
- 单位也是错的：`ROL +0.1°` 里的 `0.1` 是**归一化杆位**，不是角度。

「界面说的」和「真正发出去的」对不上，正是 E1 修过的那一类问题（同一个 bug 的另一个出口）。

**做法**：把「按模式显示哪几格」抽成 `Model/HudReadout.swift`（纯函数，`swiftc` 可直测），
喂给它的是 `AxisMap.resolve(...)` 的输出，也就是 `Packet.pack` 真正写进字节的那 8 个轴：

```
ControllerState.wireAxes   ← 唯一的真值表调用点
   ├─ Packet.pack()        （发出去）
   └─ HudReadout.axis()    （显示出来）
```

| 模式 | 显示 | 不显示 |
|---|---|---|
| 飞机 | 横滚 / 俯仰 / 方向 / 总距 | 视角、左右扳机（不常用） |
| 开车 | 转向 / 离合 / 油门 / 刹车 | **方向**（`Rz` 恒 0） |
| 手柄 | 摇杆X / 摇杆Y / 视角X / 视角Y | **油门 / 刹车 / 总距**（恒 0） |

**格式**：双极轴 `+0.32`（两位小数，**不带 `°`**；小于 `0.005` 一律显示 `+0.00`，
免得自回中残留的 `-1e-5` 打印成看着像有信号的 `-0.00`）；单极轴 `35%`。

**约束（测试会拦）**：`AxisMap.resolve` 全工程只允许在 `ControllerState.wireAxes` 里出现一次；
`Packet.pack` 与状态条都读它。两边各算一遍，就又会分家。

---

## 12.10 盖在画布上的东西改成占位（看得见的都能摸到）

**背景**：座舱主体原来是 `ZStack { 画布; 编辑工具条 }` + `.overlay(alignment: .top) { 未连接横幅 }`。
浮层本身只有胶囊那点高，但它压在画布上：被盖住的组件**既点不动也拖不动**
（手势先落到浮层上），而且看不出“那里还有东西”。默认布局从 `y = 0.10` 起，
就是为了躲这条横幅 —— 躲得越干净，越说明那个位置本该能用。

**做法**：`deckBody` 改成 `VStack`：横幅 / 编辑工具条各占**一行**，画布拿剩下的高度。

```
VStack(spacing: 0) {
    if editing { editBar } else { notConnectedBanner }   // 占位（可能高 0）
    WidgetCanvas(...)                                    // 剩下的全是画布
}
```

- 不再有“看不见却存在”的禁区，画布里的每个像素都属于某个组件。
- 画布高度只在「连上 / 断开」「进 / 出编辑」时变，组件是归一化坐标，跟着画布一起缩放。
- 编辑工具条不再需要 `Spacer` 撑满整屏（它以前其实盖住了整个画布顶部）。

**没跟着改的**：三个默认布局仍从 `y = 0.10` 起。这个值原来是为了躲横幅，
现在只是普通顶部留白 —— 但**已经装过的用户存在本地的是同一个数**，
改默认值会让新装和旧装长得不一样，所以保持不动（视觉上也确实需要一点边距）。

---

## 12.11 拖拽/缩放用 `.global`：组件要跟得上手指

`EditableWidget` 的拖动与缩放把手原来都是 `DragGesture()`（默认 `.local`，即**手势视图自己的**
坐标空间）。而同一次拖动里，这个视图正随着手指移动 —— 于是同一根手指的位移被抵消掉一半：

```
translation = (手指位移) - (视图已走的距离)    →  稳态：视图只走到手指的一半
```

实测（Mac Catalyst，拖「视角」组件，手指从 `(1136,305)` 移到 `(930,500)`，位移 `(-206,+195)`）：

| | 落点 | 实际位移 | 比例 |
|---|---|---|---|
| `.local`（修前） | `(1055,377)` | `(-81,+70)` | ≈ 37% |
| `.global`（修后） | `(915,501)` | `(-221,+196)` | ≈ 100%（差在目测读数） |

修法：两个手势都写 `DragGesture(coordinateSpace: .global)`。`.global` 是固定的窗口坐标系，
视图怎么动都不影响量出来的位移。

**注意**：这条只适用于「会被自己拖动」的视图。`Controls.swift` / `SteeringWheel.swift`
里的滑条/摇杆/方向盘都是固定大小、只动内部指针，用 `.local` 是对的，不要顺手全改。

`TestCanvasEditGesturesUseGlobalSpace` 守卫（钉死 `EditableWidget` 里两个手势都是 `.global`）。

---

## 12.12 整表操作别藏起来，空画布要说人话

**背景**：`清空当前模式` / `恢复默认布局` / `撤销上一次改动` 三件事只在
设置 → 布局 里 —— 可改布局的人就在座舱编辑态，得先「完成」退出、再进设置、再回来。
而这恰好是最想用的三个（手滑拖乱了要重来、清空重摆、后悔一步）。

**做法**：编辑条上「存为预设」旁边加一个 `⋯` 菜单（三行：恢复默认布局 / 清空画布 / 撤销上一次改动）。

- **不做二次确认**：`clear` / `applyDefault` 各自会压一道撤销槽（`pushUndo`），当场就能后悔；
  而且「放弃」也能一键回到进编辑前的状态。跟设置页一致（那里也只是 `role: .destructive` 红字，没弹窗）。
- **没得撤销就置灰**（`.disabled(!canUndo)`），不是点了没反应。
- 菜单里的撤销 = 回到上一次**整表操作**前（应用预设 / 清空 / 恢复默认）。
  拖拽与增删**不进**撤销槽（要保持拖动流畅，见 §12 开头的 `revision` 说明），
  这种细粒度反悔用「放弃」。

**配套：空画布要有提示**（原来清空、或把最后一个组件拖走后就是一块白板，
看不出「本来就空」和「没加载出来」的区别）：

| 状态 | 画布中间显示 |
|---|---|
| 编辑态且为空 | `画布是空的` + 「点上方「添加：」放一个组件；拖动移动、拖右下角缩放、✕ 删除」 |
| 非编辑态且为空 | `画布是空的` + 「点顶栏「布局」开始添加，或进「⋯」恢复默认布局」 |

提示层 `allowsHitTesting(false)`：它只是个占位，不抢画布手势。

**顺带把「✕ 误删」变成能后悔**：`add` / `remove` 也各压一道撤销槽。`✕` 只有 22pt，
而且就在「抓组件拖拽时手会按到的左上角」，原来删错了只能靠「放弃」（一旦点了「完成」就无从挽回）。
拖动 / 改名走 `update`，是高频调用，仍然不压槽。

实测（Mac Catalyst）：`⋯` 菜单三项正确（两个整表项红字，无撤销槽时「撤销」置灰）→
清空后画布出现空态提示 → `⋯` → 恢复默认布局，方向盘 / 视角 / 三个滑条回来、提示消失。

---

## 12.13 拖拽吸附与对齐线（组件能摆齐，也拖不丢）

方案：`docs/PalmDeck-v4-drag-snap.md`（P1.7）。规则落在 `Model/Snap.swift`（纯函数、`swiftc` 单测），
`Views/Layout.swift` 只做坐标换算与接线。

**为什么值得做**：摆布局是 App 里唯一需要「手工对准」的活。原来两个滑条要对齐只能目测，
差 3~5pt 完全看不出来；而「居中」得猜中线在哪。更麻烦的是 `WRect` 是归一化坐标、
代码里没有任何夹取 —— **组件可以被拖到画布外面**，那时 `✕` / `Aa` / 缩放手柄都不在可视区，
只能「放弃编辑」或整表回滚。

**规则**（每个轴各吸一条最近的，两轴独立）：

| 类 | 候选线 | 被吸的锚点 |
|---|---|---|
| 边 ↔ 边 | 画布左/右（上/下），其它组件的 left/right（top/bottom） | 本框 left/right（top/bottom） |
| 中心 ↔ 中心 | 画布中线，其它组件的 centerX/centerY | 本框 centerX/centerY |

- 阈值 **7pt**：吸得住但不会「怎么拖都不动」。大于 7pt 一律不吸。
- **中心绝不吸别人的边**。看着像吹毛求疵，实测会被坑：两个同宽滑条并排想「左对齐」时，
  本框中心到对方右边缘的距离比左边缘差更小 —— 结果被「中心-右边缘」抢走，屏幕上就是歪的。
- 吸附基于「**本次拖动的起点 + 位移**」，不是「上一次吸附后的位置」：所以往回拖会自然脱吸，不粘。
- **夹住不许拖丢**：任何方向至少留 40pt（≈一根手指）在画布内。夹取改掉了落点时，
  **对应那条对齐线也要撤掉** —— 否则屏幕上会出现「线在一边、组件在另一边」的假对齐。
- 对齐线是 `LayoutStore` 的**瞬时**状态（`guidesX/guidesY`），不落盘、值变才发布；
  退出编辑自动清空（不能留下一条线）；渲染层 `allowsHitTesting(false)`。
- 缩放**不**吸附、**不**夹取（本次有意不做：缩放越界时组件仍在可视区，出得来）。

实测（Mac Catalyst，逐次落盘后读回 `palmdeck_widgets_v10` 比对，画布 ≈ 998×756pt）：

| 场景 | 算出来的落点 | 实际落点 |
|---|---|---|
| 中心离画布中线差 10pt（超阈值） | 0.4098 | **0.4098**（不吸，纯算术值）|
| 油门左边缘离刹车左边缘差 3pt | 0.4127 | **0.4098**（吸住，与刹车 x 完全相等）|
| 视角中心离画布中线差 4pt | 0.4260 | **0.4300**（吸住，中心正好 0.5000）|
| 中心对着「别人的边」差 4pt（跨类） | 0.5098 | **0.5133**（不吸）|

因为 `≪把手会跟着手指跑≫`，这俩手势用的是 `.global`（§12.11）；
而 `Snap` 里**必须排掉自己**（`filter { $0.id != widget.id }`）——否则每个组件都被自己吸住，怎么拖都不动。

---

## 12.14 「模板」并进「预设」：一个概念，两种形态（P1.5）

方案：`docs/PalmDeck-v4-unified-presets.md`。

**问题**：到 P1.7 为止，App 里有两套「命名快照」：

| | 存什么 | 存哪 | 在哪用 |
|---|---|---|---|
| 设置 → 游戏预设 | 模式 + 手感 + 轴表名（+ 可选布局） | `palmdeck_game_profiles_v1` | 设置页 |
| 设置 → 布局 / 编辑条 | 只有组件表 | `palmdeck_layout_templates_v1` | 布局页 + 座舱编辑条 |

两者都是「存一套、以后一键拿回来」，用户却要在**两个分类**里找「我上次存的那套」，
而且编辑条上的「存为模板」与设置里的「游戏预设」看上去毫无关系。

**做法**：删掉「模板」这个词（`LayoutTemplate` 类型、`templatesByMode`、`TplPrompt` 全部删除），
预设分两种形态，用**同一个类型、同一个 store、同一个列表**：

- **整机**（`hasShaping == true`）：模式 + 手感 + 有布局就换。跨模式出现（换游戏就是干这个的）。
- **布局**（`hasShaping == false`）：只装组件、不碰手感；**只在自己那个模式下出现**。
- **内置「默认」是列表里最后一行只读的「布局」预设**：点了走 `LayoutStore.applyDefault(mode:)`，
  不入库、不占 24 个名额。（原来它是「布局」分类里的一个按钮。）
- 上限 **24**（原预设 12 + 模板 12，合并后不再分半）；名称 ≤16 字符、非空、
  **不得叫「默认」**、不得与内置重名（两种形态打通后，重名是真的会撞）。
- **空预设在两级被拦**：`save` 兵底（既没手感也没布局 → 直接返回错误文案）
  + UI 把「存为整机预设」/「存为布局预设」按钮置灰。
- 迁移一次性且幂等：v2 不存在时把两个老键合并（`GameProfileMigration`），
  重名加「·布局」后缀；之后老键**只读不写**（否则用户删掉的预设会在下次启动复活）。

**编辑条上的「存为预设」存的是布局预设**（人在摆布局，手感不在这件事的范围里）；
想连手感一起存，去设置 → 预设里的「存为整机预设」。
它旁边新增一行**回执**（`已存为「X」· 设置 → 预设里能看到` / `「默认」是内置预设，换个名字`）——
以前是 `_ = profiles.save(p)`：重名或名字非法时界面纹丝不动，用户只能自己怀疑人生。
回执和提示横幅同规矩：占画布**上面**一行，不用 overlay。

实测（Mac Catalyst，逐次 `defaults export` 读回比对）：

| 场景 | 结果 |
|---|---|
| 老键 = 2 个整机 + 2 个模板 | `palmdeck_game_profiles_v2` = 4 条（`卡车台` / `WARDOGS·布局` 是布局，其余整机） |
| 开车模式下的列表 | 内置整机 2 + 用户整机 + **本模式**布局预设，末尾「默认」；heli 的布局预设**不出现** |
| 点一条 heli 布局预设 | `palmdeck_widgets_v10` 的 heli 换成那 1 个组件，`palmdeck_dz.heli` 仍是 0.06（手感没动） |
| 点「默认」行 | heli 回到出厂 5 个组件（仪表盘/总距/脚舵/周期杆/视角） |
| 编辑条「存为预设」 | 新增一条 `heli / hasShaping=false` 的记录，画布上出现回执 |
| 名字填「默认」 | 回执报错，库里没有新记录 |
| 清空画布后 | 「存为预设」置灰、点不动 |

> Catalyst 侧的合成点击对**带 `swipeActions` 的列表行**时灵时不灵（同一个 List 里的普通按钮正常）。
> 上表里「点一条布局预设」是成功了的那次；真机上再点一下确认手感即可。

**顺带修掉的显示问题**：预设名 + 章（「内置 / 整机 / 当前」）挤在一行时，
名字会被折成两行（`WARDOGS·` / `布局`）。改成标题 `lineLimit(1)` + `layoutPriority(1)`、
章 `fixedSize()`、详情行 `lineLimit(2)`（详情尾巴是「含布局 / 仅手感」，不能被裁掉）。

---

## 12.15 设置页一致性 / 可发现性（P2）

**问题**：设置页是 P7 一路增量堆出来的——分类按“谁先做”而不是按“用户怎么想”排，
段头里混着动作词（「清空」）与空话（「参数」），**同一个东西在设置页与座舱里叫两个名字**
（设置 →「清空当前模式」vs 座舱 `⋯` →「清空画布」；启动页 →「高级设置」vs 顶栏齿轮 →「设置」），
搜索索引 `entries` 是手写的，写进去的词在界面上根本搜不到。

**做法**（只改文案 / 分组 / 用词，**不动数据、协议、存储键、画布**）：

| 位置 | 之前 | 之后 | 理由 |
|---|---|---|---|
| 侧栏 | 8 项（含独立的「方向盘」） | **7 项**：连接 / 预设 / 布局 / 操纵与手感 / 触觉 / 外观 / 帮助 | 满舵角度 / 回正速度只占两个滑条，不值得一个顶级分类；想知道“方向盘为什么自己回正”的人会先点“操纵与手感” |
| 侧栏 `.profiles` | 「游戏预设」 | **「预设」** | P1.5 起它同时装整机与布局预设 |
| 方向盘段头 | 「参数」 | **「方向盘」**（并进操纵与手感最后一段） | 头要说得出这一组是什么；且它们**是全局键**，footer 必须写明“三个模式共用” |
| 布局页段头 | 模式 / 清空 /（无） | **编辑 / 重置 / 撤销** | 动作词不当头；`undoSection` 是唯一没头的段 |
| 触觉页 | 段头「反馈」+ 项「触觉反馈」 | 段头**「触觉反馈」** + 项**「开启振动」** | 头与项不重复 |
| 预设页段头 | 「电脑侧」 | **「电脑」** | 与「连接」页同一个意思用同一个词 |
| 电脑 | 「电脑端」（分类名/段头/按钮/空态） | **「电脑」** | 「电脑端」只在**与 App 对举**时用（「电脑端版本」「App 与电脑端主版本号不一致」） |
| 存按钮 | 「将当前状态存为预设（整机）」等 | **「存为整机预设」/「存为布局预设」** | 短名；行尾章已写「整机 / 布局」 |
| 清空 | 「清空当前模式」 | **「清空画布」** | 与座舱 `⋯` 菜单同名；footer 补“只清「飞机」这一个模式” |
| 启动页 | 「高级设置」/「发现的电脑」 | **「设置」/「可用电脑」** | 与设置页同一个概念同名 |
| 搜索索引 | `自定义组件布局` / `清空当前模式` / `存为预设`… | 一律改成**界面上真实存在的字**（`组件布局` / `默认布局` / `清空画布` / `存为整机预设` / `存为布局预设` / `电脑当前轴表` / 方向盘的 `满舵角度` / `回正速度`） | 搜到的词点进去要能看到同样的词 |
| 搜索空态 | 只有「没有匹配的设置项」 | 多一行灰字**示例词**：「试试「死区」「轴表」「预设」」 | 空态要给下一步 |

**不做**：不动存储键（老用户设置一字不动）、不动座舱编辑条（横向空间是硬约束，
「存为预设」保持短名，弹窗标题已写清“存为布局预设”）、不为方向盘加按模式分开（那是行为变更）、
不做“搜索跳转到具体控件”、不动分类顺序（「连接」第一是为首启服务的）。

**机器验证**：`tests/test_deck_bindings.py::TestSettingsConsistency`（12 条源码守卫）
—— 侧栏不再有「游戏预设」；不存在 `case wheel` 且 `wheelSection` 在 `controlsSections` 里；
段头黑名单（电脑侧 / 清空 / 参数 / 反馈）+ 白名单（编辑 / 重置 / 撤销 / 电脑 / 方向盘 / 触觉反馈）；
`undoSection` 有头；两个存按钮与「清空画布」在设置页与座舱同名；
源码里不再出现「仅布局」「高级设置」「发现的电脑」「电脑端已启动」；空态有示例词；
索引 title 能在源码里找到同名文案（抽查）。

**实测**（Mac Catalyst 2026-09-25，逐张截图）：

| 看哪 | 结果 |
|---|---|
| 设置侧栏 | 7 项，无「游戏预设」、无独立「方向盘」 |
| 预设页 | 段头「电脑」（`电脑当前轴表` 只读）、「预设」段；行上是 `WARDOGS`(整机) / `欧洲卡车模拟`(整机) / `WARDOGS·布局`(布局) / `机舱台`(布局) / `默认`(内置·布局)；底部 `⊕ 存为整机预设`、`⊕ 存为布局预设`（画布为空时后者**置灰**） |
| 布局页 | 段头「重置 → 清空画布」「撤销 → 撤销上一次改动」「与电脑同步 → 从电脑拉取布局 / 上传当前模式到电脑」 |
| 操纵与手感页末尾 | 段头「方向盘」+ `满舵角度 2.5 圈` / `回正速度 720°/s`，footer「这两个是**全局项**：三个模式共用…」 |
| 触觉页 | 段头「触觉反馈」+ 项「开启振动」+「试一下振动」 |
| 启动页 | 「可用电脑（点一下连接）」+ `192.168.3.103`；底部「> 设置」折叠（展开后是电脑 IP + 轴反向） |
| 搜索「存为布局预设」 | 命中「预设」分类，标题与按钮上的字**完全一致** |
| 搜索「zzz」 | 「没有匹配的设置项」+「试试「死区」「轴表」「预设」」 |

> Catalyst 合成点击在本机踩到两个坑，记下来免得下次再来一遍：
> ① `.buttonStyle(.plain)` 的小按钮（如启动页「设置」折叠）**单击不生效**，要 `dd:` → `du:` 慢按；
> ② `osascript … whose name "App"` 会报 `-2741` 语法错误，要写 `whose name is "App"`；
> ③ 列表滚动用 cliclick 拖拽 / `page-down` 都无效，改用一段 `CGEventCreateScrollWheelEvent`
> （`kCGHIDEventTap`）的 Python 小脚本，鼠标停在列表上再滚。

---

## 12.16 可发现性补完：看得见、点得到、说人话（P2 残留）

**问题**：§12.15 只统一了「名字」，还有四条「能不能发现 / 说不说清代价」的问题：

| # | 问题 | 代价 |
|---|---|---|
| a | 顶栏三个入口里**只有齿轮没字** | 新用户不知道它是什么；教程只好绕开它说「齿轮设置」 |
| b | 预设的**改名 / 删除只有左滑** | 大部分用户在鼠标（Catalyst）上根本不会去左滑，以为存下去就改不了 |
| c | **已连接时**切模式**一点就切** | 电脑端要在 vJoy ↔ 虚拟 Xbox 之间换后端，游戏里手柄会掉一下；用户当成「App 卡了」 |
| d | 状态条 `LINK / MODE / SRC`、绑定列表「仅飞行」 | 同一行轴标签是中文，这三个是英文；`仅飞行` 没说清开车/手柄为什么没有这些键 |

**做法**（只改 App 三个 View，**不动协议 / 电脑侧 / 存储键 / 画布结构**）：

| 位置 | 之前 | 之后 |
|---|---|---|
| 顶栏「设置」 | 纯齿轮（宽 40） | 齿轮 + **「设置」**（宽 64，与「布局」同套：图标 13 / 字 11 medium / `HStack(spacing: 4)` / 同高 `CardButton`） |
| 预设行 | 整行 `Button` + 左滑两键 | `contentShape + onTapGesture` 应用预设 + 行尾 `Menu`（`ellipsis.circle`：**重命名 / 删除**）；`swipeActions` **保留**；内置预设与「默认」行**不显示**菜单 |
| 模式胶囊 | 一点就切 | **已连接且不是当前模式**时先弹确认（标题「切换到「X」？」+ 代价说明 + 「切换 / 取消」）；未连接直接切 |
| 状态条 | `LINK` / `MODE` / `SRC` | **`链路` / `模式` / `通道`**（值仍是 `UDP` / `WS`：协议名，改了对不上控制台） |
| 绑定列表 | `按钮 11 · 仅飞行` | **`按钮 11 · 开车/手柄不生效`**；选中后多一段 ⚠️ 说明 |
| 教程 | 「齿轮设置」，无换模式/状态条说明 | 「设置」；补两节：**换模式**（说明为什么会掉手柄）与**底部状态条**（`通道` 的 UDP / WS 各是什么） |

**为什么切模式要问**：换后端会重建虚拟手柄，这是电脑侧的**事实**（不是 App 的 bug），
说清代价比事后解释便宜。**未连接时不问**：本机切模式没有代价，多一层弹窗只会变慢。

**不做**：Dynamic Type / 无障碍标签（已另起一轮落地，见 `docs/PalmDeck-v4-accessibility.md`）；
不改模式胶囊样式；不给内置预设加菜单；不动 `UDP` / `WS` 的字面值。

**机器验证**：`tests/test_deck_bindings.py::TestDiscoverability`（11 条源码守卫）。
**实测**（Catalyst 逐张截图）与顺手发现的问题：见 `docs/PalmDeck-v4-discoverability.md` §9 / §8.4。

## 12.17 组件库绑定按类型收敛（只列真正生效的）

**问题**：`LibrarySheet` 的绑定下拉不管类型，一律列全部 `WidgetBinding`；
类型选「按键」照样能选「油门」这类**轴**绑定，而 `Widgets.swift` 的 `tapButton`
对轴绑定是空实现 ⇒ 加出来是**按了没反应的按键**。更糟的是新建组件默认
`@State binding = .throttle`，**选「按键」→ 直接「添加到画布」一步就踩**。

**做法**（只改两个 View，不动协议 / 存储键 / 画布结构）：

| 位置 | 之前 | 之后 |
|---|---|---|
| 绑定下拉 | 列全部 `WidgetBinding.allCases`（含轴 + 键 + 视角） | 只列该类型真正会读的：`WidgetKind.bindingOptions`（`.slider`→`WidgetBinding.axes`，`.button`→`.buttons`，其余为空） |
| 固定通道组件 | 也给下拉，选了不生效 | 方向盘 / 触摸板 / 摇杆 / 苦力帽 / 姿态球 → 一行「固定发…」说明（`fixedBindingNote`），因为渲染时读的是写死通道、`binding` 被忽略 |
| 只读组件 | 也给下拉 | 仪表盘 → 「只读显示，不绑定轴或按键」 |
| 弹窗初值 | 写死 `.throttle` | `bindingOptions.first ?? defaultBinding`（滑条→横滚/转向，按键→按钮 1） |
| 换类型时 | 绑定不变（可能留下不生效的旧值） | `.onChange(of: kind)` 归到新类型的第一个 |
| 组件库入口 | 只 `isPresented`，不知道点的是哪个 | `.sheet(item: $libraryKind)` 把类型当弹窗输入（**别用「先改 state 再 `isPresented`」**：同一 action 里改两个 state，sheet 内容闭包可能拿到旧值 —— 点「按键」却从「滑条」起。实测踩到，见方案文档 §8.3） |

**边界**：`WidgetBinding.look` 仍留在枚举里（方向盘等写死通道内部仍以它作默认 `binding` 占位），
只是不再作为任何下拉选项出现；老布局里的历史死组件不迁移。

**方案 / 实测**：`docs/PalmDeck-v4-binding-filter.md`。
**机器验证**：`tests/test_deck_bindings.py::TestBindingOptions`（9 条，交叉核对
`axes`↔`bindAxis`、`buttons`↔`tapButton`，以及上述接线）。

## 12.18 动态字号 + 无障碍标签（走查第 5 条）

**问题**：全 App 固定 `pt` 字号（约 130 处 `.font(.system(size: N))`），系统字号调多大都不变；
方向盘 / 摇杆 / 苦力帽 / 滑条 / 视角板 / 姿态球 / 仪表盘全是自绘，VoiceOver 读不出值；
编辑态 ✕ / `Aa` 只报 SF Symbol 名。

**做法**（只动 View 层，零新增存储键）：

| 位置 | 之前 | 之后 |
|---|---|---|
| 字号 | `.font(.system(size: N))` 固定 | `.pdFont(N)` / `Font.pd(N)`（`@ScaledMetric`，默认字号下外观不变；几何比例字号不动） |
| 根视图 | 无 | `.palmDynamicType()` → 放到 `.accessibility2` |
| 座舱 chrome | 跟随根 | 收口 `.xxLarge`：固定横排 HUD，放开到无障碍档必挤裂；`minimumScaleFactor` 兜底 |
| 设置 / 首启 / 速览 | 跟随根 | `.palmDynamicType()`（文字为主、可滚动，放开） |
| 自绘控件 | 无标签 | `.accessibilityElement(children: .ignore)` + `label` + `value` |

**边界**：画布上的拖拽 / 缩放不给 VoiceOver 替代手势（像素级拖动是另一套「无障碍编辑布局」）。
**方案 / 实测**：`docs/PalmDeck-v4-accessibility.md`。
**机器验证**：`tests/test_deck_bindings.py::TestAccessibility`（8 条）。

---

## 12.19 未连接提示不该“顶”一下画布（走查反馈）

**问题**（用户）：**点「点此连接电脑」的提示，其它组件会闪一下。**

**根因**：`deckBody` 是 `VStack { 横幅 / 编辑条; 提示回执; 画布 }`，而横幅的出现条件是
`s.link != .live && s.link != .connecting`。点按 → `link = .connecting` → **横幅整行消失** →
下面 `WidgetCanvas`（`GeometryReader` + 全部组件 **归一化** 坐标）变高 → 所有组件按比例重排。

**做法**（只动 `CockpitView.swift` 一个 View，不动状态机 / 协议 / 存储）：

1. 条件改成 `s.link != .live`：**`connecting` 不再收起**，只换文案「正在连接…」+ 换青色；
   点按瞬间行高不变。
2. `deckTopRowH: CGFloat = 32` + `.frame(height: deckTopRowH)`：文案 / 图标 / 发现的 IP 变化
   都不再影响高度，文字 `.lineLimit(1)` + `minimumScaleFactor(0.8)`。
3. `live` 才收成 0，并给 `deckBody` 的 `VStack` 挂 `.animation(.easeInOut(duration: 0.22), value: s.link)`：
   连上 / 断线是平滑展开 / 收起。
4. 连接中用 `.allowsHitTesting(!connecting)` + `guard !connecting` 挡住重复点（不用 `.disabled`，
   那会把胶囊压暗）。

**实测**（Mac Catalyst，临时把初始 `link` 置为 `.connecting` 后重建）：`idle` 与 `connecting`
两张截图里，组件区域（视角板）的裁剪 **md5 完全一致** —— 点按前后组件像素未动。

**不做的**：编辑条 ↔ 横幅行高仍不同（进 / 出编辑模式仍会变一次，属用户主动操作）；
「存为预设」回执（`presetNoteRow`，仅编辑态）同理。
**方案**：`docs/PalmDeck-v4-connect-banner-stable.md`。
**机器验证**：`tests/test_deck_bindings.py::TestConnectBanner`（5 条）。

---

## 13. 不做 / 明确边界

- 不恢复 v3 的“整机倾斜体感”“锁定/校准 HUD”（v4 为触控硬件皮肤）。
- 不做手机端游戏遥测回读（见 `docs/TODO.md`）。
- **引擎里不再有任何固定皮肤**：三个模式共用一块通用组件画布，默认都是「轴 + 用户自加按键」。
  **App 不为任何游戏硬编码按钮语义**；含义与绑定由用户在游戏内完成（见 §12.6）。
- **动态字号 / 无障碍（§12.18）**：视图层 `.pdFont` 随系统字号缩放；座舱 chrome 收口
  到 `.xxLarge`，设置 / 首启 / 速览放开到 `.accessibility2`；自绘控件补
  `accessibilityLabel` / `accessibilityValue`。见 `docs/PalmDeck-v4-accessibility.md`。
- 不引入第三方依赖 / 不改电脑侧协议。
- **连接状态变化不改画布几何（§12.19）**：画布上方那行（连接横幅）高度锛死；
  `idle ↔ connecting` 不改变 `WidgetCanvas` 尺寸。进 / 出编辑模式、存预设回执仍会变
  （用户主动操作，且那行本就是编辑 UI）。
