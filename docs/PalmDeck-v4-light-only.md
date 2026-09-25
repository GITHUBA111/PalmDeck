# PalmDeck v4 · 只保留浅色：删掉深色模式（走查反馈）

### 方案名
浅色定版 —— App 与网页控制台都不再有深色

### 状态
已落地

### 影响范围
App 侧（Info.plist / Theme / 设置页）+ 电脑侧（`web/host.html` 配色）+ 文档

### 一句话
「不要再出现任何深色模式」：iOS 座舱 App 固化浅色（连系统深色也管不着），
网页控制台从深底改成浅底，两个界面从此一套色。

---

## 1. 目标

1. **App 不可能再变深色**——不管手机是不是深色模式、设置里点了什么。
2. **网页控制台不再是一块黑底**——它和 App 现在是同一个产品，配色也该是一套。
3. 深色不是「隐藏起来」而是**删掉**：没有开关、没有兜底分支、没有第二套色值留在源码里等着被重新打开。

## 2. 现状与证据

| 证据 | 位置 | 现在会怎样 |
|---|---|---|
| 外观开关 | `Views/SettingsView.swift:860` `appearanceSections` + `Theme.swift:93 AppAppearance` | 设置里有「跟随系统 / 浅色 / 深色」三项，`palmdeck_appearance` 可存 `dark` |
| 没有系统级兜底 | `Info.plist` 无 `UIUserInterfaceStyle` | App 只在根视图用 `.preferredColorScheme` 覆盖；**系统弹出的东西（alert / 键盘 / 分享面板 / Catalyst 菜单栏）跟着系统走** |
| 弹窗漏包 | `Views/CockpitView.swift:468 LibrarySheet`（无 `.palmAppearance()`） | 组件库弹窗**自带**一层 presentation；12.7 已写明「漏一处就会出现『外面浅色、弹窗黑底』」——这是真漏了 |
| 控制台固定深底 | `web/host.html` `:root{--bg:#070b12 …}` | 网页端没有主题开关，就是深底；与 App 的浅色不是一个产品观感 |

深色从哪来的：`af62a5f 浅色模式：Theme 改成浅/深双主题，设置加「外观」开关`
——当时把原来的深色主题保留成了「可选项」，于是它一直有办法再冒出来。

## 3. 方案

### 3.1 App：先上「系统级」开关，再删源码里的深色

1. **`Info.plist` 加 `UIUserInterfaceStyle = Light`**。
   这是唯一一处能让 **所有** UIKit 呈现（alert、键盘、分享、ActionSheet、
   LaunchScreen、Catalyst 菜单栏）都不能深色的开关 —— 比在每个视图上贴
   `.preferredColorScheme` 可靠得多，也不会再漏。
2. **`Theme.swift`**：
   - 删 `Color.pd(_ light:_ dark:)`（19 个调用点直接用浅色值），主题色变回普通常量；
   - 删 `AppAppearance` / `AppearanceModifier` / `.palmAppearance()`；
   - `Theme.instr* / hud*`（姿态球、表盘）**保持深底亮线**：那是仪表盘面，不是主题。
     文档里写清这条例外，免得下次又当成「深色模式残留」。
3. **删掉所有 `.palmAppearance()` 调用点**（`PalmDeckApp` / `SettingsView` / `PreflightView` / `CockpitView` ×2），
   `LibrarySheet` 的漏包问题随 `preferredColorScheme` 一起消失。
4. **`SettingsView`**：删掉「外观」整个分类（`SettingsCategory.appearance`、
   侧栏项、`appearanceSections`、`@AppStorage appearanceRaw`、搜索索引里的
   「外观模式」条目）。侧栏从 7 项变 6 项。
   **另外**：`Splash.imageset` 那张图本身是旧的**黑底**画（冷启动必闪黑屏），
   换成同色系的浅底（`#EEF4FA` + 青环姿态球，即 App 的图标元素）。
   注：**不要**给启动页铺渐变 —— 浏览器渲染的平滑渐变在 PNG 里变成 2.5 MB 抖动噪点，
   纯色底同一张图只有 83 KB；这张图每个冷启动只出现零点几秒，不值得。

### 3.2 控制台：深底 → 浅底（同一套色）

`web/host.html` 的样式本来就集中在 `:root` 变量上，改法是**换调色板 + 收掉散落的硬编码深色**：

| 变量 | 现在 | 改成 |
|---|---|---|
| `--bg` | `#070b12` | `#f4f7fb`（= App 的 `bgTop`） |
| `--card` / `--card2` | `#101826` / `#0c1420` | `#ffffff` / `#f6f8fc` |
| `--line` | `#243044` | `#c9d4e2`（= App 的 `border`） |
| `--text` | `#e8f1ff` | `#0e1724`（= App 的 `text`） |
| `--muted` | `#8ea0b8` | `#5f6d80`（= App 的 `textFaint`） |
| `--cyan` / `--green` / `--amber` / `--red` | 亮色 | App 浅色侧那四个（压深一档，白底才够对比） |
| 硬编码 `#0a1220` / `#1b2738` / `#33445c` / `#162033` / `#0e2a3a` / `radial-gradient(...#123...)` | 深色块 | 换成浅色等价物（浅灰轨道 / `#dfe7f1` 分隔线 / 白底按钮） |

**监测页的柱子/条**保持「深色轨道 + 高饱和填充」的读法（浅灰轨道 + 青/绿填充），
不然白底上看不出指针在哪。二维码仍是黑模块白底。

## 4. 影响面

