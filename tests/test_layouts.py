"""布局存储：schema/校验/原子写回。"""

import tempfile
import unittest
from pathlib import Path

import palmdeck_layouts as pl


def widget(**kw):
    base = {"id": "a1", "kind": "slider", "binding": "throttle",
            "rect": {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.1}, "label": "油门"}
    base.update(kw)
    return base


class LayoutStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self._orig = pl.layout_path
        pl.layout_path = lambda: Path(self._tmp.name) / "layouts.json"  # type: ignore[assignment]

    def tearDown(self) -> None:
        pl.layout_path = self._orig  # type: ignore[assignment]
        self._tmp.cleanup()

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


if __name__ == "__main__":
    unittest.main()
