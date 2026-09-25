# PalmDeck v4 · 真窗口（O3-full）：把控制台做成罗技驱动那样的窗口

> 立项来源：`docs/PalmDeck-v4-windows-installer.md §3.4` 的 **O3-full** ——
> 当时写「等 S1–S5 落地 + G4 反馈后另立方案」。v4.0.0 已发，本方案接上。
> 目标一句话：**控制台从「浏览器假装成窗口」变成 PalmDeck 自己的窗口**，
> 观感 / 行为对齐罗技鼠标驱动（Logitech Options / G HUB）。

---

## 1. 现状（证据）

| 维度 | 现在 | 问题 |
|---|---|---|
| 窗口 | `start.py::open_console()` 用 `msedge.exe --app=<url>` 打开 | **依赖 Edge/Chrome**；找不到就退回 `webbrowser.open`（普通标签页，带地址栏） |
| 任务栏 | 进程是 `msedge.exe` | 任务栏图标是 Edge 的，不是 PalmDeck 的 —— 「不像一个软件」 |
| 关闭 | 关掉窗口即结束 | **没有「关闭 = 最小化回托盘」**，托盘与窗口没有关系 |
| 几何 | 无 | 每次打开都是默认大小/位置，不记忆 |
| 状态 | 无窗口状态机 | 「窗口已关 / 托盘还活着」这件事不存在 |

`docs/PalmDeck-v4-windows-installer.md §3.4` 已把这条定性为 **O3-full**，
并列出代价：新增依赖 + WebView2 Runtime + 打包体积 + 一套窗口/托盘状态机。
**本方案就是来还这笔债的。**

## 2. 目标（可验收）

1. **真窗口**：PalmDeck 自己的窗口（任务栏是 PalmDeck 图标），内容仍是 `web/host.html`（**不新做一套 UI**）。
2. **关闭 = 最小化回托盘**：点窗口的 × 只是隐藏；进程/桥接/托盘继续跑。
3. **记忆几何**：窗口大小与位置落盘，下次原样恢复。
4. **托盘联动**：
   - 托盘「打开控制台」→ **显示已有窗口**（没有才新建）。
   - 托盘「退出」→ 销毁窗口 + 停托盘 + 退进程。
   - 重复双击 exe（单实例锁）→ 唤出已有窗口（`#doctor` 等 hash 直达仍有效）。
5. **绝不倒退**：pywebview / WebView2 / 平台任一层不可用时，**自动退回 O3-lite**
   （Edge/Chrome `--app=` → 默认浏览器）。**不存在「窗口打不开」**。

## 3. 方案

### 3.1 依赖与平台

- 新增 `pywebview`（Windows 后端 = **Edge WebView2**）。
- **只对 Windows 开启**（`os.name == "nt"`）：本方案的服务对象是 Windows 桌面程序；
  macOS/Linux 继续走 O3-lite。**macOS 是开发机，不是交付面**，所以本方案的核心行为只能在
  Windows CI 冒烟 + G4 真机上验（与安装包同款诚实口径）。

### 3.2 线程模型（关键）

```
主线程          → pywebview 的 GUI 消息循环（webview.start()，会阻塞）
  ├─ 后台线程    → pystray 托盘（win32 后端自带消息循环，可跑在子线程）
  ├─ 后台线程    → bridge（现状不变）
  └─ 后台线程    → 单实例锁命令通道（现状不变）
```

- **GUI 必须在主线程**（pywebview 各平台的一致要求），所以托盘让位到子线程。
- 退回 O3-lite 时，托盘仍占主线程（现状不变）。

### 3.3 状态机

```
                 可用                       「打开控制台」
   [ 无窗口 ] ─────────► [ 窗口=显示 ] ◄────────────────┐
        ▲                   │  × (closing)              │
        │  退出(托盘)         ▼                           │
        │              [ 窗口=隐藏 ] ── 「打开控制台」────┘
        └──── 进程退出 ◄──── 退出(托盘)
```

- `closing` 事件：保存几何 → `window.hide()` → **返回 False**（取消真正的关闭）。
- 托盘「退出」：置 `_quitting = True` → `window.destroy()`（放行这次关闭）→ `icon.stop()`。

### 3.4 几何持久化

