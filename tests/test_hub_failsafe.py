import time
import unittest

from bridge import Hub
from tests.fakes import FakeHotas


class FailsafeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.hub = Hub(hotas=FakeHotas())
        self.hub.park_ms = 0.05
        self.hub.udp_allowlist = False

    def test_boot_does_not_park(self) -> None:
        self.assertIsNone(self.hub.rate.last)
        self.hub.tick_failsafe()
        self.assertFalse(self.hub.last_parked)
        self.assertEqual(self.hub.hotas.axes, {})
        self.assertNotIn("离线", self.hub.status["error"])

    def test_silence_with_phone_online_holds(self) -> None:
        self.hub.note_ws_up("192.168.1.8", lambda m: None)
        self.hub.apply_packet(
            __import__("bridge").PKT.pack(b"PD", 1, 255, 10000, 0, 0, 0, 0, 20000, 0, 0, 0),
            src="udp",
            ip="192.168.1.8",
        )
        self.hub.rate.last = time.monotonic() - 1.0
        self.hub.tick_failsafe()
        self.assertFalse(self.hub.last_parked)
        self.assertAlmostEqual(self.hub.hotas.axes["roll"], 10000 / 32767, places=2)

    def test_a7_heli_clears_rt_holds_throttle(self) -> None:
        self.hub.cockpit_mode = "heli"
        self.hub.apply_packet(
            __import__("bridge").PKT.pack(b"PD", 1, 255, 8000, 0, 0, 0, 0, 16000, 0, 30000, 0),
            src="ws",
            ip="127.0.0.1",
        )
        self.assertGreater(self.hub.last_axes["rt"], 0.8)
        self.hub.phones = 0
        self.hub.rate.last = time.monotonic() - 1.0
        self.hub.tick_failsafe()
        self.assertTrue(self.hub.last_parked)
        self.assertEqual(self.hub.hotas.axes["roll"], 0)
        self.assertAlmostEqual(self.hub.hotas.axes["throttle"], 16000 / 32767, places=2)
        self.assertEqual(self.hub.hotas.axes["rt"], 0.0)
        self.assertIn("离线", self.hub.status["error"])

    def test_a7b_drive_holds_rt(self) -> None:
        self.hub.cockpit_mode = "drive"
        self.hub.apply_packet(
            __import__("bridge").PKT.pack(b"PD", 1, 255, 4000, 0, 0, 0, 0, 20000, 0, 32767, 0),
            src="ws",
            ip="127.0.0.1",
        )
        self.hub.phones = 0
        self.hub.rate.last = time.monotonic() - 1.0
        self.hub.tick_failsafe()
        self.assertEqual(self.hub.hotas.axes["roll"], 0)
        self.assertAlmostEqual(self.hub.hotas.axes["rt"], 1.0, places=2)
        self.assertAlmostEqual(self.hub.hotas.axes["throttle"], 20000 / 32767, places=2)

    def test_infantry_phones_zero_releases_buttons_only(self) -> None:
        self.hub.cockpit_mode = "infantry"
        self.hub.apply_packet(
            __import__("bridge").PKT.pack(b"PD", 1, 255, 0, 0, 0, 0, 0, 0, 0, 0, 4),
            src="ws",
            ip="127.0.0.1",
        )
        self.hub.phones = 0
        self.hub.rate.last = time.monotonic() - 1.0
        self.hub.hotas.axes = {"throttle": 0, "rt": 0}
        self.hub.tick_failsafe()
        self.assertTrue(self.hub.last_parked)
        self.assertIn(("release_all", False), self.hub.hotas.buttons)
        self.assertNotIn("离线", self.hub.status["error"])

    def test_accepted_packet_clears_failsafe(self) -> None:
        self.hub.cockpit_mode = "heli"
        self.hub.apply_packet(
            __import__("bridge").PKT.pack(b"PD", 1, 255, 0, 0, 0, 0, 0, 10000, 0, 0, 0),
            src="ws",
            ip="127.0.0.1",
        )
        self.hub.phones = 0
        self.hub.rate.last = time.monotonic() - 1.0
        self.hub.tick_failsafe()
        self.assertIn("离线", self.hub.status["error"])
        self.hub.apply_packet(
            __import__("bridge").PKT.pack(b"PD", 1, 255, 0, 0, 0, 0, 0, 10000, 0, 0, 0),
            src="ws",
            ip="127.0.0.1",
        )
        self.assertFalse(self.hub.last_parked)
        self.assertEqual(self.hub.status["error"], "")


if __name__ == "__main__":
    unittest.main()
