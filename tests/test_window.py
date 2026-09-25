"""守卫 O3-full 真窗口（`palmdeck_window.py`）—— 见 docs/PalmDeck-v4-native-window.md。

真窗口的**行为**只能在 Windows 上真跑（CI 冒烟 + G4 真机），所以这里用**手写的假
`webview` 模块**把「建窗参数 / 关闭=隐藏回托盘 / 唤出 / 退出 / 几何落盘」这些**接线**
钉死：参数写错、closing 的返回值写反、几何忘了存，在 macOS 上就会红。

假模块是注入进 `sys.modules["webview"]` 的 —— `palmdeck_window` 里 `import webview`
全在函数内部，所以本文件不需要真的装 pywebview。
"""

import json
import os
import sys
import tempfile
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import palmdeck_window as pw  # noqa: E402


# ---------------------------------------------------------------- 假 webview
class _Addable:
    """pywebview 的事件用 `+=` 订阅（`win.events.closing += fn`）。"""

    def __init__(self):
        self.handlers = []

    def __iadd__(self, fn):
        self.handlers.append(fn)
        return self


class FakeWindow:
    def __init__(self, **kw):
        self.kw = kw
        self.width = kw.get("width", 1000)
        self.height = kw.get("height", 720)
        self.x = kw.get("x", 0)
        self.y = kw.get("y", 0)
        self.events = types.SimpleNamespace(closing=_Addable())
        self.calls = []
        self.boom = set()  # 想让它抛异常的方法名

    def _do(self, name):
        self.calls.append(name)
        if name in self.boom:
            raise RuntimeError(name)

    def show(self):
        self._do("show")

    def restore(self):
        self._do("restore")

    def hide(self):
        self._do("hide")

    def destroy(self):
        self._do("destroy")

    def evaluate_js(self, js):
        self.calls.append(("js", js))


class FakeWebview:
    def __init__(self, fail_create=False, fail_start=False):
        self.fail_create = fail_create
        self.fail_start = fail_start
        self.created = []
        self.started = 0

    def create_window(self, **kw):
        if self.fail_create:
            raise RuntimeError("create_window")
        w = FakeWindow(**kw)
        self.created.append(w)
        return w

    def start(self, **kw):
        self.started += 1
        if self.fail_start:
            raise RuntimeError("start")


_MISSING = object()


