"""版本号一致性守卫。

`APP_VERSION`（发版号，托盘 / 网页 / 自更新用）与 `PROTOCOL_VERSION`
（hello 帧里的协议号）是两件事，但**主版本号必须一致**——
否则会出现“程序 v4.0 自报协议 3.2”或反过来的自相矛盾。

这套测试的存在理由：`APP_VERSION` 是自更新比较的基准（`updater._ver_tuple`），
发版时忘了改它，`check_update()` 就会拿新 tag 和旧版本号比，
老用户收不到提示；同时界面会一直显示错的版本号。
"""

import json
import os
import unittest
import urllib.error

import bridge
import updater
from updater import APP_VERSION, _ver_tuple


class _FakeResp:
    def __init__(self, payload: bytes):
        self._payload = payload

    def read(self):
        return self._payload

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class _StubURL:
    """把 updater 的 urlopen 换成「给什么就是什么」，用完还原。

    仓库里不用 unittest.mock（测试零第三方依赖的老规矩），所以手写一个只做
    一件事的上下文管理器。
    """

    def __init__(self, *, tag=None, exc=None):
        self.tag, self.exc = tag, exc

    def __enter__(self):
        self._orig = updater.urllib.request.urlopen

        def fake(req, timeout=None):
            if self.exc is not None:
                raise self.exc
            return _FakeResp(json.dumps({"tag_name": self.tag}).encode())

        updater.urllib.request.urlopen = fake
        return self

    def __exit__(self, *exc):
        updater.urllib.request.urlopen = self._orig
        return False


