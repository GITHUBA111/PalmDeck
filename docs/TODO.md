# PalmDeck 待办

## 遥测（Telemetry）
- **不做**。v4 移除了整套游戏遥测（`telemetry.py` / `bridge.py --telemetry*` / WS `attitude`）。
  姿态球与飞行仪表板只显示本机发往电脑的**平滑杆位**（`smRoll/smPitch/smYaw`），
  与 UDP/WS 上真正送出的值同源；不再有「游戏真实姿态」回读与显示源切换。

## 已完成
- **布局模板（保存 / 切换 / 还原）** —— 每模式 12 个命名快照，点行即切换，左滑重命名/删除，
  内置「默认」即还原点；`清空`/`恢复默认`/`应用模板` 前压撤销槽。
  存储 `palmdeck_layout_templates_v1` / `palmdeck_layout_undo_v1`。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §7.2，方案留存于 `docs/PalmDeck-proposal-template.md` §2。

## 已存档（方案已保存，未实施）
- 无。

## 其它
- 无。
