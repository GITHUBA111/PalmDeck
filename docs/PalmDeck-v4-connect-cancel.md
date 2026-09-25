# PalmDeck v4 连接可取消 / 重连有上限

**状态**：✅ 已落地
**影响范围**：App 侧（连接状态机 + 三处连接入口）。**不碰协议、不碰电脑侧。**
**一句话**：连不上电脑时不再无限重连 —— 用户在「连接中」随时能「取消」，
自动尝试若干次仍失败就停下来，给一个「重试」。

## 1. 目标

现在点「一键连接」后，如果电脑没开 / 防火墙拦了 8765，App 会**永远**退避重连；
而三个连接入口在「连接中」都没有取消：

| 入口 | 位置 | 「连接中」时的行为 |
|---|---|---|
| 座舱顶栏「一键连接」 | `CockpitView.swift` `connectionChip` | 再点只会又发一次 connect（不取消） |
| 起飞页状态条按钮 | `PreflightView.swift` `statusButton` | 显示「…」且 `disabled`（点不动） |
| 设置 → 可用电脑 | `SettingsView.swift` `connectionSections` | 只有「连接」，没有停 |

用户能做的只有**等**，或者杀掉 App。这是产品缺陷，不是体验优化：
「不做的代价 = 用户被卡在一个没有出口的转圈里」。

## 2. 现状与证据

- `CockpitController.swift`：`private var retry = 0`；`handleClose()` 与
  `handleConnectTimeout()` 各自 `DispatchQueue.main.asyncAfter` 重排一次
  `reconnect()`，唯一的停止条件是 `guard autoReconnect`——**`retry` 没有上限**。
- `NetClient.swift`：`connectTimeoutWork` 8s 触发 `onConnectTimeout`（电脑不在线也走这条路）。
- `CockpitView.swift:245`：顶栏按钮 action 与 `s.link` 无关，连接中点了还是 `connect()`。
- `PreflightView.swift:158`：`Button(s.link == .connecting ? "…" : "连接")` 且 `.disabled`。
- `SettingsView.swift:637`：`.live` 才给「断开连接」，`.connecting` 什么都不给。

## 3. 方案

**状态机**（`CockpitController`）：
- 新增 `private let maxAttempts = 6`、`@Published var connectFailed = false`。
- 新增 `private func scheduleReconnect(base:step:cap:)`，`handleClose` /
  `handleConnectTimeout` 都改走它；`retry >= maxAttempts` 时：
  `autoReconnect = false`、`connectFailed = true`、文案
  「连不上 <host>（已试 N 次），点「重试」」。
- 新增 `func cancelConnect()`：`autoReconnect = false` + `net.disconnect()` +
  回 `.idle` + 文案「已取消连接」。
- `connect()` 重置 `retry = 0` / `connectFailed = false`；`handleOpen()` 清 `connectFailed`。

**三个入口**（`连接中` → 取消，`connectFailed` → 重试）：
- `CockpitView.connectionChip`：连接中改显示 `xmark.circle.fill` + 「取消连接」，
  action 走 `cancelConnect()`；失败后文字变「重试」。
- `PreflightView.statusButton` + `statusTitle`：连接中按钮变「取消」；
  整条状态栏的 `onTapGesture` 在 connecting / live 时不重复发起。
- `SettingsView.connectionSections`：新增 `.connecting` 分支「取消连接」，
  以及 `connectFailed` 时的「重试连接 <host>」。

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | 不改 |
| 电脑侧（bridge / pack） | 无 |
| App 侧 | `CockpitController.swift` / `CockpitView.swift` / `PreflightView.swift` / `SettingsView.swift` |
| 文档 | 本文件 + `docs/README.md` 状态表 |

## 5. 验证方式

- 新守卫 `tests/test_connect_ux.py::TestConnectHasAnEscapeHatch`（源码级对账）。
- 手动：关掉电脑 → 点连接 → 要么中途点「取消」立刻停、要么等它自己停在
  「连不上…点「重试」」，**不再永远转**。

## 6. 边界与不做

- **不改退避算法本身**（仍 `0.6 + n*0.4` 封顶 4s / `1.0 + n*0.5` 封顶 8s），
  只加上限与出口。
- 不重做手动 IP 输入校验，不动自动发现。
- 协议与电脑侧一行不动。

## 7. 工作量

**S**。步骤：①状态机 + `cancelConnect`；②三处入口接线；③守卫。
