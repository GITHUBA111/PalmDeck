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
        self.assertIn("case connection, profiles, layout, controls, haptics, appearance, help", s)
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
        # 两种形态在这一行要能一眼分清：整机带布局 / 整机不带布局 / 只装布局。
        self.assertIn('p.hasLayout ? "含布局" : "仅手感"', s)
        self.assertIn('只装组件', s, "布局预设要说清楚它不带手感")
        self.assertIn("个组件", s, "布局预设要显示会铺多少个组件")
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


class TestBindingOptions(unittest.TestCase):
    """组件库「绑定」下拉必须按类型收敛。

    历史坑：下拉列的是 `WidgetBinding.allCases`（8 轴 + 20 键），类型选「按键」
    照样能选「油门」这类**轴**绑定；而 `tapButton` 对轴绑定是空实现 ⇒ 加出来的是
    **按了没反应的按键**；更糟的是默认绑定写死 `.throttle`，选「按键」→「添加到画布」
    一步就能踩到。方向盘的绑定下拉同样是假的（渲染时写死通道，`binding` 被忽略）。

    修法：`WidgetBinding.axes` / `.buttons` 只列**真会被用到**的那些；
    `WidgetKind.bindingOptions` 只说滑条/按键有绑定；弹窗按它给选项、换类型归第一个。
    方案：`docs/PalmDeck-v4-binding-filter.md`。
    """

    def setUp(self):
        self.widgets = _ios("Views", "Widgets.swift")
        self.cockpit = _ios("Views", "CockpitView.swift")

    def _swift_list(self, name):
        body = self.widgets.split("static let %s: [WidgetBinding] = [" % name, 1)[1]
        body = body.split("]", 1)[0]
        return set(re.findall(r"\.(\w+)", body))

    # ---- 模型层：清单必须与真正的实现一一对应 ----

    def test_axes_match_what_bind_axis_handles(self):
        """`axes` 与 `bindAxis` 的 case 必须完全一致 —— 不然又是一个「选了等于没选」。"""
        body = self.widgets.split("private func bindAxis", 1)[1]
        body = body.split("private func isButtonActive", 1)[0]
        handled = set(re.findall(r"case \.(\w+):", body))
        self.assertEqual(self._swift_list("axes"), handled,
                         "滑条下拉给的轴，必须每一项都被 bindAxis 处理")

    def test_axes_do_not_include_look(self):
        """`look` 只被写死通道的组件（触摸板/摇杆/苦力帽）内部用，滑条 bindAxis 不处理它。"""
        self.assertNotIn("look", self._swift_list("axes"),
                         "滑条选「视角」会落进 bindAxis 的 default → 静默变成横滚")

    def test_buttons_match_what_tap_button_handles(self):
        """`buttons` = 16 个 vJoy 键 + 升/降档 + 开火，且不含任何轴。"""
        body = self.widgets.split("private func tapButton", 1)[1]
        named = set(re.findall(r"b == \.(\w+)", body))       # gearUp / gearDown / fire
        expected = {"vjoy%d" % i for i in range(1, 17)} | named
        self.assertEqual(self._swift_list("buttons"), expected,
                         "按键下拉给的键，必须每一项都被 tapButton 处理")
        self.assertNotIn("roll", self._swift_list("buttons"))

    def test_only_slider_and_button_have_binding_options(self):
        body = self.widgets.split("var bindingOptions: [WidgetBinding] {", 1)[1]
        body = body.split("\n    }", 1)[0]
        self.assertRegex(body, r"case \.slider:\s*return WidgetBinding\.axes")
        self.assertRegex(body, r"case \.button:\s*return WidgetBinding\.buttons")
        self.assertRegex(body, r"default:\s*return \[\]",
                         "方向盘/触摸板/摇杆/苦力帽/姿态球不读 binding，不该给下拉")

    def test_button_default_binding_is_a_key(self):
        body = self.widgets.split("var defaultBinding: WidgetBinding {", 1)[1]
        body = body.split("\n    }", 1)[0]
        self.assertRegex(body, r"case \.button:\s*return \.vjoy1",
                         "换到按键时绑定要落到「按钮 1」，不能留着 .throttle")

    # ---- UI 层：弹窗用的是类型清单，而不是全量枚举 ----

    def test_library_picker_uses_kind_options(self):
        self.assertIn("ForEach(kind.bindingOptions, id: \\.self)", self.cockpit)
        self.assertNotIn("ForEach(WidgetBinding.allCases", self.cockpit,
                         "全量枚举正是「按键能选油门」的根因")

    def test_sheet_preselects_the_tapped_kind(self):
        self.assertIn("init(store: LayoutStore, mode: CockpitMode, initialKind: WidgetKind)",
                      self.cockpit, "弹窗要能从被点的类型开始，而不是总从滑条起")
        # 用 .sheet(item:) 把类型当成弹窗输入：先改 state 再 isPresented 会拿到旧值
        self.assertIn(".sheet(item: $libraryKind)", self.cockpit)
        self.assertIn("LibrarySheet(store: layout, mode: s.mode, initialKind: kind)", self.cockpit)
        self.assertNotIn("showLibrary", self.cockpit, "presented 开关会被 state 更新时序坑到")
        self.assertIn("libraryKind = kind", self.cockpit)
        self.assertIn("var id: String { rawValue }", self.widgets, "WidgetKind 要能当 sheet 的 item")
        self.assertIn("initialKind.bindingOptions.first ?? initialKind.defaultBinding", self.cockpit)

    def test_changing_kind_resets_binding_to_first_of_class(self):
        self.assertIn(".onChange(of: kind)", self.cockpit)
        self.assertIn("newKind.bindingOptions.first ?? newKind.defaultBinding", self.cockpit,
                      "换类型后必须把绑定归到该类第一个，不能让轴的绑定留在按键上")

    def test_fixed_kinds_explain_what_they_send(self):
        for note in ('固定发「横滚/转向」', '固定发「视角」', '固定发「横滚 + 俯仰」',
                     '固定发「苦力帽 + 视角」', '只显示本机杆位'):
            self.assertIn(note, self.widgets, "固定通道组件要说明它到底发什么")
        self.assertIn("kind.fixedBindingNote", self.cockpit)


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


