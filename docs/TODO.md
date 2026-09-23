# PalmDeck 待办

## 遥测（Telemetry）
- [x] 手机端：WebSocket 收到 `{"type":"attitude"}` 时，切换姿态球/直升机的显示源
      （从"本地杆位 smRoll/smPitch"切到"游戏真实姿态"）；收不到则回退杆位。
      实现：`ControllerState.displayRoll/Pitch/Yaw` 按 `displaySource` 选源，
      `AttitudeBall` 与 `HelicopterScene` 均用 display*，读数同步；
      `CockpitController` 1.5s 无姿态包自动 `telemValid=false` 回退杆位。
      这样以后接上 WARDOGS 数据源时，App 无需再改。
- [ ] 确认 WARDOGS 是否提供姿态数据、字段名、获取方式（HTTP? 内存? 插件?）
- [ ] 若提供：补 `telemetry.py` 的 WARDOGS 专用读取器 + `--telemetry-map`
      （现有 `HttpJsonTelemetry` / `UdpJsonTelemetry` 已可接通用 HTTP/UDP JSON 源）
