# PalmDeck v4 自动发现：手动「重新搜索」

**状态**：✅ 已落地
**影响范围**：App 侧（`Discovery.swift` + `PreflightView.swift`）。**不碰协议、不碰电脑侧。**
**一句话**：起飞页发现列表加一个「重新搜索」，换 Wi-Fi / 电脑刚开机时不用退出重进。

## 1. 目标

`Discovery` 只在 `PreflightView.onAppear` 时 `start()` 一次，`onDisappear` 时 `stop()`。
首轮没搜到（电脑后开机 / 手机刚切到新 Wi-Fi / 本地网络授权弹窗点晚了）之后，
**没有任何办法在同一个页面里再搜一次**，只能退出重进。而「没搜到」恰恰是最常见的状态。

## 2. 现状与证据

- `PreflightView.swift`：`.onAppear { discovery.start() }` / `.onDisappear { discovery.stop() }`，
  页面里没有第二个触发点。
- `Discovery.swift`：`start()` 有 `guard !running`；`stop()` 只把 `browser` 停掉、
  不清 `found` / `services`。6s 后若仍空，只把 `statusText` 改成
  「没搜到电脑（需同一 Wi-Fi / 已授权本地网络）」——**告诉了他原因，没给他动作**。

## 3. 方案

- `Discovery.restart()`：`stop()` → 清空 `found` / `services` → `statusText = "搜索中…"`
  → `start()`。
- `start()` 加一个 `searchGen` 计数器，6s 兜底定时器回调里校验
  `self.searchGen == gen`：不这么做的话，手动重搜后**上一轮**的定时器会立刻
  把状态改成「没搜到电脑」（刚点完重搜就报失败）。
- `PreflightView` 右栏在三步卡片下方加一个常驻的「重新搜索」小按钮
  （`arrow.clockwise`，`Theme.cyan`），点它调 `discovery.restart()`。
  发现列表非空时也在。

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 | 不改 |
| 电脑侧 | 无 |
| App 侧 | `Discovery.swift` / `PreflightView.swift` |
| 文档 | 本文件 + `docs/README.md` |

## 5. 验证方式

- 守卫 `tests/test_connect_ux.py::TestDiscoveryRescan`（源码级）。
- 手动：起飞页先不开电脑 → 看到「没搜到电脑」→ 开电脑 → 点「重新搜索」→ 列表出现。

## 6. 边界与不做

- 不做「按 IP 段主动扫」（Bonjour 够用；主动扫会触发本地网络权限噪音且慢）。
- 不改 6s 兜底时长，不改发现结果排序。

## 7. 工作量

**S**。
