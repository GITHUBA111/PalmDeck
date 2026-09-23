"""A3/A4: cockpit pack rules for PD v1 (must match web/index.html packState)."""

import struct
import unittest

PKT = struct.Struct("<2sBB8hH")
SCALE = 32767


def pack_state(mode: str, throttle: float, rt: float, lt: float = 0.0, brakes: float = 0.0) -> bytes:
    if mode == "drive":
        rt_out = throttle
    elif mode == "infantry":
        rt_out = 0.0
    else:
        rt_out = rt
    thr_out = 0.0 if mode == "infantry" else throttle
    lt_out = 0.0 if mode == "infantry" else (lt or brakes)

    def i16(v: float) -> int:
        return max(-32767, min(32767, round(v * SCALE)))

    return PKT.pack(b"PD", 1, 255, 0, 0, 0, 0, 0, i16(thr_out), i16(lt_out), i16(rt_out), 0)


class PackStateTests(unittest.TestCase):
    def test_a3_drive_rt_is_throttle(self) -> None:
        raw = pack_state("drive", throttle=0.8, rt=0.0)
        *_, thr, lt, rt, _btn = PKT.unpack(raw)
        self.assertAlmostEqual(thr / SCALE, 0.8, places=3)
        self.assertAlmostEqual(rt / SCALE, 0.8, places=3)
        self.assertEqual(lt, 0)

    def test_a4_heli_rt_is_fire_not_throttle(self) -> None:
        raw = pack_state("heli", throttle=0.42, rt=1.0)
        *_, thr, _lt, rt, _btn = PKT.unpack(raw)
        self.assertAlmostEqual(thr / SCALE, 0.42, places=3)
        self.assertAlmostEqual(rt / SCALE, 1.0, places=3)

    def test_heli_released_fire_is_zero(self) -> None:
        raw = pack_state("heli", throttle=0.42, rt=0.0)
        *_, _thr, _lt, rt, _btn = PKT.unpack(raw)
        self.assertEqual(rt, 0)

    def test_drive_brake_lt(self) -> None:
        raw = pack_state("drive", throttle=0.5, rt=0.0, lt=1.0)
        *_, _thr, lt, rt, _btn = PKT.unpack(raw)
        self.assertAlmostEqual(lt / SCALE, 1.0, places=3)
        self.assertAlmostEqual(rt / SCALE, 0.5, places=3)

    def test_hub_applies_drive_rt(self) -> None:
        from bridge import Hub
        from tests.fakes import FakeHotas

        hub = Hub(hotas=FakeHotas())
        hub.udp_allowlist = False
        hub.apply_packet(pack_state("drive", throttle=0.7, rt=0.0), src="ws", ip="127.0.0.1")
        self.assertAlmostEqual(hub.hotas.axes["rt"], 0.7, places=2)
        self.assertAlmostEqual(hub.hotas.axes["throttle"], 0.7, places=2)


if __name__ == "__main__":
    unittest.main()
