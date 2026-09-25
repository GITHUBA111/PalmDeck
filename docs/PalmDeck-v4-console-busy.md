# PalmDeck v4 控制台长动作：超时 + 忙碌态

**状态**：✅ 已落地
**影响范围**：电脑侧控制台网页（`web/host.html`）。**不碰服务接口。**
**一句话**：控制台里几个会「卡住不动」的按钮（检查更新 / 下载并重启 / 保存配置 /
保存布局）加请求超时与忙碌态，不再出现「点了没反应、还能连点」。

## 1. 目标

`api()` 直接用 `fetch`，**没有任何超时**；而这几条请求在服务端是**同步**跑的：

| 按钮 | 服务端耗时上限 | 现状 |
|---|---|---|
| 检查更新 | 8s 网络 + 排队 | 无超时；文本停在「检查中…」 |
| 下载并重启 | 8s 检查 + **120s 下载** | 无超时、无进度、按钮**可连点** |
| 保存配置 / 保存布局 | 快 | 无超时、无忙碌态 |
| 环境自检 | 多条 PowerShell，可能几十秒 | 无超时 |

服务一旦卡住（磁盘慢 / 网络半死），按钮就永远是那个样子，用户不知道是在忙还是死了。
「不做的代价 = 用户分不清『在下载』和『程序死了』」。

## 2. 现状与证据

- `web/host.html` `async function api(path, opts)`：`await fetch(path, opts)`，
  无 `AbortController`、无 `signal`。
- `$("applyUp").onclick`：`await api("/api/update/apply", { method: "POST" })`，
  期间**不 disable**，可重复触发；`updater.py:113` 的 `urlopen(..., timeout=120)`
  意味着最坏要等 2 分钟。
- `$("checkUp").onclick` / `$("saveCfg").onclick` / `$("layoutSave").onclick` 同样无忙碌态。
- 对照（做对了的）：`fixDoctor()` 会 `btn.disabled = true` + `finally` 恢复，
  且重查循环 15×2s 有界、切走即停。

## 3. 方案

- `api(path, opts, timeoutMs = 30000)`：`AbortController` + `setTimeout`，
  超时抛「请求超时（Ns）」，`finally` 清定时器。自检 / 修复类给 60s，
  下载并重启给 180s，覆盖服务端 120s 上限。
- 新增 `busy(btn, label, on)`：进忙碌态记住原文案、`disabled = true`、改文案；
  退出时恢复。`applyUp` 退出后再按 `!info.can_self_update || !LATEST` 重算 disabled
  （不能简单恢复成可点——没有新版时它本就该灰）。
- 接线：`checkUp`「检查中…」、`applyUp`「下载中…」+ `latestVer` 提示最长约 2 分钟、
  `saveCfg`「保存中…」、`layoutSave`「保存中…」、`layoutReset`「重置中…」。

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 / REST | 不改（只加了客户端 `signal`） |
| 电脑侧 | 只有 `web/host.html` |
| App 侧 | 无 |
| 文档 | 本文件 + `docs/README.md` |

## 5. 验证方式

- 守卫 `tests/test_connect_ux.py::TestLongActionsHaveAnEscapeHatch`（源码级）。
- 手动：断网后点「检查更新」，30s 内应给出「请求超时」而不是永远「检查中…」。

## 6. 边界与不做

- 不做真正的下载进度条（服务端同步阻塞，没有 progress 接口；要加得先改
  `/api/update/apply` 为异步 + 轮询，成本不小，收益只是视觉）。
- 不动服务端任何端点。
- `tick()` 加了 `tickBusy` 重入锁：10Hz + 30s 超时下，服务端卡住会堆几百个
  在途 `/api/status`，所以同时只允许一个在飞。

## 7. 工作量

**S**。
