# PalmDeck 待办

## 遥测（Telemetry）
- **不做**。v4 移除了整套游戏遥测（`telemetry.py` / `bridge.py --telemetry*` / WS `attitude`）。
  姿态球与飞行仪表板只显示本机发往电脑的**平滑杆位**（`smRoll/smPitch/smYaw`），
  与 UDP/WS 上真正送出的值同源；不再有「游戏真实姿态」回读与显示源切换。

## 已完成
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
- 无。
