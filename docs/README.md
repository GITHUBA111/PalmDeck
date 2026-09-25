# PalmDeck 设计文档

| 文件 | 主题 | 状态 |
|---|---|---|
| `PalmDeck-v4-redesign.md` | **v4 总纲**：只保留 Windows 常驻服务（自带网页控制台）+ iOS App；手机 Web 座舱作废 | **P1–P6 已落地** |
| `PalmDeck-v4-app-interaction.md` | **App 端功能与交互规格**：信息架构 / 连接 / 通用组件画布 / 触摸手感 / 触觉 / 设置 / 持久化；P7 加固 | **P7 已落地** |
| `PalmDeck-v3-feature-design.md` | **电脑侧**：HID / vJoy+Xbox / PD v1 协议 / Hub 锁 / allowlist / failsafe / 轴预设 | 已落地（代码 + 测试对齐） |
| `PalmDeck-v3-cockpit-design.md` | **手机座舱**：横屏完整飞行杆的产品/像素级布局/体感管道/滑条手感/状态机/三种模式皮肤 | PR1–PR5 已实现（见下） |
| `PalmDeck-v3-cockpit-design.summary.md` | 座舱设计总结（关键决策 + PR 施工顺序摘要） | 配套 |
| `PalmDeck-v3-cockpit-design.review.md` | 座舱设计的审查报告（13 条 open issue） | 配套 — 待逐条修订 |
| `PalmDeck-v4-game-profiles.md` | **方案（待评审）**：游戏预设 —— 电脑侧轴映射表 + App 侧手感 + 布局，一键切游戏 | G0–G2 已落地；G3 降级；G4 待真机验收 |
| `PalmDeck-v4-binding-filter.md` | **组件库绑定按类型收敛**：按键只列按键、滑条只列轴，固定通道组件不再给假下拉 | 已落地 |
| `PalmDeck-v4-accessibility.md` | **动态字号 + 无障碍标签**（走查第 5 条）：`.pdFont` 随系统字号、自绘控件补 VoiceOver | 已落地 |
| `PalmDeck-v4-connect-banner-stable.md` | **连接提示横幅不掉高**：点按「连接电脑」不再把画布组件“顶”得重排（走查反馈） | 已落地 |
| `PalmDeck-v4-instant-recenter.md` | **脚舵 / 视角 松手立即回正**：滑条与视角板瞬回 0（走查反馈） | 已落地 |
| `PalmDeck-v4-windows-product.md` | **Windows 端产品化**：新增 `palmdeck_doctor.py` 唯一自检真相源（驱动/防火墙/端口/依赖），控制台「自检」页 + 一键修复，删孤儿 `open_firewall.bat` | 已落地 |
| `PalmDeck-proposal-template.md` | **方案模板**：新功能/改造动代码前的统一提案格式（§1 骨架 + §2 已填示例） | 工具 |

## 关系

- **新功能/改造先写方案**：按 `PalmDeck-proposal-template.md` 落成文档，评审通过再动代码。
  当前待评审：`PalmDeck-v4-game-profiles.md`（游戏预设，G0–G4 分阶段）。
- **`PalmDeck-v4-redesign.md` 为当前总纲**：产品只剩 Windows 常驻服务 + iOS App，
  手机 Web 座舱（`web/index.html`）已删除；服务端 `/` 一律指向控制台 `web/host.html`。
  下文关于 `web/index.html` 的座舱描述仅作历史参考。
- **`PalmDeck-v4-app-interaction.md` 为 App 交互权威规格**：屏幕/状态机、通用组件画布交互、
  触摸手感模型、触觉词汇、设置与持久化键、P7 差距清单。
- `PalmDeck-v3-feature-design.md` 冻结**电脑侧协议**，座舱设计**不得重开** HID / PD v1 / `awaitModeAck` / failsafe / 轴预设。
- `PalmDeck-v3-cockpit-design.md` 冻结**手机座舱**，其实现必须遵守 v3 电脑侧合同；若 UX 不需要新字段，禁止改包。

## 座舱实现状态（`web/index.html`，v3 历史，v4 已删除）

已按文档 PR1–PR5 落地：