class TestCanvasEditGesturesUseGlobalSpace(unittest.TestCase):
    """拖/缩放组件的手势必须在**固定**坐标空间里量位移。

    组件自己会跟着手指跑。在 `.local`（手势视图自己的坐标空间）里量位移，
    视图一动就把同一根手指的位移抵消掉一半：拖一下只走一半 ——「组件总追不上手指」。
    """

    def setUp(self):
        self.edit = _ios("Views", "Layout.swift").split("struct EditableWidget", 1)[1]

    def test_move_and_resize_use_global(self):
        self.assertEqual(self.edit.count("DragGesture(coordinateSpace: .global)"), 2,
                         "拖动本体与缩放把手两个手势都要 .global")

    def test_no_local_drag_gesture(self):
        self.assertEqual(self.edit.count("DragGesture("), 2,
                         "EditableWidget 里只应有拖动 + 缩放两个手势")


class TestEditBarReachesWholeTableActions(unittest.TestCase):
    """清空 / 恢复默认 / 撤销不能只藏在设置里 —— 改布局的人就在座舱里（编辑态）。

    它们都是整表操作，`clear` / `reset` 都会压一道撤销槽，所以不需要二次确认
    （与设置页一致：只是 `role: .destructive` 红字）。
    """

    def setUp(self):
        src = _ios("Views", "CockpitView.swift")
        self.bar = src.split("private var editBar", 1)[1].split("private var dotColor", 1)[0]

    def test_edit_bar_has_a_menu(self):
        self.assertIn("Menu {", self.bar, "编辑条要有整表操作的入口")

    def test_menu_wires_restore_clear_undo(self):
        for call in ("layout.applyDefault(mode: s.mode)",
                     "layout.clear(mode: s.mode)",
                     "layout.undoLast(mode: s.mode)"):
            self.assertIn(call, self.bar)
        self.assertIn("disabled(!layout.canUndo(mode: s.mode))", self.bar,
                      "没得撤销时该置灰，而不是点了没反应")

    def test_whole_table_items_are_destructive(self):
        self.assertEqual(self.bar.count("Button(role: .destructive) {"), 2,
                         "恢复默认 / 清空都要红字（与设置页一致）")


