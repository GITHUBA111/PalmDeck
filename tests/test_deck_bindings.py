"""App 侧「界面上的字」和「真实发出去的键」的一致性回归。

历史上这里守的是「固定皮肤」上的标签 ↔ 键号，E1 修的都是同一类问题
（界面写 A、实际发 B）。E2 收尾后**固定皮肤已全部删除**，只剩一块通用
组件画布：按键由用户自己添加、命名、绑定，所以现在守的是：

1. 三个模式的默认布局不替游戏拍板语义——飞机/开车默认只有轴、没有任何按键
   （见 `TestDefaultHeliLayout` / `TestDefaultDriveLayout`）。飞机额外带一块**只读**
   仪表盘（`panel`），它不绑定任何轴/键，不携带游戏语义（见 `TestInstrumentPanel`）。
2. 手柄默认布局里凡是有名字的按键，名字必须与真实 Xbox 键号一致
   （`gearUp`→RB=b6、`gearDown`→LB=b5，且不得用 Xbox 没有的键号）。
3. 引擎里不再残留任何固定/经典皮肤，否则硬编码语义会从后门回来。

这些是源码级对应关系，用 XCTest 表达不了（要编译整个 SwiftUI 视图层），
所以这里直接读 Swift 源码 + 读 `hotas.py` 的映射表对账。
"""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native")


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
        return f.read()


def _ios(*parts):
    with open(os.path.join(IOS, *parts), encoding="utf-8") as f:
        return f.read()


def func_body(src, name):
    """取 `static func <name>(...)` 的函数体，到下一个顶层 `static func` 或类型结束为止。

    这样给 LayoutStore 加新的默认布局（如 `defaultDrive()`）不会污染
    对 `defaultGamepad()` 的断言。
    """
    after = src.split("static func " + name + "(", 1)[1]
    m = re.search(r"\n    static func |\n}", after)
    return after[: m.start()] if m else after


def xbox_map():
    """`hotas.py` 里 X360 的 alias → XUSB_BUTTON 后缀。"""
    body = _read("hotas.py").split("X360 = {", 1)[1].split("\n    }", 1)[0]
    return dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', body))


# Xbox 无线控制器只有这 10 个键（LT/RT 是模拟轴，十字键是 hat）
XBOX_B1_TO_B10 = {
    "1": "A",
    "2": "B",
    "3": "X",
    "4": "Y",
    "5": "LEFT_SHOULDER",
    "6": "RIGHT_SHOULDER",
    "7": "BACK",
    "8": "START",
    "9": "LEFT_THUMB",
    "10": "RIGHT_THUMB",
}


class TestXboxTable(unittest.TestCase):
    def test_b1_to_b10_match_the_standard_xbox_layout(self):
        m = xbox_map()
        for n, token in XBOX_B1_TO_B10.items():
            self.assertEqual(m.get("b" + n), token, "X360[b%s] 应为 %s" % (n, token))

    def test_there_is_no_b11_in_xbox_map(self):
        m = xbox_map()
        self.assertNotIn("b11", m)
        self.assertNotIn("b16", m)
        self.assertEqual(len([k for k in m if re.fullmatch(r"b\d+", k)]), 10)


class TestNoFixedSkins(unittest.TestCase):
    """E2 收尾：引擎里不再保留任何固定皮肤，一切均可由用户配置。"""

    SKINS = ["FlightDeck.swift", "DriveDeck.swift", "GamepadDeck.swift"]

    def test_skin_files_are_gone(self):
        for name in self.SKINS:
            self.assertFalse(
                os.path.exists(os.path.join(IOS, "Views", name)),
                "固定皮肤 %s 还在；它自带的硬编码按键会重新把游戏语义带回来" % name,
            )

    def test_cockpit_always_renders_the_canvas(self):
        src = _ios("Views", "CockpitView.swift")
        self.assertIn("WidgetCanvas(store: layout, mode: s.mode", src,
                      "座舱没有走通用组件画布")
        for gone in ("FlightDeckView", "DriveDeck", "GamepadDeck", "经典皮肤"):
            self.assertNotIn(gone, src, "CockpitView 还残留固定皮肤分支：%s" % gone)

    def test_no_classic_skin_toggle_left(self):
        src = _ios("Views", "CockpitView.swift") + _ios("Views", "SettingsView.swift")
        for key in ("palmdeck_gamepad_custom", "palmdeck_heli_custom",
                    "palmdeck_drive_custom"):
            self.assertNotIn(key, src, "还有残留的固定皮肤开关：%s" % key)


