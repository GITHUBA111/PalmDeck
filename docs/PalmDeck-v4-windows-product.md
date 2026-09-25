# PalmDeck v4 · Windows 端服务产品化：统一自检 / 一键修复

### 方案名
Windows 端服务产品化 —— 统一自检（doctor）+ 一键修复 + 单一真相源

### 状态
已落地（P0-1 ~ P0-4；实现回写见 §8）

### 影响范围
电脑侧（bridge / 新增 doctor / 打包 / 托盘 / 网页控制台）+ 文档

### 一句话
把 Windows 侧散落的 4 个 `.bat`、2 份互抄的说明书、3 处各写一遍的驱动/防火墙/端口逻辑，
收成一个**服务自己说自己缺什么、并一键修**的「自检」页 —— 玩家装完驱动之后该看到的第一个界面。

---

## 1. 目标

要解决的真实问题（每条都能验证，不写「提升体验」）：

1. **不知道该双击哪个文件**。现在有 4 个 bat：`start.bat` / `setup_windows.bat` /
   `build_exe.bat` / `open_firewall.bat`；说明散在 `使用说明.txt` 和 `README.md` 两处，
   且互相矛盾（一个说「双击 setup_windows.bat」，一个说「运行 `python bridge.py`」）。
2. **出问题时服务不说话**。iPhone 连不上、游戏里没有设备，原因可能是：驱动没装、
   防火墙没放行、端口被占、依赖没装好。现在**只有一句**「未检测到 vJoy / ViGEm / uinput」，
   不说是缺哪一个、去哪装、怎么放行 —— 用户只能猜。
3. **同一件事写了两遍**：端口写死在 `open_firewall.bat`（8765/8080/7773/7774），
   真相源却在 `palmdeck_config.py`；驱动检测写死在 `setup_windows.bat`。
   用户在控制台改了端口 → 防火墙规则还是旧的。
4. **`open_firewall.bat` 是孤儿**：不在 `pack_windows.py` 的 FILES 里（**zip 里根本没有它**），
   也没有任何文档或界面指向它。「有功能但没人知道」≈ 没有。
5. **名字不统一**：「掌舵舱 / 座舱 / 控制台 / 桥接 / 守护程序 / 后端」混着用，
   托盘标题、网页标题、安装脚本各写各的。

**不做的代价**：这是产品唯一的「装机第一公里」。玩家在 Windows 上装完 vJoy + ViGEmBus、
双击 exe、开着游戏，却发现游戏里没有设备时，**没有任何地方可以问为什么** ——
只能来问作者。这是最贵的一种支持成本。

## 2. 现状与证据

| 结论 | 证据 |
|---|---|
| 4 个 bat、2 份说明书 | `start.bat` / `setup_windows.bat` / `build_exe.bat` / `open_firewall.bat`；`使用说明.txt:6`「双击 setup_windows.bat」、`README.md`「Windows 可双击 `start.bat`」 |
| 驱动检测只在一个 bat 里 | `setup_windows.bat` 的 `sc query vjoy` / `sc query ViGEmBus`；只有用户重新双击安装脚本才会再跑一次 |
| 端口两处写死 | `open_firewall.bat:22-26` 的 `-LocalPort 8765/8080/7773/7774` vs `palmdeck_config.py:20-26` 的 `DEFAULTS` |
| 防火墙脚本是孤儿 | `grep -rn open_firewall` 全仓库无引用；`pack_windows.py:20-33` 的 `FILES` 里没有它 |
| 后端探测已经有，但只到一句话 | `hotas.py:61-73`（`backend = "+".join(kinds)`）；`bridge.py:296-298`（`error: 未检测到 vJoy / ViGEm / uinput`） |
| 控制台没有「体检」入口 | `web/host.html:119-126` 六个 Tab 全是配置/监测（概览/输入监测/配置/布局/更新/日志） |
| 托盘不可见版本 | `start.py:301` `pystray.Icon("PalmDeck", …, "PalmDeck 掌舵舱", menu)` |
| 广播端口 7774 只在 bridge 里 | `bridge.py:58` `BEACON_PORT = 7774`（防火墙也得放行它） |

## 3. 方案

### 3.1 唯一自检真相源：新增 `palmdeck_doctor.py`

