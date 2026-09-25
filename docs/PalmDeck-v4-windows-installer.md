# PalmDeck v4 · Windows 端「软件化」：安装包 + 图标/版本 + 窗口化控制台

### 方案名
Windows 端从「绿色单文件 exe」升级为「装上去像正规软件」

### 状态
**已落地（S0–S5 + O1b 全部实施）**。S0 三个决策点按评审结论执行：
① 加 `PALMDECK_NO_TRAY`；② 装到 `{localappdata}\Programs\PalmDeck`（免 UAC + 安装目录可写）；
③ 卸载保留 `%APPDATA%\PalmDeck`、但删掉自启项。**签名仍不做**（见 §6）。
守卫测试：`tests/test_installer.py`（38 条）、`tests/test_ci.py`（CI 与清单）。

### 影响范围
**电脑侧打包 / CI / 文档**。协议不动、App 不动、`bridge.py` 逻辑不动。
唯一碰到的运行时代码是 `packaging/PalmDeck.spec`（图标 + 版本资源）与
`start.py:147/269`（用哪个程序打开控制台）。

### 一句话
给 Windows 端做真正的安装包（安装向导、开始菜单、卸载项、可选开机自启）、
给 exe 配上图标与版本资源、把「控制台」从浏览器标签页变成独立窗口；
做成/免安装两条路都保留。

---

## 1. 目标

### 现状对玩家的三处「不像软件」

| 玩家看到 | 感受 |
|---|---|
| 下载 `PalmDeck.exe` → 双击 → **SmartScreen「Windows 已保护你的电脑」** → 得自己找「更多信息 → 仍要运行」 | 「这是不是病毒？」——第一印象就崩了 |
| 文件属性里**没有产品名 / 版本 / 公司**，exe 图标是 PyInstaller 默认图标；任务管理器里是一行没有形状的进程 | 「这什么东西」 |
| 装完只有托盘图标；「控制台」是**默认浏览器里多出来的一个标签页**（混在自己一堆网页里），没有开始菜单项、没有桌面快捷方式、控制面板「应用」里查不到、想卸载只能去删文件 | 「这不叫装了软件，这叫放了个 exe」 |

### 不做的代价（可验证）

- 玩家每次首启都要过一次 SmartScreen 恐怖页 —— 这一条会直接劝退一部分人，
  而它是**纯观感成本**：exe 本身没问题。
- 没有卸载项 ⇒ 玩家想清掉时去删 exe，**而托盘「开机自启」注册表项还在**
  （`start.py:181` HKCU Run 键），下次开机 `PalmDeck.exe` 找不到 → Windows 弹报错框。
  这是真实的功能缺陷，不是观感问题。
- 控制台在浏览器标签页里 ⇒ 玩家关掉浏览器就「找不到设置了」，
  只能凭记忆去点托盘菜单。

---

## 2. 现状与证据

**分发方式**：GitHub Release 直挂**单个 portable exe**，自更新按固定 URL 拉同名资产。

```
updater.py:27  GITHUB_EXE = ".../releases/latest/download/PalmDeck.exe"   # 资产名写死
updater.py:31  def can_self_update(): return sys.frozen and os.name == "nt"
updater.py:62  def apply_update(): exe_dir = dirname(sys.executable); 写 PalmDeck.exe.new + update.bat
updater.py:100 def restart_after_update(): cmd /c update.bat → 自替换 → 重启
```
→ `apply_update` 把新 exe 写在**自己所在目录**：**安装目录必须可写**，
否则自更新静默失效（`main()` 里失败只 log 一句就继续用旧版，`start.py:335`）。

**exe 现状**（`packaging/PalmDeck.spec` 尾部 EXE 调用）
```
console=False,     # 已经没有黑框了（这点不用改）
icon=None,         # ← 没有图标
# 没有 version= 参数   ← 没有版本资源，文件属性空白
```

**原生 UI 只有托盘**，唯一窗口是外部浏览器：
```
start.py:147/154   notify_existing(): webbrowser.open(http_url())
start.py:269/270   open_console():  webbrowser.open(http_url())
start.py:273/274   open_doctor():   webbrowser.open(http_url("#doctor"))
start.py:301-312   托盘菜单 7 项 + tooltip "PalmDeck v4.0.0 — 掌舵舱"
```