class TestDefaultGamepadLayout(unittest.TestCase):
    def _body(self):
        return func_body(_ios("Views", "Layout.swift"), "defaultGamepad")

    def test_gear_labels_match_the_pulse_indices(self):
        body = self._body()
        found = dict(
            (name, label)
            for name, _between, label in re.findall(
                r"\.make\(\.button,\s*\.(gearUp|gearDown),(.{0,80}?)label:\s*\"([^\"]+)\"",
                body,
                re.S,
            )
        )
        self.assertEqual(found.get("gearUp"), "RB", "gearUp → pulse(5) → b6 = RB")
        self.assertEqual(found.get("gearDown"), "LB", "gearDown → pulse(4) → b5 = LB")

    def test_right_trigger_slider_is_bound_to_the_rt_axis(self):
        body = self._body()
        self.assertIn('.make(.slider, .rt,', body, "RT 滑条绑到了 throttle —— Xbox 不读 throttle")
        self.assertNotIn('.make(.slider, .throttle,', body)

    def test_no_layout_button_uses_a_key_xbox_does_not_have(self):
        body = self._body()
        nums = [int(n) for n in re.findall(r"\.make\(\.button,\s*\.vjoy(\d+)", body)]
        self.assertTrue(nums)
        self.assertTrue(max(nums) <= 10, "默认布局用了 Xbox 没有的键号：%r" % nums)


class TestDefaultDriveLayout(unittest.TestCase):
    """开车默认布局 = 只保留基本轴输入 + **没有任何内置按键**。

    用户诉求：轴控件（方向盘/油门/离合…）保留，按键完全由用户自己添加、命名。
    “升/降档”这类语义一旦硬编码，就会和游戏默认绑键撞车（欧卡2 的 LB/RB = 看镜头）。
    """

    def _body(self):
        return func_body(_ios("Views", "Layout.swift"), "defaultDrive")

    def test_has_no_builtin_buttons(self):
        self.assertNotIn(".make(.button,", self._body(), "开车默认布局不该内置任何按键")

    def test_has_the_basic_axis_modules(self):
        body = self._body()
        for kind, binding in ((".wheel", ".roll"),
                              (".slider", ".clutch"),
                              (".slider", ".brake"),
                              (".slider", ".throttle"),
                              (".pad", ".look")):
            self.assertRegex(body, r"\.make\(%s,\s*%s," % (re.escape(kind), re.escape(binding)),
                             "开车默认布局缺 %s/%s" % (kind, binding))

    def test_no_hardcoded_game_semantics(self):
        body = self._body()
        for word in ("左转", "右转", "危险灯", "喇叭", "手刹", "雨刷",
                     "大灯", "远光", "换挡", "升档", "降档"):
            self.assertNotIn(word, body, "开车默认布局仍硬编码了游戏语义：%s" % word)


class TestDefaultHeliLayout(unittest.TestCase):
    """飞机默认布局 = 只保留基本轴输入 + **没有任何内置按键**。"""

    def _body(self):
        return func_body(_ios("Views", "Layout.swift"), "defaultHeli")

    def test_has_no_builtin_buttons(self):
        self.assertNotIn(".make(.button,", self._body(), "飞机默认布局不该内置任何按键")

    def test_has_the_basic_axis_modules(self):
        body = self._body()
        for kind, binding in ((".stick", ".roll"),        # 周期杆（2D → roll+pitch）
                              (".slider", ".throttle"),   # 总距
                              (".slider", ".yaw"),        # 脚舵
                              (".pad", ".look")):         # 视角
            self.assertRegex(body, r"\.make\(%s,\s*%s," % (re.escape(kind), re.escape(binding)),
                             "飞机默认布局缺 %s/%s" % (kind, binding))

    def test_no_hardcoded_game_semantics(self):
        body = self._body()
        for word in ("开火", "投弹", "起落架", "灯光", "悬停"):
            self.assertNotIn(word, body, "飞机默认布局仍硬编码了游戏语义：%s" % word)

    def test_keeps_the_readonly_instrument_panel(self):
        body = self._body()
        self.assertRegex(body, r"\.make\(\.panel,\s*\.roll,",
                         "飞机默认布局缺仪表盘（只读显示，不算按键）")
        self.assertIn("仪表盘", body)