一个模块，**只有它**知道「什么算环境不对、以及怎么修」。托盘、控制台、bat、命令行 `--json`
四处都调它，不再各写一遍。

```python
checks(extra: dict | None = None) -> list[dict]   # 逐项体检
report(extra: dict | None = None) -> dict         # 给控制台 / --json 的完整报告
fix(fix_id: str, extra=None) -> dict              # 一键修复 {"ok":bool,"message":str}
allow_firewall() -> dict                          # 提权后真正加规则
firewall_rules() -> list[dict]                    # 当前规则（Windows）
main(argv)                                        # CLI：默认打报告；--json；--firewall
```

**检查项**（每项 `{id, level, title, detail, fix}`，`level ∈ ok/warn/error/info`）：

| id | 检查 | 不通过时 |
|---|---|---|
| `python` | 解释器版本 ≥ 3.9 | 给下载地址 |
| `dep.qrcode` / `dep.zeroconf` / `dep.pyvjoy` / `dep.vgamepad` / `dep.pystray` | 逐个 `importlib` 试 | 给 `pip install` 与「驱动下载页」两种修法 |
| `backend` | `extra["backend"]`（来自 hotas） | `none` → 指到驱动检查项 |
| `driver.vjoy` | `sc query vjoy`（Windows） | 打开 vJoy 下载页 |
| `driver.vigembus` | `sc query ViGEmBus`（Windows） | 打开 ViGEmBus 下载页 |
| `firewall` | `Get-NetFirewallRule -DisplayName 'PalmDeck*'` 条数够不够 | **一键放行**（提权） |
| `listener.http` / `listener.ws` / `listener.udp` | 读 `extra["listeners"]`（`serve_*` 里 bind 的成败） | 说「哪个端口被占了 / 去配置页改端口后重启」 |
| `lan` | `lan_ip()` 不是回环 | 说「没连上局域网」 |

**修法**（`fix(id)`）：
`firewall` → 提权跑 `palmdeck_doctor.py --firewall`（子进程，不阻塞）；
`driver.*` / `dep.*` → `webbrowser.open(...)` 打开对应下载页 / 给出 pip 命令。

非 Windows 平台，`driver.*` / `firewall` 返回 `info`「仅 Windows 需要」，不报错
（这样在 macOS 上开发也能跑同一份报告）。

### 3.2 控制台新增「自检」Tab（`web/host.html`）

- Tab 顺序：`概览` → **`自检`** → 输入监测 → 配置 → 布局 → 更新 → 日志。
- 内容：一张清单，每行 = 级别图标 + 标题 + `detail` + 右侧「修复」按钮（`fix` 为空则不显示）。
- 顶部一句话总结：`全部正常，去手机上打开座舱 App 就行` / `还有 2 项要处理`。
- 概览页在 `backend=none` 或 `error` 时，加一行「→ 去自检页看看」。
- 支持 `#doctor` 直达（托盘「自检…」用得上）。

### 3.3 托盘（`start.py`）

- tooltip 带版本：`title=f"PalmDeck v{APP_VERSION}"`。
- 菜单加「**自检…**」（打开控制台 `#doctor`），放在「打开控制台」下面。
- 启动时如果 `report()` 有 `error`，气泡提醒一次「有 N 项需要处理，点这里自检」。

### 3.4 防火墙：逻辑搬进 Python，删掉孤儿 bat

- `palmdeck_doctor.allow_firewall()` 用 `New-NetFirewallRule` 加 4 条规则，
  **端口从 `load_config()` 读**（http / ws / udp）+ `BEACON_PORT`。
- `BEACON_PORT` 从 `bridge.py` 提到 `palmdeck_config.py`（bridge 反向 import），
  这样防火墙和广播**同一个常量**，不再有第二处 7774。
- 删除 `open_firewall.bat`：它的功能进了控制台按钮 + 托盘，而它本来就不在 zip 里、
  也没人告诉用户去双击它。
- `setup_windows.bat` 的驱动检查同样改为调用 `palmdeck_doctor.py`（bat 只留 UAC/找 Python），
  不再自己 `sc query` + 自己拼下载链接。

### 3.5 术语统一（只改**面向用户**的字符串）