class _WithFakeWebview(unittest.TestCase):
    """给每个用例一个临时几何文件 + 一个可控的 `sys.modules["webview"]`。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.geo = os.path.join(self._tmp.name, "window.json")
        self._saved = sys.modules.get("webview", _MISSING)

    def tearDown(self):
        if self._saved is _MISSING:
            sys.modules.pop("webview", None)
        else:
            sys.modules["webview"] = self._saved
        self._tmp.cleanup()

    def install(self, fake):
        sys.modules["webview"] = fake
        return fake

    def host(self, url="http://127.0.0.1:8080/", fake=None):
        self.install(fake if fake is not None else FakeWebview())
        return pw.WindowHost(url, geo_file=self.geo)


# ---------------------------------------------------------------- 几何
class GeometryTests(unittest.TestCase):
    def test_rejects_too_small(self):
        self.assertIsNone(pw._clean_geometry({"w": 100, "h": 100, "x": 0, "y": 0}))

    def test_rejects_missing_keys(self):
        self.assertIsNone(pw._clean_geometry({"w": 900, "h": 600}))
        self.assertIsNone(pw._clean_geometry(None))

    def test_rejects_absurd_position(self):
        self.assertIsNone(pw._clean_geometry({"w": 900, "h": 600, "x": 999999, "y": 0}))

    def test_accepts_negative_but_sane_position(self):
        self.assertEqual(
            pw._clean_geometry({"w": 900, "h": 600, "x": -1200, "y": 40}),
            {"w": 900, "h": 600, "x": -1200, "y": 40},
        )


class GeometryPersistenceTests(_WithFakeWebview):
    def test_roundtrip(self):
        win = types.SimpleNamespace(width=900, height=600, x=10, y=20)
        self.assertEqual(pw.save_geometry(win, self.geo),
                         {"w": 900, "h": 600, "x": 10, "y": 20})
        self.assertEqual(pw.load_geometry(self.geo),
                         {"w": 900, "h": 600, "x": 10, "y": 20})

    def test_save_returns_none_when_window_has_no_geometry(self):
        self.assertIsNone(pw.save_geometry(object(), self.geo))

    def test_load_missing_or_corrupt_is_none(self):
        self.assertIsNone(pw.load_geometry(self.geo))
        with open(self.geo, "w", encoding="utf-8") as f:
            f.write("{not json")
        self.assertIsNone(pw.load_geometry(self.geo))


# ---------------------------------------------------------------- 可用性探测
class AvailabilityTests(unittest.TestCase):
    def setUp(self):
        self._saved = (pw.platform_ok, pw.webview_importable, pw.webview2_installed)

    def tearDown(self):
        pw.platform_ok, pw.webview_importable, pw.webview2_installed = self._saved
        pw._IMPORT_ERROR = ""

    def _probe(self, platform, imp, runtime):
        pw.platform_ok = lambda: platform
        pw.webview_importable = lambda: imp
        pw.webview2_installed = lambda: runtime
        pw._IMPORT_ERROR = ""

    def test_non_windows(self):
        self._probe(False, True, True)
        self.assertEqual(pw.unavailable_reason(), "非 Windows 平台")
        self.assertFalse(pw.available())

    def test_missing_pywebview(self):
        self._probe(True, False, True)
        self.assertEqual(pw.unavailable_reason(), "没装 pywebview")

    def test_missing_pywebview_says_why(self):
        # 打包后「真窗口开不出来」得能一眼看到卡在哪一层（CI 注解 / 日志）
        self._probe(True, False, True)
        pw._IMPORT_ERROR = "ModuleNotFoundError: No module named 'clr'"
        self.assertEqual(
            pw.unavailable_reason(),
            "没装 pywebview（ModuleNotFoundError: No module named 'clr'）")

    def test_missing_webview2_runtime(self):
        self._probe(True, True, False)
        self.assertEqual(pw.unavailable_reason(), "缺 WebView2 Runtime")

    def test_available_when_everything_is_there(self):
        self._probe(True, True, True)
        self.assertEqual(pw.unavailable_reason(), "")
        self.assertTrue(pw.available())


# ---------------------------------------------------------------- 窗口手柄
class WindowHostTests(_WithFakeWebview):
    def test_open_creates_window_with_saved_geometry(self):
        with open(self.geo, "w", encoding="utf-8") as f:
            json.dump({"w": 900, "h": 600, "x": 10, "y": 20}, f)
        fake = self.install(FakeWebview())
        self.assertTrue(self.host(fake=fake).open())
        kw = fake.created[0].kw
        self.assertEqual(kw["title"], pw.TITLE)
        self.assertEqual((kw["width"], kw["height"]), (900, 600))
        self.assertEqual((kw["x"], kw["y"]), (10, 20))
        self.assertEqual(kw["min_size"], (pw.MIN_W, pw.MIN_H))

    def test_open_uses_default_size_without_geometry(self):
        fake = self.install(FakeWebview())
        self.assertTrue(self.host(fake=fake).open())
        kw = fake.created[0].kw
        self.assertEqual((kw["width"], kw["height"]), (pw.DEFAULT_W, pw.DEFAULT_H))
        self.assertNotIn("x", kw)

    def test_open_false_when_import_fails(self):
        sys.modules["webview"] = None  # 让 `import webview` 抛 ImportError
        self.assertFalse(pw.WindowHost("http://x/", geo_file=self.geo).open())

    def test_open_false_when_create_raises(self):
        self.assertFalse(self.host(fake=FakeWebview(fail_create=True)).open())

    def test_closing_hides_and_cancels(self):
        host = self.host()
        host.open()
        win = host._window
        self.assertFalse(host._on_closing())          # False = 取消关闭
        self.assertIn("hide", win.calls)              # 隐藏回托盘
        self.assertTrue(os.path.isfile(self.geo))     # 几何落盘

    def test_closing_when_quitting_is_allowed(self):
        host = self.host()
        host.open()
        host.quit()
        self.assertTrue(host._on_closing())

    def test_closing_when_hide_unsupported_allows_and_drops_window(self):
        host = self.host()
        host.open()
        host._window.boom = {"hide"}
        self.assertTrue(host._on_closing())           # 藏不了就别拦着
        self.assertFalse(host.alive)                  # 窗口放下，托盘继续

    def test_show_calls_show_and_jumps_to_hash(self):
        host = self.host()
        host.open()
        self.assertTrue(host.show("#doctor"))
        self.assertIn("show", host._window.calls)
        self.assertIn(("js", 'location.hash="#doctor"'), host._window.calls)

    def test_show_false_without_window(self):
        self.assertFalse(self.host().show())

    def test_show_false_when_underlying_raises(self):
        host = self.host()
        host.open()
        host._window.boom = {"show"}
        self.assertFalse(host.show())

    def test_quit_destroys_and_flags(self):
        host = self.host()
        host.open()
        host.quit()
        self.assertTrue(host.quitting)
        self.assertIn("destroy", host._window.calls)

    def test_start_swallows_exception(self):
        host = self.host(fake=FakeWebview(fail_start=True))
        host.open()
        host.start()  # 不抛
        self.assertFalse(host.alive)


# ---------------------------------------------------------------- start.py 接线
class StartWiringTests(unittest.TestCase):
    """真窗口的价值全在「接进 start.py」—— 光有模块没人调等于没做。"""

    def setUp(self):
        with open(os.path.join(ROOT, "start.py"), encoding="utf-8") as f:
            self.src = f.read()

    def test_main_asks_availability_and_falls_back(self):
        self.assertIn("palmdeck_window.unavailable_reason()", self.src)
        self.assertIn("run_desktop()", self.src)

    def test_desktop_puts_tray_in_a_thread(self):
        # GUI（pywebview）必须占主线程，所以托盘要跑在子线程
        self.assertIn("threading.Thread(target=run_tray", self.src)

    def test_open_console_tries_the_window_first(self):
        self.assertIn("host.show(frag)", self.src)

    def test_tray_quit_closes_the_window(self):
        self.assertIn("window_host.quit()", self.src)


# ---------------------------------------------------------------- 打包 / CI
SPEC = os.path.join(ROOT, "packaging", "PalmDeck.spec")
ISS = os.path.join(ROOT, "packaging", "PalmDeck.iss")
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "build-windows.yml")
START = os.path.join(ROOT, "start.py")


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class PackagingTests(unittest.TestCase):
    """真窗口要真发出去，才算数 —— 模块写了没人打包/没人验，等于没做。"""

    def test_spec_collects_pywebview(self):
        self.assertIn('"webview"', _read(SPEC),
                      "spec 没收 pywebview，打出来的 exe 没有真窗口")

    def test_ci_installs_and_verifies_pywebview(self):
        wf = _read(WORKFLOW)
        self.assertIn("pywebview", wf, "CI 打包环境没装 pywebview")
        self.assertIn("webview=ok", wf, "CI 没断言 exe 里真的带了 pywebview")

    def test_selftest_writes_a_file_not_stdout(self):
        # exe 是 console=False 的窗口程序，print 出不来 —— 自检必须写文件
        src = _read(START)
        self.assertIn("PALMDECK_SELFTEST", src)
        self.assertIn("def selftest(path", src)

    def test_installer_checks_the_same_webview2_guid(self):
        iss = _read(ISS)
        self.assertIn(pw._WEBVIEW2_CLIENT, iss,
                      ".iss 的 WebView2 检测 GUID 与 palmdeck_window 不一致")
        self.assertIn("WebView2Missing", iss)
        self.assertIn("FileExists", iss, "引导器是可选的：要用 #if FileExists 兜底")

    def test_ci_prepares_the_webview2_bootstrapper(self):
        self.assertIn("MicrosoftEdgeWebview2Setup.exe", _read(WORKFLOW))


class SelfTestTests(unittest.TestCase):
    """`PALMDECK_SELFTEST`：把「包里有没有 pywebview」变成一条可见的断言。"""

    def setUp(self):
        self._saved = (pw.webview_importable, pw.unavailable_reason)

    def tearDown(self):
        pw.webview_importable, pw.unavailable_reason = self._saved

    def test_reports_ok_and_exit_zero(self):
        import start
        pw.webview_importable = lambda: True
        pw.unavailable_reason = lambda: ""
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "selftest.txt")
            self.assertEqual(start.selftest(out), 0)
            self.assertIn("webview=ok", open(out, encoding="utf-8").read())

    def test_reports_missing_and_nonzero(self):
        import start
        pw.webview_importable = lambda: False
        pw.unavailable_reason = lambda: "没装 pywebview"
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "selftest.txt")
            self.assertEqual(start.selftest(out), 3)
            self.assertIn("webview=missing", open(out, encoding="utf-8").read())


if __name__ == "__main__":
    unittest.main()
