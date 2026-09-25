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


if __name__ == "__main__":
    unittest.main()
