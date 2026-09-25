# PalmDeck 待办

## 遥测（Telemetry）
- **不做**。v4 移除了整套游戏遥测（`telemetry.py` / `bridge.py --telemetry*` / WS `attitude`）。
  姿态球与飞行仪表板只显示本机发往电脑的**平滑杆位**（`smRoll/smPitch/smYaw`），
  与 UDP/WS 上真正送出的值同源；不再有「游戏真实姿态」回读与显示源切换。

## 已完成
- **拆除 Capacitor 壳子（G0a）** —— v3 是「WebView 里跑网页座舱」，v4 改成纯 SwiftUI
  但壳子只拆了一半。删掉 `App/App/public/`（84 KB `cap sync` 产物）、
  `PalmDeckUdpPlugin.swift`（全仓库唯一 `import Capacitor`）、
  `Base.lproj/Main.storyboard`（里面是 `CAPBridgeViewController` ——
  一旦有人补上 `UIMainStoryboardFile`，App 会以网页壳启动）、
  `SceneDelegate.swift`、`capacitor.config.json`/`config.xml`，
  以及 pbxproj 里 24 行引用。
  它们之前只是「打进包但没人引用的死资源」，所以跑起来看不出问题。
  `tests/test_pack_windows.py::TestNoCapacitorResidue` 守卫。
- **摘掉 CocoaPods（G0b）** —— 它当初只为装 Capacitor，而且 Podfile 用的是
  **本地路径 pod**（`../../node_modules/@capacitor/ios`），指向 gitignored 的
  `mobile/node_modules/` ⇒ **新克隆的仓库 `pod install` 必定失败**。
  拆后工程是普通 `App.xcodeproj`（xcodebuild 会从 target 自动合成 scheme），
  构建命令由 `-workspace` 改回 `-project`（`mac.sh` ×3、`deploy_wifi.sh` ×1）。
  App 包里不再有 Capacitor / `host.html`。`TestNoCocoaPods` 守卫。
- **曲线数学收敛为一处实现** —— 原来 `ControllerState.shape` / `Packet.shape` /
  `SettingsView.AxisResponseCurve.output` 三份，设置里的曲线预览靠「复刻」来假装一致。
  现全部走 `Model/AxisCurve.swift`；`tests/test_ios_axis.py` 会在别处再出现
  `pow(` / `func shape(` 时失败。规格见 `docs/PalmDeck-v4-app-interaction.md` §4.3。
- **iOS 纯逻辑测试** —— `tests/test_ios_axis.py` 用 `swiftc` 编译真实源码运行
  （1300+ 断言），覆盖曲线、`AxisMap` 真值表、`PacketFormat` 字节布局。
  同时把 `AxisMap` 变成全函数（入参先夹到 [-1,1]）——
  此前超范围视角输入会被 `shape` 放大到 1.77，只是被下游 `quantize` 兜住了。
- **打包清单自检** —— `pack_windows.verify()` 用 ast 扫入口的同目录 import，
  漏文件直接拦下。此前 v4 漏了 `palmdeck_layouts.py` / `updater.py`，
  打出的 Windows zip 一启动就 ImportError，且本地/CI 都测不出来。
- **版本号语义统一** —— 产品版本 `updater.APP_VERSION`（4.0.0）与协议版本
  `bridge.PROTOCOL_VERSION`（4.0）分开，`tests/test_version.py` 守卫。
  此前漏改 `APP_VERSION` 会让老用户收不到更新（拿 0.3.2 比 0.3.2）。
- **布局模板（保存 / 切换 / 还原）** —— 每模式 12 个命名快照，点行即切换，左滑重命名/删除，
  内置「默认」即还原点；`清空`/`恢复默认`/`应用模板` 前压撤销槽。
  存储 `palmdeck_layout_templates_v1` / `palmdeck_layout_undo_v1`。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §7.2，方案留存于 `docs/PalmDeck-proposal-template.md` §2。
- **游戏预设（G2）** —— 设置新增「游戏预设」分类：一键把「模式 + 手感 + 轴表名 + 布局」
  一起切到位，不重建虚拟设备、不打断游戏。内置 **WARDOGS**（heli / hotas / dz 0.06，现状固化）
  与 **欧洲卡车模拟**（drive / **dz 0** / 线性 / **900° 满舵** / 720°/s）；用户可自建（上限 12）。
  存储 `palmdeck_game_profiles_v1` / `palmdeck_active_game_profile`。
  类型与应用顺序见 `Model/GameProfile.swift`，规格见 `docs/PalmDeck-v4-app-interaction.md` §12.5。
  **G3 之前 App 不改电脑轴表**：只读显示电脑实际 `axis_profile`，不一致时给黄标。
- **通用模块化（E2）** —— App 不再替游戏硬编码按钮语义：飞机 / 开车**默认只有轴控件、
  不放任何按键**（`defaultHeli()` / `defaultDrive()`）；飞机另带一块**只读**仪表盘
  （`panel` / `Views/FlightPanel.swift`，纯显示、无绑定）；按键由用户自己添加（默认叫「按钮 N」）、
  编辑态 `Aa` 重命名。三个模式共用一块通用组件画布；**固定皮肤已整份删除**
  （`FlightDeck.swift` / `DriveDeck.swift` / `GamepadDeck.swift`，含 `supportsCustom`
  与三个 `palmdeck_*_custom` 开关）。
  修「欧卡2 降档撞默认 LB/RB 看镜头」的报障：以后「哪个键是降档」由用户自己绑，App 不再拍板。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.6、`docs/PalmDeck-v4-game-profiles.md` §3.9。