**开机自启**是 HKCU Run 键，托盘菜单可切：
```
start.py:160  _AUTOSTART_KEY  = r"Software\Microsoft\Windows\CurrentVersion\Run"
start.py:161  _AUTOSTART_NAME = "PalmDeck"
start.py:188  SetValueEx(..., f'"{_exe_path()}"')      # _exe_path() = sys.executable
```

**版本号唯一真相源**：`updater.py:25 APP_VERSION = "4.0.0"`
（`tests/test_version.py` 要求它与 `bridge.PROTOCOL_VERSION` 主版本一致）。

**源码路径下的 bat 是开发者的，不是玩家的**：
`setup_windows.bat` 要 Python + pip（玩家机器没有）；
`start.bat` 同理；`build_exe.bat` 是打包脚本。玩家的说明书（`使用说明.txt`）
把「双击 ① / 双击 ②」当成主线 —— 这条主线只对**从源码跑**的人成立。

**历史上是主动推迟的**：
```
docs/PalmDeck-v4-windows-product.md:172
  - **不做安装包**（Inno Setup / MSI）。要做，得在 Windows 上迭代签名与 UAC 文案，
    本机验证不了。→ P2。
```
这条理由要更新：**开发机是 macOS，但 CI 的 `windows-latest` 是台真 Windows**
（`.github/workflows/build-windows.yml` 已经在上面出 exe），
而且 G4 真机验收（`docs/windows-acceptance-checklist.md`）本来就要在真 Windows 上做。
「本机验证不了」变成了「在 CI + G4 上验证」。

---

## 3. 方案

### 3.1 决策点（四档，可拆开选）

| 档 | 内容 | 成本 | 风险 | 建议 |
|---|---|---|---|---|
| **O1** | **图标 + 版本资源**（改 spec 两行 + 一个 `.ico`） | **S** | 极低 | ✅ **已落地（见 §8）** |
| **O2** | **Inno Setup 安装包**（向导 / 开始菜单 / 卸载 / 可选自启） | **M** | 中（卸载 UAC、CloseApplications 文案只能在真机试） | **建议做** |
| **O3** | **控制台窗口化** —— 两档见 §3.4 | S（lite）/ L（full） | 低 / 中 | lite 顺手做；full 待证据 |
| **O4** | 代码签名（消 SmartScreen） | 钱 + 实名 | — | **不做**（§6），但要给玩家一句「怎么绕过」 |

### 3.2 O1：图标 + 版本资源（S）

- 图标源：`mobile/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png`
  （1024×1024，已是产品图标）→ PIL 生成多尺寸 `packaging/PalmDeck.ico`
  （16/32/48/64/128/256）。**生成的 `.ico` 入库**（PNG 源不变，`.ico` 是派生物，
  和 `dist/` 无关，体积 ~100 KB）。生成脚本可选放 `packaging/make_icon.py`，
  但不是构建必经路径 —— 免得给 CI 加一步可失败的东西。
- 版本资源：PyInstaller `version=` 指向 `packaging/version_info.txt`（`VSVersionInfo`），
  字段值**从 `updater.APP_VERSION` 读**，不手抄：

```python
# packaging/version_info.py（spec 里 import）
from updater import APP_VERSION      # ← 唯一真相源，不在第二处写 "4.0.0"
VSVersionInfo(ffi=FixedFileInfo(filevers=vtuple(APP_VERSION), prodvers=vtuple(APP_VERSION)),
              kids=[StringFileInfo([StringTable('040904B0', [
                  StringStruct('CompanyName',    'PalmDeck'),
                  StringStruct('FileDescription','PalmDeck — 手机当杆的电脑端服务'),
                  StringStruct('FileVersion',    APP_VERSION),
                  StringStruct('ProductName',    'PalmDeck'),
                  StringStruct('ProductVersion', APP_VERSION),
                  StringStruct('OriginalFilename','PalmDeck.exe')])]),
                    VarFileInfo([VarStruct('Translation', [1033, 1200])])])
```
- spec 改动：`icon=...ico`、`version=...`。

**验证**：CI 里 `(Get-Item dist\PalmDeck.exe).VersionInfo` 断言 `ProductVersion == APP_VERSION`；
本地 macOS 上可断言 `packaging/PalmDeck.ico` 存在且含 256 尺寸。

### 3.3 O2：Inno Setup 安装包（M）

