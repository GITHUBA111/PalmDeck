"""版本号一致性守卫。

`APP_VERSION`（发版号，托盘 / 网页 / 自更新用）与 `PROTOCOL_VERSION`
（hello 帧里的协议号）是两件事，但**主版本号必须一致**——
否则会出现“程序 v4.0 自报协议 3.2”或反过来的自相矛盾。

这套测试的存在理由：`APP_VERSION` 是自更新比较的基准（`updater._ver_tuple`），
发版时忘了改它，`check_update()` 就会拿新 tag 和旧版本号比，
老用户收不到提示；同时界面会一直显示错的版本号。
"""

import unittest

import bridge
from updater import APP_VERSION, _ver_tuple


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


if __name__ == "__main__":
    unittest.main()
