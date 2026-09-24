"""打包清单自检。

背景：v4 给 bridge.py 加了 `import palmdeck_layouts` 和 `from updater import ...`，
但 `pack_windows.py` 的 `FILES` 是手写清单，没跟着加。结果打出来的
PalmDeck-Windows.zip 在 Windows 上一启动就 ImportError —— 而且这个错误
只有真正解压运行的人才会遇到，本地跟 CI 都发现不了。

所以这里把「清单必须覆盖入口的所有同目录 import」变成一条测试。
同类的还有 `packaging/PalmDeck.spec` 的 hiddenimports。
"""

import ast
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

import pack_windows  # noqa: E402  （同目录脚本，ROOT 在 sys.path 里）


class TestPackWindows(unittest.TestCase):
    def test_local_modules_are_discovered(self):
        mods = pack_windows.local_modules()
        # 这几个是 v4 真实踩过的坑，必须被发现
        self.assertIn("palmdeck_layouts", mods)
        self.assertIn("updater", mods)
        self.assertIn("palmdeck_config", mods)

    def test_verify_passes(self):
        """verify() 不抛异常，即 FILES 覆盖了所有同目录 import 且文件都存在。"""
        pack_windows.verify()

    def test_spec_hiddenimports_cover_local_modules(self):
        spec = os.path.join(ROOT, "packaging", "PalmDeck.spec")
        with open(spec, encoding="utf-8") as fh:
            text = fh.read()
        block = re.search(r"hiddenimports\s*=\s*\[(.*?)\]", text, re.S)
        self.assertIsNotNone(block, "PalmDeck.spec 里找不到 hiddenimports")
        listed = set(re.findall(r'"([^"]+)"', block.group(1)))
        for mod in sorted(pack_windows.local_modules()):
            self.assertIn(
                mod, listed,
                f"packaging/PalmDeck.spec 的 hiddenimports 缺少 {mod}；"
                "PyInstaller 打出的 exe 会缺模块。",
            )

    def test_entrypoints_exist(self):
        for entry in pack_windows.ENTRYPOINTS:
            self.assertTrue(
                os.path.isfile(os.path.join(ROOT, entry)), f"缺少入口 {entry}"
            )

    def test_files_list_is_covered_by_dirs(self):
        """FILES 里的路径不能落在 DIRS 里（否则会重复打包）。"""
        dirs = [d + os.sep for d in pack_windows.DIRS]
        for rel in pack_windows.FILES:
            for d in dirs:
                self.assertFalse(rel.startswith(d), f"{rel} 与 DIRS 里的 {d} 重复")


class TestRepoCleanliness(unittest.TestCase):
    """仓库里不应该留下一次性产物 / 旧版本产物。"""

    def test_no_stale_one_off_screenshot(self):
        self.assertFalse(
            os.path.exists(os.path.join(ROOT, "1.png")),
            "根目录的 1.png 是一次性截图，应删除（.gitignore 里的条目也该一起删）",
        )

    def test_gitignore_has_no_dead_rules(self):
        path = os.path.join(ROOT, ".gitignore")
        with open(path, encoding="utf-8") as fh:
            rules = {ln.strip() for ln in fh}
        self.assertNotIn("1.png", rules, ".gitignore 里还留着已删除产物的规则")

    def test_git_tracks_no_ignored_artifacts(self):
        """tracked 文件不应命中 .gitignore（历史遗留的误提交）。"""
        import subprocess
        out = subprocess.run(
            ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True
        ).stdout.split()
        bad = [
            f for f in out
            if f.endswith((".pyc", ".zip", ".xcuserstate")) or "__pycache__" in f
        ]
        self.assertEqual(bad, [], f"仓库里跟踪了构建产物：{bad}")


if __name__ == "__main__":
    unittest.main()
