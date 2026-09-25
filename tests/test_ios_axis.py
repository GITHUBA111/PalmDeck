"""iOS 纯逻辑测试（swiftc 直跑，不依赖 Xcode 工程 / XCTest）。

为什么不用 XCTest target：被测对象（曲线数学、轴真值表、包字节布局）都是**纯函数**，
在 `project.pbxproj` 里手加一个 unit-test target 只能换来「要跑就得开 Xcode」。
`swiftc` 直接编译运行更简单，还能跟着 `python3 -m unittest` 一起跑。

被测文件（App 里的真实源码，不是副本）：
  - Native/Model/AxisCurve.swift   ← 曲线（预览与发送共用同一个实现）
  - Native/Model/AxisMap.swift     ← 模式 → 8 个轴的真值表
  - Native/Model/CockpitMode.swift ← 模式枚举 + 旧值兼容
  - Native/Model/PacketFormat.swift← 22 字节包布局
  - Native/Model/ShapingKeys.swift← G1 手感键名与旧值迁移

注意：Swift 的 top-level 代码只允许出现在 `main.swift`，
所以测试源码会被复制到临时目录并改名 `main.swift` 再编译。
"""

import os
import re
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
    "ShapingKeys.swift",
    # 底部仪表条按模式取字段（吃的就是 AxisMap 的输出）
    "HudReadout.swift",
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


class TestShapingParamsAreModeScoped(unittest.TestCase):
    """G1：手感参数必须按模式分开存。

    这个 bug 的特征是「改了 A 模式，B 模式跟着变」—— 不崩、不报错，
    只是手感静默地不对，所以靠人眼看代码是拦不住的。
    """

    SWIFT_DIRS = ("Model", "Views")

    def _swift_files(self):
        base = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native")
        for sub in self.SWIFT_DIRS:
            d = os.path.join(base, sub)
            for name in sorted(os.listdir(d)):
                if name.endswith(".swift"):
                    yield os.path.join(d, name)

    def test_shaping_keys_file_is_compiled_by_this_suite(self):
        self.assertIn("ShapingKeys.swift", SOURCES,
                      "迁移逻辑必须跑在纯逻辑测试里，否则没人验证它")

    def test_no_global_shaping_key_survives(self):
        path = os.path.join(MODEL, "ShapingKeys.swift")
        with open(path, encoding="utf-8") as fh:
            keys_src = fh.read()
        legacy = sorted(set(re.findall(r'static let \w+ = "(palmdeck_[a-z_]+)"', keys_src)))
        self.assertEqual(
            legacy,
            sorted([
                "palmdeck_sens_x", "palmdeck_sens_y", "palmdeck_dz",
                "palmdeck_inv_x", "palmdeck_inv_y", "palmdeck_inv_yaw", "palmdeck_inv_coll",
            ]),
            "ShapingKeys.swift 里的旧键清单变了一一请同步更新这里的断言",
        )
        self.assertRegex(keys_src, r"legacyKeys = legacyDoubles \+ legacyBools",
                         "legacyKeys 必须是两个子清单的并集，不能另写一份")

        offenders = []
        for path in self._swift_files():
            if os.path.basename(path) == "ShapingKeys.swift":
                continue
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            for key in legacy:
                if f'"{key}"' in text:
                    offenders.append(f"{os.path.relpath(path, ROOT)} 用了全局键 \"{key}\"")
        self.assertEqual(
            offenders, [],
            "手感参数又变回全局键了（应该走 ShapingKeys.scoped(_, mode)）：\n  "
            + "\n  ".join(offenders),
        )

    def test_controller_state_has_one_load_path(self):
        with open(os.path.join(MODEL, "ControllerState.swift"), encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("ShapingMigration.run(", text, "启动时必须跑一次迁移")
        self.assertIn("private func reloadShaping()", text, "读取只能有一条路径")
        self.assertIn("func applyMode(", text, "切模式必须重新读该模式的参数")
        # 读取路径唯一：ShapingParams.double/bool 只出现在 reloadShaping 里
        self.assertEqual(
            len(re.findall(r"ShapingParams\.(?:double|bool)\(", text)), 7,
            "七个受模式影响的手感参数各读一次（读多了就说明有两处读取会滞）",
        )

    def test_set_mode_goes_through_apply_mode(self):
        with open(os.path.join(MODEL, "CockpitController.swift"), encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("state.applyMode(m)", text,
                      "切模式必须走 applyMode，不能只改 state.mode（那样手感参数不会跟着换）")
        self.assertNotIn("state.mode = m", text,
                         "直接赋 state.mode 会跳过手感参数重读")


if __name__ == "__main__":
    unittest.main()
