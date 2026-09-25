# PalmDeck 待办

## 遥测（Telemetry）
- **不做**。v4 移除了整套游戏遥测（`telemetry.py` / `bridge.py --telemetry*` / WS `attitude`）。
  姿态球与飞行仪表板只显示本机发往电脑的**平滑杆位**（`smRoll/smPitch/smYaw`），
  与 UDP/WS 上真正送出的值同源；不再有「游戏真实姿态」回读与显示源切换。

## 已完成
- **Windows exe 长出「软件样」（S1）** —— 以前 `packaging/PalmDeck.spec` 里是 `icon=None`、
  没有 `version=`：exe 顶着 PyInstaller 默认图标，右键「属性 → 详细信息」一片空白。
  玩家看到的第一个东西就是这个。现补上：
  `packaging/make_icon.py` 从 iOS 产品图标生成多尺寸 `packaging/PalmDeck.ico`（入库，
  免得让 CI 为了一张图多装一个包）；`packaging/version_info.py` 把 `VSVersionInfo(...)`
  拼成**裸表达式**（不 import PyInstaller ⇒ macOS 上就能测），spec 现场用
  `updater.APP_VERSION` 拼出 `build/version_info.txt` 交给 `EXE(version=...)` ——
  版本号依旧只有一处真相源，不可能出现「程序 v4.0.0、属性写 3.9」。
  守卫 `tests/test_installer.py`（38 条，探针验过非空转）。
- **Windows 端整体「软件化」（S0–S5 + O1b）** —— 方案 `docs/PalmDeck-v4-windows-installer.md` 已全部落地：
  - **安装包**：`packaging/PalmDeck.iss`（Inno Setup 6 + 中文向导 `ChineseSimplified.isl`）。
    装到 `%LocalAppData%\Programs\PalmDeck`、`PrivilegesRequired=lowest`（全程不弹 UAC）；
    **必须装用户目录** —— `updater.apply_update()` 靠「下到 exe 旁边再自替换」，装进
    `Program Files` 会让自动更新**静默失效**（玩家只会觉得「怎么一直是旧版」）。
    卸载删掉「开机自启」那条（旧版裸 exe 的真实病：exe 删了，Run 项还指着它），
    但**保留** `%APPDATA%\PalmDeck`（丢布局比留几个日志糟）。
  - **CI 真验一遍能自动化那部分**（`.github/workflows/build-windows.yml`）：读版本 → 打包 →
    断言 exe `VersionInfo` → ISCC 编译 → 静默装 → 断言注册表自启项 → `PALMDECK_NO_TRAY=1`
    起进程 → 轮询 `/api/status` → 卸载 → 断言目录/自启项没了、配置还在 → 传两个 Release 资产
    （`PalmDeck.exe` 的资产名不能动：`updater.py` 的直链写死了它，安装包是**额外**那份）。
  - **`PALMDECK_NO_TRAY`**（新增，`start.py`）：没有它，「装完到底能不能起来」在自动化里没法验。
    必须在 `run_tray()` **之前**判断 —— 写在里面等于没写。
  - **控制台窗口化**（O3-lite）：`open_console()` 优先用 Edge/Chrome 的 `--app=`（没有地址栏，
    像个原生窗口），逐层回退到默认浏览器；托盘 / 自检 / 重复双击三个入口都走它。
  - **控制台真窗口**（O3-full，已落地）：见 `docs/PalmDeck-v4-native-window.md` —— 用
    pywebview/WebView2 把控制台放进 **PalmDeck 自己的窗口**（任务栏是自己的图标）、关闭 = 最小化回托盘、
    记忆窗口几何、托盘联动（唤出 / 退出）；任一层不可用自动退回上面那条 O3-lite。
    守卫 `tests/test_window.py` 35 条；spec 收 pywebview / CI 断言 `webview=ok` / `.iss` 的
    WebView2 检测与 `palmdeck_window` 逐字对账。真机行为（任务栏图标 / × 只隐藏 / 位置记忆）待 G4。
  - **托盘图标统一**（O1b）：以前托盘是 PIL 自绘的青色方向盘、exe 是产品图标 ——
    同一台机器两个 logo。现在优先读打进包的 `packaging/PalmDeck.ico`，自绘降为兜底。
  - 守卫：`tests/test_installer.py` 38 条 + `tests/test_ci.py` 22 条，**15 条探针**验过会咬
    （装到需要管理员 / 卸载不删自启项 / 版本号硬编码 / 向导变英文 / CI 忘设 `NO_TRAY`…）。
  - 诚实记一笔：**macOS 上验不了「向导真的长那样」「注册表真的那样」「卸载真的没删配置」** ——
    这些靠 CI 的 windows-latest 冒烟 + G4 真机；本机验的是 `.iss` 与 `start.py` 的一致性、
    `.ico` 字节、版本资源渲染、spec 真跑一遍、开关与回退路径的接线。
