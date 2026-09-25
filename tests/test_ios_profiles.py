"""G2 纯逻辑测试：游戏预设（`GameProfile`）。

和 `tests/test_ios_axis.py` / `test_ios_state_keys.py` 同一路子：用 `swiftc`
编译 App 里的**真实源码**（不是副本）+ `tests/ios/GameProfileTests.swift` 跑。

`GameProfile.swift` 是纯类型（只 import Foundation）：内置预设定义、编解码、
存储增删改、以及**应用顺序**（先切模式、再写手感、最后换布局）都在这里钉死。
应用顺序写反了症状是「切了预设但手感没变」，真机上难归因，所以必须有断言。

被测源：`CockpitMode.swift` / `ShapingKeys.swift`（`GameProfileStore` 的
`ShapingStore` 注入依赖）/ `GameProfile.swift`。
"""

import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MODEL = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native", "Model")

SOURCES = [
    "CockpitMode.swift",
    "ShapingKeys.swift",
    "GameProfile.swift",
]

TEST_SRC = os.path.join(HERE, "ios", "GameProfileTests.swift")


class TestGameProfiles(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.swiftc = shutil.which("swiftc")
        if not cls.swiftc:
            raise unittest.SkipTest("没有 swiftc（需要 Xcode Command Line Tools）")
        for name in SOURCES:
            path = os.path.join(MODEL, name)
            if not os.path.isfile(path):
                raise AssertionError(
                    f"缺少被测源文件：{path}\n"
                    "本测试测的是 App 里的真实源码，文件被改名/搬走时请同步更新 SOURCES。"
                )
        if not os.path.isfile(TEST_SRC):
            raise AssertionError(f"缺少测试源文件：{TEST_SRC}")

        cls.tmp = tempfile.mkdtemp(prefix="pd-profiles-")
        # top-level 代码只允许出现在 main.swift
        shutil.copyfile(TEST_SRC, os.path.join(cls.tmp, "main.swift"))
        for name in SOURCES:
            shutil.copyfile(os.path.join(MODEL, name), os.path.join(cls.tmp, name))

        cls.bin = os.path.join(cls.tmp, "profile-tests")
        cmd = ([cls.swiftc, "-o", cls.bin]
               + [os.path.join(cls.tmp, n) for n in SOURCES]
               + [os.path.join(cls.tmp, "main.swift")])
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise AssertionError("swiftc 编译失败：\n" + (proc.stderr or proc.stdout)[-4000:])

    @classmethod
    def tearDownClass(cls):
        if getattr(cls, "tmp", None):
            shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_game_profiles(self):
        proc = subprocess.run([self.bin], capture_output=True, text=True,
                              timeout=120, cwd=self.tmp)
        out = (proc.stdout or "") + (proc.stderr or "")
        self.assertEqual(proc.returncode, 0,
                         "G2 纯逻辑测试失败：\n" + out[-4000:])
        self.assertIn("OK", out, "未看到 OK：" + out[-1000:])

    def test_new_source_is_registered_in_xcode_project(self):
        """新加的 `GameProfile.swift` 必须登记进 pbxproj。

        少了这一步：纯逻辑测试照跑（它们直接 `swiftc` 编译源码），
        但**真机 App 根本编译不到这个文件** —— 症状是模拟器里点预设毫无反应，
        而 CI 全绿。这类漏登记只能靠静态守卫抓。
        """
        path = os.path.join(ROOT, "mobile", "ios", "App", "App.xcodeproj", "project.pbxproj")
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("GameProfile.swift", text, "pbxproj 没有登记 GameProfile.swift")
        self.assertRegex(
            text, r"GameProfile\.swift in Sources",
            "GameProfile.swift 必须在 Sources 构建阶段，否则不会编进 App",
        )


if __name__ == "__main__":
    unittest.main()