| 统一为 | 指 | 不再用 |
|---|---|---|
| **PalmDeck 服务** | 电脑上常驻的那个程序（托盘） | 守护程序 / 桥接 / bridge / 后端 |
| **控制台** | 浏览器里那个网页（`web/host.html`） | 网页控制台 / host 页 |
| **座舱 App** | iPhone 上的 App | 手机端 / 座舱 / App 侧 |
| **虚拟手柄设备** | vJoy / ViGEmBus 造出来的那个设备 | 虚拟设备 / 后端设备 |

代码内部标识（`bridge.py` / `hotas.py` / `Hub`）**不改名**，见 §6。

### 3.6 打包 / 打包清单同步

- `pack_windows.py` 的 `FILES` += `palmdeck_doctor.py`（否则 zip 里没有它 → 一启动 ImportError）。
  **已有测试会自动拦**：`tests/test_pack_windows.py::TestPackWindows` 用 ast 扫入口的同目录 import。
- `packaging/PalmDeck.spec` 的 `hiddenimports` += `palmdeck_doctor`（同一个测试也守）。
- `FILES` -= `open_firewall.bat`（已删）。

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改** |
| 电脑侧 | 新增 `palmdeck_doctor.py`；`bridge.py` +2 路由 + import；`start.py` 托盘 2 处；`palmdeck_config.py` +`BEACON_PORT`；`web/host.html` +1 Tab；`pack_windows.py` / `PalmDeck.spec` / `setup_windows.bat` 清单；删 `open_firewall.bat` |
| App 侧 | **不改** |
| 持久化 | 无新增键；`config.json` 结构不变 |
| 文档 | 本文件、`docs/README.md`、`docs/TODO.md`、`README.md`、`使用说明.txt` |

## 5. 验证方式

```bash
python3 -m unittest discover -s tests -t .
# 新增 tests/test_doctor.py：
#   report() 结构合法 / 每项都有 id+level+title / level 取值合法
#   listener.* 用的一定是运行时真实 bind 结果（不是再试一次 bind —— 端口已被自己占着）
#   非 Windows 上 driver.* / firewall 是 info，不出 error（macOS 开发机可跑）
#   BEACON_PORT 只在 palmdeck_config 定义一次（bridge 不再自己定义）
#   firewall 规则端口不含硬编码漂移（open_firewall.bat 已不存在）
#   bridge.py 注册了 /api/doctor 与 /api/doctor/fix
#   web/host.html 有 data-tab="doctor" 且调 /api/doctor
#   start.py 托盘 tooltip 带 APP_VERSION、菜单有「自检」
#   pack_windows.FILES / PalmDeck.spec 覆盖 palmdeck_doctor
```

可复现的人工验证（macOS 上就能做，因为 bridge 是跨平台的）：

```bash
PALMDECK_NO_UPDATE=1 python3 bridge.py --no-browser --no-beacon --no-bonjour
# 浏览器开 http://127.0.0.1:8080/#doctor → 截图「自检」页
curl -s http://127.0.0.1:8080/api/doctor | python3 -m json.tool
python3 palmdeck_doctor.py --json | python3 -m json.tool
```

Windows 专属项（`sc query` / `Get-NetFirewallRule` / 提权）**本机无法验证**，
只能靠「非 Windows 返回 info 不抛异常」+ 源码守卫，在方案里明写这条限制。

## 6. 边界与不做

- ~~**不做安装包**（Inno Setup / MSI）~~ → **已推翻并落地**：
  `docs/PalmDeck-v4-windows-installer.md`（Inno Setup 6，用户目录安装、免 UAC、中文向导、
  卸载删自启项但保留 `%APPDATA%\PalmDeck`）。当初写「本机验证不了」是对的 ——
  所以验证搬到 **CI 的 windows-latest（静默装 → 启动 → 探活 → 卸载的冒烟测试）**
  加 G4 真机；签名仍然是「不做」（见下）。
- **不静默安装驱动**。vJoy / ViGEmBus 是内核驱动，必须用户点「安装」+ 重启，没法塞进 exe。
  doctor 只做「检测 + 打开下载页」。
