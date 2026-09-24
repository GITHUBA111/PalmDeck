"""配置存储：save_config 校验/强转/原子写回。"""

import tempfile
import unittest
from pathlib import Path

import palmdeck_config as pc


class ConfigStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self._orig = pc.config_path
        pc.config_path = lambda: Path(self._tmp.name) / "config.json"  # type: ignore[assignment]

    def tearDown(self) -> None:
        pc.config_path = self._orig  # type: ignore[assignment]
        self._tmp.cleanup()

    def test_defaults_when_missing(self) -> None:
        cfg = pc.load_config()
        self.assertEqual(cfg["http"], pc.DEFAULTS["http"])
        self.assertEqual(cfg["beacon"], pc.DEFAULTS["beacon"])

    def test_save_then_load_roundtrip(self) -> None:
        cfg = pc.save_config({"http": 9090, "host": "127.0.0.1", "udp_allowlist": False})
        self.assertEqual(cfg["http"], 9090)
        self.assertEqual(cfg["host"], "127.0.0.1")
        self.assertFalse(cfg["udp_allowlist"])
        again = pc.load_config()
        self.assertEqual(again["http"], 9090)
        self.assertFalse(again["udp_allowlist"])

    def test_unknown_key_ignored(self) -> None:
        cfg = pc.save_config({"nonsense": 123})
        self.assertNotIn("nonsense", cfg)

    def test_enum_falls_back_to_default(self) -> None:
        cfg = pc.save_config({"axis_profile": "banana"})
        self.assertEqual(cfg["axis_profile"], pc.DEFAULTS["axis_profile"])

    def test_bool_and_int_coercion(self) -> None:
        cfg = pc.save_config({"beacon": "false", "http": "8123"})
        self.assertIs(cfg["beacon"], False)
        self.assertEqual(cfg["http"], 8123)

    def test_clamps(self) -> None:
        cfg = pc.save_config({"http": 999999, "park_ms": 1, "allowlist_ttl_ms": 0})
        self.assertEqual(cfg["http"], 65535)
        self.assertEqual(cfg["park_ms"], 200)
        self.assertEqual(cfg["allowlist_ttl_ms"], 500)

    def test_partial_update_keeps_other_values(self) -> None:
        pc.save_config({"http": 9090})
        pc.save_config({"park_ms": 3000})
        cfg = pc.load_config()
        self.assertEqual(cfg["http"], 9090)
        self.assertEqual(cfg["park_ms"], 3000)


if __name__ == "__main__":
    unittest.main()