- **把「现状文档」钉在代码上**（`tests/test_docs.py`，7 条守卫）—— 走查时发现索引文档还在描述**早就删了**的东西：
  `docs/README.md` 的 `Views/` 那行写着「**浅/深双主题**（`Color.pd(浅,深)` + `AppAppearance` 外观枚举 + `.palmAppearance()` 修饰器）」，
  而深色模式整份删掉已半年；同一句里的设置侧栏写着「7 项」（实际 6 项，"外观"早没了）；
  交互文档的视图树也还画着 `触觉 / 外观 / 帮助`。
  索引文档是新人第一份读物，它说还有双主题，新人就会去找 `AppAppearance` —— 找不到，然后开始怀疑自己。
  现已修正（只该说「只浅色」+ 指向 `docs/PalmDeck-v4-light-only.md`），并加三道守卫：
  ① `docs/README.md` / 根 `README.md` / `使用说明.txt` **不得把已删 API 当成还活着**
  （提可以，但符号 ±120 字内必须写明是「删除 / 不再 / 已移除」；判据只看符号周围——
  索引文档有些行是整段话，整行匹配会被同一行里的「可拖 / 缩放 / **删除**」蒙混过去，实测踩到）；
  ② 文档枚举的设置分类必须与 `SettingsCategory` **逐项同序**；
  ③ 文档里每一句「`TestX`（N 条）」的 N，必须等于那个类真的有几个 `def test_`
  （这类数字最容易漂：加一条测试没人会回头改文档，读的人却拿它当覆盖面依据；
  同时管根 `README.md` / 使用说明里的表格行，但不算「N 条**断言**」—— 循环生成的 assert 数不出来）。
  历史方案文档（light-only / redesign / TODO…）不在范围内：它们写的就是「当时是什么」。
- **修掉「上传到电脑就删组件」** —— 电脑侧 `palmdeck_layouts.KINDS/BINDINGS` 白名单漏了
  `panel`（飞机出厂布局的仪表盘）、`rt`（右扳机轴）、`collective`（遥控器双杆左杆）。
  `_coerce_layout` 静默丢弃非法项，而 `layouts_put` 会把校验后的列表回传、
  `LayoutStore.applyServer` 整表替换 → 一次上传即永久丢失（实测 5 件上传只剩 2 件）。
  两份清单补全，加 `tests/test_layouts.py::KindAndBindingListsMatchTheApp`
  （解析 `Widgets.swift` 枚举对账 + 白名单逐项存得下去 + 两套出厂布局回归），
  `bridge.py` 在丢弃件数非零时写警告日志。
- **拆除 Capacitor 壳子（G0a）** —— v3 是「WebView 里跑网页座舱」，v4 改成纯 SwiftUI
  但壳子只拆了一半。删掉 `App/App/public/`（84 KB `cap sync` 产物）、
  `PalmDeckUdpPlugin.swift`（全仓库唯一 `import Capacitor`）、
  `Base.lproj/Main.storyboard`（里面是 `CAPBridgeViewController` ——
  一旦有人补上 `UIMainStoryboardFile`，App 会以网页壳启动）、
  `SceneDelegate.swift`、`capacitor.config.json`/`config.xml`，
  以及 pbxproj 里 24 行引用。
  它们之前只是「打进包但没人引用的死资源」，所以跑起来看不出问题。
  `tests/test_pack_windows.py::TestNoCapacitorResidue` 守卫。