- **飞机仪表盘改回只读组件** —— `WidgetKind.panel` / `Views/FlightPanel.swift`
  （`ArcGauge` 270° 弧表 + `BarGauge` 双极条 + `AttitudeBall`）。
  **纯显示**：无 `DragGesture` / 无 `@Binding` / 不碰 `btnMask`，只读 `smRoll/smPitch/smYaw`；
  组件库里选到它时隐藏绑定选择。删除固定皮肤后仪具是靠这个回来的，不是靠皮肤。
  `tests/test_deck_bindings.py::TestInstrumentPanel` 守卫。
- **布局编辑「放弃」** —— 进编辑时按模式记一份回滚点（`LayoutStore.editBaseline`，仅内存），
  一键退回本次编辑前；「完成」/ 顶栏「完成」/ 换模式都会 `commitEditing`。
  放弃走 `replaceWidgets` 但**故意不压撤销槽**（它本身就是回滚）。
  `TestEditSession` 守卫。
- **浅色模式（默认浅色）** —— `Theme` 全色值改成 `Color.pd(浅, 深)`（`UIColor(dynamicProvider:)`），
  视图层 120 个引用点一行未改；新增 `AppAppearance`（跟随系统/浅色/深色，
  `palmdeck_appearance`，默认 `.light`）+ `.palmAppearance()`，挂在根视图与三个 presentation。
  姿态球是真仪表，用固定色 `instr*`/`hud*` 保持深底亮线。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.7，`TestThemeAppearance` 守卫。
- **切预设把画布擦成白板** —— 内置预设的 `widgetsJSON` 是 nil（它们只是“手感快照”），
  而 `LayoutStore.applyProfile` 把 nil 当空布局整表替换了。
  现在 nil / 空数组 / 坏 JSON 一律 = “不带布局”→ 不碰用户画布；
  唯一例外是该模式当前就是空表，那就铺回该模式默认模块。
  `TestProfileDoesNotBlankTheCanvas` 守卫。
- **待机不烧 CPU（重绘只跟「有没有在动」成正比）** —— `@Published` 不做等值去重，
  而热路径（`CADisplayLink` 60~75Hz）上原来每 6 帧写一次 `readout` 字符串（全工程没人读，
  v3 遗留的死字段）当刷新心跳 ⇒ 空闲待机也稳定重绘 10 次/秒。
  现在删掉 `readout`/`pfMotionState`，改由 `smRoll/smPitch/smYaw`（姿态唯一数据源、
  本身就是 `@Published`）带领刷新，并且**只经 `applySm()` 且变化 > `smEpsilon` 才赋值**。
  实测 Mac Catalyst：启动页 12~13% → 1.2%，座舱 13~15% → 1.3~1.7%，
  按住方向盘保持角度 1.3~1.4%（顺带姿态刷新从 10Hz 提到满帧，更顺了）。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.8，`TestNoIdleRepaint` 守卫。
- **状态条按模式取字段（显示的就是发出去的）** —— 底栏原来三个模式共用写死的
  `ROL/PIT/YAW/THR`：开车模式 `Rz` 恒 0 却在显示「方向」，手柄模式 `thr/lt/rt` 全清零
  却在显示「油门」，而且 `0.1°` 里的 `0.1` 是归一化杆位、不是角度。
  现在轴真值表只在 `ControllerState.wireAxes` 算一处，`Packet.pack` 与新的
  `HudReadout`（纯函数）都读它 —— 开车显示 转向/离合/油门/刹车，
  手柄显示 摇杆X/摇杆Y/视角X/视角Y。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.9，
  `TestStatusStripFollowsTheMode` + `AxisCoreTests::testHudReadout*` 守卫。

## 已存档（方案已保存，未实施）
- 无。

## 其它
- **拆方案待施工（按已定顺序）**：~~**E1**~~（已施工）→ ~~**G1**~~（已施工）
  → ~~**G2**~~（已施工）→ ~~**E2**~~（已施工）→ **G4**（WARDOGS / 欧洲卡车模拟两个预设）。
  取证与理由见 `docs/PalmDeck-v4-game-profiles.md`。
- **G2 起预设 = 模式 + 手感 + 轴表名 + 布局**：`GameProfileStore`（`palmdeck_game_profiles_v1`），
  内置 WARDOGS / 欧洲卡车模拟。G4 的「两个预设」其实是**把 §3.6 的定义坐实**——
  当前 `GameProfileBuiltin` 已按规格填好，剩下的 G4 是**真机验收**（对照游戏内绑定/参数），
  以及把 ETS2 的两条“必须游戏内确认”（LS Y 归属、序列式变速箱）在实机对一遍。
- **G1 起手感参数带模式后缀**：`palmdeck_dz` → `palmdeck_dz.<mode>` 等七个键；
  旧键启动时一次性迁移（`Model/ShapingKeys.swift`）。
  新增持久化键时注意：未带后缀的写法会被 `tests/test_ios_axis.py` 拦住。
- ~~**`CockpitView.swift:58` 一条 Swift 警告**（`'weak' ownership of capture 'layout'`）
  —— 外层闭包已隐式强引用 `layout`，内层再 `[weak layout]` 语义矛盾。~~
  已随 E1 修掉（先落局部变量再弱引用）。