class TestEmptyCanvasHasAHint(unittest.TestCase):
    """空画布不能就是一块白板（看不出是「本来就空」还是「没加载出来」）。"""

    def setUp(self):
        src = _ios("Views", "Layout.swift")
        self.canvas = src.split("struct WidgetCanvas", 1)[1].split("/// 单个可编辑组件", 1)[0]

    def test_hint_when_empty(self):
        self.assertIn("store.widgets(mode: mode).isEmpty", self.canvas)
        self.assertIn("画布是空的", self.canvas)
        self.assertIn("allowsHitTesting(false)", self.canvas,
                      "提示不能被点/拖（不能抢画布手势）")


class TestDeleteAndAddAreUndoable(unittest.TestCase):
    """✕ 删除只有 22pt，又在「抓组件拖拽时手会按到」的左上角，误删必须能后悔。

    add / remove 各压一道撤销槽（整表快照），⋯ 菜单里的「撤销上一次改动」就把它捞回来。
    拖动 / 改名走 `update`（高频），**不能**压撤销槽。
    """

    def setUp(self):
        self.layout = _ios("Views", "Layout.swift")

    def _body(self, sig):
        self.assertIn(sig, self.layout, "LayoutStore 缺 %s" % sig)
        return self.layout.split(sig, 1)[1].split("\n    }", 1)[0]

    def test_add_pushes_undo(self):
        self.assertIn("pushUndo(mode: mode)", self._body("func add(kind: WidgetKind"))

    def test_remove_pushes_undo(self):
        self.assertIn("pushUndo(mode: mode)", self._body("func remove(id: String"))

    def test_update_does_not_push_undo(self):
        self.assertNotIn("pushUndo", self._body("func update(_ w: DeckWidget"),
                         "拖拽是高频调用，压撤销槽会打断手势")


