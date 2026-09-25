# PalmDeck v4 控制台「输入监测」实时化

**状态**：✅ 已落地
**影响范围**：电脑侧控制台网页（`web/host.html`）。**不碰协议、不碰服务接口。**
**一句话**：输入监测页从「1 秒轮询一次」改成监测页激活时 10Hz 刷新，
并把会被误读成「延迟」的 `last_ms` 写清楚。

## 1. 目标

用户在「输入监测」页看到的轴条**一秒才跳一下**，于是以为 App 到电脑的输入有
一秒延迟。真实链路是 iOS 60Hz → UDP 7773 → vJoy，延迟是毫秒级（见
`docs/PalmDeck-v4-redesign.md`「输入监测 10–20ms」）。慢的是**看板刷新**，不是链路。
看板慢会误导用户去调本来就好的东西。

## 2. 现状与证据

- `web/host.html` boot：`setInterval(tick, 1000)`，`tick()` 拉 `/api/status`，
  `renderStatus` 里 `renderAxes(s.axes)`。→ 轴值最多滞后 ~1s。
- 同一个时间线里还挂了 `setInterval(loadLogs, 2000)` 与 doctor 轮询 5000ms，
  都只在对应 tab 激活时才发请求；**监测页没有同类加速**。
- `$("hz").textContent = s.hz + " Hz · " + s.last_ms + "ms"`：
  `last_ms` 是 `bridge.py` 里 `time.monotonic() - last`，即「距上一包多久」，
  在流动时约等于 `1000/hz`，**不是延迟**；挂机时它会一直涨。带个 `ms` 显示会被当成 ping。

## 3. 方案

- 新增 `monitorFast` 定时器：`activateTab("monitor")` 时开 100ms 轮询，
  切走即关；1s 的那个 tick 在快轮询运行时跳过，避免重复请求。
- 文案：`Hz` 后的 `… ms` 改成「上包 X ms 前」，明确是**包间隔**而非延迟。

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 / 服务接口 | 不改（仍是 `/api/status`） |
| 电脑侧 | 只有 `web/host.html` |
| App 侧 | 无 |
| 文档 | 本文件 + `docs/README.md` 状态表 |

## 5. 验证方式

- 新守卫 `tests/test_connect_ux.py::TestMonitorRefreshesFast`（源码级）。
- 手动：打开监测页，快速推杆，轴条应连续跟随而不是一秒一跳。

## 6. 边界与不做

- **不做 SSE / WebSocket 推送**：本地回环 HTTP 10Hz 已够看，先不引入长连接。
- 不改 `/api/status` 的字段与 `bridge.py` 的统计口径。

## 7. 工作量

**S**。
