# PalmDeck · iPhone 端

iPhone 有两条路。先用 A 就能玩；要上架或主屏幕图标更像 App，再走 B。

电脑端必须先在 Windows / Mac 上开着（`python3 bridge.py` 或以后的 exe）。iPhone 只当杆，不生成手柄。

---

## A. 现在就能用：Safari 加到主屏幕

不需要苹果开发者账号，不需要 Mac。

1. 电脑打开 PalmDeck 控制台，记下二维码或 `http://192.168.x.x:8080/index.html`
2. iPhone 连**同一 Wi-Fi**（不要用「与电脑共用热点」的访客隔离；个人热点有时可以）
3. Safari 打开该地址（必须用 Safari，「添加到主屏幕」才有效）
4. 分享 → **添加到主屏幕** → 打开图标
5. 起飞检查单里点「开启体感」时，允许动作与方向；双手横握后点「校准」
6. HUD 圆点变绿后，到电脑游戏里绑定手柄

若打不开：检查电脑防火墙是否放行 8080、8765；iPhone 和电脑是不是同一个网段。

倾斜在 iOS 上必须由你点按钮触发授权，不能在后台默默打开。

---

## B. 原生 App：Capacitor + Xcode

需要：一台 Mac、Xcode、苹果开发者账号（真机调试 / 上架）。

```bash
cd mobile
npm install
npx cap add ios
npx cap copy ios
node ensure-udp-plugin.js
```

用文本编辑器打开生成的 `ios/App/App/Info.plist`，把 `ios-Info.plist.additions` 里的权限加进去。

```bash
npx cap open ios
```

在 Xcode 里：

1. Signing & Capabilities → 选你的 Team
2. Bundle Identifier 保持 `com.palmdeck.yoke` 或改成你自己的
3. 插上 iPhone，选设备，Run
4. 第一次系统会问「本地网络」，选允许

App 用原生 UDP（端口默认 `7773`）发体感轴包，WebSocket `8765` 只做握手和状态。`capacitor.config.json` 的 `packageClassList` **必须**含 `PalmDeckUdpPlugin`，空数组不能发布。

App 里打开后，点「连接」，填 **Windows 电脑** 的局域网 IP，端口默认 `8765`。电脑上先开 `python bridge.py`（已装 vJoy）。切到后台再回来会自动重连；体感锁定时不会因切后台重校准俯仰。

打测试包：Xcode → Product → Archive。上架还要走 App Store Connect、隐私问卷（运动传感器、本地网络）。

---

## iOS 上常见坑

| 现象 | 原因 |
|---|---|
| Safari 能开、主屏幕图标打不开 | 没用 Safari 添加，或电脑休眠断网 |
| 连上又断 | 锁屏后 WKWebView 被挂起，回到前台会自动重连 |
| 点倾斜没反应 | 没授权；或校准前杆位被固定为 0，先点「校准」 |
| 游戏里没设备 | 那是电脑端 vJoy / ViGEm 没装好，与 iPhone 无关 |
| `ws://192.168.x.x` 被拦 | Info.plist 没允许本地明文网络 |

不需要把 iPhone 插到电脑上当手柄。iPhone 和游戏电脑只要同一局域网。
