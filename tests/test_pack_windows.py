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

    def test_gitignore_has_no_dead_ios_rules(self):
        """iOS 的 .gitignore 不该再留着 Capacitor 时代的规则。"""
        path = os.path.join(ROOT, "mobile", "ios", ".gitignore")
        with open(path, encoding="utf-8") as fh:
            rules = {ln.strip() for ln in fh}
        dead = {
            "App/App/public",
            "App/App/capacitor.config.json",
            "App/App/config.xml",
            "capacitor-cordova-ios-plugins",
        }
        self.assertEqual(
            rules & dead,
            set(),
            ".gitignore 里还留着 Capacitor 时代产物的规则，说明它们还会被重新生成",
        )


class TestNoCapacitorResidue(unittest.TestCase):
    """v4 是纯 SwiftUI，全 App 没有 WebView。

    Capacitor 的壳子是 v3（网页座舱）时代的，删掉后必须不能回来 ——
    它不只是 84 KB 的死资源，更会把人重新引向「WebView 里跑控制台」这条
    v4 明确否掉的路。另外 `Main.storyboard` 里是 `CAPBridgeViewController`，
    一旦有人给它补上 `UIMainStoryboardFile`，App 会以网页壳启动。
    """

    IOS_APP = os.path.join(ROOT, "mobile", "ios", "App", "App")

    def _swift_sources(self):
        for base, _dirs, files in os.walk(self.IOS_APP):
            for fn in files:
                if fn.endswith(".swift"):
                    yield os.path.join(base, fn)

    def test_no_swift_file_imports_capacitor(self):
        offenders = []
        for path in self._swift_sources():
            with open(path, encoding="utf-8") as fh:
                for i, line in enumerate(fh, 1):
                    if "import Capacitor" in line or "CAPPlugin" in line:
                        offenders.append(f"{os.path.relpath(path, ROOT)}:{i}")
        self.assertEqual(offenders, [], f"还有 Swift 文件依赖 Capacitor：{offenders}")

    def test_no_capacitor_bridge_storyboard(self):
        for name in ("Main.storyboard", "capacitor.config.json", "config.xml"):
            path = os.path.join(self.IOS_APP, name)
            self.assertFalse(os.path.exists(path), f"Capacitor 残骸又回来了：{name}")
        self.assertFalse(
            os.path.exists(os.path.join(self.IOS_APP, "public")),
            "App/App/public/ 是 `cap sync` 生成的网页座舱，v4 不该再有",
        )

    def test_pbxproj_does_not_reference_capacitor(self):
        path = os.path.join(ROOT, "mobile", "ios", "App", "App.xcodeproj", "project.pbxproj")
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for token in ("PalmDeckUdpPlugin", "Main.storyboard", "capacitor.config.json",
                      "config.xml", "public in Resources"):
            self.assertNotIn(token, text, f"project.pbxproj 还在引用 Capacitor 残骸：{token}")


class TestNoCocoaPods(unittest.TestCase):
    """工程不再用 CocoaPods（它当初只为装 Capacitor）。

    Podfile 用的是本地路径 pod：`pod 'Capacitor', :path => '../../node_modules/@capacitor/ios'`，
    而 `mobile/node_modules/` 是 gitignored 的 —— 意味着**新克隆的仓库里
    `pod install` 必定失败**。本地能构建只因为 `mobile/node_modules/` 和 `Pods/`
    这两份未入库的东西还在。所以这不是「能不能跑」，是「能不能克隆」。

    拆掉后工程就是普通 `App.xcodeproj`（xcodebuild 会从 target 自动合成 scheme），
    构建命令也必须从 `-workspace` 改回 `-project`。
    """

    IOS = os.path.join(ROOT, "mobile", "ios")

    def test_podfile_and_workspace_are_gone(self):
        for rel in ("App/Podfile", "App/Podfile.lock", "App/App.xcworkspace", "App/Pods"):
            self.assertFalse(
                os.path.exists(os.path.join(self.IOS, rel)),
                f"CocoaPods 脚手架又回来了：{rel}（它依赖未入库的 mobile/node_modules）",
            )

    def test_pbxproj_has_no_pods_integration(self):
        path = os.path.join(self.IOS, "App", "App.xcodeproj", "project.pbxproj")
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for token in ("Pods_App", "Pods-App", "PODS_ROOT", "[CP]",
                      "baseConfigurationReference", "Pods/Target Support Files"):
            self.assertNotIn(token, text, f"project.pbxproj 还接着 CocoaPods：{token}")

    def test_build_scripts_use_project_not_workspace(self):
        for rel in ("mac.sh", os.path.join("mobile", "ios", "deploy_wifi.sh")):
            with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
                text = fh.read()
            self.assertIn("-project App.xcodeproj", text, f"{rel} 没改成 -project")
            self.assertNotIn("-workspace App.xcworkspace", text, f"{rel} 还在用已删除的 workspace")


if __name__ == "__main__":
    unittest.main()