**选型 Inno Setup 6**（免费、单文件产物、脚本即代码、CI 上现成：
GitHub 的 `windows-latest` 镜像自带 `ISCC.exe`，缺失时 `choco install innosetup -y` 兜底）。
不用 MSI（WiX 学习/维护成本高）、不用 NSIS（脚本语言更别扭）。

**关键决策：装到用户目录，不要管理员权限**
```
DefaultDirName={localappdata}\Programs\PalmDeck
PrivilegesRequired=lowest
```
三个连带好处：① 全程**不弹 UAC**，安装像普通软件一样顺；② 目录可写 ⇒
**`updater.apply_update()` 原地自替换继续有效**（装到 `Program Files` 就会静默失效）；
③ 卸载不需要提权。

**`packaging/PalmDeck.iss`（草案）**
```ini
[Setup]
AppName=PalmDeck
AppVersion={#AppVersion}                      ; 由 CI 从 updater.APP_VERSION 生成 /d 传入
AppPublisher=PalmDeck
DefaultDirName={localappdata}\Programs\PalmDeck
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
SetupIconFile=..\packaging\PalmDeck.ico
UninstallDisplayIcon={app}\PalmDeck.exe
OutputDir=..\dist
OutputBaseFilename=PalmDeck-Setup-{#AppVersion}
WizardStyle=modern
Compression=lzma2/max
CloseApplications=yes                          ; 卸载/覆盖时用 Restart Manager 让托盘进程退出
ArchitecturesInstallIn64BitMode=x64compatible   ; Inno ≥6.3；6.2 写 x64

[Files]
Source: "..\dist\PalmDeck.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\PalmDeck"; Filename: "{app}\PalmDeck.exe"
Name: "{autodesktop}\PalmDeck"; Filename: "{app}\PalmDeck.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked
Name: "autostart";   Description: "开机自动启动";     Flags: unchecked

[Registry]
; 与 start.py:160/161 的键名逐字一致 → 托盘开关与安装选项是同一个开关，不会打架
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
  ValueType: string; ValueName: "PalmDeck"; ValueData: """{app}\PalmDeck.exe"""; \
  Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\PalmDeck.exe"; Description: "立即启动 PalmDeck"; \
  Flags: nowait postinstall skipifsilent
```

**卸载语义（要写进文档，也要进 G4 清单）**
- 卸载**不管** `%APPDATA%\PalmDeck`（日志 / 配置 / 布局）—— 默认保留，理由：
  重装不该丢布局；玩家想清干净的地方在「打开日志」里能看到路径。
- `uninsdeletevalue` ⇒ 卸载时**把开机自启注册表项一起删掉**。
  这正好修掉 §1 里那条真实缺陷（现在删 exe 会留个失效自启项）。
- 托盘里手动开的自启与安装时的选项**是同一个值**，任一处关掉即关掉。

**`setup_windows.bat` 的定位收回**：它继续存在，但**只服务源码运行/开发**
（文档里明确写「玩家用安装包，不需要 bat」）。

### 3.4 O3：控制台窗口化（两档）

**O3-lite（S，建议顺手做）**：仍然用系统浏览器，但用**应用窗口模式**打开：
```
msedge.exe --app=http://127.0.0.1:8080     （或 chrome.exe --app=...）
```
效果：**没有地址栏 / 标签栏 / 后退键**的独立窗口，观感与原生窗口几乎无差，
关掉即结束。实现只需在 `start.py` 的 `open_console()` 里优先找 Edge/Chrome
（注册表 `App Paths` 或标准安装路径），找不到就退回现在的 `webbrowser.open`。
**不新增任何依赖、不影响打包体积。**

**O3-full（已落地 → 见 `PalmDeck-v4-native-window.md`）**：用 WebView2 把控制台做成
真窗口（pywebview 宿主），记住窗口大小位置、关闭 = 最小化回托盘、托盘联动（唤出 / 退出）。
代价兑现：新增 `pywebview` 依赖 + WebView2 Runtime 兜底（Win11 自带；安装包用
`#if FileExists` 决定要不要带引导器、缺失时静默装，**装不上也不崩 —— 运行期退回 O3-lite**）
+ 打包体积 + 一套窗口状态机。原本推迟的理由是「有证据再改」：v4.0.0 发完、真机反馈到位，
本条即接上。（`docs/PalmDeck-v4-windows-product.md:178` 那条「不做托盘里的设置窗口、避免两套 UI
分家」仍成立：WebView2 只是把**同一个网页**放进自己的窗口，没有第二套 UI。）

