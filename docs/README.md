# PalmDeck 设计文档

| 文件 | 主题 | 状态 |
|---|---|---|
| `PalmDeck-v4-redesign.md` | **v4 总纲**：只保留 Windows 常驻服务（自带网页控制台）+ iOS App；手机 Web 座舱作废 | **P1–P6 已落地** |
| `PalmDeck-v4-app-interaction.md` | **App 端功能与交互规格**：信息架构 / 连接 / 三皮肤 / 触摸手感 / 触觉 / 设置 / 持久化；P7 加固 | **P7 已落地** |
| `PalmDeck-v3-feature-design.md` | **电脑侧**：HID / vJoy+Xbox / PD v1 协议 / Hub 锁 / allowlist / failsafe / 轴预设 | 已落地（代码 + 测试对齐） |
| `PalmDeck-v3-cockpit-design.md` | **手机座舱**：横屏完整飞行杆的产品/像素级布局/体感管道/滑条手感/状态机/三种模式皮肤 | PR1–PR5 已实现（见下） |
| `PalmDeck-v3-cockpit-design.summary.md` | 座舱设计总结（关键决策 + PR 施工顺序摘要） | 配套 |
| `PalmDeck-v3-cockpit-design.review.md` | 座舱设计的审查报告（13 条 open issue） | 配套 — 待逐条修订 |
| `PalmDeck-v4-game-profiles.md` | **方案（待评审）**：游戏预设 —— 电脑侧轴映射表 + App 侧手感 + 布局，一键切游戏 | 待评审 |
| `PalmDeck-proposal-template.md` | **方案模板**：新功能/改造动代码前的统一提案格式（§1 骨架 + §2 已填示例） | 工具 |

## 关系

- **新功能/改造先写方案**：按 `PalmDeck-proposal-template.md` 落成文档，评审通过再动代码。
  当前待评审：`PalmDeck-v4-game-profiles.md`（游戏预设，G0–G4 分阶段）。
- **`PalmDeck-v4-redesign.md` 为当前总纲**：产品只剩 Windows 常驻服务 + iOS App，
  手机 Web 座舱（`web/index.html`）已删除；服务端 `/` 一律指向控制台 `web/host.html`。
  下文关于 `web/index.html` 的座舱描述仅作历史参考。
- **`PalmDeck-v4-app-interaction.md` 为 App 交互权威规格**：屏幕/状态机、三皮肤交互、
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
  | `Packet.swift` | 只做「`ControllerState` → 纯数据」的适配，调上面两个 |

  注意：曲线数学、轴真值表、包字节布局三者**都不允许**在别处再写一遍。
  `tests/test_ios_axis.py` 会拦住 `pow(` / `func shape(` 的重复实现。
- `Views/`：`Theme`（统一暗色主题 + 模拟器 HUD 组件：`CockpitBackdrop` 深色渐变+微光晕+HUD 网格、`hudPanel` 仪表面板/四角括号、`HudCell` 数据单元、`CornerBrackets`、`glow` 光晕）、`CockpitView`（顶栏状态条 + 底部状态条 ROL/PIT/YAW/THR/LINK/MODE/SRC）、`AttitudeBall`（PFD 姿态球）、`Controls`（摇杆/双极滑条/单极滑条/苦力帽/视角板）、`SteeringWheel`（触摸方向盘，多圈+可调回正速度）、`Layout`（`LayoutStore`+`WidgetCanvas` 可拖/缩放/删除）、`Widgets`（组件类型/绑定/渲染）、`PreflightView`。

v4 硬件皮肤（均为固定布局）：`FlightDeck`（飞机：总距杆+脚舵+周期变距杆+仪表板）、`DriveDeck`（开车：方向盘+三踏板+档杆+转速表+十字键视角）、`GamepadDeck`（手柄：双摇杆+十字键+ABXY+LB/RB+L3/R3）。

### 三种模式（v4 硬件皮肤）
- **飞机 heli**：`FlightDeckView` —— 总距杆（IDLE/FLY/MAX 止动）+ 脚舵 + 周期变距杆 + 仪表板（COLL/TRQ 弧形 + 姿态球 PFD + ROL/PIT/YAW 条）+ 硬件按键（开火/投弹/起落架/灯光/悬停/视角）。
- **开车 drive**：`DriveDeck` —— 方向盘（多圈+回正）+ 离合/刹车/油门三踏板 + 序列式档杆 + 转速表与中控仪表盘 + 视角板 + 按键簇。
- **游戏手柄 gamepad**：默认 `GamepadDeck` 硬件手柄；可在设置里切「自定义组件布局」（`palmdeck_gamepad_custom`）回到 `WidgetCanvas`，并由 `/api/layouts` 同步。此时轴停发，不抢电脑键鼠。

### 组件系统（模块化/乐高式）
- 7 类组件：方向盘/滑条/触摸板/按键/摇杆/苦力帽/姿态球，各绑定一个语义轴或 vJoy 键。
- 编辑模式：顶栏组件库添加、拖拽移动、右下角缩放手柄、✕ 删除、一键清空/恢复默认；布局按模式持久化（`palmdeck_widgets_v10`），并可「从电脑拉取」/「上传当前模式到电脑」（WS `layouts_get`/`layouts_put`）。

### 无遥测
姿态球与飞行仪表板只显示本机发往电脑的**平滑杆位**（`smRoll/smPitch/smYaw`），
不做游戏遥测回读（v4 已移除 `telemetry.py` 与 `--telemetry*` 参数，见 `docs/TODO.md`）。

### 测试

```bash
python3 -m unittest discover -s tests -t .      # 76 项
```

其中 `tests/test_ios_axis.py` 用 `swiftc` 直接编译 `Native/Model/` 里的**真实源码**
并跑 1300+ 条断言（曲线对称性/单调性/死区连续性/夹紧顺序、三模式真值表、
包长/偏移/小端序/量化边界）。不引入 Xcode unit-test target ——
被测对象全是**纯函数**，手写 target 要同时改 `project.pbxproj` 的
target/scheme/构建设置，风险大于收益；`swiftc` 足够了，而且能跟着
`python3 -m unittest` 一起跑。没有 `swiftc` 的环境自动 skip。

### 待办
见 `docs/TODO.md`。
