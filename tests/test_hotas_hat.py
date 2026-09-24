"""苦力帽只写 POV、不再同时按 vJoy 按钮 11–14（修复 b11~b14 与 hat 重复）。"""

from __future__ import annotations

import unittest

from hotas import Hotas


class FakeVJoy:
    def __init__(self) -> None:
        self.povs: list = []
        self.buttons: list = []

    def set_disc_pov(self, n: int, v: int) -> None:
        self.povs.append((n, v))

    def set_button(self, n: int, v: int) -> None:
        self.buttons.append((n, v))


class HotasHatTests(unittest.TestCase):
    def make(self) -> tuple[Hotas, FakeVJoy]:
        h = Hotas()
        dev = FakeVJoy()
        h._devs = [("vjoy", object(), dev)]  # 只注入 vjoy，隔离验证
        return h, dev

    def test_hat_up_writes_pov_only(self) -> None:
        h, dev = self.make()
        h.tap_button("hat_up", True)
        h.tap_button("hat_up", False)
        self.assertEqual(dev.povs, [(1, 0), (1, -1)])
        self.assertEqual(dev.buttons, [], "苦力帽不应再写 vJoy 按钮 11–14")

    def test_hat_momentary_centers_pov(self) -> None:
        h, dev = self.make()
        h.tap_button("hat_down")  # pressed=None → 瞬时：写 POV 后立即回中
        self.assertEqual(dev.povs, [(1, 2), (1, -1)])
        self.assertEqual(dev.buttons, [])

    def test_b11_still_a_normal_button(self) -> None:
        h, dev = self.make()
        h.tap_button("b11", True)
        self.assertEqual(dev.buttons, [(11, 1)])
        self.assertEqual(dev.povs, [])

    def test_all_hat_directions_are_pov(self) -> None:
        h, dev = self.make()
        for alias in ("hat_up", "hat_right", "hat_down", "hat_left"):
            h.tap_button(alias, True)
            h.tap_button(alias, False)
        self.assertEqual([v for _, v in dev.povs], [0, -1, 1, -1, 2, -1, 3, -1])
        self.assertEqual(dev.buttons, [])


class FakeVGamepad:
    """最小 vgamepad 替身：记录 press/release 的 XUSB_BUTTON 名字。"""

    class XUSB_BUTTON:
        XUSB_GAMEPAD_A = "A"
        XUSB_GAMEPAD_B = "B"
        XUSB_GAMEPAD_X = "X"
        XUSB_GAMEPAD_Y = "Y"
        XUSB_GAMEPAD_LEFT_SHOULDER = "LEFT_SHOULDER"
        XUSB_GAMEPAD_RIGHT_SHOULDER = "RIGHT_SHOULDER"
        XUSB_GAMEPAD_BACK = "BACK"
        XUSB_GAMEPAD_START = "START"
        XUSB_GAMEPAD_LEFT_THUMB = "LEFT_THUMB"
        XUSB_GAMEPAD_RIGHT_THUMB = "RIGHT_THUMB"
        XUSB_GAMEPAD_DPAD_UP = "DPAD_UP"
        XUSB_GAMEPAD_DPAD_DOWN = "DPAD_DOWN"
        XUSB_GAMEPAD_DPAD_LEFT = "DPAD_LEFT"
        XUSB_GAMEPAD_DPAD_RIGHT = "DPAD_RIGHT"

    def __init__(self) -> None:
        self.log: list = []

    def press_button(self, button=None) -> None:
        self.log.append(("press", button))

    def release_button(self, button=None) -> None:
        self.log.append(("release", button))

    def update(self) -> None:
        pass


class HotasXboxHatTests(unittest.TestCase):
    """E1：开车模式的视角键改走 hat → Xbox D-pad，这条链路必须真的通。"""

    HAT_TO_DPAD = {
        "hat_up": "DPAD_UP",
        "hat_right": "DPAD_RIGHT",
        "hat_down": "DPAD_DOWN",
        "hat_left": "DPAD_LEFT",
    }

    def make(self) -> tuple[Hotas, FakeVGamepad]:
        h = Hotas()
        dev = FakeVGamepad()
        h._devs = [("vgamepad", FakeVGamepad, dev)]
        return h, dev

    def test_hat_directions_reach_the_xbox_dpad(self) -> None:
        h, dev = self.make()
        for alias, token in self.HAT_TO_DPAD.items():
            dev.log.clear()
            h.tap_button(alias, True)
            h.tap_button(alias, False)
            self.assertEqual(
                dev.log,
                [("press", token), ("release", token)],
                "hat %s 应映射到 Xbox %s" % (alias, token),
            )

    def test_center_hat_is_not_a_button(self) -> None:
        h, dev = self.make()
        h.tap_button("hat_center", True)
        self.assertEqual(dev.log, [])



if __name__ == "__main__":
    unittest.main()