### 3.5 数据 / 接口

**零新增**。安装包只摆布文件与注册表；控制台仍是 `http://127.0.0.1:<port>`
上的同一套 REST + WS；App 完全不知情。**不新增持久化键。**

---

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT（22B `<2sBB8hH`） | **不改** |
| `bridge.py` / `palmdeck_*.py` / `hotas.py` | **不改** |
| `start.py` | `open_console()` / `open_doctor()` 加浏览器 app 模式（O3-lite，约 20 行）；其余不动 |
| `packaging/PalmDeck.spec` | 加 `icon=` / `version=`；新增 `PalmDeck.ico` / `version_info.py` / `PalmDeck.iss` |
| `.github/workflows/build-windows.yml` | `build` job 加 ISCC 编译 + **静默安装冒烟**；Release 资产从 1 个变 2 个 |
| Release 资产 | **必须保留 `PalmDeck.exe` 原名**（`updater.py:27` 写死）—— 新增 `PalmDeck-Setup-x.y.z.exe`，两个都传 |
| 文档 | `使用说明.txt`（玩家主线改成「跑安装包」）、`docs/windows-acceptance-checklist.md`（§1 安装、§7 更新加真机步骤）、`docs/PalmDeck-v4-windows-product.md:172`（「不做安装包」改为指向本方案）、`docs/README.md`、`docs/TODO.md` |
| 测试 | 新增 `tests/test_installer.py`：spec 里 `icon=` 不为 None、`version=` 指向真文件、`.ico` 存在且含 256 尺寸、`.iss` 的 `DefaultDirName` 在 `{localappdata}`、`PrivilegesRequired=lowest`、`[Registry]` 的键名与 `start.py:160/161` **逐字相同**、`AppVersion` 不是硬编码（来自 `updater.APP_VERSION`）、CI 两个资产名都在 |

`tests/test_version.py` 已有 `APP_VERSION` 唯一真相源守卫 ⇒ 安装包的版本号天然跟着走。

---

## 5. 验证方式

**CI（`windows-latest`，这是本方案相对旧决策的关键增量）**
1. `pyinstaller packaging/PalmDeck.spec` → 断言
   `(Get-Item dist\PalmDeck.exe).VersionInfo.ProductVersion -eq $APP_VERSION`；`FileDescription` 非空。
2. `ISCC packaging\PalmDeck.iss` → 断言 `dist\PalmDeck-Setup-*.exe` 生成。
3. **静默安装冒烟（真端到端）**：
   ```powershell
   .\dist\PalmDeck-Setup-4.0.0.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
   $env:PALMDECK_NO_UPDATE=1; $env:PALMDECK_NO_TRAY=1
   Start-Process "$env:LOCALAPPDATA\Programs\PalmDeck\PalmDeck.exe"
   # 轮询 http://127.0.0.1:8080/api/status，最多 30s；拿到 JSON 即通过
   Stop-Process -Name PalmDeck
   & "$env:LOCALAPPDATA\Programs\PalmDeck\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES
   # 断言：安装目录空了、HKCU Run 项没了
   ```
   这条能一次性挡住「打包缺模块 / 装错目录 / 自启项残留」三类问题 ——
   也就是「Windows 真机从没验过」这个老缺口里**可自动化的那部分**。
   ⚠️ 需要 `PALMDECK_NO_TRAY`：`start.py` 现在没有这个开关
   （`run_headless()` 只在托盘 import 失败 / 运行时抛异常时才走，`start.py:265`、`start.py:318`）。
   加一个环境变量与既有的 `PALMDECK_NO_UPDATE`（`updater.py:45`）同款式；
   **没有它，CI 里托盘窗口可能导致冒烟不稳**。这条要在评审时确认（见 §7 S0）。
4. 若冒烟不稳：降级为只装不跑（1+2 保留），把「启动 → `/api/status`」挪进 G4 真机。

**本地（macOS）**
- `python3 -m unittest tests.test_installer -q`（全是源码/配置守卫）
- `python3 -c "import ast; ast.parse(open('packaging/version_info.py').read())"`

