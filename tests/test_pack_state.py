"""A3/A4: cockpit pack rules for PD v1 (must match iOS Packet.swift)."""

import struct
import unittest

PKT = struct.Struct("<2sBB8hH")
SCALE = 32767


def pack_state(mode: str, throttle: float, rt: float, lt: float = 0.0, brakes: float = 0.0) -> bytes:
    # v4 canonical `gamepad`；`infantry` 为旧客户端别名
    gamepad = mode in ("gamepad", "infantry")
    if mode == "drive":
        rt_out = throttle
    elif gamepad:
        rt_out = 0.0
    else:
        rt_out = rt
    thr_out = 0.0 if gamepad else throttle
    lt_out = 0.0 if gamepad else (lt or brakes)

    def i16(v: float) -> int:
        return max(-32767, min(32767, round(v * SCALE)))

    return PKT.pack(b"PD", 1, 255, 0, 0, 0, 0, 0, i16(thr_out), i16(lt_out), i16(rt_out), 0)


class PackStateTests(unittest.TestCase):
    def test_gamepad_and_legacy_alias_pack_identically(self) -> None:
        self.assertEqual(
            pack_state("gamepad", throttle=0.9, rt=1.0, lt=1.0),
            pack_state("infantry", throttle=0.9, rt=1.0, lt=1.0),
        )

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


def pack_full(
    roll: float = 0.0, pitch: float = 0.0, yaw: float = 0.0,
    look_x: float = 0.0, look_y: float = 0.0, thr: float = 0.0,
    lt: float = 0.0, rt: float = 0.0, buttons: int = 0,
) -> bytes:
    def i16(v: float) -> int:
        return max(-32767, min(32767, round(v * SCALE)))
    return PKT.pack(b"PD", 1, 255, i16(roll), i16(pitch), i16(yaw),
                    i16(look_x), i16(look_y), i16(thr), i16(lt), i16(rt), buttons)


class DriveAxisTests(unittest.TestCase):
    """开车拨杆约定（iOS Packet.swift）：
    方向盘=左摇杆 X，离合=左摇杆 Y（0 → 中位，1 → -1），视角触屏=右摇杆。
    """

    def test_drive_axis_mapping_vjoy(self) -> None:
        from hotas import remap_vjoy
        m = remap_vjoy("hotas", roll=0.3, pitch=0.8, throttle=0.5,
                       yaw=0.0, left_t=0.0, look_x=1.0, look_y=0.0)
        self.assertAlmostEqual(m["x"], 0.3, places=3)     # 方向盘 → X
        self.assertAlmostEqual(m["y"], -0.8, places=3)    # 左摇杆 Y = -离合
        self.assertEqual(m["rz"], 0.0)                    # 离合不再占 Rz
        self.assertAlmostEqual(m["rx"], 1.0, places=3)    # 视角 → RX

    def test_drive_packet_carries_clutch_in_pitch_leaves_yaw_zero(self) -> None:
        from bridge import Hub
        from tests.fakes import FakeHotas

        hub = Hub(hotas=FakeHotas())
        hub.udp_allowlist = False
        # iOS 开车：pitch 字段载离合，yaw(Rz) 置 0，视角走 look
        hub.apply_packet(
            pack_full(roll=0.3, pitch=0.8, yaw=0.0, look_x=1.0, look_y=-0.4),
            src="ws", ip="127.0.0.1",
        )
        self.assertAlmostEqual(hub.hotas.axes["roll"], 0.3, places=2)    # 方向盘
        self.assertAlmostEqual(hub.hotas.axes["pitch"], 0.8, places=2)   # 离合（左摇杆 Y）
        self.assertEqual(hub.hotas.axes["yaw"], 0)                       # Rz 不再给离合
        self.assertAlmostEqual(hub.hotas.axes["look_x"], 1.0, places=2)  # 视角 → 右摇杆 X


if __name__ == "__main__":
    unittest.main()