- **PR1** 横屏甲板 #hud + #deck 三列 + 竖屏闸门 #gate-rotate + PFD 姿态球（pitch ladder / bank scale / R/P 磁带）+ 双向舵填充
- **PR2** 体感管道（raw 采样与 rAF 分离）、LOCK/CAL 迁 HUD、油门止动+穿越振动、舵中位+双击回中、`yawSpring`/`thrReturnDrive`
- **PR3** #preflight 起飞检查单 + #reconnect 全屏重连 + HUD Hz/传输/着色
- **PR4** 开车方向盘皮肤 + 步兵休息屏 + 模式 400ms 按住 + 进入零清表
- **PR5** iOS 仅横屏（Info.plist）+ `contentInset: "never"` + 文档对齐

补充：原生 Taptic 震动（`PalmDeckUdpPlugin.haptic`，iOS WKWebView 不支持 `navigator.vibrate`）、
品牌 App 图标 + 启动图、`host.html` 本地 QR（内联 `qrcode.js`）。

review 报告（现标为历史文档）里的 13 条 issue 已在设计文档 KD14–17 与当时实现中吸收（hat 改真帽垫、竖屏冻结、
步兵流闩、HUD 截断、packageClassList 已核实）。

## 原生 iOS 端实现状态（`mobile/ios/App/App/Native/`）

v4 为**纯原生 SwiftUI**（`@main`），协议与电脑侧完全一致，不走任何 WebView。
（历史：v3 曾同时提供 Safari 网页座舱与 Capacitor 外壳，均已作废。）

### 入口与结构
- `PalmDeckApp.swift` — `@main`，首启走 `PreflightView`（三步引导/手动 IP/轴反向），之后进 `CockpitView`（`palmdeck_entered` 持久化）；首次进座舱自动弹「速览教程」（`palmdeck_tutored` 持久化，设置 → 帮助可重开）。
- `Model/`：`ControllerState`（共享状态 + 语义轴 + EMA 平滑）、`CockpitController`（60Hz 热路径 `CADisplayLink` + 连接/心跳 + 布局同步）、`NetClient`（WS 8765 控制面 + UDP 7773 热路径）、`Discovery`（Bonjour `_palmdeck._udp`）、`Haptics`。

  **纯逻辑层（无 SwiftUI/UIKit 依赖，可脱离 App 单测）**：
  | 文件 | 职责 |
  |---|---|
  | `AxisCurve.swift` | 轴整形曲线（反转 / 灵敏度 / 死区 / `^1.35`）。**全仓库唯一实现** —— 平滑、发送、设置里的曲线预览三处共用 |
  | `AxisMap.swift` | 模式 → 8 个 i16 轴的真值表（全函数：入参先夹到 [-1,1]） |
  | `PacketFormat.swift` | 22 字节包 `<2sBB8hH` 的偏移 / 小端序 / `[-32767,32767]` 标度 |
  | `CockpitMode.swift` | 模式枚举 + `infantry → gamepad` 旧值兼容 |
  | `ShapingKeys.swift` | 手感参数的键名（`palmdeck_dz` → `palmdeck_dz.<mode>`）+ 旧键一次性迁移 |
  | `Packet.swift` | 只做「`ControllerState` → 纯数据」的适配：`PacketFormat.encode(axes: s.wireAxes)`，轴真值表只在 `wireAxes` 算一处 |
  | `HudReadout.swift` | 底栏状态条「按模式显示哪几格」：吃 `AxisOutputs`（= 发出去的那 8 个轴），开车不显「方向」、手柄不显油门/刹车 |
  | `GameProfile.swift` | **G2** 游戏预设：`GameProfile`（模式+手感+轴表名+布局）、内置 WARDOGS / 欧洲卡车模拟、`GameProfileStore`、`GameProfileApplier`（应用顺序）。纯类型，可脱离 App 单测 |

  注意：曲线数学、轴真值表、包字节布局三者**都不允许**在别处再写一遍。
  `tests/test_ios_axis.py` 会拦住 `pow(` / `func shape(` 的重复实现，
  也会拦住无后缀的全局手感键（G1 起手感参数按模式分键）。