**G4 真机（`docs/windows-acceptance-checklist.md`，人工 + 截图）**
- 干净 Win10/11 上跑安装包：向导、开始菜单项、桌面快捷方式（勾选后）、
  首启不弹 SmartScreen ~~（未签名 ⇒ 还是会弹，见 §6）~~、控制台是独立窗口。
- 文件属性显示产品名/版本；任务管理器里显示图标与「PalmDeck」。
- 「应用和功能」里能看到 PalmDeck 并可卸载；卸载后自启项消失、`%APPDATA%` 保留。
- 装机后自更新仍能自替换（造一个假 Release 或把 `APP_VERSION` 调小验证）。
- 覆盖安装（同版本重跑安装包）不报错、不清配置。

---

## 6. 边界与不做

- **不做代码签名（O4）**。OV/EV 证书要花钱 + 实名，本方案不含。
  后果要**明写在说明书里**：未签名 exe 首启仍会过 SmartScreen / 浏览器下载警告；
  安装包本身也有一条「未知发布者」提示。这是**已知且接受**的成本，不是缺陷。
  （若将来买了证书，本方案的 `.iss` 加两行 `SignTool` 即可，不用重构。）
- **不静默安装 vJoy / ViGEmBus**。内核驱动必须用户点安装 + 重启 —— 与
  `PalmDeck-v4-windows-product.md:173` 一致，安装包只在结束时提示去控制台「自检」装驱动。
- **不动 `bridge.py` / 协议 / App**。
- **不给 exe 改名**（`PalmDeck.exe` 是自更新 URL 的一部分）。
- **不删 `setup_windows.bat` / `start.bat`**（源码运行仍需要），只在文档里分清主次。
- **不做自动更新改用安装包**。已装用户继续走原地自替换；安装包是**首次安装**路径。
  （想改成「下载新版安装包再静默覆盖」也做得到，但那要动 `updater.py` 的语义 ⇒ 另立方案。）

## 7. 工作量

**M**，五步，每步独立可验证：

| 步 | 内容 | 验证 | 预估 |
|---|---|---|---|
| **S0** | ✅ 评审确认：① 是否加 `PALMDECK_NO_TRAY`（CI 冒烟的前提）② 装到 `{localappdata}` 是否接受（免 UAC 换「程序在用户目录」）③ 卸载保留 `%APPDATA%` | — | 本次评审 |
| **S1** | O1：`.ico` + `version_info.py` + spec 两行 | CI 断言 `VersionInfo.ProductVersion`；`test_installer.py` | ✅ 已落地 |
| **S2** | O2：`PalmDeck.iss` + CI 里 ISCC 编译 + Release 传第二个资产 | `dist\PalmDeck-Setup-*.exe` 生成；测试守卫 `.iss` 与 `start.py` 键名一致 | ✅ 已落地 |
| **S3** | CI 静默安装冒烟（含 `PALMDECK_NO_TRAY`） | 上面的 PowerShell 脚本全绿 | ✅ 已落地 |
| **S4** | O3-lite：`open_console()` 优先 Edge/Chrome `--app=` | 真机截图（G4 §1）；找不到浏览器时退回原路径 | ✅ 已落地（真机截图待 G4）|
| **S5** | 文档回写：`使用说明.txt` 主线改安装包、G4 清单加安装/卸载/覆盖安装、`windows-product.md:172` 改指向 | 文档守卫 + G4 走一遍 | ✅ 已落地（G4 走一遍待真机）|

O3-full（WebView2）**不在本方案工作量里**，等 S1–S5 落地 + G4 反馈后另立方案。

---

## 8. 落地记录

### S1 已落地（exe 图标 + 版本资源）

