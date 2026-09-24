"""iOS 纯逻辑测试（swiftc 直跑，不依赖 Xcode 工程 / XCTest）。

为什么不用 XCTest target：被测对象（曲线数学、轴真值表、包字节布局）都是**纯函数**，
在 `project.pbxproj` 里手加一个 unit-test target 只能换来「要跑就得开 Xcode」。
`swiftc` 直接编译运行更简单，还能跟着 `python3 -m unittest` 一起跑。

被测文件（App 里的真实源码，不是副本）：
  - Native/Model/AxisCurve.swift   ← 曲线（预览与发送共用同一个实现）
  - Native/Model/AxisMap.swift     ← 模式 → 8 个轴的真值表
  - Native/Model/CockpitMode.swift ← 模式枚举 + 旧值兼容
  - Native/Model/PacketFormat.swift← 22 字节包布局

注意：Swift 的 top-level 代码只允许出现在 `main.swift`，
所以测试源码会被复制到临时目录并改名 `main.swift` 再编译。
"""

import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MODEL = os.path.join(
    ROOT, "mobile", "ios", "App", "App", "Native", "Model"
)

SOURCES = [
    "AxisCurve.swift",
    "AxisMap.swift",
    "CockpitMode.swift",
    "PacketFormat.swift",
]

TEST_SRC = os.path.join(HERE, "ios", "AxisCoreTests.swift")


class TestIOSAxisCore(unittest.TestCase):
    """编译并运行 tests/ios/AxisCoreTests.swift。"""

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
                    "tests/ios/AxisCoreTests.swift 测的是 App 里的真实源码，"
                    "文件被改名/搬走时请同步更新 tests/test_ios_axis.py 的 SOURCES。"
                )
        if not os.path.isfile(TEST_SRC):
            raise AssertionError(f"缺少测试源文件：{TEST_SRC}")

        cls.tmp = tempfile.mkdtemp(prefix="pd-axis-")
        # top-level 代码只允许在 main.swift 里
        shutil.copyfile(TEST_SRC, os.path.join(cls.tmp, "main.swift"))
        for name in SOURCES:
            shutil.copyfile(os.path.join(MODEL, name), os.path.join(cls.tmp, name))

        cls.bin = os.path.join(cls.tmp, "axis-tests")
        cls.raw = [  # 源码内容，供下面的「实现唯一性」断言用
            os.path.join(cls.tmp, name) for name in SOURCES
        ]
        cmd = [cls.swiftc, "-O", "-o", cls.bin] + cls.raw + [os.path.join(cls.tmp, "main.swift")]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise AssertionError(
                "swiftc 编译失败：\n" + (proc.stderr or proc.stdout)[-4000:]
            )

    @classmethod
    def tearDownClass(cls):
        if getattr(cls, "tmp", None):
            shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_axis_core(self):
        proc = subprocess.run([self.bin], capture_output=True, text=True, timeout=120)
        out = (proc.stdout or "") + (proc.stderr or "")
        self.assertEqual(
            proc.returncode, 0,
            "iOS 纯逻辑测试失败：\n" + out[-4000:],
        )
        self.assertIn("OK", out, "未看到 OK：" + out[-1000:])


class TestCurveHasSingleImplementation(unittest.TestCase):
    """曲线数学在全仓库只能有一处实现。

    这条断言保护的是「设置里的预览不能和真正发出去的整形函数不一致」——
    预览如果自己复刻一份公式，就会在没人注意的时候漂掉，而骗人的预览比没有预览更糟。
    """

    SWIFT_DIRS = ("Model", "Views")

    def _swift_files(self):
        base = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native")
        for sub in self.SWIFT_DIRS:
            d = os.path.join(base, sub)
            for name in sorted(os.listdir(d)):
                if name.endswith(".swift"):
                    yield os.path.join(d, name)

    def test_only_axis_curve_computes_the_curve(self):
        offenders = []
        for path in self._swift_files():
            if os.path.basename(path) == "AxisCurve.swift":
                continue
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            # 幂运算只能出现在 AxisCurve.swift
            if "pow(" in text:
                offenders.append(f"{os.path.relpath(path, ROOT)} 出现 pow(")
            if "func shape(" in text:
                offenders.append(f"{os.path.relpath(path, ROOT)} 又定义了一份 shape(")
        self.assertEqual(
            offenders, [],
            "曲线数学被重复实现，预览会与实际不一致：\n  " + "\n  ".join(offenders),
        )

    def test_preview_calls_shared_implementation(self):
        path = os.path.join(
            ROOT, "mobile", "ios", "App", "App", "Native", "Views", "SettingsView.swift"
        )
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("AxisCurve.output(", text, "响应曲线预览必须调用 AxisCurve.output")


if __name__ == "__main__":
    unittest.main()
