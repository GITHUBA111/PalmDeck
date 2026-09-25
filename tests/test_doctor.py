"""Windows 端「产品化」自检（palmdeck_doctor）的守卫测试。

背景：以前环境问题散在四处 —— 驱动检测只在 setup_windows.bat 里，
端口常量在 open_firewall.bat 与 palmdeck_config.py 各写一份，
控制台只报一句 `backend=none`，用户根本不知道缺什么、怎么修。

现在唯一真相源是 `palmdeck_doctor.py`：托盘 / 控制台 / 安装脚本 / 命令行共用。
这些测试锁住「单一真相源」本身，免得以后又长出第二份。
"""

import ast
import json
import os
import re
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

import palmdeck_config as pc  # noqa: E402
import palmdeck_doctor as doctor  # noqa: E402


def _src(rel: str) -> str:
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


class TestDoctorCore(unittest.TestCase):
    def test_report_structure(self):
        rep = doctor.report()
        for key in ("app", "version", "platform", "ports", "ok", "summary", "checks"):
            self.assertIn(key, rep, f"报告缺字段 {key}")
        self.assertEqual(rep["app"], "PalmDeck")
        self.assertTrue(rep["checks"], "检查清单是空的")

    def test_every_check_has_id_level_title(self):
        ids = []
        for c in doctor.report()["checks"]:
            for key in ("id", "level", "title"):
                self.assertTrue(c.get(key), f"检查项缺 {key}：{c}")
            self.assertIn(c["level"], doctor.LEVELS, f"未知等级 {c['level']}")
            ids.append(c["id"])
        self.assertEqual(len(ids), len(set(ids)), f"检查项 id 重复：{ids}")

    def test_runs_on_non_windows_without_error(self):
        """开发机（macOS）上必须能跑出完整报告 —— Windows 专属项报 info 而不是炸。"""
        if os.name == "nt":
            self.skipTest("Windows 上不适用")
        rep = doctor.report()
        kinds = {c["id"]: c["level"] for c in rep["checks"]}
        for cid in ("driver.vjoy", "driver.vigembus", "firewall"):
            self.assertEqual(kinds[cid], "info", f"{cid} 在非 Windows 上应当是 info")
        self.assertNotIn("error", [
            c["id"] for c in rep["checks"] if c["level"] == "error"
        ], "macOS 上不该出现故障项（除了没有虚拟设备的 backend）")

    def test_backend_error_has_guidance(self):
        rep = doctor.report({"backend": "none", "device": ""})
        item = next(c for c in rep["checks"] if c["id"] == "backend")
        self.assertEqual(item["level"], "error")
        self.assertIn("vJoy", item["detail"])
        self.assertIn("ViGEmBus", item["detail"])

    def test_listener_failure_is_reported(self):
        rep = doctor.report({
            "backend": "vjoy", "device": "vJoy Device",
            "ip": "192.168.1.5",
            "listeners": {"ws": {"ok": False, "addr": "0.0.0.0:8765", "error": "[Errno 48] address in use"}},
        })
        item = next(c for c in rep["checks"] if c["id"] == "listener.ws")
        self.assertEqual(item["level"], "error")
        self.assertIn("address in use", item["detail"])

    def test_cli_json_is_parseable(self):
        out = subprocess.run(
            [sys.executable, os.path.join(ROOT, "palmdeck_doctor.py"), "--json"],
            capture_output=True, text=True, cwd=ROOT, timeout=120,
        )
        data = json.loads(out.stdout)
        self.assertEqual(data["app"], "PalmDeck")
        self.assertTrue(data["checks"])

    def test_does_not_import_bridge(self):
        """doctor 必须能被 setup_windows.bat 单独跑 —— import bridge 会拉起设备依赖，还会成环。"""
        tree = ast.parse(_src("palmdeck_doctor.py"))
        mods = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                mods |= {a.name.split(".")[0] for a in node.names}
            elif isinstance(node, ast.ImportFrom) and node.module:
                mods.add(node.module.split(".")[0])
        self.assertNotIn("bridge", mods, "palmdeck_doctor 不能 import bridge")
        self.assertNotIn("hotas", mods, "自检不该拉起虚拟手柄依赖")


class TestListenerTracking(unittest.TestCase):
    def test_bind_failure_is_recorded_not_raised(self):
        """端口被占是真故障（用户只看到「手机连不上」），bind 失败必须被记下来而不是静默死线程。"""
        import bridge
        # 192.0.2.1 是 TEST-NET-1，本机不会拥有，bind 必然失败
        try:
            bridge.serve_udp("192.0.2.1", 7773)
        except OSError:  # pragma: no cover - 平台差异
            self.skipTest("这个平台上 bind 非本地地址不报错")
        try:
            st = bridge.HUB.listener_state.get("udp")
            self.assertIsNotNone(st, "bind 失败没被记录（自检页会说不清原因）")
            self.assertFalse(st["ok"])
            self.assertTrue(st["error"])
            rep = doctor.report(bridge.doctor_extra())
            item = next(c for c in rep["checks"] if c["id"] == "listener.udp")
            self.assertEqual(item["level"], "error")
        finally:
            bridge.HUB.listener_state.pop("udp", None)


