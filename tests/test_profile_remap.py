import unittest

from hotas import remap_vjoy


class ProfileRemapTests(unittest.TestCase):
    def test_a13_hotas_z_is_throttle(self) -> None:
        m = remap_vjoy("hotas", roll=0.1, pitch=0.2, throttle=0.75, yaw=-0.4, left_t=0.5, look_x=0, look_y=0)
        self.assertAlmostEqual(m["z"], 0.75 * 2 - 1)
        self.assertAlmostEqual(m["rz"], -0.4)
        self.assertAlmostEqual(m["sl0"], 0.0)

    def test_a14_fbw_z_is_yaw_rz_centered(self) -> None:
        m = remap_vjoy("fbw", roll=0.1, pitch=0.2, throttle=0.75, yaw=-0.4, left_t=1.0, look_x=0.3, look_y=0)
        self.assertAlmostEqual(m["z"], -0.4)
        self.assertEqual(m["rz"], 0.0)
        self.assertAlmostEqual(m["sl0"], 0.75 * 2 - 1)
        self.assertAlmostEqual(m["rx"], 0.3)

    def test_unknown_profile_is_hotas(self) -> None:
        a = remap_vjoy("nope", 0, 0, 1, 0.5, 0, 0, 0)
        b = remap_vjoy("hotas", 0, 0, 1, 0.5, 0, 0, 0)
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