class TestInstrumentPanel(unittest.TestCase):
    """仪表盘 = 只读组件：有显示、无绑定、无游戏语义。"""

    def test_widget_kind_exists_and_is_read_only(self):
        widgets = _ios("Views", "Widgets.swift")
        self.assertIn("case panel", widgets)
        self.assertIn('case .panel: return "仪表盘"', widgets)
        self.assertIn("var isReadOnly: Bool { self == .panel }", widgets)
        self.assertIn("case .panel:\n            FlightPanel(s: s)", widgets)

    def test_panel_view_is_pure_display(self):
        src = _ios("Views", "FlightPanel.swift")
        for want in ("struct ArcGauge", "struct BarGauge", "struct FlightPanel"):
            self.assertIn(want, src, "FlightPanel.swift 缺 %s" % want)
        # 只读：不得有手势、不得写回 state、不得碰按键回调
        for banned in ("DragGesture", "@Binding", "onButton?(", "btnMask"):
            self.assertNotIn(banned, src, "仪表盘应只读，不该出现 %s" % banned)

    def test_panel_is_in_the_component_library(self):
        cockpit = _ios("Views", "CockpitView.swift")
        self.assertIn('libraryButton("仪表盘", .panel, .roll)', cockpit)
        self.assertIn("kind.isReadOnly", cockpit, "组件库没有对只读组件隐藏绑定选择")

    def test_panel_file_is_registered_in_the_project(self):
        pbx = _read("mobile", "ios", "App", "App.xcodeproj", "project.pbxproj")
        self.assertIn("FlightPanel.swift in Sources", pbx,
                      "FlightPanel.swift 没登记进 Xcode 工程，真机会漏编")


