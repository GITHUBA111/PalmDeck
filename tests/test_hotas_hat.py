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


if __name__ == "__main__":
    unittest.main()