| 项 | 实现 | 验证 |
|---|---|---|
| 图标 | 新增 `packaging/make_icon.py`（从 iOS 产品图标 `AppIcon-512@2x.png` 生成多尺寸）；产物 `packaging/PalmDeck.ico` **入库**（45 KB，7 帧：16/24/32/48/64/128/256） | `tests/test_installer.py::TestWindowsIcon` 解析 ICO 目录逐帧核（含 256、帧数据完整、是 PNG 或 DIB） |
| spec 真跑 | `TestSpecReallyRuns`（打桩 `collect_all`/`Analysis`/`PYZ`/`EXE`，在 macOS 上**真执行一遍 spec**）—— spec 是发版路径，名字拼错本机全绿、到 Windows 打包才炸 |
| 版本资源 | 新增 `packaging/version_info.py`：把 `VSVersionInfo(...)` **拼成裸表达式**（不 import PyInstaller ⇒ macOS 上就能测）；spec 里 `from updater import APP_VERSION` + `write(build/version_info.txt, APP_VERSION)`，再交给 `EXE(version=...)` | `TestWindowsVersionResource`：渲染结果跟着 `APP_VERSION` 走、spec 不许出现硬编码版本号、不许有 `import`、六个属性字段 + `Translation` 齐全 |
| spec | `icon=None` → `icon=os.path.join(root, "packaging", "PalmDeck.ico")`；`EXE(...)` 增 `version=_version_file` | 同上的 `test_spec_*`；另 `ast.parse` 确保 spec 仍是合法 Python（PyInstaller 是 exec 它） |

**为什么版本资源不写在 spec 里、而单独一个模块**：PyInstaller 用
`eval(文件内容, versioninfo.__dict__)` 读那个文件 —— 也就是说**文件里不能有 `import`**，
所以「版本号只取一处」只能靠 **spec 现场拼**；而 spec 本身是 PyInstaller 独有的脚本，
macOS 上跑不了 ⇒ 拼接逻辑单独放 `packaging/version_info.py`，才能被单测覆盖。

**踩到的坑（已写进测试注释）**：本地做「改坏 → 变红」探针时，
把模板里的 `"version": version,` 换成 `"version": "4.0.0",`（**长度恰好相同**），
`cp` 还原又发生在**同一秒内** ⇒ `packaging/__pycache__` 里那份 `.pyc`
被判定为「没变」而复用，于是「还原后仍然红」。
现在测试**直接 `exec` 源码**（PyInstaller 读该文件的方式本来就是这个），彻底绕开 pyc。

**未在本机验证的部分**（诚实记一笔）：macOS 上没有 PyInstaller、也没有 Windows 资源编译器，
所以「打出来的 exe 属性里真的显示这些字段」「Explorer 里图标真的正常」**只能靠 CI
（§5 第 1 条）与 G4 真机确认**。本机验的是：图标字节合法、模板渲染正确、spec 语法合法。

**完成 S1 时顺带拆掉的一个隐患**：最初 spec 里用 `sys.path.insert(0, root)` 来 import
`updater` —— 但**仓库根下就有个 `packaging/` 目录**，把它放进 `sys.path` 就多出一个叫
`packaging` 的命名空间包候选，而 PyInstaller 自己要用 PyPI 的 `packaging`。
构建结果是否正常会取决于导入顺序，这种不确定性不该出现在发版路径上。
现改为 `importlib.util.spec_from_file_location` 按路径加载（告诉 PyInstaller 模块在哪
用 `Analysis(pathex=...)`，那才是正经入口），并加守卫：
`test_spec_does_not_pollute_sys_path` 用 `ast` 查**真代码**里有没有 `sys.path`
（不用字符串匹配 —— spec 里那段注释正好在解释「为什么不这么做」，纯文本会被自己误伤）。
迁移到托盘图标与快捷键时复用这份 `.ico` 即可（托盘目前是 PIL 自绘的青色方向盘，
与产品图标不是同一个视觉 —— 要不要统一另议，属 O1b）。

**测试自己反过来教了一课**：`TestSpecReallyRuns` 第一版里，
把 spec 的版本生成语句改成 `pass`（等于「忘了写版本资源」）**测试仍然是绿的** ——
因为 `build/version_info.txt` 是上一轮跑测试留下的旧产物，
断言 `isfile()` 看的是那份旧文件。现在跑 spec 前先 `unlink` 掉产物
（跟本轮开头那个 `__pycache__` 假红/假绿是同一类毛病：**磁盘上的残留物**）。

### S2–S5 已落地（安装包 + 冒烟测试 + 窗口化控制台 + 文档）

**S0 的答案（评审拍板）**：① 加 `PALMDECK_NO_TRAY` —— 没有它，「装完能不能启动」这件事在
自动化里根本无从验起（按 `PALMDECK_NO_UPDATE` 的款式写：设了非空值就 `run_headless()`）。
② 装到 `%LocalAppData%\Programs\PalmDeck` —— `Program Files` 会让 `updater.apply_update()`
**静默失效**（它靠「下到 exe 旁边再自替换」，而那里不可写），这个代价比「程序在用户目录」
大得多。③ 卸载保留 `%APPDATA%\PalmDeck`：丢布局比留几个日志文件糟。

