"""iOS 拖拽吸附纯逻辑测试（swiftc 直跑，不依赖 Xcode 工程 / XCTest）。

为什么单独开一个文件：`tests/test_ios_axis.py` 编译的是「轴/曲线/包布局」那一组，
本文件只编译 `Model/Snap.swift`（拖动落点的吸附与夹取规则）。
它同样是 App 里的**真实源码**，不是副本。

规则本身很短，但错法很隐蔽（吸错一条线、把组件夹丢、画出假对齐线），
在真机上只能靠眼睛看 —— 所以放在这里钉死。
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
    "Snap.swift",
]

TEST_SRC = os.path.join(HERE, "ios", "SnapTests.swift")


class TestIOSSnap(unittest.TestCase):
    """编译并运行 tests/ios/SnapTests.swift。"""

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

        cls.tmp = tempfile.mkdtemp(prefix="pd-snap-")
        # top-level 代码只允许出现在 main.swift
        shutil.copyfile(TEST_SRC, os.path.join(cls.tmp, "main.swift"))
        for name in SOURCES:
            shutil.copyfile(os.path.join(MODEL, name), os.path.join(cls.tmp, name))

        cls.bin = os.path.join(cls.tmp, "snap-tests")
        cmd = ([cls.swiftc, "-O", "-o", cls.bin]
               + [os.path.join(cls.tmp, n) for n in SOURCES]
               + [os.path.join(cls.tmp, "main.swift")])
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise AssertionError("swiftc 编译失败：\n" + (proc.stderr or proc.stdout)[-4000:])

    @classmethod
    def tearDownClass(cls):
        if getattr(cls, "tmp", None):
            shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_snap_core(self):
        proc = subprocess.run([self.bin], capture_output=True, text=True, timeout=120)
        out = (proc.stdout or "") + (proc.stderr or "")
        self.assertEqual(proc.returncode, 0, "拖拽吸附测试失败：\n" + out[-4000:])
        self.assertIn("OK", out, "未看到 OK：" + out[-1000:])


class TestSnapStaysPure(unittest.TestCase):
    """吸附规则必须能被 swiftc 单独编译 —— 不许把 SwiftUI 拖进来。"""

    def test_only_foundation(self):
        path = os.path.join(MODEL, "Snap.swift")
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        imports = [ln.strip() for ln in text.splitlines() if ln.strip().startswith("import ")]
        self.assertEqual(imports, ["import Foundation"],
                         "Model/Snap.swift 只能 import Foundation（否则 swiftc 测不了）")


if __name__ == "__main__":
    unittest.main()
