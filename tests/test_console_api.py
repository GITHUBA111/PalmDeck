"""网页控制台 REST API（bridge.CockpitHandler）冒烟测试。"""

import json
import tempfile
import threading
import unittest
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

import palmdeck_config as pc
import palmdeck_layouts as pl


class ConsoleApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        from bridge import CockpitHandler

        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), CockpitHandler)
        cls.httpd.palm_http = 8080
        cls.httpd.palm_ws = 8765
        cls.port = cls.httpd.server_address[1]
        cls.base = f"http://127.0.0.1:{cls.port}"
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.httpd.shutdown()

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self._orig = pc.config_path
        self._orig_layout = pl.layout_path
        pc.config_path = lambda: Path(self._tmp.name) / "config.json"  # type: ignore[assignment]
        pl.layout_path = lambda: Path(self._tmp.name) / "layouts.json"  # type: ignore[assignment]

    def tearDown(self) -> None:
        pc.config_path = self._orig  # type: ignore[assignment]
        pl.layout_path = self._orig_layout  # type: ignore[assignment]
        self._tmp.cleanup()

    def _get(self, path: str) -> dict:
        with urllib.request.urlopen(self.base + path, timeout=5) as r:
            return json.loads(r.read().decode("utf-8"))

    def _post(self, path: str, body: dict) -> dict:
        req = urllib.request.Request(
            self.base + path,
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read().decode("utf-8"))

    def test_status_has_monitor_fields(self) -> None:
        st = self._get("/api/status")
        for key in ("device", "backend", "cockpit_mode", "hz", "transport",
                    "axes", "buttons", "hat", "dropped_udp", "http", "ws"):
            self.assertIn(key, st, key)

    def test_info(self) -> None:
        info = self._get("/api/info")
        self.assertEqual(info["app"], "PalmDeck")
        self.assertIn("version", info)
        self.assertIn("can_self_update", info)

    def test_config_roundtrip(self) -> None:
        got = self._get("/api/config")
        self.assertIn("config", got)
        self.assertIn("defaults", got)
        res = self._post("/api/config", {"http": 9411, "axis_profile": "fbw", "nonsense": 1})
        self.assertTrue(res["ok"])
        self.assertEqual(res["config"]["http"], 9411)
        self.assertEqual(res["config"]["axis_profile"], "fbw")
        self.assertNotIn("nonsense", res["config"])

    def test_mode_switch_and_alias(self) -> None:
        res = self._post("/api/mode", {"name": "gamepad"})
        self.assertTrue(res["ok"])
        self.assertEqual(res["status"]["cockpit_mode"], "gamepad")
        # 旧客户端发 infantry 也要落到 gamepad
        res = self._post("/api/mode", {"name": "infantry"})
        self.assertEqual(res["status"]["cockpit_mode"], "gamepad")
        res = self._post("/api/mode", {"name": "heli"})
        self.assertEqual(res["status"]["cockpit_mode"], "heli")
        # 非法值被拒
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self._post("/api/mode", {"name": "banana"})
        self.assertEqual(ctx.exception.code, 400)

    def test_logs(self) -> None:
        self.assertIsInstance(self._get("/api/logs")["lines"], list)

    def test_layouts_roundtrip(self) -> None:
        meta = self._get("/api/layouts")
        for key in ("schema", "modes", "kinds", "bindings", "layouts"):
            self.assertIn(key, meta)
        w = {"id": "a", "kind": "slider", "binding": "throttle",
             "rect": {"x": 0.1, "y": 0.1, "w": 0.2, "h": 0.1}, "label": "t"}
        res = self._post("/api/layouts", {"mode": "heli", "layout": [w]})
        self.assertTrue(res["ok"])
        self.assertEqual(len(self._get("/api/layouts?mode=heli")["layout"]), 1)
        # DELETE resets
        req = urllib.request.Request(self.base + "/api/layouts?mode=heli", method="DELETE")
        with urllib.request.urlopen(req, timeout=5) as r:
            self.assertTrue(json.loads(r.read().decode("utf-8"))["ok"])
        self.assertIsNone(self._get("/api/layouts?mode=heli")["layout"])

    def test_layouts_bad_mode(self) -> None:
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self._post("/api/layouts", {"mode": "banana", "layout": []})
        self.assertEqual(ctx.exception.code, 400)

    def test_config_export_import_roundtrip(self) -> None:
        # 先造出与默认不同的状态：配置 + 一个布局
        self._post("/api/config", {"http": 9311, "axis_profile": "fbw", "park_ms": 1500})
        w = {"id": "a", "kind": "slider", "binding": "throttle",
             "rect": {"x": 0.1, "y": 0.1, "w": 0.2, "h": 0.1}, "label": "t"}
        self._post("/api/layouts", {"mode": "heli", "layout": [w]})

        bundle = self._get("/api/config/export")
        self.assertEqual(bundle["product"], "PalmDeck")
        self.assertEqual(bundle["bundle"], 1)
        self.assertEqual(bundle["config"]["http"], 9311)
        self.assertIn("heli", bundle["layouts"])

        # 改乱：配置回默认、删掉布局
        self._post("/api/config", {"http": 8080, "axis_profile": "hotas", "park_ms": 2000})
        req = urllib.request.Request(self.base + "/api/layouts?mode=heli", method="DELETE")
        with urllib.request.urlopen(req, timeout=5) as r:
            r.read()
        self.assertIsNone(self._get("/api/layouts?mode=heli")["layout"])

        # 导入还原
        res = self._post("/api/config/import", bundle)
        self.assertTrue(res["ok"])
        self.assertEqual(res["config"]["http"], 9311)
        self.assertEqual(res["config"]["axis_profile"], "fbw")
        self.assertTrue(res["restart_required"])  # http 是重启项，且值变了
        self.assertEqual(len(self._get("/api/layouts?mode=heli")["layout"]), 1)

    def test_config_import_reports_restart(self) -> None:
        res = self._post("/api/config/import",
                         {"bundle": 1, "config": {"ws": 9777}})
        self.assertTrue(res["ok"])
        self.assertEqual(res["config"]["ws"], 9777)
        self.assertTrue(res["restart_required"])  # ws 是重启项且变了

    def test_config_import_rejects_bad_bundle(self) -> None:
        for bad in ({"bundle": 99}, {"bundle": 1}, {"bundle": 1, "config": []}, [1, 2]):
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                self._post("/api/config/import", bad)
            self.assertEqual(ctx.exception.code, 400)

    def test_update_check_shape(self) -> None:
        res = self._get("/api/update/check")
        self.assertIn("current", res)
        self.assertIn("can_self_update", res)


if __name__ == "__main__":
    unittest.main()