- 存 `%APPDATA%\PalmDeck\window.json`（`palmdeck_config.config_dir()` 同目录）。
- **不进 `palmdeck_config.DEFAULTS`**：那是服务配置（会出现在 `/api/config` 面板），
  窗口几何是 UI 状态，两码事。
- 只记 `{w,h,x,y}`；越界 / 尺寸过小 → 校验后丢弃，回落默认（显示器换了不至于开到屏幕外）。
- 卸载保留 `%APPDATA%\PalmDeck`（既有语义），所以几何跨更新存活。

### 3.5 兜底矩阵（每一层失败都往下退）

| 条件 | 行为 |
|---|---|
| 非 Windows | O3-lite（现状） |
| `import webview` 失败 | O3-lite（现状） |
| WebView2 Runtime 不在（注册表查不到） | O3-lite，并**在日志里写明原因** |
| 窗口创建/启动抛异常 | 捕获 → 停窗口路径 → O3-lite + 日志 |
| `PALMDECK_NO_TRAY=1`（CI/无人值守） | 完全无界面（`run_headless`，现状），**不碰窗口** |

## 4. 影响面

| 文件 | 改动 |
|---|---|
| `palmdeck_window.py` | **新增**：可用性探测 / 几何读写 / `run()`（建窗、事件、`webview.start()`）/ `show()` / `quit()` |
| `start.py` | `main()` 第 4 步分叉：可用则「托盘走子线程 + 窗口占主线程」，否则现状 `run_tray()`；`open_console()` 先试显示已有窗口；`quit_app` 兼顾窗口 |
| `packaging/PalmDeck.spec` | `collect_all("webview")`（+ `pythonnet` / `clr_loader` 兜底）；hiddenimports 补 EdgeChromium 后端 |
| `packaging/PalmDeck.iss` | 安装时检测 WebView2 Runtime，缺失则静默装 Evergreen Bootstrapper（`PrivilegesRequired=lowest` → 按用户装） |
| `.github/workflows/build-windows.yml` | 装 `pywebview`；打包后**断言 webview 真的进了包**；冒烟仍 `PALMDECK_NO_TRAY=1` |
| `tests/test_window.py` | **新增**：手写假 `webview` 模块，验「closing→hide+存几何+返回 False」「托盘唤出→show」「退出→destroy」「缺依赖/非 Windows→不可用」；方案/守卫探针要能咬 |
| `docs/*` | 本文；`windows-installer.md §3.4` 标注 O3-full 已做；`README.md` / `TODO.md` 计数 |
| 协议 / `bridge.py` / `palmdeck_*.py` | **不改**（窗口只是把同一个网页放进自己的壳） |

**不变量**：控制台仍是 `http://127.0.0.1:<port>` 上的同一套 REST + WS；App 完全不知情；
**不新增服务配置键**（几何只进 `window.json`）。

## 5. 风险与对策

| 风险 | 对策 |
|---|---|
| pywebview 打包进 exe 很挑（pythonnet / clr_loader / WebView2 loader） | 用 `collect_all` + CI 里**真跑一遍 exe** 断言可导入；CI 红了用 `ci-diag` git 回传诊断（已有套路） |
| Win10 没有 WebView2 Runtime | 安装包带 Evergreen Bootstrapper，缺失则装；**装不上也不崩** —— 运行期退回 O3-lite |
| 窗口/托盘双循环死锁 / 关不掉 | 状态机 + `_quitting` 放行；**退回路径永远可达** |
| exe 体积上涨 | 记录前后体积；只在 Windows 侧收，`vendor/` 的 vgamepad 不受影响 |
| macOS 开发机验不了 | 诚实写进文档：核心行为靠 **Windows CI 冒烟 + G4 真机**，与安装包同一口径 |

## 6. 验收

- 真机（G4 补条目）：① 任务栏是 PalmDeck 图标；② × 只隐藏，托盘还在；③ 重开位置/大小不变；
  ④ 托盘「打开控制台」唤出、`#doctor` 直达；⑤ 托盘「退出」真退；⑥ 关掉窗口后手机仍连、游戏里手柄仍动。
- CI（已验，run 36165113841 / `ci-diag` 分支 `status=success`）：`test` job 新守卫全绿；
  `build` job 断言 webview 在包内 + 冒烟（无界面）仍绿。
- 退回：把 WebView2 检测打桩为「缺失」时，日志出现退回原因、O3-lite 打开成功。
