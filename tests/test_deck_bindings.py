"""App 侧「皮肤上的字」和「真实发出去的键」的一致性回归。

E1 修掉的都是同一类问题：界面写的是 A，实际发出去的是 B。

1. 开车模式「视角键」占 `vjoy5`，和「降档」撞同一个键
   （降档 → `pulse(4)` → b5 = LB）⇒ 按一次降档会连带跳一次镜头。
2. 组件库提供 `vjoy11`–`vjoy16`，但 `hotas.py` 的 `X360` 字典到 `b10` 为止，
   开车/手柄模式下选这几个键不会送到 Xbox 虚拟手柄。
3. 标签和实际键号对不上：
   - `Layout.defaultGamepad()` 把 `gearUp` 标成 LB、`gearDown` 标成 RB，正好相反
     （`Widgets.swift` 里 `gearUp → pulse(5)` → b6 = RIGHT_SHOULDER）。
   - `GamepadDeck` 把 b9/b10 标成 LT/RT，实际 `X360["b9"] = LEFT_THUMB`、
     `X360["b10"] = RIGHT_THUMB`（LT/RT 是模拟扳机轴，不是按键）。

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

# 手柄皮肤上出现的标签 → 它应该对应的 Xbox 键
LABEL_TO_XBOX = {
    "A": "A",
    "B": "B",
    "X": "X",
    "Y": "Y",
    "LB": "LEFT_SHOULDER",
    "RB": "RIGHT_SHOULDER",
    "视图": "BACK",
    "菜单": "START",
    "L3": "LEFT_THUMB",
    "R3": "RIGHT_THUMB",
}


def titled_bindings(src):
    """抓 `title: "X"` 后面最近的 `.vjoyN`，返回 [(标签, 键号 int)]。"""
    out = []
    for label, _between, num in re.findall(r'title: "([^"]+)"(.{0,140}?)\.(vjoy\d+)', src, re.S):
        out.append((label, int(num[4:])))
    return out


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


class TestGamepadDeck(unittest.TestCase):
    def test_every_labelled_button_points_at_the_matching_xbox_key(self):
        src = _ios("Views", "GamepadDeck.swift")
        pairs = titled_bindings(src)
        self.assertGreaterEqual(len(pairs), 10, "手柄皮肤的按键没抓全：%r" % (pairs,))
        m = xbox_map()
        for label, num in pairs:
            self.assertIn(label, LABEL_TO_XBOX, "手柄皮肤出现未登记标签 %r" % label)
            want = LABEL_TO_XBOX[label]
            got = m.get("b%d" % num)
            self.assertEqual(
                got,
                want,
                '手柄皮肤上 "{}" 绑到 vjoy{} → X360[b{}] = {}，应该是 {}'.format(
                    label, num, num, got, want
                ),
            )

    def test_no_two_labels_share_a_button(self):
        pairs = titled_bindings(_ios("Views", "GamepadDeck.swift"))
        by_num = {}
        for label, num in pairs:
            by_num.setdefault(num, set()).add(label)
        dupes = {n: sorted(v) for n, v in by_num.items() if len(v) > 1}
        self.assertEqual(dupes, {}, "手柄皮肤有按键撞号：%r" % dupes)


class TestDriveDeck(unittest.TestCase):
    def _cluster_and_pulses(self):
        src = _ios("Views", "DriveDeck.swift")
        cluster = {int(n) for n in re.findall(r"toggle\(\.vjoy(\d+)\)", src)}
        pulses = set()
        for arg in re.findall(r"pulse\(([^)]*)\)", src):
            # shift 里是 pulse(dir > 0 ? 5 : 4)，丢掉条件只看两个分支
            expr = arg.split("?")[-1]
            pulses |= {int(x) + 1 for x in re.findall(r"\d+", expr)}
        return src, cluster, pulses

    def test_view_key_does_not_collide_with_downshift(self):
        _src, cluster, pulses = self._cluster_and_pulses()
        self.assertIn(5, pulses, "换档没用到 b5（LB）？")
        self.assertIn(6, pulses, "换档没用到 b6（RB）？")
        self.assertEqual(
            cluster & pulses,
            set(),
            "开车模式里这些键既被按键簇 toggle、又被换档 pulse：%r"
            % sorted(cluster & pulses),
        )

    def test_cluster_buttons_are_all_distinct(self):
        src, cluster, _ = self._cluster_and_pulses()
        uses = re.findall(r"toggle\(\.vjoy(\d+)\)", src)
        self.assertEqual(len(uses), len(set(uses)), "按键簇里有重复绑定：%r" % uses)

    def test_view_keys_go_through_the_hat(self):
        src, _, _ = self._cluster_and_pulses()
        self.assertIn("s.hat = dir", src, "视角没有走 hat/D-pad")
        self.assertIn("s.hat = 255", src, "视角松手没有回中")
        for direction in ('glance(0)', 'glance(1)', 'glance(3)'):
            self.assertIn(direction, src, "缺少 %s" % direction)

    def test_all_drive_buttons_stay_within_the_xbox_button_set(self):
        _src, cluster, pulses = self._cluster_and_pulses()
        live = cluster | pulses
        self.assertTrue(
            max(live) <= 10,
            "开车模式用了 Xbox 没有的键号：%r" % sorted(n for n in live if n > 10),
        )


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


class TestLayoutModuleWiring(unittest.TestCase):
    """三个模式都走通用模块，且都插了轴类的默认布局。"""

    def test_all_modes_support_custom(self):
        src = _ios("Views", "Layout.swift")
        self.assertIn("case .gamepad, .heli, .drive: return true", src,
                      "supportsCustom 没有覆盖三个模式")

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


if __name__ == "__main__":
    unittest.main()