- **摘掉 CocoaPods（G0b）** —— 它当初只为装 Capacitor，而且 Podfile 用的是
  **本地路径 pod**（`../../node_modules/@capacitor/ios`），指向 gitignored 的
  `mobile/node_modules/` ⇒ **新克隆的仓库 `pod install` 必定失败**。
  拆后工程是普通 `App.xcodeproj`（xcodebuild 会从 target 自动合成 scheme），
  构建命令由 `-workspace` 改回 `-project`（`mac.sh` ×3、`deploy_wifi.sh` ×1）。
  App 包里不再有 Capacitor / `host.html`。`TestNoCocoaPods` 守卫。
- **曲线数学收敛为一处实现** —— 原来 `ControllerState.shape` / `Packet.shape` /
  `SettingsView.AxisResponseCurve.output` 三份，设置里的曲线预览靠「复刻」来假装一致。
  现全部走 `Model/AxisCurve.swift`；`tests/test_ios_axis.py` 会在别处再出现
  `pow(` / `func shape(` 时失败。规格见 `docs/PalmDeck-v4-app-interaction.md` §4.3。
- **iOS 纯逻辑测试** —— `tests/test_ios_axis.py` 用 `swiftc` 编译真实源码运行
  （1300+ 断言），覆盖曲线、`AxisMap` 真值表、`PacketFormat` 字节布局。
  同时把 `AxisMap` 变成全函数（入参先夹到 [-1,1]）——
  此前超范围视角输入会被 `shape` 放大到 1.77，只是被下游 `quantize` 兜住了。
- **打包清单自检** —— `pack_windows.verify()` 用 ast 扫入口的同目录 import，
  漏文件直接拦下。此前 v4 漏了 `palmdeck_layouts.py` / `updater.py`，
  打出的 Windows zip 一启动就 ImportError，且本地/CI 都测不出来。
- **版本号语义统一** —— 产品版本 `updater.APP_VERSION`（4.0.0）与协议版本
  `bridge.PROTOCOL_VERSION`（4.0）分开，`tests/test_version.py` 守卫。
  此前漏改 `APP_VERSION` 会让老用户收不到更新（拿 0.3.2 比 0.3.2）。
- **预设合并（P1.5）** —— 「布局模板」与「游戏预设」合并成一个概念：都是命名快照，
  只分**两种形态** —— **整机**（模式 + 手感 + 有布局就换，跨模式出现）与
  **布局**（只装组件、不碰手感，**只在自己那个模式下出现**）。
  「模板」这个词从 UI 与代码里删干净（`LayoutTemplate` 类型已不存在）；
  内置「默认」变成列表里最后一行只读的「布局」预设（不入库）；上限 24；空预设在模型层与 UI 层被拦。
  编辑条上的「存为预设」存布局预设，并给一行回执。
  存储 `palmdeck_game_profiles_v2`（老键 `…_v1` / `palmdeck_layout_templates_v1` 一次性迁移后**只读**）、
  `palmdeck_layout_undo_v1`。方案与机器验证记录：`docs/PalmDeck-v4-unified-presets.md`；
  交互规格：`docs/PalmDeck-v4-app-interaction.md` §7.2 / §12.14。
- **游戏预设（G2）** —— 设置新增「预设」分类：一键把「模式 + 手感 + 轴表名 + 布局」
  一起切到位，不重建虚拟设备、不打断游戏。内置 **WARDOGS**（heli / hotas / dz 0.06，现状固化）
  与 **欧洲卡车模拟**（drive / **dz 0** / 线性 / **900° 满舵** / 720°/s）；用户可自建（上限 24，同模板合并后）。
  存储 `palmdeck_game_profiles_v2` / `palmdeck_active_game_profile`。
  类型与应用顺序见 `Model/GameProfile.swift`，规格见 `docs/PalmDeck-v4-app-interaction.md` §12.5。
  **G3 之前 App 不改电脑轴表**：只读显示电脑实际 `axis_profile`，不一致时给黄标。
