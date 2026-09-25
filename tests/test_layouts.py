"""布局存储：schema/校验/原子写回。"""

import ast
import os
import re
import tempfile
import unittest
from pathlib import Path

import palmdeck_layouts as pl

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def widget(**kw):
    base = {"id": "a1", "kind": "slider", "binding": "throttle",
            "rect": {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.1}, "label": "油门"}
    base.update(kw)
    return base


class LayoutPathIsolated(unittest.TestCase):
    """把 `pl.layout_path` 指到临时目录 —— 本文件里**每个会写布局的测试类都必须继承它**。

    踩过：新加的测试类忘了继承 `LayoutStoreTests` 的 `setUp`，于是 `save_layout` 直接写进了
    用户真实的 `~/Library/Application Support/PalmDeck/layouts.json`
    （Windows：`%APPDATA%\PalmDeck\layouts.json`）。
    代价不是「测试变红」，而是**静默改写用户机器上的文件**：那份文件会覆盖 App 的内置布局，
    而 CI 上完全看不出来。`AllLayoutTestsAreIsolated` 守卫这条规矩。
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self._orig = pl.layout_path
        pl.layout_path = lambda: Path(self._tmp.name) / "layouts.json"  # type: ignore[assignment]
        # 双保险：确保真的指到了临时目录（指错就会写用户真实文件）
        self.assertTrue(str(pl.layout_path()).startswith(self._tmp.name),
                        "layout_path 没被隔离，会写用户真实布局文件")

    def tearDown(self) -> None:
        pl.layout_path = self._orig  # type: ignore[assignment]
        self._tmp.cleanup()


class LayoutStoreTests(LayoutPathIsolated):
    def setUp(self) -> None:
        super().setUp()

    def test_empty_by_default(self) -> None:
        self.assertEqual(pl.load_layouts(), {})
        self.assertIsNone(pl.get_layout("heli"))

    def test_save_and_get(self) -> None:
        saved = pl.save_layout("heli", [widget()])
        self.assertEqual(len(saved), 1)
        self.assertEqual(pl.get_layout("heli")[0]["binding"], "throttle")
        self.assertIsNone(pl.get_layout("drive"))

    def test_unknown_mode_rejected(self) -> None:
        self.assertIsNone(pl.save_layout("banana", [widget()]))
        self.assertFalse(pl.delete_layout("banana"))

    def test_bad_widgets_dropped(self) -> None:
        saved = pl.save_layout("drive", [
            widget(),
            {"kind": "nope", "binding": "roll"},
            {"kind": "wheel", "binding": "nope"},
            "garbage",
        ])
        self.assertEqual(len(saved), 1)

    def test_missing_id_and_bad_rect_normalized(self) -> None:
        saved = pl.save_layout("heli", [{"kind": "button", "binding": "fire",
                                         "rect": {"x": "0.5", "y": 0.1}}])
        w = saved[0]
        self.assertTrue(w["id"])
        self.assertEqual(w["rect"]["x"], 0.5)
        self.assertGreaterEqual(w["rect"]["w"], 0.02)

    def test_duplicate_ids_are_reassigned(self) -> None:
        saved = pl.save_layout("heli", [widget(), widget(key="roll")])
        self.assertEqual(len({w["id"] for w in saved}), 2)

    def test_widget_cap(self) -> None:
        saved = pl.save_layout("heli", [widget(id=f"w{i}") for i in range(100)])
        self.assertEqual(len(saved), pl.MAX_WIDGETS)

    def test_delete_resets_to_none(self) -> None:
        pl.save_layout("drive", [widget()])
        self.assertTrue(pl.delete_layout("drive"))
        self.assertIsNone(pl.get_layout("drive"))

    def test_replace_layouts_is_exact(self) -> None:
        pl.save_layout("heli", [widget()])
        pl.save_layout("drive", [widget(key="roll")])
        # 只给 gamepad：应整包替换，heli/drive 被清掉
        out = pl.replace_layouts({"gamepad": [widget(key="vjoy1")]})
        self.assertEqual(set(out), {"gamepad"})
        self.assertIsNone(pl.get_layout("heli"))
        # 非法模式/非法组件被丢弃；非 dict 入参清空
        self.assertEqual(pl.replace_layouts({"banana": [widget()]}), {})
        pl.save_layout("heli", [widget()])
        self.assertEqual(pl.replace_layouts("oops"), {})

    def test_save_layouts_bulk(self) -> None:
        saved = pl.save_layouts({"heli": [widget()], "gamepad": [], "bad": [widget()]})
        self.assertIn("heli", saved)
        self.assertIn("gamepad", saved)
        self.assertNotIn("bad", saved)

    def test_valid_bindings_include_vjoy_and_gear(self) -> None:
        for binding in ("vjoy16", "gearUp", "gearDown", "fire", "clutch"):
            saved = pl.save_layout("heli", [widget(binding=binding)])
            self.assertEqual(saved[0]["binding"], binding)


class KindAndBindingListsMatchTheApp(LayoutPathIsolated):
    """电脑侧的白名单必须与 iOS 的 `WidgetKind` / `WidgetBinding` **一一对应**。

    为什么这条比看上去重要：`_coerce_widget` 对不在清单里的组件返回 `None`，
    `_coerce_layout` 就把它跳过；而 `bridge.py` 的 `layouts_put` 又把**校验后**的列表
    回传给 App，App 的 `LayoutStore.applyServer` 是**整表替换**本地布局。
    所以白名单漏一项 = 「点一下『上传到电脑』就把这个组件删了」，而且一声不响。

    历史上真漏过：`panel`（飞机出厂布局里的仪表盘）、`rt`（右扳机/手刹轴）、
    `collective`（遥控器双杆的左杆）—— 前两个漏了很久没人发现。
    """

    SWIFT = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native", "Views", "Widgets.swift")

    @staticmethod
    def _swift_enum_cases(src: str, name: str) -> list:
        """取 `enum <name> { case a, b  // 注 …` 顶部声明的所有 case 名。"""
        body = src.split("enum %s:" % name, 1)[1].split("\n\n", 1)[0]
        out = []
        for line in body.splitlines():
            m = re.match(r"\s*case\s+(.+)$", line)
            if not m:
                continue
            for part in m.group(1).split("//")[0].split(","):
                part = part.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", part):
                    out.append(part)
        return out

    def setUp(self) -> None:
        super().setUp()  # 临时布局目录：下面几条会真写 `save_layout`
        with open(self.SWIFT, encoding="utf-8") as f:
            self.swift = f.read()

    def test_kinds_match_widget_kind(self) -> None:
        self.assertEqual(list(pl.KINDS), self._swift_enum_cases(self.swift, "WidgetKind"),
                         "KINDS 与 WidgetKind 必须一致（顺序也对齐，便于对账）")

    def test_bindings_match_widget_binding(self) -> None:
        self.assertEqual(list(pl.BINDINGS), self._swift_enum_cases(self.swift, "WidgetBinding"),
                         "BINDINGS 与 WidgetBinding 必须一致（顺序也对齐）")

    def test_meta_exposes_the_same_lists(self) -> None:
        m = pl.meta()
        self.assertEqual(m["kinds"], list(pl.KINDS))
        self.assertEqual(m["bindings"], list(pl.BINDINGS))

    def test_every_kind_and_binding_survives_a_save(self) -> None:
        """白名单里每一项都必须能存下去 —— 被吞就是「上传即删除」。"""
        for kind in pl.KINDS:
            saved = pl.save_layout("heli", [widget(kind=kind)])
            self.assertEqual(len(saved), 1, "kind=%s 被白名单吞了" % kind)
            self.assertEqual(saved[0]["kind"], kind)
        for binding in pl.BINDINGS:
            saved = pl.save_layout("heli", [widget(binding=binding)])
            self.assertEqual(len(saved), 1, "binding=%s 被白名单吞了" % binding)
            self.assertEqual(saved[0]["binding"], binding)

    def test_app_heli_default_layout_survives_a_round_trip(self) -> None:
        """飞机出厂布局（`LayoutStore.defaultHeli()`）一件都不能少。

        它就是当年被吞掉 `panel` 的那套：上传后回传 → App 整表替换 → 仪表盘消失。
        """
        heli = [
            widget(id="p1", kind="panel", binding="roll", label="仪表盘"),
            widget(id="p2", kind="slider", binding="throttle", label="总距"),
            widget(id="p3", kind="slider", binding="yaw", label="脚舵"),
            widget(id="p4", kind="stick", binding="roll", label="周期杆"),
            widget(id="p5", kind="pad", binding="look", label="视角"),
        ]
        saved = pl.save_layout("heli", heli)
        self.assertEqual([w["id"] for w in saved], [w["id"] for w in heli])
        self.assertEqual([w["kind"] for w in saved], [w["kind"] for w in heli])

    def test_rc_mode2_layout_survives_a_round_trip(self) -> None:
        """遥控器双杆布局（`LayoutStore.defaultRCMode2()`）也不能少件。"""
        rc = [
            widget(id="r1", kind="collective", binding="yaw", label="总距/尾桨"),
            widget(id="r2", kind="stick", binding="roll", label="副翼/升降"),
            widget(id="r3", kind="pad", binding="look", label="视角"),
        ]
        self.assertEqual(len(pl.save_layout("heli", rc)), 3)

    def test_still_rejects_truly_unknown_values(self) -> None:
        """放宽清单不是关掉校验：真未知的值照样丢。"""
        saved = pl.save_layout("drive", [
            widget(),
            widget(kind="joystick2"),
            widget(binding="elevator"),
        ])
        self.assertEqual(len(saved), 1)


class AllLayoutTestsAreIsolated(LayoutPathIsolated):
    """本文件里所有会写布局的测试类都必须继承 `LayoutPathIsolated`。

    为什么值一条测试：忘了继承的代价不是「测试失败」，而是**静默改写用户机器上的
    `layouts.json`**（进而覆盖 App 的内置布局），CI 上完全看不出来。
    """

    WRITERS = ("save_layout", "save_layouts", "replace_layouts", "delete_layout")

    def test_every_writer_class_inherits_isolation(self) -> None:
        tree = ast.parse(Path(__file__).read_text(encoding="utf-8"))
        offenders = []
        for node in tree.body:
            if not isinstance(node, ast.ClassDef):
                continue
            writes = any(
                isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                and n.func.attr in self.WRITERS
                for n in ast.walk(node)
            )
            if not writes:
                continue
            bases = {b.id for b in node.bases if isinstance(b, ast.Name)}
            if "LayoutPathIsolated" not in bases:
                offenders.append(node.name)
        self.assertEqual(offenders, [],
                         "这些测试类会写到用户真实布局文件，必须继承 LayoutPathIsolated")

    def test_isolation_actually_redirects_the_path(self) -> None:
        """守卫本身不能是空转：隔离后的路径必须真的不是用户真实那一份。"""
        here = pl.layout_path()
        pl.save_layout("heli", [widget()])
        self.assertTrue(here.is_file(), "save_layout 没落到隔离目录")
        self.assertNotIn(str(Path.home()), str(here), "隔离路径居然在 home 下，可疑")


if __name__ == "__main__":
    unittest.main()
