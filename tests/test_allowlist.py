import struct
import unittest

from bridge import PKT, Hub
from tests.fakes import FakeHotas


def pd(*, roll=0, throttle=0.5, rt=0.0, lt=0.0, buttons=0, hat=255) -> bytes:
    s = 32767
    return PKT.pack(
        b"PD",
        1,
        hat,
        int(roll * s),
        0,
        0,
        0,
        0,
        int(throttle * s),
        int(lt * s),
        int(rt * s),
        buttons,
    )


class AllowlistTests(unittest.TestCase):
    def setUp(self) -> None:
        self.hub = Hub(hotas=FakeHotas())
        self.hub.udp_allowlist = True

    def test_udp_dropped_when_never_had_ws(self) -> None:
        ok = self.hub.apply_packet(pd(roll=1), src="udp", ip="192.168.1.8")
        self.assertFalse(ok)
        self.assertIsNone(self.hub.rate.last)
        self.assertEqual(self.hub.dropped_udp, 1)
        self.assertEqual(self.hub.hotas.axes, {})

    def test_udp_accepted_from_ws_peer(self) -> None:
        self.hub.note_ws_up("192.168.1.8", lambda m: None)
        ok = self.hub.apply_packet(pd(roll=0.5), src="udp", ip="192.168.1.8")
        self.assertTrue(ok)
        self.assertIsNotNone(self.hub.rate.last)
        self.assertAlmostEqual(self.hub.hotas.axes["roll"], 0.5, places=2)

    def test_udp_other_ip_dropped_while_peer_connected(self) -> None:
        self.hub.note_ws_up("192.168.1.8", lambda m: None)
        ok = self.hub.apply_packet(pd(roll=1), src="udp", ip="10.0.0.9")
        self.assertFalse(ok)
        self.assertEqual(self.hub.hotas.axes, {})

    def test_open_udp_accepts_any_source(self) -> None:
        self.hub.udp_allowlist = False
        ok = self.hub.apply_packet(pd(roll=-0.25), src="udp", ip="8.8.8.8")
        self.assertTrue(ok)
        self.assertAlmostEqual(self.hub.hotas.axes["roll"], -0.25, places=2)

    def test_owner_blocks_second_phone_json(self) -> None:
        self.hub.set_cockpit_mode("heli", ip="192.168.1.8")
        self.hub.axes({"roll": 1, "throttle": 0.4}, ip="10.0.0.9")
        self.assertEqual(self.hub.hotas.axes, {})
        self.hub.axes({"roll": 0.2, "throttle": 0.4}, ip="192.168.1.8")
        self.assertAlmostEqual(self.hub.hotas.axes["roll"], 0.2, places=2)


if __name__ == "__main__":
    unittest.main()