class TestThemeAppearance(unittest.TestCase):
    """浅/深双主题：色值必须动态解析，且没有任何地方再把界面锁死成单一主题。

    历史上从 `Theme` 到 4 处 `.preferredColorScheme(.dark)` 全是写死的暗色，
    白底上直接看不见字。现在只允许在 `AppAppearance` 里出现 `.light` / `.dark`。
    """

    VIEWS = ("CockpitView.swift", "PreflightView.swift", "SettingsView.swift",
             "Theme.swift", "Widgets.swift", "Layout.swift", "Controls.swift",
             "AttitudeBall.swift", "SteeringWheel.swift", "FlightPanel.swift")

    def test_theme_colors_are_dynamic(self):
        theme = _ios("Views", "Theme.swift")
        self.assertIn("static func pd(", theme, "缺 Color.pd 动态色助手")
        self.assertIn("UIColor { traits in", theme, "动态色没有走 UIColor(dynamicProvider:)")
        # 两套色值都得到位
        for token in ("bgTop", "bgBottom", "panel", "panelHi", "border",
                      "text", "textDim", "textFaint", "onAccent",
                      "cyan", "green", "orange", "red", "amber",
                      "glass", "glassBorder", "gridStroke", "glowTop", "glowBottom"):
            self.assertIn("static let %s" % token, theme, "Theme 缺 %s" % token)
        self.assertEqual(theme.count("= Color.pd("), 18,
                         "每个主题色都必须给出浅/深两套值")

    def test_no_view_locks_the_color_scheme(self):
        for name in self.VIEWS:
            src = _ios("Views", name)
            self.assertNotIn("preferredColorScheme(.dark)", src,
                             "%s 还在把界面写死成暗色" % name)
            self.assertNotIn("preferredColorScheme(.light)", src, name)
        app = _ios("PalmDeckApp.swift")
        self.assertNotIn("preferredColorScheme", app,
                         "根视图应该用 .palmAppearance() 而不是写死")

    def test_appearance_modifier_is_applied_at_every_presentation(self):
        theme = _ios("Views", "Theme.swift")
        for want in ("enum AppAppearance", "static let key = \"palmdeck_appearance\"",
                     "static let fallback: AppAppearance = .light",
                     "struct AppearanceModifier", "func palmAppearance()"):
            self.assertIn(want, theme, "Theme.swift 缺 %s" % want)
        # 根 + 三个 presentation（sheet/cover 不一定继承窗口 override）
        for name in ("PalmDeckApp.swift", "Views/CockpitView.swift",
                     "Views/PreflightView.swift", "Views/SettingsView.swift"):
            self.assertIn(".palmAppearance()", _ios(*name.split("/")),
                          "%s 没带 .palmAppearance()" % name)

    def test_appearance_setting_is_reachable_from_search(self):
        s = _ios("Views", "SettingsView.swift")
        self.assertIn("case connection, profiles, layout, controls, haptics, wheel, appearance, help", s)
        self.assertIn('case .appearance: return "外观"', s)
        self.assertIn("case .appearance: appearanceSections", s)
        self.assertIn(".init(self, \"外观模式\",", s, "外观没进搜索索引")
        self.assertIn("@AppStorage(AppAppearance.key)", s)

    def test_instruments_stay_dark_on_purpose(self):
        """姿态球是真仪表：白底上放黑表盘，所以它的色值不跟着主题走。"""
        theme = _ios("Views", "Theme.swift")
        for token in ("instrBg", "instrSkyHi", "instrSkyLo",
                      "instrGroundHi", "instrGroundLo", "instrLine", "hudAmber", "hudOrange"):
            self.assertIn("static let %s" % token, theme, "Theme 缺固定仪表色 %s" % token)
        # 它们必须是固定色，不能是 Color.pd(
        block = theme.split("// ---- 仪表专用", 1)[1].split("}", 1)[0]
        self.assertNotIn("Color.pd(", block, "仪表色不该随主题变")
        ball = _ios("Views", "AttitudeBall.swift")
        self.assertIn("Theme.instrBg", ball)
        self.assertNotIn("Theme.amber", ball, "姿态球该用固定 hudAmber")
        self.assertNotIn("Theme.orange", ball, "姿态球该用固定 hudOrange")


class TestProfileDoesNotBlankTheCanvas(unittest.TestCase):
    """切预设不得把画布擦成白板。

    症状（用户报的）：设置 → 游戏预设 → 点任意一个 → 座舱面板全空。
    根因：内置预设的 `widgetsJSON` 是 nil（它们只是“手感快照”），
    而 `LayoutStore.applyProfile` 把 nil 当成「空布局」整表替换了。
    """

    def test_builtin_profiles_carry_no_layout(self):
        src = _read("mobile", "ios", "App", "App", "Native", "Model", "GameProfile.swift")
        for fn in ("wardogsProfile", "ets2Profile"):
            body = func_body(src, fn)
            self.assertNotIn("widgetsJSON", body,
                             "%s 是内置“手感快照”，不该夹带布局" % fn)

    def test_apply_profile_skips_when_no_layout(self):
        src = _ios("Views", "Layout.swift")
        body = src.split("func applyProfile(", 1)[1].split("func snapshotWidgetsJSON", 1)[0]
        # 必须先判空再动撤销槽/整表替换
        self.assertIn("guard let list = target else { return }", body,
                      "不带布局时必须直接返回，不能整表替换")
        self.assertLess(body.index("guard let list = target"),
                        body.index("pushUndo"),
                        "先判空再压撤销槽")
        self.assertIn("!list.isEmpty", body, "空数组也得当成“不带布局”")
        self.assertIn("LayoutStore.defaults(mode: mode)", body,
                      "当前是空表时应该铺回默认模块，而不是留白板")

    def test_settings_row_tells_whether_layout_comes_along(self):
        s = _ios("Views", "SettingsView.swift")
        self.assertIn('"仅手感，不动布局"', s)
        self.assertIn('"含布局"', s)
        self.assertIn("布局保持不动", s, "应用后要给反馈，否则用户以为又坏了")


    def test_status_colors_come_from_the_theme(self):
        """状态点/状态字统一走 Theme。

        系统色（`.cyan` / `.green`…）会跟着系统外观走，浅色底上 `.cyan` 淡得读不出来；
        Theme 的两套值是按各自底色配过的。
        """
        pre = _ios("Views", "PreflightView.swift")
        for want in ("return Theme.green", "return Theme.orange", "return Theme.red",
                     "return Theme.cyan", "return Theme.textFaint"):
            self.assertIn(want, pre, "PreflightView 缺 %s" % want)
        for banned in ("return .cyan", "return .green", "return .orange",
                       "return .red", "return .gray"):
            self.assertNotIn(banned, pre, "系统色 `%s` 在浅色底上对比度不够" % banned)