| 维度 | 影响 |
|---|---|
| 协议 PKT | **不改** |
| App 侧 | `Info.plist` +1 键；`Theme.swift` 删双色；`SettingsView` 少一个分类；5 处 `.palmAppearance()` 删除 |
| 电脑侧 | `web/host.html` 只改 `<style>`（结构 / JS 一行不动） |
| 持久化 | `palmdeck_appearance` 键**不再读写**（老值留在 UserDefaults 里不清理、不影响任何行为） |
| 文档 | 本文件、`docs/PalmDeck-v4-app-interaction.md`（§12.7 重写、设置表去掉「外观」）、`docs/README.md`、`docs/TODO.md` |

## 5. 验证方式

```bash
python3 -m unittest discover -s tests -t .    # 新增 tests/test_light_only.py
```

源码守卫（新 `tests/test_light_only.py`）：

- `Info.plist` 里 `UIUserInterfaceStyle == Light`；
- 全仓 `*.swift` 不再出现 `Color.pd(` / `AppAppearance` / `.palmAppearance()` / `preferredColorScheme`；
- `SettingsCategory` 没有 `appearance`、搜索索引里没有「外观模式」、源码里没有「跟随系统 / 深色」字样；
- `web/host.html` 的 `:root` 里 `--bg` / `--card` / `--text` 是浅色（用亮度判断，不写死色号），
  且全文件不再出现 `#070b12` / `#101826` 这类旧深色；
- **启动页图片**是浅底：`sips` 降到 32px 后用 70 行纯 Python（`zlib` + 反滤波）解出平均亮度，
  必须 > 0.6（旧黑底图 0.01，新图 0.74）；
- 原有 `TestThemeAppearance`（`tests/test_deck_bindings.py`）由「双主题」改写为「只浅色」5 条。

人工验证（**关键**：把系统设成深色，看 App 还是不是浅色）：

```bash
xcrun simctl ui <udid> appearance dark      # 模拟器切深色
xcrun simctl terminate <udid> com.palmdeck.yoke
xcrun simctl launch   <udid> com.palmdeck.yoke
xcrun simctl io       <udid> screenshot /tmp/dark_forced.png   # 应该是浅色
open http://127.0.0.1:8080/                 # 控制台截图：浅底
```

Catalyst 同理（Catalyst 跟随 `NSApp` appearance，`UIUserInterfaceStyle` 同样生效）。

## 6. 边界与不做

- **不删仪表盘的深底**。姿态球 / 弧形表 / 条形表是「真仪表」：黑底亮线才读得出刻度，
  这是仪表语义，不是主题。若也要浅底表盘，那是另一个需求（要重画整套刻度对比色）。
- **不清理 UserDefaults 里的 `palmdeck_appearance`**。没人再读它，清不清都一样，
  而去动持久化要连带迁移测试，不值。
- **不给控制台做主题开关**。刚删掉一个「可以变深色」的入口，不再加第二个。
- **不改控制台的结构 / JS**。只换配色，避免把刚做完的自检页动坏。

## 7. 工作量

**S**，三步，各自独立可验证：

| 步 | 内容 | 验证 |
|---|---|---|
| P0-1 | `Info.plist` + `Theme.swift` + `SettingsView` 去深色 | 源码守卫；模拟器强制深色截图 |
| P0-2 | `web/host.html` 浅色调色板 | 控制台截图（概览 / 自检 / 监测） |
| P0-3 | 文档与测试同步 | 全套测试；`docs/README.md` 计数 |

---

## 8. 落地结果（2026-09-25）

全套测试 **262 项 OK**（原 251 + `tests/test_light_only.py` 11 条；`TestThemeAppearance` 原地改写）。

| 步 | 落到哪 | 结果 |
|---|---|---|
| P0-1 | `Info.plist`（`UIUserInterfaceStyle=Light`）、`Views/Theme.swift`（删 `Color.pd` / `AppAppearance` / `palmAppearance`，18 个调用点改为浅色单值）、`PalmDeckApp` / `PreflightView` / `CockpitView` / `SettingsView`（删 5 处 `.palmAppearance()` 与整个「外观」分类） | Catalyst + iOS 模拟器 **0 warning** 构建通过 |
| P0-1b | `Assets.xcassets/Splash.imageset/splash-2732x2732{,-1,-2}.png` 换成浅底图（3 份同一张，各 83 KB） | `xcrun assetutil --info App.app/Assets.car` 里 `Splash` = 2732×2732 已更新 |
| P0-2 | `web/host.html`：`color-scheme: light` + 全套浅色变量；`.fill` / `.track` / 徽标 / 日志底色跟着走；二维码仍黑模块白底 | 无头 Chrome 截图：概览 / 自检 / 监测 / 配置四页都浅底可读 |
| P0-3 | `docs/PalmDeck-v4-app-interaction.md` §12.7 重写 + 设置表去「外观」+ 侧栏计数、`docs/PalmDeck-v4-consistency.md` 两处计数、`docs/README.md`（262 项 + 新测试行）、`docs/TODO.md` | — |

**强推深色的实测**（这就是「有没有漏」的证据）：

| 场景 | 命令 | 结果 |
|---|---|---|
| iOS 模拟器 | `xcrun simctl ui <udid> appearance dark` → 装 → 启动 | 座舱 / 首启页全浅色；启动页图已含在 `Assets.car` 里 |
| Mac Catalyst | `open -a App --args -AppleInterfaceStyle Dark` | 窗口标题栏与内容仍全浅色（`Info.plist` 压过了 `NSApp` 偏好） |
| 网页控制台 | 浏览器本身处在深色主题下打开 | 页面仍是浅底（固定调色板 + `color-scheme: light`） |

**遗留的深色只有一处**：姿态球 / 仪表盘的**表盘面**（`Theme.instr*` / `hud*`，见 §6）。