- **通用模块化（E2）** —— App 不再替游戏硬编码按钮语义：飞机 / 开车**默认只有轴控件、
  不放任何按键**（`defaultHeli()` / `defaultDrive()`）；飞机另带一块**只读**仪表盘
  （`panel` / `Views/FlightPanel.swift`，纯显示、无绑定）；按键由用户自己添加（默认叫「按钮 N」）、
  编辑态 `Aa` 重命名。三个模式共用一块通用组件画布；**固定皮肤已整份删除**
  （`FlightDeck.swift` / `DriveDeck.swift` / `GamepadDeck.swift`，含 `supportsCustom`
  与三个 `palmdeck_*_custom` 开关）。
  修「欧卡2 降档撞默认 LB/RB 看镜头」的报障：以后「哪个键是降档」由用户自己绑，App 不再拍板。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.6、`docs/PalmDeck-v4-game-profiles.md` §3.9。
- **飞机仪表盘改回只读组件** —— `WidgetKind.panel` / `Views/FlightPanel.swift`
  （`ArcGauge` 270° 弧表 + `BarGauge` 双极条 + `AttitudeBall`）。
  **纯显示**：无 `DragGesture` / 无 `@Binding` / 不碰 `btnMask`，只读 `smRoll/smPitch/smYaw`；
  组件库里选到它时隐藏绑定选择。删除固定皮肤后仪具是靠这个回来的，不是靠皮肤。
  `tests/test_deck_bindings.py::TestInstrumentPanel` 守卫。
- **布局编辑「放弃」** —— 进编辑时按模式记一份回滚点（`LayoutStore.editBaseline`，仅内存），
  一键退回本次编辑前；「完成」/ 顶栏「完成」/ 换模式都会 `commitEditing`。
  放弃走 `replaceWidgets` 但**故意不压撤销槽**（它本身就是回滚）。
  `TestEditSession` 守卫。
- **只浅色：深色模式已删除（含启动页与网页控制台）** —— 走查要求「不要再出现任何深色模式」。
  以前是 `Color.pd(浅, 深)`（`UIColor(dynamicProvider:)`）+ `AppAppearance`（跟随系统/浅色/深色）
  + `.palmAppearance()` 挂在根视图与三个 presentation；
  真拦系统深色的是 **`Info.plist` 的 `UIUserInterfaceStyle = Light`**（UIWindow 层，
  alert / 键盘 / 分享 / LaunchScreen / Catalyst 菜单栏都挡得住；
  以前靠 `.preferredColorScheme` 漏过组件库弹窗）。
  启动页那张 **黑底** 图也换了（冷启动闪黑屏 = 最显眼的深色）；
  `web/host.html` 从深底换成与 App 同一套浅色调色板 + `color-scheme: light`。
  姿态球是真仪表，用固定色 `instr*`/`hud*` 保持深底亮线（表盘语义，不是主题）。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.7、`docs/PalmDeck-v4-light-only.md`，
  `TestThemeAppearance` / `tests/test_light_only.py` 守卫。
- **切预设把画布擦成白板** —— 内置预设的 `widgetsJSON` 是 nil（它们只是“手感快照”），
  而 `LayoutStore.applyProfile` 把 nil 当空布局整表替换了。
  现在 nil / 空数组 / 坏 JSON 一律 = “不带布局”→ 不碰用户画布；
  唯一例外是该模式当前就是空表，那就铺回该模式默认模块。
  `TestProfileDoesNotBlankTheCanvas` 守卫。
- **待机不烧 CPU（重绘只跟「有没有在动」成正比）** —— `@Published` 不做等值去重，
  而热路径（`CADisplayLink` 60~75Hz）上原来每 6 帧写一次 `readout` 字符串（全工程没人读，
  v3 遗留的死字段）当刷新心跳 ⇒ 空闲待机也稳定重绘 10 次/秒。
  现在删掉 `readout`/`pfMotionState`，改由 `smRoll/smPitch/smYaw`（姿态唯一数据源、
  本身就是 `@Published`）带领刷新，并且**只经 `applySm()` 且变化 > `smEpsilon` 才赋值**。
  实测 Mac Catalyst：启动页 12~13% → 1.2%，座舱 13~15% → 1.3~1.7%，
  按住方向盘保持角度 1.3~1.4%（顺带姿态刷新从 10Hz 提到满帧，更顺了）。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.8，`TestNoIdleRepaint` 守卫。
