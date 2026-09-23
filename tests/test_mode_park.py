import unittest

from bridge import Hub, PKT
from tests.fakes import FakeHotas


def pd(throttle=0.0, rt=0.0, buttons=0) -> bytes:
    s = 32767
    return PKT.pack(b"PD", 1, 255, 0, 0, 0, 0, 0, int(throttle * s), 0, int(rt * s), buttons)


class ModeParkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.hub = Hub(hotas=FakeHotas())
        self.hub.udp_allowlist = False

    def test_heli_parks_xbox_once(self) -> None:
        self.hub.set_cockpit_mode("heli", ip="192.168.1.8")
        parks = [c for c in self.hub.hotas.calls if c[0] == "park"]
        self.assertIn(("park", "vgamepad"), parks)
        self.assertEqual(self.hub.live_targets, {"vjoy"})
        self.hub.hotas.calls.clear()
        self.hub.apply_packet(pd(throttle=0.4), src="ws", ip="192.168.1.8")
        axes = [c for c in self.hub.hotas.calls if c[0] == "axes"]
        self.assertEqual(axes[-1][3], {"vjoy"})
        self.assertEqual(axes[-1][4], "heli")

    def test_drive_parks_vjoy_once(self) -> None:
        self.hub.set_cockpit_mode("drive", ip="192.168.1.8")
        self.assertIn(("park", "vjoy"), self.hub.hotas.calls)
        self.assertEqual(self.hub.live_targets, {"vgamepad"})

    def test_infantry_skips_identical_heartbeat(self) -> None:
        self.hub.set_cockpit_mode("infantry", ip="192.168.1.8")
        self.hub.hotas.calls.clear()
        self.hub.apply_packet(pd(buttons=0), src="ws", ip="192.168.1.8")
        first = len(self.hub.hotas.calls)
        self.hub.apply_packet(pd(buttons=0), src="ws", ip="192.168.1.8")
        self.assertEqual(len(self.hub.hotas.calls), first)

    def test_a5_status_after_mode(self) -> None:
        seen = []
        self.hub.listeners.append(lambda m: seen.append(m))
        self.hub.set_cockpit_mode("drive", ip="10.0.0.2")
        statuses = [m for m in seen if m.get("type") == "status"]
        self.assertTrue(statuses)
        self.assertEqual(statuses[-1]["cockpit_mode"], "drive")

    def test_connect_status_unknown(self) -> None:
        st = self.hub.snapshot_status()
        self.assertIn("cockpit_mode", st)
        self.assertEqual(st["cockpit_mode"], "unknown")


if __name__ == "__main__":
    unittest.main()