class TestVersionConsistency(unittest.TestCase):
    def test_major_matches(self):
        app = _ver_tuple(APP_VERSION)
        proto = _ver_tuple(bridge.PROTOCOL_VERSION)
        self.assertGreaterEqual(len(app), 3, f"APP_VERSION 应为 x.y.z：{APP_VERSION}")
        self.assertGreaterEqual(len(proto), 2, f"PROTOCOL_VERSION 应为 x.y：{bridge.PROTOCOL_VERSION}")
        self.assertEqual(
            app[0], proto[0],
            f"APP_VERSION {APP_VERSION} 与 PROTOCOL_VERSION {bridge.PROTOCOL_VERSION} 主版本号不一致",
        )

    def test_hello_reports_protocol_version(self):
        """hello 帧里的 version 必须就是 PROTOCOL_VERSION，不能是硬编码字面量。"""
        self.assertNotEqual(bridge.PROTOCOL_VERSION, "")
        src = (bridge.__file__, )
        with open(src[0], encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn('"version": PROTOCOL_VERSION', text,
                      "hello 帧应引用 PROTOCOL_VERSION，而不是写死字符串")

    def test_app_version_parses_and_is_not_stale(self):
        """APP_VERSION 必须能解析，且不得低于 v4（v4 重设计后的下限）。"""
        v = _ver_tuple(APP_VERSION)
        self.assertNotEqual(v, (0, 0, 0), f"APP_VERSION 解析失败：{APP_VERSION}")
        self.assertGreaterEqual(v[0], 4, f"v4 重设计后主版本号应 >= 4，当前 {APP_VERSION}")

    def test_info_payload_reports_app_version(self):
        self.assertEqual(bridge._info_payload()["version"], APP_VERSION)




def _bump() -> str:
    """比当前 APP_VERSION 更高的一个版本号（不写死，跟着 APP_VERSION 走）。"""
    return f"v{_ver_tuple(APP_VERSION)[0] + 1}.0.0"


class TestUpdateCheckStatus(unittest.TestCase):
    """「检查更新」必须说得出结论的原因。

    以前只有空串表示「没有新版」，于是「已是最新」「连不上网」「仓库根本没发过版」
    在界面上长得一模一样 —— 玩家点了「检查更新」只能看到一句可能是假话的
    「已是最新版本」。这里的核心断言就是：**别把查不到说成最新**。
    """

    def test_newer_release_is_reported(self):
        with _StubURL(tag=_bump()):
            st = updater.check_update_status()
        self.assertTrue(st["ok"])
        self.assertEqual(st["reason"], updater.UPD_UPDATE)
        self.assertEqual(st["latest"], _bump().lstrip("vV"))
        self.assertEqual(st["current"], APP_VERSION)
        self.assertIn(_bump().lstrip("vV"), st["message"])

    def test_same_version_is_current(self):
        with _StubURL(tag="v" + APP_VERSION):
            st = updater.check_update_status()
        self.assertTrue(st["ok"])
        self.assertEqual(st["reason"], updater.UPD_CURRENT)
        self.assertEqual(st["latest"], "")
        self.assertIn("已是最新", st["message"])

    def test_older_release_is_not_an_update(self):
        """tag 比 APP_VERSION 低（现在仓库就是这个状态：tag v0.3.x / APP 4.0.0）。

        这是**合法**结论（本地比发布的高），但绝不能因此变成「发现新版本」。
        """
        with _StubURL(tag="v0.0.1"):
            st = updater.check_update_status()
        self.assertEqual(st["reason"], updater.UPD_CURRENT)
        self.assertEqual(st["latest"], "")

    def test_never_says_current_when_the_check_failed(self):
        cases = (
            (urllib.error.HTTPError("u", 404, "nf", None, None), updater.UPD_NO_RELEASE),
            (urllib.error.HTTPError("u", 403, "rate limited", None, None), updater.UPD_OFFLINE),
            (urllib.error.URLError("dns"), updater.UPD_OFFLINE),
            (TimeoutError("timeout"), updater.UPD_OFFLINE),
        )
        for exc, reason in cases:
            with self.subTest(exc=type(exc).__name__):
                with _StubURL(exc=exc):
                    st = updater.check_update_status()
                self.assertFalse(st["ok"], f"{exc!r} 不该被当成检查成功")
                self.assertEqual(st["reason"], reason)
                self.assertEqual(st["latest"], "")
                self.assertNotIn("已是最新", st["message"],
                                 "检查失败时显示「已是最新」＝ 骗人；用户永远不会去查网络")
                self.assertTrue(st["message"], "总得有句话给用户看")

    def test_unparsable_tag_is_not_current(self):
        with _StubURL(tag="nightly"):
            st = updater.check_update_status()
        self.assertFalse(st["ok"])
        self.assertNotIn("已是最新", st["message"])

    def test_disabled_by_env(self):
        os.environ["PALMDECK_NO_UPDATE"] = "1"
        try:
            st = updater.check_update_status()
            self.assertEqual(st["reason"], updater.UPD_DISABLED)
            self.assertFalse(st["ok"])
            self.assertEqual(updater.check_update(), "")
        finally:
            os.environ.pop("PALMDECK_NO_UPDATE", None)

    def test_check_update_keeps_the_old_contract(self):
        """`check_update() -> str` 还有调用方（外部脚本 / 老行为），别改签名。"""
        with _StubURL(tag=_bump()):
            self.assertEqual(updater.check_update(), _bump().lstrip("vV"))
        with _StubURL(exc=urllib.error.URLError("x")):
            self.assertEqual(updater.check_update(), "")

    def test_status_is_json_serialisable(self):
        with _StubURL(tag="v0.0.1"):
            st = updater.check_update_status()
        json.dumps(st, ensure_ascii=False)   # 控制台要直接塞进 HTTP JSON


class TestUpdateUiTellsWhy(unittest.TestCase):
    """接线的三处界面/接口都不许再把「没查到」说成「已是最新」。"""

    def setUp(self):
        self.root = os.path.dirname(os.path.abspath(bridge.__file__))

    def _read(self, rel):
        with open(os.path.join(self.root, rel), encoding="utf-8") as fh:
            return fh.read()

    def test_console_shows_the_reason(self):
        html = self._read(os.path.join("web", "host.html"))
        self.assertIn("r.message", html, "控制台要显示服务端给的结论（含失败原因）")
        self.assertIn("!info.can_self_update || !LATEST", html,
                      "没有新版时不该能点「下载并重启」——那是拿 latest 资产覆盖，可能降级")

    def test_tray_logs_the_reason_too(self):
        src = self._read("start.py")
        self.assertIn('log("更新检查：" + st["message"])', src,
                      "Windows 通知气泡可能被系统静默，所以结果必须同时进日志")

    def test_apply_endpoint_returns_the_real_reason(self):
        src = self._read("bridge.py")
        self.assertIn('"error": st["message"]', src,
                      "/api/update/apply 失败时要把真实原因给出去")

    def test_server_side_api_exposes_reason(self):
        src = self._read("bridge.py")
        self.assertIn('"reason": st["reason"]', src)
        self.assertIn('"ok": st["ok"]', src)


if __name__ == "__main__":
    unittest.main()