class TestDragSnappingIsWired(unittest.TestCase):
    """吸附规则本身在 `Model/Snap.swift`（有 swiftc 单测）。

    这里只钉**接线**：拖动分支真的走了 Snap、松手/退出编辑会收线、
    缩放**不**吸（本次不做）、对齐线不落盘。
    """

    def setUp(self):
        self.layout = _ios("Views", "Layout.swift")
        self.edit = self.layout.split("struct EditableWidget", 1)[1]
        self.move = self.edit.split("// 缩放", 1)[0]
        self.resize = self.edit.split("// 缩放", 1)[1].split("// 删除", 1)[0]

    def test_snap_is_resolved_in_exactly_one_place(self):
        self.assertEqual(self.layout.count("Snap.drag("), 1,
                         "吸附只能由 dragOutcome 一处算（别分散到手势里）")

    def test_move_gesture_snaps_and_reports_guides(self):
        self.assertIn("dragOutcome(from: st", self.move)
        self.assertIn("store.setGuides(x: o.guideX, y: o.guideY)", self.move)

    def test_guides_are_cleared_when_the_drag_ends(self):
        self.assertIn("store.clearGuides()", self.move, "松手必须收线")

    def test_leaving_edit_mode_clears_the_guides(self):
        self.assertIn("if !editing { clearGuides() }", self.layout,
                      "退出编辑不能让一条对齐线留在画布上")

    def test_guides_are_not_persisted(self):
        save = self.layout.split("private func saveUndo()", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("guide", save, "对齐线只是瞬时提示，不该进存储")

    def test_resize_does_not_snap(self):
        self.assertNotIn("Snap", self.resize, "本次只做拖动吸附，缩放不接")

    def test_canvas_draws_the_guides(self):
        canvas = self.layout.split("struct WidgetCanvas", 1)[1].split("/// 单个可编辑组件", 1)[0]
        self.assertIn("store.guidesX", canvas)
        self.assertIn("store.guidesY", canvas)
        self.assertIn("allowsHitTesting(false)", canvas)

    def test_others_exclude_the_dragged_widget(self):
        self.assertIn("filter { $0.id != widget.id }", self.layout,
                      "“其它组件”不能含自己，否则会被自己吸住")


if __name__ == "__main__":
    unittest.main()


class TestUnifiedPresets(unittest.TestCase):
    """「模板」和「游戏预设」合并成一个概念：都是命名快照，只是一个记整机、一个只记布局。

    合并前两套系统各存各的键、各有一套 UI，用户要在两个分类里找「我上次存的那套」。
    现在只有「设置 → 预设」一处，且「布局」预设只在自己那个模式下出现。
    """

    def test_template_vocabulary_is_gone(self):
        for rel in (("Views", "Layout.swift"),
                    ("Views", "SettingsView.swift"),
                    ("Views", "CockpitView.swift")):
            src = _ios(*rel)
            for dead in ("LayoutTemplate", "saveTemplate", "renameTemplate",
                         "deleteTemplate", "applyTemplate", "templatesByMode",
                         "customTemplates", "maxTemplates", "TplPrompt"):
                self.assertNotIn(dead, src, "%s 里不该再有「模板」这套东西" % (rel,))

    def test_store_key_is_v2_and_old_keys_are_read_only(self):
        src = _ios("Model", "GameProfile.swift")
        self.assertIn('static let key = "palmdeck_game_profiles_v2"', src)
        self.assertIn('static let legacyProfilesKey = "palmdeck_game_profiles_v1"', src)
        self.assertIn('static let legacyTemplatesKey = "palmdeck_layout_templates_v1"', src)
        # 旧键只读：只能从它们 object(...)，绝不能往它们写（否则回滚 App 版本会读到半新半旧的数据）
        body = src.split("private func load()", 1)[1].split("func saveToDisk", 1)[0]
        self.assertIn("object(forKey: GameProfileStore.legacyProfilesKey)", body)
        self.assertIn("object(forKey: GameProfileStore.legacyTemplatesKey)", body)
        self.assertNotIn("set(", body, "load() 里写盘只能走 saveToDisk()")

    def test_migration_only_runs_when_v2_is_absent(self):
        src = _ios("Model", "GameProfile.swift")
        body = src.split("private func load()", 1)[1].split("func saveToDisk", 1)[0]
        # 有 v2 就直接 return —— 否则用户删掉的预设会在下次启动复活
        self.assertLess(body.index("object(forKey: GameProfileStore.key)"),
                        body.index("GameProfileMigration.merge"),
                        "先读 v2；有就直接用")
        self.assertIn("return", body.split("GameProfileMigration.merge", 1)[0].split("custom = obj", 1)[1])

    def test_builtin_default_layout_is_a_row_not_a_button(self):
        src = _ios("Views", "SettingsView.swift")
        self.assertIn("case profile(GameProfile), restoreDefault", src,
                      "内置「默认」应该在预设列表里占一行")
        self.assertIn("layout.applyDefault(mode: s.mode)", src)
        self.assertNotIn("恢复默认布局", src, "它是列表里的一行，不再是另一个分类里的按钮")

    def test_layout_presets_are_mode_scoped(self):
        src = _ios("Views", "SettingsView.swift")
        self.assertIn("$0.hasShaping || $0.mode == s.mode", src,
                      "「布局」预设只在自己那个模式下出现")

    def test_cockpit_edit_bar_saves_a_layout_preset(self):
        src = _ios("Views", "CockpitView.swift")
        self.assertIn("存为预设", src, "编辑条上的入口改名了（模板 → 预设）")
        self.assertIn("GameProfile.layoutOnly(name: presetName", src)
        self.assertIn("widgetsJSON: layout.snapshotWidgetsJSON(mode: s.mode)", src)
        self.assertIn("profiles.save(p)", src)

    def test_save_layout_preset_speaks_back(self):
        """存预设必须回一句话（成功 / 重名 / 名字非法）。

        以前是 `_ = profiles.save(p)`：重名或名字非法时**什么都不发生**，
        用户点完「确定」界面纹丝不动，只能自己怀疑人生。
        """
        src = _ios("Views", "CockpitView.swift")
        body = src.split("private func saveLayoutPreset()", 1)[1].split("private var editBar", 1)[0]
        self.assertIn("presetNote = profiles.save(p) ??", body,
                      "save 的返回值（错误文案）必须显示出来")
        self.assertNotIn("_ = profiles.save(p)", body)
        # 回执是画布**上面的一行**（和横幅同规矩），不许用 overlay 盖画布
        self.assertIn("presetNoteRow", src)
        row = src.split("private var presetNoteRow", 1)[1].split("private var editBar", 1)[0]
        self.assertNotIn("overlay", row)
        self.assertIn("if layout.editing && !presetNote.isEmpty", row)

    def test_layout_preset_default_name_counts_from_one(self):
        src = _ios("Views", "CockpitView.swift")
        self.assertIn('presetName = "布局 \(profiles.custom.filter { !$0.hasShaping && $0.mode == s.mode }.count + 1)"',
                      src, "默认名从头数，别从 2 开始（用户会以为少了一个）")


class TestSettingsConsistency(unittest.TestCase):
    """P2：设置页的「一致性 / 可发现性」。

    这一轮只动文案与分组，不动模型 / 存储 / 协议 —— 所以这里守的也全是「字」：

    1. 同一个东西只叫一个名字（清空画布 / 预设 / 电脑 / 可用电脑）；
    2. 标题说得出这一组是什么（不拿动作词或空话当头）；
    3. 分类少而准：只有 2 个滑条的「方向盘」并进「操纵与手感」，
       且要看得出它是**全局项**（不像旁边那些按模式分）。

    方案与理由：`docs/PalmDeck-v4-consistency.md`。
    """

    def setUp(self):
        self.s = _ios("Views", "SettingsView.swift")
        self.pre = _ios("Views", "PreflightView.swift")

    # ---- 分类 ----

    def test_sidebar_says_presets_not_game_presets(self):
        self.assertNotIn('return "游戏预设"', self.s,
                         "侧栏与分区头（「预设」）要同名；P1.5 后它同时装布局预设")
        self.assertIn('case .profiles: return "预设"', self.s)

    def test_wheel_is_not_a_top_level_category(self):
        self.assertNotIn("case wheel", self.s, "两个滑条不值得占一个顶级分类")
        self.assertIn("wheelSection", self.s, "它应该并进「操纵与手感」")
        body = self.s.split("private var controlsSections", 1)[1]
        body = body.split("// ---- 方向盘（全局项，不按模式分） ----", 1)[0]
        self.assertIn("wheelSection", body, "「方向盘」段要在操纵与手感里")
        entries = self.s.split("case .controls:\n            return [", 1)[1]
        entries = entries.split("case .haptics:", 1)[0]
        self.assertIn('"满舵 角度 steering 方向盘 wheel 舵角 圈"', entries,
                      "搜索索引也要跟着搬（否则搜索结果指向不存在的分类）")

    def test_wheel_section_says_it_is_global(self):
        body = self.s.split("private var wheelSection", 1)[1].split("// ---- 外观", 1)[0]
        self.assertIn("全局项", body,
                      "旁边全是按模式分的，这里是全局的 —— 不说清会一直有人找「为什么改了飞机也变」")

    # ---- 段头 ----

    def test_headers_name_their_content(self):
        for bad, why in (("电脑侧", "与「连接」页的「电脑」同名"),
                         ("清空", "动作词不当段头，改「重置」"),
                         ("参数", "废话标题"),
                         ("反馈", "与项名「触觉反馈」重复")):
            self.assertNotIn('SettingsHeader("%s")' % bad, self.s, why)
        for good in ("编辑", "重置", "撤销", "电脑", "方向盘", "触觉反馈"):
            self.assertIn('SettingsHeader("%s")' % good, self.s, "缺段头：%s" % good)

    def test_every_layout_section_has_a_header(self):
        """「撤销」原来是全页唯一一个没头的段（只有 footer）。"""
        undo = self.s.split("private var undoSection", 1)[1].split("private var controlsSections", 1)[0]
        self.assertIn('SettingsHeader("撤销")', undo)

    def test_haptics_toggle_does_not_repeat_its_header(self):
        self.assertIn('Label("开启振动", systemImage: "hand.tap")', self.s)

    # ---- 一个动作一个名字 ----

    def test_clear_says_clear_canvas_here_and_in_cockpit(self):
        self.assertNotIn("清空当前模式", self.s, "座舱里叫「清空画布」，这里也要同名")
        self.assertIn('Label("清空画布", systemImage: "trash")', self.s)
        self.assertIn('Label("清空画布", systemImage: "trash")',
                      _ios("Views", "CockpitView.swift"))

    def test_no_slash_layout_wording(self):
        self.assertNotIn("仅布局", self.s, "行尾章与搜索词都是「布局」，按钮别自己发明第三个词")
        self.assertIn('Label("存为整机预设", systemImage: "plus.circle")', self.s)
        self.assertIn('Label("存为布局预设", systemImage: "plus.circle")', self.s)

    def test_preflight_uses_settings_and_available_computers(self):
        self.assertNotIn("高级设置", self.pre, "座舱里叫「设置」")
        self.assertIn('Text("设置")', self.pre)
        self.assertNotIn("发现的电脑", self.pre, "设置页叫「可用电脑」")
        self.assertIn('Text("可用电脑（点一下连接）")', self.pre)

    def test_computer_is_the_noun(self):
        self.assertNotIn("电脑端已启动", self.s, "名词用「电脑」；「电脑端」只在与 App 对举时用")
        self.assertIn("确认电脑上的 PalmDeck 已启动", self.s)

    # ---- 搜索索引与界面同字 ----

    def test_search_index_labels_exist_in_the_ui(self):
        """搜到的词，点进去得能在界面上看到同样的词。"""
        for label in ("存为整机预设", "存为布局预设", "清空画布", "组件布局",
                      "默认布局", "触觉反馈", "满舵角度", "回正速度"):
            self.assertIn('.init(self, "%s"' % label, self.s, "索引里有：%s" % label)
        for gone in ("自定义组件布局", "预设里恢复默认", "电脑轴映射表", "存为预设\""):
            self.assertNotIn('.init(self, "%s' % gone, self.s, "界面上没有这个字：%s" % gone)

    def test_empty_search_gives_a_next_step(self):
        self.assertIn("试试「死区」", self.s, "搜不到时给个例子，别只说「没有」")


class TestDiscoverability(unittest.TestCase):
    """P2 残留：看得见、点得到、说人话。

    上一轮（`TestSettingsConsistency`）管的是「命名一致性」；这一轮管的是
    **界面上有没有入口、说没说清代价、词是不是人话**：

    a. 顶栏三个入口等权：齿轮也要带字（它是唯一没有标签的入口）；
    b. 预设的改名 / 删除不能只藏在左滑里，行尾要有 `⋯` 菜单（左滑保留）；
    c. 已连接时换模式要先问一句（电脑端换后端，游戏里手柄会掉）；
    d. 状态条与绑定列表说人话（`链路/模式/通道`、「开车/手柄不生效」）。

    方案与理由：`docs/PalmDeck-v4-discoverability.md`。
    """

    def setUp(self):
        self.s = _ios("Views", "SettingsView.swift")
        self.c = _ios("Views", "CockpitView.swift")

    # ---- a. 顶栏三个入口等权 ----

    def test_top_bar_settings_has_a_label(self):
        self.assertNotIn('Image(systemName: "gearshape.fill").font(.system(size: 15))', self.c,
                         "纯齿轮是顶栏唯一没字的入口，新用户不知道它是什么")
        body = self.c.split("connectionChip(height: height)", 1)[1]
        body = body.split("private func connectionChip", 1)[0]
        self.assertIn('Image(systemName: "gearshape.fill")', body)
        self.assertIn('Text("设置")', body, "齿轮旁边要有「设置」两个字")
        self.assertIn(".frame(width: 64)", body, "与「布局」同宽，才像同一类控件")

    def test_tutorial_does_not_say_gear(self):
        self.assertNotIn("齿轮设置", self.c, "教程要与顶栏同字：「设置」")

    # ---- b. 预设行的改名 / 删除看得见 ----

    def test_preset_row_has_a_visible_menu(self):
        self.assertIn("ellipsis.circle", self.s, "只藏在左滑里 = 大部分用户永远找不到")
        row = self.s.split("private func rowBody", 1)[1]
        self.assertIn('Label("重命名", systemImage: "pencil")', row)
        self.assertIn('Label("删除", systemImage: "trash")', row)

    def test_swipe_still_works(self):
        self.assertIn(".swipeActions(edge: .trailing, allowsFullSwipe: false)", self.s,
                      "老路径（左滑）删掉会让已经会用的用户困惑")

    def test_row_is_not_a_button_anymore(self):
        """行整行当 Button 时，行尾的 Menu 点不动（外层把点击吃掉）。"""
        self.assertIn(".onTapGesture { applyPreset(row) }", self.s)
        self.assertNotIn("} label: {\n                    presetRowView(row)", self.s)

    def test_builtin_rows_have_no_menu(self):
        self.assertIn("editable: profiles.isBuiltin(p) ? nil : p", self.s,
                      "内置预设不可删改 —— 菜单点进去发现点不动，比没有菜单更糟")

    def test_footer_says_where_to_rename(self):
        self.assertIn("行尾的 ⋯ 菜单", self.s)

    # ---- c. 已连接时换模式先问一句 ----

    def test_mode_switch_confirms_when_connected(self):
        self.assertIn("pendingMode", self.c)
        self.assertIn("if s.link == .live { pendingMode = m; Haptics.tap() } else { applyMode(m) }",
                      self.c, "未连接时不要多弹一层窗")
        self.assertIn('Button("切换")', self.c)
        self.assertIn('Button("取消", role: .cancel)', self.c)
        # 确认后仍要结束编辑会话（原来是 Button 里直接干这件事）
        apply = self.c.split("private func applyMode", 1)[1].split("/// 顶栏连接胶囊", 1)[0]
        self.assertIn("layout.commitEditing(mode: s.mode)", apply)

    def test_confirm_text_explains_the_cost(self):
        self.assertIn("虚拟 Xbox", self.c, "要说清为什么手柄会掉")

    # ---- d. 说人话 ----

    def test_status_strip_labels_are_chinese(self):
        for gone in ('HudCell(label: "LINK"', 'HudCell(label: "SRC"', 'HudCell(label: "MODE"'):
            self.assertNotIn(gone, self.c, "同一行里轴标签是中文，这三个不该是英文：%s" % gone)
        for good in ('HudCell(label: "链路"', 'HudCell(label: "模式"', 'HudCell(label: "通道"'):
            self.assertIn(good, self.c)
        self.assertIn('s.transport.uppercased()', self.c,
                      "UDP / WS 是协议名，值不动（改了就对不上控制台）")

    def test_binding_list_uses_plain_words(self):
        self.assertNotIn("仅飞行", self.c, "「仅飞行」太省，没说清开车/手柄为什么不生效")
        self.assertIn("开车/手柄不生效", self.c)
        self.assertNotIn("只存在于 vJoy", self.c)
        self.assertIn("只在飞行模式里存在", self.c)
        self.assertIn("vJoy", self.c, "对照电脑侧时仍然要点名，不然没法在游戏里找")
