"""G1 集成测试：真的 `ControllerState`，注入的字典存储。

为什么要在 `AxisCoreTests` 之外再开一个：那个测的是**迁移算法**，
这个测的是**接线**。「改了 A 模式、B 模式跟着变」这类 bug 的形状恰好是
算法对、接线错（比如 `ControllerState` 忘了调迁移，或者 `setMode`
只改了 `state.mode` 没重新读参数）—— 只测算法是抓不到的。

被测文件就是 App 里的真实源码，不是副本。存储是注入的
（`ControllerState(shapingStore:)`），所以跑测试不会碰真实 `UserDefaults`。
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
    "AxisCurve.swift",
    "ShapingKeys.swift",
    "ControllerState.swift",
]

TEST_SRC = os.path.join(HERE, "ios", "ControllerStateKeysTests.swift")


class TestControllerStateShapingKeys(unittest.TestCase):

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

        cls.tmp = tempfile.mkdtemp(prefix="pd-state-keys-")
        # top-level 代码只允许出现在 main.swift
        shutil.copyfile(TEST_SRC, os.path.join(cls.tmp, "main.swift"))
        for name in SOURCES:
            shutil.copyfile(os.path.join(MODEL, name), os.path.join(cls.tmp, name))

        # 被测代码会读 UserDefaults.standard 拿当前模式（读不写），
        # 真正的手感参数走注入的字典存储，不会污染真实偏好设置。
        cls.bin = os.path.join(cls.tmp, "state-keys-tests")
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

    def test_shaping_params_are_mode_scoped(self):
        proc = subprocess.run([self.bin], capture_output=True, text=True,
                              timeout=120, cwd=self.tmp)
        out = (proc.stdout or "") + (proc.stderr or "")
        self.assertEqual(proc.returncode, 0,
                         "G1 集成测试失败：\n" + out[-4000:])
        self.assertIn("OK", out, "未看到 OK：" + out[-1000:])


if __name__ == "__main__":
    unittest.main()