class TestLayoutModuleWiring(unittest.TestCase):
    """三个模式都走通用模块，且都插了默认布局。"""

    def test_defaults_map_each_mode(self):
        src = _ios("Views", "Layout.swift")
        for want in ("case .heli:    return defaultHeli()",
                     "case .drive:   return defaultDrive()",
                     "case .gamepad: return defaultGamepad()"):
            self.assertIn(want, src)

    def test_init_seeds_all_three_modes(self):
        src = _ios("Views", "Layout.swift")
        for want in ("LayoutStore.defaultHeli()",
                     "LayoutStore.defaultDrive()",
                     "LayoutStore.defaultGamepad()"):
            self.assertIn(want, src, "init 没有播种 %s" % want)


class TestWidgetLibrary(unittest.TestCase):
    def test_dead_bindings_are_flagged_in_the_library(self):
        widgets = _ios("Views", "Widgets.swift")
        cockpit = _ios("Views", "CockpitView.swift")
        self.assertIn("onlyOnVJoy", widgets)
        # 阈值必须和 X360 里真实存在的 b 键数量一致
        n = len([k for k in xbox_map() if re.fullmatch(r"b\d+", k)])
        self.assertIn("idx >= %d" % n, widgets, "onlyOnVJoy 的阈值和 X360 对不上")
        self.assertIn("onlyOnVJoy", cockpit, "组件库没有对死绑定做任何提示")

    def test_rt_axis_binding_exists(self):
        widgets = _ios("Views", "Widgets.swift")
        self.assertIn("case roll, pitch, yaw, throttle, brake, clutch, rt, look", widgets)
        self.assertIn("case .rt: return $s.rt", widgets)


class TestEditSession(unittest.TestCase):
    """编辑布局必须能「放弃」：进编辑记回滚点，放弃 = 整表回滚，完成 = 丢掉回滚点。

    历史问题：拖一下就落盘，编辑条上只有「完成」，反悔只能靠设置里的
    「恢复默认布局」（会把你之前的所有定制一起清掉）。
    """

    def setUp(self):
        self.layout = _ios("Views", "Layout.swift")

    def test_store_has_the_session_api(self):
        for sig in ("func beginEditing(mode: CockpitMode)",
                    "func canDiscardEditing(mode: CockpitMode) -> Bool",
                    "func discardEditing(mode: CockpitMode)",
                    "func commitEditing(mode: CockpitMode)"):
            self.assertIn(sig, self.layout, "LayoutStore 缺 %s" % sig)

    def test_begin_records_a_per_mode_baseline(self):
        body = self.layout.split("func beginEditing(mode: CockpitMode)", 1)[1].split("\n    }", 1)[0]
        self.assertIn("editBaseline[mode.rawValue] = widgets(mode: mode)", body)

    def test_discard_restores_and_does_not_touch_the_undo_slot(self):
        body = self.layout.split("func discardEditing(mode: CockpitMode)", 1)[1].split("\n    }", 1)[0]
        self.assertIn("replaceWidgets(base, mode: mode)", body,
                      "放弃必须整表回滚（会重建画布）")
        self.assertNotIn("pushUndo", body,
                         "放弃本身就是回退，不该再叠一层「撤销放弃」")

    def test_commit_only_drops_the_baseline(self):
        body = self.layout.split("func commitEditing(mode: CockpitMode)", 1)[1].split("\n    }", 1)[0]
        self.assertIn("editBaseline[mode.rawValue] = nil", body)
        self.assertNotIn("replaceWidgets", body, "完成不该动布局")

    def test_discard_is_off_when_nothing_changed(self):
        body = self.layout.split("func canDiscardEditing(mode: CockpitMode)", 1)[1].split("\n    }", 1)[0]
        self.assertIn("sameShape", body,
                      "「有没有改过」要用形状比较（UUID 每次重建都变，不能用 ==）")

    def test_edit_bar_has_a_discard_button(self):
        cockpit = _ios("Views", "CockpitView.swift")
        self.assertIn('Button("放弃")', cockpit, "座舱编辑条缺「放弃」")
        self.assertIn("layout.discardEditing(mode: s.mode)", cockpit)
        self.assertIn(".disabled(!layout.canDiscardEditing(mode: s.mode))", cockpit)

    def test_settings_also_offers_discard(self):
        settings = _ios("Views", "SettingsView.swift")
        self.assertIn('Label("放弃本次编辑", systemImage: "arrow.uturn.backward")', settings,
                      "设置 → 布局 也应能放弃（座舱编辑条是被动入口）")
        self.assertIn("layout.discardEditing(mode: s.mode)", settings)

    def test_every_way_into_edit_mode_records_a_baseline(self):
        cockpit = _ios("Views", "CockpitView.swift")
        settings = _ios("Views", "SettingsView.swift")
        self.assertIn("layout.beginEditing(mode: s.mode)", cockpit, "顶栏 [布局] 没记回滚点")
        self.assertIn("layout.beginEditing(mode: s.mode)", settings, "设置里的「编辑布局」没记回滚点")

    def test_leaving_edit_mode_always_commits(self):
        cockpit = _ios("Views", "CockpitView.swift")
        # 完成、顶栏 [完成]、换模式 三条路都得丢掉回滚点，否则下次进来会回滚到旧快照
        self.assertGreaterEqual(cockpit.count("layout.commitEditing(mode: s.mode)"), 3,
                                "离开编辑态的路径没有全部 commitEditing")


