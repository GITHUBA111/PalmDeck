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

## 已存档（方案已保存，未实施）
- 无。

## 其它
- **拆方案待施工（按已定顺序）**：~~**E1**~~（已施工）
  → **G1**（手感参数按模式分离，修掉「飞机 0.06 死区污染赛车」）
  → **G2**（`GameProfile` + 预设 UI）→ **G4**（WARDOGS / 欧洲卡车模拟两个预设）。
  取证与理由见 `docs/PalmDeck-v4-game-profiles.md`。
- ~~**`CockpitView.swift:58` 一条 Swift 警告**（`'weak' ownership of capture 'layout'`）
  —— 外层闭包已隐式强引用 `layout`，内层再 `[weak layout]` 语义矛盾。~~
  已随 E1 修掉（先落局部变量再弱引用）。