**落地清单**

| 文件 | 内容 |
|---|---|
| `packaging/PalmDeck.iss` | Inno Setup 6；`{localappdata}\Programs\PalmDeck`、`PrivilegesRequired=lowest`、`SetupIconFile`、`CloseApplications=yes`、`#ifndef AppVersion → #error`、`[UninstallDelete]` 只清 `{app}` |
| `packaging/ChineseSimplified.isl` | 中文向导（Inno 官方翻译列表里的 kira-96 那份，MIT，署名留在文件头）；要求 Inno **6.5+**，CI 的 windows-latest 自带 6.7.1 |
| `packaging/build_installer.bat` | 从 `updater.APP_VERSION` 读版本 → `ISCC /dAppVersion=` |
| `start.py` | `PALMDECK_NO_TRAY`；`_browser_exe()` + 模块级 `open_console()`（Edge/Chrome `--app=`，逐层回退到 `webbrowser`）；托盘 `_product_icon_path()` 优先用产品图标、PIL 自绘降为兜底（**O1b**） |
| `packaging/PalmDeck.spec` | `datas` 加 `packaging/PalmDeck.ico → packaging/`（`icon=` 只写 exe 资源，**运行时读不到**） |
| `.github/workflows/build-windows.yml` | 读版本 → 打包 → 断言 exe `VersionInfo` → ISCC 编译 → **静默安装冒烟**（装 → 断言 Run 项 → `PALMDECK_NO_TRAY=1` 起进程 → 轮询 `/api/status` 30s → 杀进程 → 卸载 → 断言目录/自启项没了、`%APPDATA%\PalmDeck` 还在）→ 传两个资产 |
| `pack_windows.py` | `FILES` 补上 6 个打包相关文件（否则源码 zip 只能打出裸 exe） |
| 文档 | `使用说明.txt`（主线改安装包，源码路线降为「开发者，可选」）、G4 清单 §1 拆成「安装包 / 裸 exe」两条路 + §7 加覆盖安装 / 自动更新 / 卸载 / 自启项；`windows-product.md` 的「不做安装包」「不在 Windows CI 里跑测试」两条边界改为已落地 |

**`PALMDECK_NO_TRAY` 的判定位置有讲究**：必须在 `run_tray()` **之前**。写在 `run_tray()`
里面等于没写 —— 托盘会先把进程占住，CI 那边看到的是「进程活着」而不是「服务活着」。
守卫 `test_flag_short_circuits_the_tray` 就是断言这两个符号的**先后顺序**，不是断言存在。

**托盘图标这一处（O1b）值得单独说**：原本托盘是 `make_icon_image()` 用 PIL 画的青色方向盘、
exe 图标是手机 App 图标 —— 同一台机器上两个 logo，这正是「不像一个软件」的一个来源。
现在 `_product_icon_path()` 先找 `packaging/PalmDeck.ico`（打包后走 `sys._MEIPASS`、
源码运行走 `__file__`），取不到才退回自绘。**故意保留自绘兜底**：
只能读到源码的机器（比如只有 zip 里的 .py）也得能起托盘。

**测试：这一轮的重点是「本机跑不了的东西怎么钉住」**

- `.iss` 在 macOS 上编译不了 ⇒ 所有约定都变成源码断言：装到哪、自启项的**键名/键值必须
  与 `start.py` 的 `_AUTOSTART_KEY` / `_AUTOSTART_NAME` 逐字一致**（两处各写各的键名，
  玩家在托盘里关掉自启、重启又冒出来）、卸载必须 `uninsdeletevalue`、
  `[UninstallDelete]` 段里**只准有 `{app}` 一条**、版本号必须注入不能硬编码、
  向导必须是中文且 `.isl` 真在仓库里。
- **再一次踩到「自己的注释把自己测红」**：`.iss` 顶部注释里写着
  `ISCC /dAppVersion=4.0.0 ...` 和「为什么不装到 Program Files」——
  拿整份文本断言「不许出现 `4.0.0`」「不许出现 `Program Files`」直接被自己的注释打红。
  现在断言走 `_iss_code()`（先剥掉 `;` 注释行）。这是本会话第二次同类问题
  （上一次是 spec 里解释 `sys.path` 的注释），结论一样：**守卫要针对「代码」而不是「文本」**。