- **状态条按模式取字段（显示的就是发出去的）** —— 底栏原来三个模式共用写死的
  `ROL/PIT/YAW/THR`：开车模式 `Rz` 恒 0 却在显示「方向」，手柄模式 `thr/lt/rt` 全清零
  却在显示「油门」，而且 `0.1°` 里的 `0.1` 是归一化杆位、不是角度。
  现在轴真值表只在 `ControllerState.wireAxes` 算一处，`Packet.pack` 与新的
  `HudReadout`（纯函数）都读它 —— 开车显示 转向/离合/油门/刹车，
  手柄显示 摇杆X/摇杆Y/视角X/视角Y。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.9，
  `TestStatusStripFollowsTheMode` + `AxisCoreTests::testHudReadout*` 守卫。
- **横幅/编辑条不再盖在画布上** —— `deckBody` 从 `ZStack + overlay` 改成 `VStack`：
  横幅 / 编辑工具条各占一行，画布拿剩下的高度。以前浮层底下那点区域既点不动也拖不动，
  默认布局从 y=0.10 起就是为了躲横幅（这个默认值保持不动，免得新装旧装不一致）。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.10，`TestDeckChromeDoesNotCoverTheCanvas` 守卫。
- **拖拽/缩放跟不上手指** —— `EditableWidget` 的两个手势原来是默认的 `.local` 坐标空间，
  而组件自己会被拖走 ⇒ 同一根手指的位移被抵消一半，拖 206pt 只走 81pt。
  改成 `DragGesture(coordinateSpace: .global)` 后 1:1（实测落点 915 vs 手指 930）。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.11，`TestCanvasEditGesturesUseGlobalSpace` 守卫。
- **整表操作搬进编辑条 + 空画布提示** —— 编辑条「存为模板」旁加 `⋯`（恢复默认布局 / 清空画布 /
  撤销上一次改动，无撤销槽时置灰）；当前模式没组件时画布中间显示「画布是空的」+ 下一步提示
  （`allowsHitTesting(false)`，不抢手势）。以前这三件事只在设置 → 布局 里，而改布局的人就在编辑态。
  规格见 `docs/PalmDeck-v4-app-interaction.md` §12.12，`TestEditBarReachesWholeTableActions` +
  `TestEmptyCanvasHasAHint` 守卫。
- **误删能后悔** —— `add` / `remove` 各压一道撤销槽（`✕` 只有 22pt、就在抓组件拖拽时手会按到
  的左上角），`⋯` → 撤销上一次改动即可捞回；`update`（拖动/改名，高频）仍然不压槽。
  `TestDeleteAndAddAreUndoable` 守卫。
- **拖拽吸附 + 不给拖丢**（P1.7，方案 `docs/PalmDeck-v4-drag-snap.md`）—— 新增 `Model/Snap.swift`
  （纯函数：只 `import Foundation`）：拖组件时**7pt 内**吸画布/其它组件的边与中心线并画出对齐线，
  同时任何方向至少留 40pt 在画布内（原来可以把组件拖到画布外，`✕`/`Aa` 都不在可视区里，只能整表回滚）。
  **中心只吸中心、边只吸边**（不跨类）：实测两个同宽滑条想「左对齐」时，本框中心到对方右边缘的距离
  比左边缘差更小，跨类吸会把它抢走，屏幕上就是歪的。夹取改掉落点时会**撤掉那条线**（否则是假对齐）。
  对齐线是 `LayoutStore` 的瞬时状态（不落盘、退出编辑自动清、值变才发布）。
  纯逻辑测试 `tests/test_ios_snap.py` + 接线守卫 `TestDragSnappingIsWired`。
- **设置页一致性 / 可发现性**（P2，方案 `docs/PalmDeck-v4-consistency.md`）—— 只改文案与分组，
  不动数据 / 协议 / 存储键 / 画布：侧栏 **8 → 7**（`连接 / 预设 / 布局 / 操纵与手感 / 触觉 / 外观 / 帮助`，
  ——「外观」后来在「只浅色」一轮删除，现为 **6 项**，见本文件上面的条目），
  两个滑条的「方向盘」并进「操纵与手感」并标出**它是全局项**）；段头说得出这一组是什么
  （模式→**编辑**、清空→**重置**、`undoSection` 补头、触觉头/项不再重复同一个词）；
  **同一个动作一个名字**（「清空当前模式」→「清空画布」、「高级设置」→「设置」、
  「发现的电脑」→「可用电脑」、名词统一用「电脑」）；搜索索引 `entries` 的 title
  改成**界面上真实存在的字**；搜索空态补示例词。
  守卫：`tests/test_deck_bindings.py::TestSettingsConsistency`（12 条）。