class TestNoIdleRepaint(unittest.TestCase):
    """待机不该烧 CPU：`@Published` 不做等值去重，热路径上写一次 = 整棵视图树重绘一次。

    历史坑：`CockpitController` 里有个每 6 帧写一次的 `readout` 字符串（全工程没人读它），
    它实际充当了「刷新心跳」—— 空闲待机（没连电脑、手也没碰）也稳定重绘 10 次/秒。
    实测 Mac Catalyst 上白烧 12~15% CPU；手机上就是发热、掉电。
    现在改成：只由 `sm*`（姿态唯一来源）发布，而且**变了才发布**。
    """

    def setUp(self):
        self.state = _ios("Model", "ControllerState.swift")
        self.ctrl = _ios("Model", "CockpitController.swift")

    def test_smoothed_pose_is_published(self):
        for name in ("smRoll", "smPitch", "smYaw"):
            self.assertIn("@Published private(set) var %s" % name, self.state,
                          "%s 是姿态球/仪表盘/状态条的唯一数据源，不 @Published 界面就不会动" % name)

    def test_pose_is_written_through_a_change_check(self):
        body = self.state.split("private func applySm(", 1)[1].split("\n    }", 1)[0]
        for name in ("smRoll", "smPitch", "smYaw"):
            self.assertRegex(body, r"if abs\(n\w - %s\) > ControllerState\.smEpsilon \{ %s = n\w \}" % (name, name),
                             "%s 的赋值要带上 smEpsilon 判定（否则每帧都发布）" % name)
        self.assertNotIn("smRoll +=", self.state, "不能再无条件累加赋值（每帧都会发布）")

    def test_smoothing_goes_through_applySm(self):
        body = self.state.split("func tickSmoothing()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("applySm(", body, "tickSmoothing 的写回要集中在 applySm 里")

    def test_no_publisher_is_written_every_frame(self):
        tick = self.ctrl.split("private func tick()", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("readout", self.ctrl, "没人读的 readout 心跳要删掉，别用 @Published 当闹钟")
        self.assertNotIn("pfMotionState", self.ctrl)
        self.assertNotIn("frameCount", tick, "去掉 %6 降频的假心跳；刷新交给 sm* 的变化")
        # tick 里除 Haptics 外不应写任何 @Published 字段（状态条/画布靠 sm* 自己带动）
        self.assertNotRegex(tick, r"\bself\.[a-zA-Z]+ =|\bstate\.(link|hz|transport|lastError) =[^=]")


class TestStatusStripFollowsTheMode(unittest.TestCase):
    """底部仪表条显示的必须是**真正发出去**的那几个量。

    历史坑：三个模式共用一套写死的 `ROL/PIT/YAW/THR`。开车模式真值表里 Rz 恒 0
    （不发），手柄模式的 thr/lt/rt 也全清零 —— 屏幕上却照旧摆着「方向 / 油门」。
    跟 E1 修的是同一类：界面说的和发出去的对不上。
    """

    def setUp(self):
        self.cockpit = _ios("Views", "CockpitView.swift")
        self.hud = _ios("Model", "HudReadout.swift")

    def test_strip_reads_the_wire_values(self):
        self.assertIn("HudReadout.axis(mode: s.mode, out: s.wireAxes)", self.cockpit,
                      "仪表条必须按模式取字段，而且吃的是 s.wireAxes（发出去的那份）")

    def test_no_hardcoded_aviation_cells(self):
        for tag in ('label: "ROL"', 'label: "PIT"', 'label: "YAW"', 'label: "THR"'):
            self.assertNotIn(tag, self.cockpit, "状态条不该再写死 %s" % tag)

    def test_no_degree_sign_on_normalized_sticks(self):
        self.assertNotIn('"%+.1f°"', self.cockpit,
                         "杆位是 -1…1 的归一化值，不是角度，不能带 °")
        self.assertIn("static func bipolar", self.hud)

    def test_drive_drops_the_yaw_cell(self):
        body = self.hud.split("case .drive:", 1)[1].split("case .gamepad:", 1)[0]
        self.assertNotIn('label: "方向"', body, "开车模式不发 Rz，不该有「方向」格")

    def test_gamepad_drops_throttle_and_brake(self):
        pad = self.hud.split("case .gamepad:", 1)[1]
        for banned in ("油门", "刹车", "总距"):
            self.assertNotIn('label: "%s"' % banned, pad,
                             "手柄模式 thr/lt/rt 恒 0，不该有「%s」格" % banned)

    def test_the_truth_table_is_resolved_in_exactly_one_place(self):
        packet = _ios("Model", "Packet.swift")
        state = _ios("Model", "ControllerState.swift")
        self.assertIn("axes: s.wireAxes", packet, "Packet.pack 要走 s.wireAxes")
        self.assertNotIn("AxisMap.resolve", packet,
                         "真值表只能算一处（ControllerState.wireAxes），否则显示/发送会各算一遍")
        self.assertIn("var wireAxes: AxisOutputs", state)


class TestDeckChromeDoesNotCoverTheCanvas(unittest.TestCase):
    """盖在画布上的浮层 = 摸不到的组件（点不动、拖不动，而且看不出来）。

    历史坑：`deckBody` 原来是 `ZStack { 画布; 编辑条 }` + `.overlay(.top) { 未连接横幅 }`，
    默认布局从 y=0.10 起就是为了躲那条横幅。
    """

    def setUp(self):
        self.src = _ios("Views", "CockpitView.swift")
        self.body = self.src.split("private func deckBody(", 1)[1].split("private var editBar", 1)[0]
        self.bar = self.src.split("private var editBar", 1)[1].split("private var dotColor", 1)[0]

    def test_no_top_overlay_on_the_deck(self):
        self.assertNotIn("overlay(alignment: .top) { if !layout.editing", self.body,
                         "未连接横幅不能压在画布上（被盖的组件点不动）")

    def test_deck_body_stacks_chrome_above_the_canvas(self):
        self.assertIn("VStack(spacing: 0)", self.body)
        self.assertNotIn("ZStack", self.body, "横幅/编辑条要与画布上下排，不能叠在画布上")
        self.assertIn("if layout.editing { editBar }", self.body)
        self.assertIn("WidgetCanvas(store: layout", self.body)

    def test_edit_bar_does_not_stretch_over_the_canvas(self):
        self.assertNotIn("Spacer(minLength: 0)", self.bar,
                         "编辑条用 Spacer 会橑满整个画布（旧写法）——它是画布上面的一行")


if __name__ == "__main__":
    unittest.main()