class TestSingleSourceOfPorts(unittest.TestCase):
    def test_beacon_port_lives_in_config(self):
        self.assertTrue(hasattr(pc, "BEACON_PORT"))
        self.assertNotIn(
            "BEACON_PORT = 7774", _src("bridge.py"),
            "bridge.py 不该再自己定义 BEACON_PORT（改端口会漏掉广播）",
        )
        self.assertIn("from palmdeck_config import", _src("bridge.py"))

    def test_firewall_ports_match_config(self):
        cfg = pc.load_config()
        got = {(p, n) for p, n, _ in doctor.firewall_ports()}
        self.assertEqual(got, {
            ("TCP", int(cfg["http"])), ("TCP", int(cfg["ws"])),
            ("UDP", int(cfg["udp"])), ("UDP", int(pc.BEACON_PORT)),
        })

    def test_rule_name_format(self):
        self.assertEqual(doctor.rule_name("UDP", 7773), "PalmDeck UDP 7773")

    def test_no_ports_hardcoded_in_bats(self):
        for name in sorted(os.listdir(ROOT)):
            if not name.endswith(".bat"):
                continue
            text = _src(name)
            self.assertNotRegex(
                text, r"New-NetFirewallRule|netsh advfirewall",
                f"{name} 不该自己写防火墙规则（唯一真相源是 palmdeck_doctor.py）",
            )


class TestBridgeWiring(unittest.TestCase):
    def test_doctor_routes(self):
        text = _src("bridge.py")
        self.assertIn('"/api/doctor"', text)
        self.assertIn('"/api/doctor/fix"', text)
        self.assertIn("doctor.report(", text)
        self.assertIn("doctor.fix(", text)

    def test_runtime_state_is_fed_in(self):
        text = _src("bridge.py")
        self.assertIn("def doctor_extra()", text)
        self.assertIn('"listeners"', text)

    def test_listener_failures_are_recorded(self):
        text = _src("bridge.py")
        self.assertIn("def note_listener(", text)
        for name in ("http", "ws", "udp"):
            self.assertIn(f'note_listener("{name}"', text, f"{name} 监听失败没被记录")

    def test_http_404_untouched(self):
        """别把新路由插到静态文件分支后面，否则 /api/doctor 会 404。"""
        text = _src("bridge.py")
        self.assertLess(text.index('"/api/doctor"'), text.index('"/api/layouts"'))


class TestConsoleDoctorTab(unittest.TestCase):
    def setUp(self):
        self.html = _src(os.path.join("web", "host.html"))

    def test_has_tab(self):
        self.assertIn('data-tab="doctor"', self.html)
        self.assertIn('id="tab-doctor"', self.html)

    def test_calls_api(self):
        self.assertIn("/api/doctor", self.html)
        self.assertIn("loadDoctor", self.html)

    def test_fix_button_wired(self):
        self.assertIn("/api/doctor/fix", self.html)
        self.assertIn("fixDoctor", self.html)
        self.assertIn('fixDoctor("firewall"', self.html)

    def test_hash_deeplink(self):
        self.assertIn('location.hash', self.html)

    def test_overview_points_to_doctor(self):
        self.assertIn('id="docGo"', self.html)
        self.assertIn('id="docHint"', self.html)


class TestTrayAndPackaging(unittest.TestCase):
    def test_tray_shows_version_and_doctor(self):
        text = _src("start.py")
        self.assertIn('f"PalmDeck v{APP_VERSION}', text)
        self.assertIn('"自检…"', text)
        self.assertIn("def notify_doctor(", text)
        self.assertIn("http_url(\"#doctor\")", text)

    def test_doctor_is_packaged(self):
        import pack_windows
        self.assertIn("palmdeck_doctor.py", pack_windows.FILES)
        pack_windows.verify()
        self.assertIn("palmdeck_doctor", _src(os.path.join("packaging", "PalmDeck.spec")))

    def test_open_firewall_bat_is_gone(self):
        """放行逻辑搬进 Python 了，那个孤儿 bat 必须删掉（它也没进过 zip）。"""
        self.assertFalse(os.path.exists(os.path.join(ROOT, "open_firewall.bat")))
        import pack_windows
        self.assertNotIn("open_firewall.bat", pack_windows.FILES)

    def test_setup_bat_uses_doctor(self):
        text = _src("setup_windows.bat")
        self.assertIn("palmdeck_doctor.py", text)
        self.assertNotIn("sc query", text, "驱动检测应该在 doctor 里，不在这里")


if __name__ == "__main__":
    unittest.main()