- **可发现性补完**（P2 残留，方案 `docs/PalmDeck-v4-discoverability.md`）—— 只改 App 三个 View，
  不动协议 / 存储键 / 画布结构：① 顶栏齿轮 → **齿轮 + 「设置」**（与「布局」等宽，它是唯一没字的入口）；
  ② 预设行尾加 **`⋯` 菜单**（重命名 / 删除），左滑保留，内置与「默认」行不显示；
  ③ **已连接时切模式先弹确认**（电脑端要换 vJoy ↔ 虚拟 Xbox 后端，游戏里手柄会掉一下），
  未连接直接切；④ 状态条 `LINK/MODE/SRC` → **`链路/模式/通道`**（值仍是 `UDP`/`WS`），
  绑定列表「仅飞行」→ **「开车/手柄不生效」**，教程「齿轮设置」→「设置」并补「换模式」「底部状态条」两节。
  守卫：`tests/test_deck_bindings.py::TestDiscoverability`（11 条）。
- **组件库绑定按类型收敛** —— 原「小坑」：类型选「按键」照样能选「油门」这类**轴**绑定，
  而 `tapButton` 对轴绑定是空实现 ⇒ 加出来是**按了没反应的按键**（默认绑定又写死 `.throttle`，
  「按键」→「添加到画布」一步就踩到）。现在 `WidgetBinding.axes` / `.buttons` 只列
  `bindAxis` / `tapButton` 真正处理的项，`WidgetKind.bindingOptions` 只给滑条/按键；
  弹窗按它出选项、换类型归到该类第一个；方向盘/触摸板/摇杆/苦力帽/姿态球改为一行
  「固定发…」说明（它们的 `binding` 渲染时被忽略）；组件库入口用
  `.sheet(item:)` 记住点的是哪个类型。方案与实测：`docs/PalmDeck-v4-binding-filter.md`；
  守卫：`tests/test_deck_bindings.py::TestBindingOptions`（9 条）。
- **动态字号 + 无障碍标签**（走查第 5 条）—— 视图层固定 `.font(.system(size:))` → `.pdFont`
  （`@ScaledMetric`，默认字号外观不变）；座舱 chrome 收口 `.xxLarge`、设置/首启/速览放开
  `.accessibility2`；方向盘 / 摇杆 / 苦力帽 / 滑条 / 视角板 / 姿态球 / 弧表杆位条 / 编辑态 ✕·`Aa`
  全补 `accessibilityLabel` + `accessibilityValue`。方案与实测：`docs/PalmDeck-v4-accessibility.md`；
  守卫：`tests/test_deck_bindings.py::TestAccessibility`（8 条）。
- **连接提示不再“顶”画布**（走查反馈）—— 点「点此连接电脑」时 `link` 变 `.connecting`，
  旧横幅把 `connecting` 也排除 → 整行消失 → `WidgetCanvas` 变高 → 组件按归一化坐标重排，
  看上去就是「点一下其它组件全闪」。改：横幅条件只排除 `live`（连接中显示「正在连接…」），
  行高锛死 `deckTopRowH = 32`，`live` 才收成 0 并带 0.22s 动画；连接中 `allowsHitTesting` 挡重复点。
  Catalyst 实测：`idle` 与 `connecting` 下组件区域裁剪 md5 完全一致。方案：
  `docs/PalmDeck-v4-connect-banner-stable.md`；守卫：`tests/test_deck_bindings.py::TestConnectBanner`（5 条）。
- **脚舵 / 视角 松手立即回正**（走查反馈）—— `BipolarSlider.onEnded` 原来只在
  `|value| ≤ 0.08` 吸 0，满舵松手**停在原地**（而 §4.2 已写「脚舵松手回中」）；`LookPad` 的
  60Hz 指数回中尾巴约 1.5s。改成两个都 onEnded 直接归零；周期杆保留 60Hz 平滑回中。
  脚舵写 `s.yaw` 后仍过 `kYaw = 0.5` 收尾，UDP 不断崖。方案：`docs/PalmDeck-v4-instant-recenter.md`；
  守卫：`tests/test_deck_bindings.py::TestInstantRecenter`（5 条）。