- **不给现成文件改名**（`bridge.py` / `start.py` / `hotas.py` / `web/host.html` 全部保留原名）。
  名字统一只在面向用户的字符串里做 —— 改文件名要动 spec、`pack_windows.FILES`、`updater`、
  一堆测试，风险远大于收益。
- **不做托盘里的设置窗口**。设置仍然只在控制台（浏览器）里做，避免两套 UI 分家。
- **不在 Windows CI 里跑完整测试**（当初的顾虑成立：有几个测试要 Swift 编译器、
  `sips`、`ast` 读 Swift 源码，windows-latest 上跑不了）。现在的做法是两条：
  ① `test` job 在 **macos-latest** 上跑全套（`needs: test` 卡住发版；iOS 纯逻辑要
  `swiftc`、启动页亮度要 `sips`，ubuntu 镜像的 swiftc 编不了 `import Combine` 的源码）；
  ② `build` job 在 **windows-latest** 上只跑**能在那台上真跑的那部分** ——
  打包 → 断言 exe 的版本资源 → 编译安装包 → 静默装 → `PALMDECK_NO_TRAY=1` 起进程 →
  轮询 `/api/status` → 卸载 → 断言自启项没了、配置还在（见 `tests/test_ci.py`）。
  「Windows 上从没验过」这个缺口因此缩到**只剩真机 / 真驱动 / 真游戏**（G4 清单）。
- **不碰 iOS 侧**。

## 7. 工作量

**M**，可独立验证的四步：

| 步 | 内容 | 验证 |
|---|---|---|
| P0-1 | `palmdeck_doctor.py` + `BEACON_PORT` 归位 | `palmdeck_doctor.py --json` 结构正确；`test_doctor.py` |
| P0-2 | `bridge.py` 两个路由 + `web/host.html` 自检页 | `curl /api/doctor`；浏览器截图 |
| P0-3 | `start.py` 托盘（版本 tooltip + 自检菜单 + 启动提醒） | 读源码守卫；Catalyst 无关 |
| P0-4 | 打包清单 / spec / `setup_windows.bat` 瘦身；删 `open_firewall.bat`；统一文案 | `pack_windows.verify()`；`make zip` |

## 8. 落地结果（实现回写）

四步全部落地，测试 **226 → 251**（新增 `tests/test_doctor.py` 25 条），实际实现与方案的差异：

| 差异 | 原因 |
|---|---|
| `bridge.doctor_extra()` 提到**模块级**函数 | 托盘和 HTTP handler 都要喂同一份运行时状态，写两遍必漂移 |
| 运行时状态字段叫 `HUB.listener_state`，不是 `HUB.listeners` | `Hub.listeners` **已被占用**（状态订阅回调列表）。首次实现直接撞车，4 条 `test_mode_park` 报 `'dict' object has no attribute 'append'` —— 测试拦住了 |
| `serve_udp` / `accept_ws` bind 失败时 `sock.close()` | 不关会漏 fd（`-W error::ResourceWarning` 测出来的） |
| 控制台 tab 上加红色数字 badge + 概览页「去自检 →」按钮 | 光有 tab 用户不会点；badge 是唯一的“有问题”信号 |
| 自检页每 5s 自动重查（仅在该 tab 可见时） | 修完驱动/放行后不用手刷 |
| `fix()` 返回 `needs_recheck`，控制台据此连续重查 15 次 | 弹 UAC / 装 pip 都要等，重查一次会看到旧结果 |
| 提权失败 / 子进程出错弹 `MessageBoxW` | 提权子进程的黑框一闪就没，报错必须看得见 |
| `setup_windows.bat` 删掉了全部 `sc query` | 驱动检测只在 doctor 里（守卫：`assertNotIn("sc query", ...)`） |

实测（macOS，`192.0.2.1` = TEST-NET-1 本机不存在的地址）：

```text
listener udp 起不来：[Errno 49] Can't assign requested address
  listener.udp error | 手机输入没起来（端口被占？） | …换个端口：控制台「配置」页改完保存，然后重启服务。
summary: {'ok': 4, 'warn': 0, 'error': 4, 'info': 7}   # 三个 listener + backend
```

即：端口真被占时，用户第一次能在控制台看到「哪个端口、为什么、怎么改」，
而以前只有后台线程里一行 traceback。