- `Views/`：`Theme`（**浅/深双主题**（`Color.pd(浅,深)` 动态解析 + `AppAppearance` 外观枚举 + `.palmAppearance()` 修饰器）+ **动态字号** `pdFont` / `Font.pd`（`@ScaledMetric`）与 `palmDynamicType()` / `palmCockpitType()` 封顶 + 模拟器 HUD 组件：`CockpitBackdrop` 渐变+微光晕+HUD 网格、`hudPanel` 仪表面板/四角括号、`HudCell` 数据单元、`CornerBrackets`、`glow` 光晕。仪表专用色（`instr*`/`hud*`）是固定值，不随主题变——姿态球在白底上仍是一块黑表盘）、`CockpitView`（顶栏 + 底部状态条（轴格由 `HudReadout` 按模式给，见交互文档 §12.9））、`AttitudeBall`（PFD 姿态球）、`Controls`（摇杆/双极滑条/单极滑条/苦力帽/视角板）、`SteeringWheel`（触摸方向盘，多圈+可调回正速度）、`FlightPanel`（只读飞行仪表盘：`ArcGauge`/`BarGauge`/`FlightPanel`）、`Layout`（`LayoutStore`+`WidgetCanvas` 可拖/缩放/删除）、`Widgets`（组件类型/绑定/渲染）、`PreflightView`。

v4 **不再有固定皮肤**（E2 续）：`FlightDeck` / `DriveDeck` / `GamepadDeck` 已整份删除，
三个模式共用一块通用组件画布 `WidgetCanvas`；各模式的默认布局 = 一组基本轴模块
（飞机：周期杆/总距/脚舵/视角；开车：方向盘/三踏板/视角；手柄：双摇杆/ABXY/扳机轴）。

### 三种模式（共用通用组件画布）
- **飞机 heli**：默认 `defaultHeli()` —— 仪表盘（`panel`，只读：COLL/TRQ 弧表 + 姿态球 + ROL/PIT/YAW 条）+ 周期杆（`stick`→roll/pitch）+ 总距（`slider`→throttle）+ 脚舵（`slider`→yaw）+ 视角（`pad`），**只有轴、无按键**。
- **开车 drive**：默认 `defaultDrive()` —— 方向盘（多圈+回正）+ 离合/刹车/油门三滑条 + 视角，**只有轴、无按键**。
- **游戏手柄 gamepad**：默认 `defaultGamepad()` —— 双摇杆 + LT/RT 滑条 + ABXY + LB/RB + 视图/菜单 + L3/R3 + 十字键，均可改。此时轴停发，不抢电脑键鼠。

> **App 不为任何游戏硬编码按钮语义**：按键默认只有中性序号（「按钮 N」），
> 名字与绑定由用户在编辑态自己定（`Aa` 重命名 + `LibrarySheet` 选绑定）。详见
> `docs/PalmDeck-v4-app-interaction.md` §12.6。

### 组件系统（模块化/乐高式）
- 8 类组件：方向盘/滑条/触摸板/按键/摇杆/苦力帽/姿态球/仪表盘。**组件库里只有滑条（轴）与按键（vJoy 键）有绑定下拉**，且下拉只列该类型真正会用的项（`WidgetKind.bindingOptions`）；方向盘/触摸板/摇杆/苦力帽/姿态球渲染时走写死通道，弹窗改为一行「固定发…」说明；仪表盘只读（见 `docs/PalmDeck-v4-binding-filter.md`）。
- 编辑模式：顶栏组件库添加、拖拽移动（**7pt 内吸画布/其它组件的边与中心线并画出对齐线**，且任何方向至少留 40pt 在画布内、拖不丢）、右下角缩放手柄、✕ 删除、`Aa` 重命名；`⋯` 里清空 / 恢复默认 / 撤销；空画布显示「画布是空的」而不再是一块白板；布局按模式持久化（`palmdeck_widgets_v10`），并可「从电脑拉取」/「上传当前模式到电脑」（WS `layouts_get`/`layouts_put`）。
- **命名快照只有一种：预设**（P1.5 起，原「布局模板」已并进来）。两种形态：**整机**（模式 + 手感 + 有布局就换）与**布局**（只装组件、不碰手感，且只在自己那个模式下出现）。编辑条上的「存为预设」存的是后者，并在编辑条下面给一行回执。见 `docs/PalmDeck-v4-unified-presets.md`。

### 无遥测
姿态球与飞行仪表板只显示本机发往电脑的**平滑杆位**（`smRoll/smPitch/smYaw`），
不做游戏遥测回读（v4 已移除 `telemetry.py` 与 `--telemetry*` 参数，见 `docs/TODO.md`）。

### 测试