- **（待办）Windows CI 跑测试**：`build-windows.yml` 现在只打包 exe，没跑 `python -m unittest`。
  加之前得先在 windows-latest 上真验一遍（`test_doctor.py` 在 Windows 上会走 `sc query` /
  `Get-NetFirewallRule` 分支），否则可能常年红。
- **Windows 端服务产品化（统一自检 / 一键修复）**—— 以前环境问题散在四处：驱动检测只在
  `setup_windows.bat`（`sc query`），防火墙端口在 `open_firewall.bat` 与 `palmdeck_config.py`
  各写一份，而那个 bat 既没人引用也没进过 zip；控制台对“游戏里没设备”只报一句 `backend=none`；
  WS/UDP 端口被占时后台线程只留一行 traceback，用户看到的是“手机连不上”。
  新增 **`palmdeck_doctor.py`**（唯一真相源：Python/依赖/驱动/防火墙/监听端口/局域网逐项体检 +
  一键修复，防火墙端口从配置读），bridge 加 `/api/doctor` 与 `/api/doctor/fix`（新增
  `Hub.note_listener` 记录 `serve_*` 的 bind 成败），控制台新增「自检」tab（详情 + 修复按钮 +
  红色数字 badge，概览页 `backend=none` 时出现「去自检 →」），托盘 tooltip 带版本号、菜单加「自检…」、
  启动有故障时气泡提醒；删 `open_firewall.bat`，`setup_windows.bat` 瘦成「装依赖 → 调 doctor → 启动」；
  `pack_windows.FILES` / `PalmDeck.spec` 同步。方案：`docs/PalmDeck-v4-windows-product.md`；
  守卫：`tests/test_doctor.py`（25 条，含用 TEST-NET-1 地址做**真 bind 失败**的验证）。
  测试 226 → **251**。

## 已存档（方案已保存，未实施）
- 无。

## 其它
- **拆方案待施工（按已定顺序）**：~~**E1**~~（已施工）→ ~~**G1**~~（已施工）
  → ~~**G2**~~（已施工）→ ~~**E2**~~（已施工）→ ~~**P1.5**~~（已施工）→ ~~**P2**~~（已施工）
  → **G4**（WARDOGS / 欧洲卡车模拟两个预设）。
  取证与理由见 `docs/PalmDeck-v4-game-profiles.md`；**真机验收逐条按 `docs/windows-acceptance-checklist.md` 走**
  （清单里的自检项 id / 界面文案 / 章节号已被 `tests/test_ci.py::TestChecklistMatchesTheCode`
  锁在代码上，清单漂了会红）。
- **G2 起预设 = 模式 + 手感 + 轴表名 + 布局**：`GameProfileStore`（P1.5 起是 `palmdeck_game_profiles_v2`，
  老键 `…_v1` / `palmdeck_layout_templates_v1` 一次性迁移后只读），
  内置 WARDOGS / 欧洲卡车模拟。G4 的「两个预设」其实是**把 §3.6 的定义坐实**——
  当前 `GameProfileBuiltin` 已按规格填好，剩下的 G4 是**真机验收**（对照游戏内绑定/参数），
  以及把 ETS2 的两条“必须游戏内确认”（LS Y 归属、序列式变速箱）在实机对一遍。
- **G1 起手感参数带模式后缀**：`palmdeck_dz` → `palmdeck_dz.<mode>` 等七个键；
  旧键启动时一次性迁移（`Model/ShapingKeys.swift`）。
  新增持久化键时注意：未带后缀的写法会被 `tests/test_ios_axis.py` 拦住。
- ~~**`CockpitView.swift:58` 一条 Swift 警告**（`'weak' ownership of capture 'layout'`）
  —— 外层闭包已隐式强引用 `layout`，内层再 `[weak layout]` 语义矛盾。~~
  已随 E1 修掉（先落局部变量再弱引用）。
