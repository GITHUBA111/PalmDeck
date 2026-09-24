# PalmDeck

把手机做成电脑游戏的驾驶杆。产品形态是两件可分发软件：

1. **电脑端**：Windows 可执行文件（现在可用 `start.bat`，或打成 `PalmDeck.exe`）
2. **手机端**：独立 App（现在可用网页 / 加到主屏幕，或用 `mobile/` 打 Android、iOS）

---

## 用来玩 WARDOGS

直升机认 **vJoy HOTAS**，地面载具认 **Xbox 手柄**，步兵用**电脑键鼠**。

1. 电脑同时准备：
   - 已装的 **vJoy**（飞机）
   - 再装 [ViGEmBus](https://github.com/ViGEm/ViGEmBus/releases) + `pip install vgamepad`（开车）
2. 运行 `python bridge.py`，终端应出现 `vjoy+vgamepad` 或至少其中一个
3. iPhone 打开座舱 App，双手横握（**只支持横屏**），默认是飞机，可切开车 / 步兵
4. Steam 里对 WARDOGS **关掉 Steam Input**
5. 飞机：游戏内 **Settings → Gamepad → HOTAS → Enable HOTAS**  
   依次推手机摇杆 / 拉总距，绑好 Roll、Pitch、Yaw、Collective  
   总距是油门杆，不要开「Self-centering collective」
   **开火 = vJoy Button 16**（座舱帽垫旁的开火键，不是 Xbox RT）
6. 步兵：手机切「步兵」，用**电脑键盘鼠标**走路、点菜单、买装备（手机不抢 WASD）

---

## 用户流程

1. 电脑安装 vJoy（飞行模拟）和 / 或 ViGEmBus（开车）
2. 打开 PalmDeck 电脑端，浏览器弹出控制台和二维码
3. 手机扫码打开座舱（横屏）。首次走「起飞检查单」：填 IP → 连接 → 开启体感 → 校准 → 进入座舱
4. 到游戏的控制器设置里绑定 `vJoy Device` 或 `Xbox 360 Controller`
5. 座舱顶栏切换：飞机 / 开车 / 步兵（按住 0.4 秒）

---

## 开发时直接跑

```bash
cd PalmDeck
python3 bridge.py
```

Windows 可双击 `start.bat`。

- 电脑控制台：`http://127.0.0.1:8080/`
- 手机座舱：扫码，或打开 `http://电脑IP:8080/index.html`

手机座舱：横屏双手握，整机倾斜 = 周期变距 / 副翼升降舵，左滑条油门（带止动），
右滑条方向舵，中央 PFD 姿态球显示杆位，HUD 可锁定 / 校准。含断线重连、死区、灵敏度、轴反转。

手机端震动反馈在 iOS App 里走原生 Taptic Engine（Safari 网页版 iOS 不振动）。

---

## 打包分发

Windows 电脑端：

```bash
pip install pyinstaller pyvjoy
pyinstaller packaging/PalmDeck.spec
```

得到 `dist/PalmDeck.exe`。用户机器仍需先装 vJoy 或 ViGEmBus。

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

---

## 轴

| 手机 | vJoy | Xbox |
|---|---|---|
| 摇杆左右 / 左右倾斜 | X | 左摇杆 X |
| 摇杆前后 / 前后倾斜 | Y | 左摇杆 Y |
| 油门（左滑条） | Z | 右扳机 |
| 方向舵（右滑条） | Rz | 右摇杆 X |
| BRAKE | Slider | 左扳机 |
| 苦力帽 | POV 1 | 十字键 / 右摇杆视角 |
| 按钮 1–10 | 按钮 1–10 | A/B/X/Y 等 |
| 飞机开火 | 按钮 16 | （双设备时不写 Xbox RT） |

> - 苦力帽只写 **POV**，不占 vJoy 按钮（不再是 11–14）；开火独占按钮 16。vJoy 11–15 留空给自定义。
> - **网页手柄测试器（gamepad-tester 类）只能看到 Xbox（ViGEmBus），看不到 vJoy（DirectInput）。** 验证开车方向盘：装 ViGEmBus 后看 Xbox 360 的「左摇杆 X」；验证飞机杆位：在游戏内绑 vJoy，不要用网页测试器。