```bash
python3 -m unittest discover -s tests -t .      # 251 项
```

其中四个用 `swiftc` 直接编译 `Native/Model/` 里的**真实源码**（不是副本）来跑；
`test_deck_bindings.py` 是 SwiftUI 源码接线与守卫，不需要 `swiftc`：

| 文件 | 跑什么 |
| --- | --- |
| `tests/test_ios_axis.py` | 1392 条断言：曲线对称性/单调性/死区连续性/夹紧顺序、三模式真值表、包长/偏移/小端序/量化边界；另兼「实现唯一性」守卫（曲线数学、无后缀的全局手感键） |
| `tests/test_ios_state_keys.py` | 33 条断言，手感参数按模式分键的**接线**：真的 `ControllerState`（存储注入字典替身）→ 迁移跑了没、`applyMode` 换了没、写入有没有只落当前模式 |
| `tests/test_deck_bindings.py` | SwiftUI **源码接线与守卫**（不需 `swiftc`）：数据包接线、布局读写唯一入口；**P2 的 `TestSettingsConsistency`**（侧栏 7 项、段头黑 / 白名单、同一动作同名、搜索索引与界面同字）与 **`TestDiscoverability`**（顶栏等权、预设行尾 `⋯` 菜单、切模式确认、状态条 / 绑定列表说人话）；**`TestBindingOptions`**（组件库绑定按类型收敛：`axes`↔`bindAxis`、`buttons`↔`tapButton`、换类型归第一个、`.sheet(item:)` 预选）；**`TestAccessibility`**（动态字号封顶 / `.pdFont` 接线 / 自绘控件 VoiceOver 标签）；**`TestConnectBanner`**（连接横幅行高锛死、`connecting` 不收起、`live` 才收、动画）；**`TestInstantRecenter`**（脚舵/视角松手瞬回 0、周期杆保留平滑回中、保持轴仍走单极滑条） |
| `tests/test_ios_profiles.py` | G2 游戏预设：内置定义、`GameProfile` 编解码往返 / 缺字段回落、存储增删改与上限、**应用顺序**（先切模式→写手感→换布局）、**P1.5 迁移**（两个老键合并 / 重名加后缀 / 幂等 / 垃圾 JSON）、`hasShaping = false` 不碰手感；另守卫 `GameProfile.swift` 已登记进 `project.pbxproj` |
| `tests/test_ios_snap.py` | 拖拽吸附（P1.7）：边对边 / 中心对中心 / **中心不吸别人的边**、7pt 阈值边界、最近者优先、夹取三种尺寸关系、夹取改落点后撤线、画布为 0 时不产生 NaN |
| `tests/test_doctor.py` | Windows 端**自检**守卫（25 条）：报告结构 / 等级合法 / id 不重、`palmdeck_doctor` **不许 import bridge**（要能单独跑）、防火墙端口只有 `palmdeck_config` 一处真相源、`.bat` 里不许再写 `New-NetFirewallRule`、`bridge` 两路由 + `note_listener` 记录 bind 失败、`host.html` 自检页与 `#doctor` 直达、托盘带版本号 + 「自检…」、`pack_windows.FILES` / `.spec` 覆盖；另含**真 bind 失败**（TEST-NET-1）仍返回不抛、非 Windows 上不报故障 |

不引入 Xcode unit-test target —— 被测对象全是**纯函数 / 纯状态**，
手写 target 要同时改 `project.pbxproj` 的 target/scheme/构建设置，
风险大于收益；`swiftc` 足够了，而且能跟着 `python3 -m unittest` 一起跑。
没有 `swiftc` 的环境自动 skip。

### UI 走查截图（给 agent 的提醒）

本项目的 UI 验证是 Mac Catalyst 跑起来 + `cliclick` 点 + `screencapture -x` 截图肉眼比对。
**截图必须先过 `~/.pi/agent/skills/shot/shot.sh` 压成小 JPEG 再 `read`**：
Retina 全屏 PNG 一张 3～5 MB，直接 read 会把几 MB 的 base64 塞进会话，
攒到几十张后模型网关会回 `413 Failed to buffer the request body`
（pi 的上下文管理按 token 算，网关按 byte 卡，两边不是一回事）。
压完约 100 KB，肉眼判断足够。细节见该 skill 的 `SKILL.md`。

### 待办
见 `docs/TODO.md`。