- **探针 15 条**全部确认会咬（改一处配置 → 至少一条测试变红）：装到需要管理员、
  卸载不删自启项、版本号硬编码、自启项名字与 `start.py` 不一致、卸载连配置一起删、
  向导变英文、CI 不勾 `autostart`、CI 忘记设 `NO_TRAY`、CI 不验「卸载保留配置」、
  `start.py` 去掉开关、控制台退回普通标签页、托盘图标没打进包、去掉「只装到 Win10+」的 `MinVersion`、`build_installer.bat` 退回「只用 where ISCC」。

**未在本机验证的部分（诚实记一笔）**：macOS 上没有 Inno Setup、没有 Windows 资源编译器，
所以「向导真的长成中文那样」「装完注册表那条真的对」「卸载真的没删 `%APPDATA%`」
**只能由 CI 的 windows-latest 冒烟测试 + G4 真机**确认。本机验的是：`.iss` 与 `start.py`
的一致性、`.ico` 字节合法、版本资源模板渲染、spec 真跑一遍、`PALMDECK_NO_TRAY` /
`open_console` 的接线与回退路径（`_browser_exe()` 在 macOS 上按设计返回 `None`）。

### 落地时专门查证的两个「只有真打包才会炸」的疑点

这两条都不是猜的，是翻上游源码定的 —— 因为它们在 macOS 上无论怎么写都是绿的，
只有在 Windows 发版那一刻才会以「打包失败」或「向导乱码」的形式出现。

**① `--clean` 会不会把 spec 刚生成的 `build/version_info.txt` 删掉？**

会问这个是因为 CI 的打包命令是 `pyinstaller --clean --noconfirm packaging/PalmDeck.spec`，
而版本资源文件就写在 `build/` 下 —— 顺序错了就是「文件属性报错/为空」，还是只在 CI 上出现。
翻 `PyInstaller/building/build_main.py`（`build()` @ :1127）得到两条独立的保险：

1. `--clean` 的清理在 **`exec(code, spec_namespace)` 之前**（:1160 清理，:1213 才执行 spec）——
   写在 spec 里的文件不可能被这一轮清理打扫到；
2. 而且真正的 workpath 是 `build/PalmDeck/`（:1152 `workpath = os.path.join(workpath, CONF['specnm'])`），
   我们写的 `build/version_info.txt` **不在被清的那一层里**。

（结论已写进 spec 注释，免得以后有人「顺手」把路径改成 `build/PalmDeck/version_info.txt`。
`build/` 本身在 `.gitignore` 里，也不会被误提交。）

**② 这份 `.isl` 没有 BOM，中文会不会变成乱码？**

`packaging/ChineseSimplified.isl` 是从上游 **按字节原样**拿的（上游 README 也这么教 CI 用），
它是**无 BOM 的 UTF-8**、LF 行尾。Inno Setup 6 的 `Projects/Src/Shared.FileClass.pas`
里 `TTextFileReader` 明确支持**无 BOM 的 UTF-8 探测**
（:517 注释就是 "Detect BOM-less UTF8"，整份文件是合法 UTF-8 就把代码页设成 `CP_UTF8`），
所以不需要画蛇添足加 BOM —— 保持与上游逐字节一致，将来升级翻译版本才是一个干净的 diff。
真正需要注意的是**版本匹配**：这份翻译要求 Inno Setup **6.5+**
（CI 的 windows-latest 镜像自带 6.7.1，缺了会 `choco install innosetup` 装最新版），
所以 `build_installer.bat` 与 `.iss` 头部都写明了这个下限。

**验证边界（再说一次，别把本机绿当成真机绿）**：以上只能在 macOS 上验到
「`.iss` 与 `start.py` 一致 / `.ico` 字节合法 / 版本资源模板渲染 / spec 真跑一遍 /
开关与回退路径的接线」。而「向导真的长成中文那样」「装完注册表那条真的对」
「卸载真的没删 `%APPDATA%`」「Explorer 里图标真的正常」——**只有 CI 的 windows-latest
冒烟测试与 G4 真机能确认**。这也是 G4 清单 §1 拆成「安装包 / 裸 exe」两条路的原因。
