# PalmDeck

把手机做成电脑游戏的驾驶杆。产品形态是两件可分发软件：

1. **电脑端**：Windows 安装包 / 单个 `PalmDeck.exe`（托盘常驻 + 后台桥接 + 自动更新），自带**网页控制台**（配置 / 监测 / 更新 / 日志）
2. **手机端**：iOS App（原生 SwiftUI，`mobile/ios`）。**不再提供手机网页座舱**

---

## 用来玩 WARDOGS

直升机认 **vJoy HOTAS**，地面载具认 **Xbox 手柄**，落地/菜单用**电脑键鼠**。

1. 电脑同时准备：
   - 已装的 **vJoy**（飞机）
   - 再装 [ViGEmBus](https://github.com/ViGEm/ViGEmBus/releases) + `pip install vgamepad`（开车）
2. 运行 `python start.py`（托盘常驻）或 `python bridge.py`（前台带窗口），终端应出现 `vjoy+vgamepad` 或至少其中一个
3. iPhone 打开座舱 App，双手横握（**只支持横屏**），默认是飞机，可切 开车 / 手柄
4. Steam 里对 WARDOGS **关掉 Steam Input**
5. 飞机：游戏内 **Settings → Gamepad → HOTAS → Enable HOTAS**  
   依次推手机摇杆 / 拉总距，绑好 Roll、Pitch、Yaw、Collective  
   总距是油门杆，不要开「Self-centering collective」
   **开火 = vJoy Button 16**（座舱帽垫旁的开火键，不是 Xbox RT）
6. 落地/菜单：手机切「手柄」，App 停发所有轴（不抢 WASD），用**电脑键盘鼠标**走路、点菜单、买装备

---

## 用户流程

1. 电脑安装 vJoy（飞行模拟）和 / 或 ViGEmBus（开车）
2. 打开 PalmDeck 电脑端：右下角托盘出现 PalmDeck 图标（与手机 App 同一个 logo），控制台独立弹出（重复双击 exe = 只打开控制台，不会重复启动）
3. 手机打开 PalmDeck App（自动发现电脑，或扫控制台二维码配对）。首次走「起飞检查单」：电脑装好 → 同 Wi-Fi → 进入座舱
4. 到游戏的控制器设置里绑定 `vJoy Device` 或 `Xbox 360 Controller`
5. 座舱顶栏切换：飞机 / 开车 / 手柄

---

## 开发时直接跑

```bash
cd PalmDeck
python3 bridge.py
```

Windows 可双击 `start.bat`（第一次先双击 `setup_windows.bat` 装依赖）。

- 电脑控制台：`http://127.0.0.1:8080/`（分页：概览 / 输入监测 / 配置 / 布局 / 更新 / 日志）
- 配置页可「**导出/导入配置包**」：一个 JSON 含全部服务配置 + App 三模式布局，
  用于备份或换电脑迁移（导入会覆盖当前配置与布局）
- 手机端：`mobile/` 里的 iOS App；手机 Web 座舱已删除（`web/index.html`），
  服务端 `/` 一律指向控制台 `host.html`

iOS App：横屏双手握，**一套通用模块画布 + 三套起步布局**（v4 起没有固定皮肤）：
- **飞机**：仪表盘（姿态球/扭矩/滚转俯仰，只读）+ 总距杆 + 脚舵 + 周期变距杆 + 视角板（默认不含按键）
- **开车**：方向盘（多圈+回正）+ 离合/刹车/油门三踏板 + 视角板（默认不含按键；换档键自己加）
- **手柄**：左/右摇杆 + LT/RT + ABXY/LB·RB 等起步按键；油门/刹车/总距清零，不误触

所有组件都能在「布局」里拖动/缩放/改名、自己加按键，存成整机或布局预设。
按键绑什么由用户决定 —— App 不再替游戏写死「哪个键是降档」。

含断线重连、死区、灵敏度、轴反转、按键触感（原生 Taptic Engine）。
电脑控制台可实时看到 App 发出的每个轴 / 按键 / 帽子，用来验证布局与绑定。

---

## 打包分发

Windows 电脑端（罗技驱动式桌面守护程序）：

```bash
pip install pyinstaller pyvjoy zeroconf qrcode pystray Pillow
pyinstaller packaging/PalmDeck.spec
```

得到 `dist/PalmDeck.exe`。用户机器仍需先装 vJoy 或 ViGEmBus（装完重启；缺什么由「自检」页指出）。

要连**安装包**一起打（Windows 上，需 Inno Setup 6.5+）：

```
packaging\build_installer.bat        :: 先出 exe，再 ISCC 编译 → dist\PalmDeck-Setup-<版本>.exe
```

安装包做的事（玩家路线，`PalmDeck.exe` 作为免安装版继续保留）：
装到 `%LocalAppData%\Programs\PalmDeck`（**免 UAC**，且目录可写 ⇒ 原地自替换的自动更新仍然有效）、
中文向导、开始菜单 / 卸载项、可选「开机自动启动」；卸载会删掉自启项但**保留**
`%APPDATA%\PalmDeck`（日志 / 配置 / 布局）。详见
`docs/PalmDeck-v4-windows-installer.md`。

**`PalmDeck.exe` 是托盘常驻的守护程序**（类似罗技 G HUB）：
- 双击启动：托盘出现 PalmDeck 图标，后台跑桥接，自动开控制台；**没有黑框窗口**
- 重复双击 exe：只打开已有实例的控制台（不会重复启动）
- 控制台是**独立窗口**（借用 Edge / Chrome 应用模式，没有地址栏），不是浏览器标签页
- 托盘菜单：打开控制台 / **自检…** / 检查更新 / 打开日志 / 开机自启 / 退出（悬停看版本号）
- **自检**（`palmdeck_doctor.py`）：驱动 / 防火墙 / 端口占用 / 依赖 / 局域网地址逐条体检，能一键修的（防火墙放行、驱动下载页、缺依赖）就一键修。四处共用同一份：控制台「自检」页、托盘菜单、`setup_windows.bat`、`python palmdeck_doctor.py --json`
- 防火墙端口从 `palmdeck_config.py` 读，不再写死在 bat 里；改了端口回自检页重新放行即可
- **自动更新**：每次启动查 GitHub Release，有新版本自动下载 → 自替换 → 重启
- 日志文件：`%APPDATA%\PalmDeck\palmdeck.log`

手机 App：

```bash
cd mobile
npm install
npx cap add android
npx cap copy
npx cap open android
```

iOS（本仓库已有 `mobile/ios` 工程）：

```bash
cd mobile
npm install
npx cap copy ios && node ensure-udp-plugin.js
npx cap open ios   # Xcode 里选 Team、连真机、Run
```

上架需要 Apple 开发者账号（$99/年）；免费 Apple ID 只能真机调试，证书 7 天过期。

**无线（同一 Wi-Fi）部署到 iPhone**（无需数据线，首次配对仍需连一次线）：

```bash
cd mobile/ios
./deploy_wifi.sh                  # 自动选第一台已配对真机
./deploy_wifi.sh --launch hui     # 装完顺便启动
./deploy_wifi.sh --wifi-only hui  # 检测到 USB 插着 iPhone 就拒绝（强制走网络）
```
脚本会先体检网络（Mac 局域网 IP），编译真机 Debug、用 `devicectl` 无线安装，
失败时自动重试并打印排查建议（同 Wi-Fi / 解锁亮屏 / 开发者模式 / 重新配对）。

---

## 轴

| App 控件 | vJoy | Xbox |
|---|---|---|
| 横滚（飞机周期杆 / 开车方向盘） | X | 左摇杆 X |
| 俯仰（飞机周期杆 / 开车离合） | Y | 左摇杆 Y |
| 油门 / 总距（飞机总距杆 / 开车油门踏板） | Z | 右扳机 |
| 方向舵（飞机脚舵 / 手柄右摇杆 X） | Rz | 右摇杆 X |
| 刹车（开车刹车踏板） | Slider | 左扳机 |
| 视角（视角板 / 手柄右摇杆） | Rx / Ry | 右摇杆 |
| 苦力帽 | POV 1 | 十字键 |
| 按钮 1–10 | 按钮 1–10 | A/B/X/Y 等 |
| 飞机开火 | 按钮 16 | （双设备时不写 Xbox RT） |

> - 苦力帽只写 **POV**，不占 vJoy 按钮（不再是 11–14）；开火独占按钮 16。vJoy 11–15 留空给自定义。
> - **开车模式**（欧卡等）：方向盘 = **左摇杆 X**，离合 = **左摇杆 Y**（滑条 0 → 中位，1 → 到底 −1），视角触碰板 = **右摇杆**（X/Y）。此时 Rz 不输出，避免离合和视角抢右摇杆。
> - **网页手柄测试器（gamepad-tester 类）只能看到 Xbox（ViGEmBus），看不到 vJoy（DirectInput）。** 验证开车方向盘：装 ViGEmBus 后看 Xbox 360 的「左摇杆 X」；验证飞机杆位：在游戏内绑 vJoy，不要用网页测试器。
