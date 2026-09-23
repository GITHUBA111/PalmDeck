# PalmDeck 设计文档

| 文件 | 主题 | 状态 |
|---|---|---|
| `PalmDeck-v3-feature-design.md` | **电脑侧**：HID / vJoy+Xbox / PD v1 协议 / Hub 锁 / allowlist / failsafe / 轴预设 | 已落地（代码 + 测试对齐） |
| `PalmDeck-v3-cockpit-design.md` | **手机座舱**：横屏完整飞行杆的产品/像素级布局/体感管道/滑条手感/状态机/三种模式皮肤 | PR1–PR5 已实现（见下） |
| `PalmDeck-v3-cockpit-design.summary.md` | 座舱设计总结（关键决策 + PR 施工顺序摘要） | 配套 |
| `PalmDeck-v3-cockpit-design.review.md` | 座舱设计的审查报告（13 条 open issue） | 配套 — 待逐条修订 |

## 关系

- `PalmDeck-v3-feature-design.md` 冻结**电脑侧协议**，座舱设计**不得重开** HID / PD v1 / `awaitModeAck` / failsafe / 轴预设。
- `PalmDeck-v3-cockpit-design.md` 冻结**手机座舱**，其实现必须遵守 v3 电脑侧合同；若 UX 不需要新字段，禁止改包。

## 座舱实现状态（`web/index.html`）

已按文档 PR1–PR5 落地：

- **PR1** 横屏甲板 #hud + #deck 三列 + 竖屏闸门 #gate-rotate + PFD 姿态球（pitch ladder / bank scale / R/P 磁带）+ 双向舵填充
- **PR2** 体感管道（raw 采样与 rAF 分离）、LOCK/CAL 迁 HUD、油门止动+穿越振动、舵中位+双击回中、`yawSpring`/`thrReturnDrive`
- **PR3** #preflight 起飞检查单 + #reconnect 全屏重连 + HUD Hz/传输/着色
- **PR4** 开车方向盘皮肤 + 步兵休息屏 + 模式 400ms 按住 + 进入零清表
- **PR5** iOS 仅横屏（Info.plist）+ `contentInset: "never"` + 文档对齐

补充：原生 Taptic 震动（`PalmDeckUdpPlugin.haptic`，iOS WKWebView 不支持 `navigator.vibrate`）、
品牌 App 图标 + 启动图、`host.html` 本地 QR（内联 `qrcode.js`）。

review 报告里的 13 条 issue 已在设计文档 KD14–17 与本文实现中吸收（hat 改真帽垫、竖屏冻结、
步兵流闩、HUD 截断、packageClassList 已核实）。

## 原生 iOS 端实现状态（`mobile/ios/App/App/Native/`）

web 版是 A 路线（Safari 加到主屏幕）；原生端是 B 路线（Capacitor + SwiftUI/SceneKit），
协议与电脑侧完全一致，但 UI 是纯原生 SwiftUI，不走 `web/index.html`。

### 入口与结构
- `PalmDeckApp.swift` — `@main`，首启走 `PreflightView`（三步引导/手动 IP/轴反向），之后进 `CockpitView`（`palmdeck_entered` 持久化）；首次进座舱自动弹「速览教程」（`palmdeck_tutored` 持久化，设置 → 帮助可重开）。
- `Model/`：`ControllerState`（共享状态 + 语义轴 + EMA 平滑 + 遥测选源）、`CockpitController`（60Hz 热路径 `CADisplayLink` + 连接/心跳/遥测）、`NetClient`（WS 8765 控制面 + UDP 7773 热路径）、`Packet`（22 字节 `<2sBB8hH` 与 `bridge.py` 对齐）、`Discovery`（Bonjour `_palmdeck._udp`）、`Haptics`。
- `Views/`：`Theme`（统一暗色主题 + 模拟器 HUD 组件：`CockpitBackdrop` 深色渐变+微光晕+HUD 网格、`hudPanel` 仪表面板/四角括号、`HudCell` 数据单元、`CornerBrackets`、`glow` 光晕）、`CockpitView`（顶栏状态条 + 底部遥测条 ROL/PIT/YAW/THR/LINK/MODE/SRC + 仪表取景框）、`AttitudeBall`（PFD 姿态球）、`HelicopterScene`（SceneKit 3D 直升机 + 地面网格/停机坪/天空渐变）、`Controls`（摇杆/双极滑条/单极滑条/苦力帽/视角板）、`SteeringWheel`（触摸方向盘，多圈+可调回正速度）、`Layout`（`LayoutStore`+`WidgetCanvas` 可拖/缩放/删除）、`Widgets`（组件类型/绑定/渲染）、`PreflightView`。

### 三种模式（与 web 版同皮肤语义）
- **飞机 heli**：姿态球（左）+ 3D 直升机（右，并排不重叠）+ 左列油门/横滚/俯仰/苦力帽 + 右列摇杆/开火/方向舵/武器键 + 中下两行 10 键。
- **开车 drive**：方向盘 + 油门/刹车/离合滑条 + 升/降档 + 视角触摸板 + 底部功能键（转向灯/喇叭/雨刷/远光等）。
- **步兵 infantry**：休息屏（键鼠操作，轴停发不干扰鼠标），仍可布局加开火/投弹等触控键。

### 组件系统（模块化/乐高式）
- 7 类组件：方向盘/滑条/触摸板/按键/摇杆/苦力帽/姿态球，各绑定一个语义轴或 vJoy 键。
- 编辑模式：顶栏组件库添加、拖拽移动、右下角缩放手柄、✕ 删除、一键清空/恢复默认；布局按模式持久化（`palmdeck_widgets_v7`）。

### 遥测（已接）
- 电脑侧 `bridge.py` 按 `--telemetry http/udp` + `--telemetry-url/--telemetry-udp/--telemetry-map` 轮询姿态，广播 `{"type":"attitude",roll,pitch,yaw}`。
- 手机侧 `CockpitController` 收 `attitude` 写入 `telemRoll/Pitch/Yaw`，`ControllerState.display*` 按「3D 显示源」选本地杆位或遥测；姿态球与 3D 直升机、读数同源；**1.5s 无包自动 `telemValid=false` 回退杆位**。
- `telemetry.py` 提供通用 `HttpJsonTelemetry` / `UdpJsonTelemetry`，WARDOGS 若确认有遥测接口，补专用读取器即可，App 无需再改。

### 待办
见 `docs/TODO.md`（当前仅剩 WARDOGS 遥测字段确认 + 专用读取器）。
