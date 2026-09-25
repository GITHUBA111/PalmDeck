"""Windows exe 的「软件式」外壳：图标 + 版本资源。

背景（都是实测出来的）：

- `packaging/PalmDeck.spec` 里 `icon=None` ⇒ exe 顶着 PyInstaller 的默认图标，
  「属性 → 详细信息」一片空白。玩家看到的第一个东西就是它。
- 版本资源那个文件**不能写 import**（PyInstaller 用 `eval` + 自己的命名空间读它），
  所以「版本号只有一个来源」这件事只能靠「spec 现场拼、测试对账」来保证。

这些断言在 macOS 上全部可跑：只读源码 + 读那个 `.ico` 的字节（不依赖 PyInstaller）。
"""

import ast
import os
import re
import struct
import sys
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SPEC = os.path.join(ROOT, "packaging", "PalmDeck.spec")
ISS = os.path.join(ROOT, "packaging", "PalmDeck.iss")
ISS_LANG = os.path.join(ROOT, "packaging", "ChineseSimplified.isl")
BUILD_BAT = os.path.join(ROOT, "packaging", "build_installer.bat")
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "build-windows.yml")
START = os.path.join(ROOT, "start.py")
UPDATER = os.path.join(ROOT, "updater.py")
ICON = os.path.join(ROOT, "packaging", "PalmDeck.ico")
ICON_SRC = os.path.join(
    ROOT, "mobile", "ios", "App", "App", "Assets.xcassets",
    "AppIcon.appiconset", "AppIcon-512@2x.png",
)

sys.path.insert(0, ROOT)
from updater import APP_VERSION  # noqa: E402


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# 把 packaging/version_info.py **当源码执行**，不走 import / __pycache__：
# ① PyInstaller 本来就是 eval 那个文件的文本，这样测的才是同一个东西；
# ② 免得本地跑探针时被上一轮的 .pyc 蒙过去（本文件第一次写成时真的踩过：
#    替换前后长度相同的改动 + 同一秒内还原 ⇒ 字节码缓存判定“没变”）。
class _Module:
    pass


version_info = _Module()
exec(compile(_read(os.path.join(ROOT, "packaging", "version_info.py")),
             "packaging/version_info.py", "exec"), version_info.__dict__)


def _ico_frames(path):
    """解析 ICO 目录，返回 [(宽, 高, 偏移, 长度)]。宽/高为 0 表示 256。"""
    with open(path, "rb") as fh:
        raw = fh.read()
    reserved, kind, count = struct.unpack("<HHH", raw[:6])
    assert (reserved, kind) == (0, 1), "不是 ICO 文件"
    frames = []
    for i in range(count):
        w, h, _colors, _res, _planes, _bpp, size, offset = struct.unpack(
            "<BBBBHHII", raw[6 + 16 * i:22 + 16 * i])
        frames.append((w or 256, h or 256, offset, size))
    return raw, frames


class TestWindowsIcon(unittest.TestCase):
    def test_spec_points_at_a_real_icon_not_none(self):
        spec = _read(SPEC)
        self.assertNotIn("icon=None", spec, "spec 又把图标写回 None 了")
        m = re.search(r"icon=os\.path\.join\(([^)]*)\)", spec)
        self.assertIsNotNone(m, "spec 里找不到 icon=\u306e os.path.join(...)")
        parts = re.findall(r'"([^"]+)"', m.group(1))
        self.assertTrue(parts, "icon= 里没有文件名：%s" % m.group(0))
        want = os.path.join(ROOT, *parts)
        self.assertTrue(os.path.isfile(want),
                        "spec 的 icon= 指向一个不存在的文件：%s" % os.path.relpath(want, ROOT))
        self.assertTrue(want.lower().endswith(".ico"),
                        "icon= 指向的不是 .ico：%s" % parts[-1])

    def test_icon_has_every_size_windows_asks_for(self):
        self.assertTrue(os.path.isfile(ICON), "packaging/PalmDeck.ico 不存在")
        raw, frames = _ico_frames(ICON)
        got = sorted(w for w, _h, _o, _s in frames)
        # 16=任务栏/文件列表，32=桌面，48=中图标，256=大图标/预览
        for want in (16, 32, 48, 256):
            self.assertIn(want, got, "图标缺 %d×%d 尺寸（现有 %s）" % (want, want, got))
        for w, h, offset, size in frames:
            self.assertEqual(w, h, "图标帧不是正方形")
            blob = raw[offset:offset + size]
            self.assertEqual(len(blob), size, "图标帧数据被截断")
            # Pillow 存法：小尺寸是 BMP(DIB)，256 是 PNG
            self.assertTrue(blob[:4] == b"\x89PNG" or struct.unpack("<I", blob[:4])[0] == 40,
                            "%d×%d 帧既不是 PNG 也不是 DIB" % (w, h))

    def test_icon_source_is_the_product_app_icon(self):
        txt = _read(os.path.join(ROOT, "packaging", "make_icon.py"))
        self.assertIn("AppIcon-512@2x.png", txt,
                      "图标源图不再是产品 App 图标了 —— 那 Windows 与手机会长得不一样")
        self.assertTrue(os.path.isfile(ICON_SRC), "源图不在了：AppIcon-512@2x.png")


class TestWindowsVersionResource(unittest.TestCase):
    def test_spec_generates_the_version_resource(self):
        spec = _read(SPEC)
        self.assertRegex(spec, r"version=_version_file",
                         "EXE(...) 没有 version= ⇒ exe 属性里没有版本信息")
        self.assertIn("version_info", spec, "spec 没用 packaging/version_info.py")
        self.assertFalse(re.search(r"\b\d+\.\d+\.\d+\b", spec),
                         "spec 里出现了硬编码版本号；版本只能来自 updater.APP_VERSION")

    def test_spec_does_not_pollute_sys_path(self):
        """仓库根下有个 `packaging/` 目录（spec 就在里面）。

        一旦把根目录塞进 `sys.path`，就多出一个叫 `packaging` 的命名空间包候选，
        而 PyInstaller 自己要用 PyPI 的 `packaging` —— 构建结果会取决于导入顺序。
        告诉 PyInstaller 去哪里找模块的正经办法是 `Analysis(pathex=...)`。

        用 `ast` 而不是搜字符串：spec 里有一段**注释**正好在解释「为什么不 sys.path.insert」，
        纯文本匹配会把那段话说成违规（本测试第一次写成时真的这么红了）。
        """
        spec = _read(SPEC)
        for node in ast.walk(ast.parse(spec)):
            if (isinstance(node, ast.Attribute) and node.attr == "path"
                    and isinstance(node.value, ast.Name) and node.value.id == "sys"):
                self.fail("spec 里别动 sys.path；模块位置用 Analysis(pathex=) 表达")
        self.assertIn("pathex=", spec)
        self.assertIn("spec_from_file_location", spec,
                      "spec 应按文件路径加载 updater / version_info")

    def test_version_comes_from_the_single_source_of_truth(self):
        """渲染结果必须跟着 `updater.APP_VERSION` 走 —— 这才是「只有一个来源」。"""
        text = version_info.render(APP_VERSION)
        want = "(%s)" % ", ".join(str(n) for n in version_info.version_tuple(APP_VERSION))
        self.assertIn("filevers=%s" % want, text)
        self.assertIn("prodvers=%s" % want, text)
        self.assertIn("StringStruct(u'ProductVersion', u'%s')" % APP_VERSION, text)
        # 换个版本号必须跟着变（防止模板把版本写死）
        other = version_info.render("9.8.7")
        self.assertIn("filevers=(9, 8, 7, 0)", other)
        self.assertNotIn(APP_VERSION, other)

    def test_template_is_a_bare_expression_pyinstaller_can_eval(self):
        """PyInstaller 是 `eval(文件内容, versioninfo.__dict__)` —— 有 import 就炸。"""
        for line in version_info.render(APP_VERSION).splitlines():
            self.assertFalse(line.lstrip().startswith(("import ", "from ")),
                             "版本资源里不能有 import（改用 packaging/version_info.py 拼）")
        self.assertTrue(version_info.render(APP_VERSION).lstrip().startswith("VSVersionInfo("),
                        "版本资源必须从 VSVersionInfo( 开始，且整体是一个表达式")

    def test_file_properties_show_a_real_product_name(self):
        text = version_info.render(APP_VERSION)
        for field in ("CompanyName", "FileDescription", "OriginalFilename",
                      "ProductName", "ProductVersion", "InternalName"):
            self.assertIn("StringStruct(u'%s'" % field, text,
                          "文件属性的 %s 缺了" % field)
        self.assertIn("u'PalmDeck.exe'", text)
        self.assertIn("[1033, 1200]", text,
                      "VarFileInfo 的 Translation 必须与 StringTable 的 040904B0 一致")

    def test_version_tuple_is_always_four_parts(self):
        self.assertEqual(version_info.version_tuple("4"), (4, 0, 0, 0))
        self.assertEqual(version_info.version_tuple("v1.2.3"), (1, 2, 3, 0))
        self.assertEqual(version_info.version_tuple("1.2.3.4.5"), (1, 2, 3, 4))
        self.assertEqual(version_info.version_tuple("4.0.0"), (4, 0, 0, 0))


def _run_spec():
    """把 spec 真跑一遍（PyInstaller 那四个入口打桩），返回记下的 EXE/Analysis 参数。

    `packaging/PalmDeck.spec` 里除了 `collect_all` / `Analysis` / `PYZ` / `EXE`，
    其余都是**普通 Python** —— 所以打上桩就能在 macOS / Linux 上执行它。

    为什么值得跑：spec 是发版路径。名字写错、路径拼错，本机跑测试时全是绿的，
    要到 Windows 打包那一刻才炸 —— 而那时候通常已经在发版了。
    """
    class _Analysis:
        pure, binaries, datas, scripts = [], [], [], []

    hooks = types.ModuleType("PyInstaller.utils.hooks")
    hooks.collect_all = lambda pkg: ([], [], [])
    pkg = types.ModuleType("PyInstaller")
    pkg.__path__ = []
    stubs = {"PyInstaller": pkg,
             "PyInstaller.utils": types.ModuleType("PyInstaller.utils"),
             "PyInstaller.utils.hooks": hooks}
    saved = {k: sys.modules.get(k) for k in stubs}
    seen = {}
    before = list(sys.path)
    # 先删掉上一轮跑出来的产物：不然「这次根本没生成」会被旧文件掩盖成通过
    # （这个测试第一版就中招了：把 spec 里的生成语句改成 `pass` 仍然是绿的）
    stale = os.path.join(ROOT, "build", "version_info.txt")
    if os.path.isfile(stale):
        os.unlink(stale)
    sys.modules.update(stubs)
    try:
        ns = {
            "SPECPATH": os.path.join(ROOT, "packaging"),
            "Analysis": lambda *a, **kw: (seen.update(kw), _Analysis())[1],
            "PYZ": lambda *a, **kw: "pyz",
            "EXE": lambda *a, **kw: (seen.update({"exe": kw}), "exe")[1],
        }
        exec(compile(_read(SPEC), SPEC, "exec"), ns)
    finally:
        for name, mod in saved.items():
            if mod is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = mod
    assert sys.path == before, "spec 不许改 sys.path（见 test_spec_does_not_pollute_sys_path）"
    return seen


class TestSpecReallyRuns(unittest.TestCase):
    """spec 真跑一遍：图标、版本资源、pathex。"""

    def test_spec_hands_the_icon_and_version_to_exe(self):
        exe = _run_spec()["exe"]
        self.assertEqual(exe["name"], "PalmDeck",
                         "updater.py 里下载直链写死了 PalmDeck.exe，名字不能改")
        self.assertEqual(os.path.basename(exe["icon"]), "PalmDeck.ico")
        self.assertTrue(os.path.isfile(exe["icon"]), "spec 指的图标文件不存在")
        self.assertTrue(os.path.isfile(exe["version"]),
                        "spec 没真的生成版本资源文件（EXE 会拿不到 version=）")

    def test_generated_version_resource_carries_the_current_version(self):
        """这是「版本号不会写歪」的**端到端**证据：真跑 spec → 读它生成的文件。"""
        text = _read(_run_spec()["exe"]["version"])
        for key in ("FileVersion", "ProductVersion"):
            self.assertIn("u'%s', u'%s'" % (key, APP_VERSION), text,
                          "exe 属性里的 %s 与 updater.APP_VERSION 不一致" % key)
        self.assertIn("u'ProductName', u'PalmDeck'", text)

    def test_spec_points_pyinstaller_at_the_repo_root(self):
        """`hiddenimports` 里的 bridge / updater 等都是仓库根下的模块，靠 pathex 找。"""
        pathex = _run_spec()["pathex"]
        self.assertIn(ROOT, pathex)
        self.assertIn(os.path.join(ROOT, "vendor"), pathex, "vendored vgamepad 在 vendor/ 下")


if __name__ == "__main__":
    unittest.main()



def _iss_code(text):
    """去掉 `;` 注释行后的 .iss。

    注释里会举例版本号（`ISCC /dAppVersion=4.0.0`）、会解释「为什么不装到
    Program Files」—— 拿整份文本去断言「不许出现版本号 / 不许出现 Program Files」
    会被自己的注释误伤（本文件的测试第一版就这么红的）。
    """
    return "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith(";"))


def _autostart_from_start():
    """start.py 里自启项的键名/键值（托盘里那个开关用的就是它俩）。"""
    src = _read(START)
    key = re.search(r'_AUTOSTART_KEY = r"([^"]+)"', src)
    name = re.search(r'_AUTOSTART_NAME = "([^"]+)"', src)
    assert key and name, "start.py 里找不到 _AUTOSTART_KEY / _AUTOSTART_NAME"
    return key.group(1), name.group(1)


class TestSetupScript(unittest.TestCase):
    """`packaging/PalmDeck.iss` 与 `start.py`、与 CI 冒烟脚本必须对得上。

    .iss 在 macOS 上编译不了 —— 所以「装到哪」「自启项叫什么」这些一旦对不上，
    只有真机走一遍才会发现（而那时候用的是玩家的机器）。这里全钉成源码断言。
    """

    def setUp(self):
        self.raw = _read(ISS)
        self.code = _iss_code(self.raw)

    def _section(self, name):
        self.assertIn(name, self.code, ".iss 里没有 %s 段" % name)
        return self.code.split(name, 1)[1].split("\n[", 1)[0]

    def test_installs_per_user_where_the_smoke_test_looks_for_it(self):
        """装到 `{localappdata}\\Programs\\PalmDeck`。

        ① 全程不弹 UAC；② **安装目录可写** —— `updater.apply_update()` 是把新 exe
        下到 exe 旁边再自替换，装进 Program Files 会让自动更新**静默失效**
        （玩家不会发现，只会一直用旧版）。CI 冒烟也去同一个路径找 exe。
        """
        self.assertIn(r"DefaultDirName={localappdata}\Programs\PalmDeck", self.code)
        self.assertIn("PrivilegesRequired=lowest", self.code)
        self.assertNotIn("Program Files", self.code)
        # 别加 PrivilegesRequiredOverridesAllowed：向导会多一个「为所有用户安装？」页面，
        # 选它就要 UAC —— 「免 UAC」是这个方案的目标之一，不该留个反向开关给玩家踩。
        self.assertNotIn("PrivilegesRequiredOverridesAllowed", self.code)
        self.assertIn(r'Join-Path $env:LOCALAPPDATA "Programs\PalmDeck"', _read(WORKFLOW))

    def test_exe_name_is_the_shipped_asset_name(self):
        """exe 名字不能改：`updater.GITHUB_EXE` 的自动更新直链写死了它。"""
        from updater import GITHUB_EXE
        self.assertTrue(GITHUB_EXE.endswith("/PalmDeck.exe"))
        self.assertIn('#define AppExe "PalmDeck.exe"', self.raw)
        self.assertIn(r'Source: "..\dist\{#AppExe}"', self.code)
        self.assertIn(r'Filename: "{app}\{#AppExe}"', self.code)

    def test_refuses_unsupported_windows(self):
        """只装到跑得起来的系统上：exe 是 Python 3.12 + PyInstaller 产的。

        不加这条的话，Win7/8 上会「装得好好的、一启动就崩」，而报错窗口是 exe 吐的，
        玩家根本不知道发生了什么。
        """
        self.assertIn("MinVersion=10.0", self.code)
        self.assertIn("ArchitecturesAllowed=x64compatible", self.code,
                      "只发 x64：vendor 里的 ViGEmClient.dll 只有 x64/x86，没做 arm64")

    def test_icon_file_is_the_one_we_ship(self):
        self.assertIn(r"SetupIconFile=..\packaging\PalmDeck.ico", self.code)
        self.assertTrue(os.path.isfile(ICON))

    def test_autostart_entry_is_the_same_switch_as_the_tray_toggle(self):
        """安装时勾的「开机自启」和托盘菜单里那个开关必须**是同一个值**。

        两边各写各的键名 ⇒ 玩家在托盘里关掉、重启又冒出来（或反过来）。
        """
        key, name = _autostart_from_start()
        reg = self._section("[Registry]")
        self.assertIn('Subkey: "%s"' % key, reg, ".iss 的自启键名与 start.py 不一致")
        self.assertIn('#define AppName "%s"' % name, self.raw,
                      ".iss 的 AppName 与 start.py 的 _AUTOSTART_NAME 不一致")
        self.assertIn('ValueName: "{#AppName}"', reg,
                      "自启项的 ValueName 该用 AppName 变量，别手抄")
        self.assertIn("Tasks: autostart", reg, "自启项必须挂在 autostart 任务下")
        self.assertIn(r'ValueData: """{app}\{#AppExe}"""', reg,
                      "写进注册表的必须是带引号的可执行文件全路径（与 start.py 一致）")

    def test_uninstall_removes_the_autostart_key(self):
        """卸载要删掉自启项 —— 否则删完程序，开机还会去启动一个不存在的 exe。

        这是旧版（裸 exe）真实存在的缺陷：exe 删了，HKCU Run 里还留着。
        """
        self.assertIn("uninsdeletevalue", self._section("[Registry]"))

    def test_uninstall_keeps_the_user_config_dir(self):
        """卸载**不动** `%APPDATA%\\PalmDeck`：重装不该把布局 / 配置弄丢。"""
        entries = [ln.strip() for ln in self._section("[UninstallDelete]").splitlines()
                   if ln.strip().startswith("Type:")]
        self.assertEqual(len(entries), 1, "UninstallDelete 只该清程序自己的目录")
        self.assertIn('Name: "{app}"', entries[0])
        self.assertNotIn("userappdata", entries[0].lower())

    def test_version_is_injected_and_never_hardcoded(self):
        """版本号只有一个真相源（`updater.APP_VERSION`）；不传就编译失败。

        不传时的默认值最危险：会打出一个叫 `PalmDeck-Setup-0.0.0.exe` 的东西发出去。
        """
        self.assertIn("#error", self.raw, "没传 AppVersion 时必须直接报错")
        self.assertIn("AppVersion={#AppVersion}", self.code)
        self.assertNotRegex(self.code, r"AppVersion=[\"']?\d+\.\d+\.\d+",
                            ".iss 里不许出现硬编码版本号")
        self.assertIn("OutputBaseFilename=PalmDeck-Setup-{#AppVersion}", self.code)
        self.assertIn("dist/PalmDeck-Setup-*.exe", _read(WORKFLOW))

    def test_closes_the_running_tray_before_replacing_files(self):
        """覆盖安装 / 卸载时让托盘进程先退出，否则文件被占用会失败。"""
        self.assertIn("CloseApplications=yes", self.code)

    def test_wizard_is_in_chinese(self):
        """向导得是中文的 —— 产品面向中文用户，英文向导本身就是「不像软件」。"""
        self.assertIn('MessagesFile: "ChineseSimplified.isl"', self.code)
        self.assertTrue(os.path.isfile(ISS_LANG), "中文语言文件不在仓库里")
        lang = _read(ISS_LANG)
        self.assertIn("LanguageName=简体中文", lang)
        self.assertIn("[Messages]", lang)
        self.assertIn("kira-96/Inno-Setup-Chinese-Simplified-Translation", lang,
                      "上游署名要留着（Inno 官方翻译列表里的那个仓库）")


class TestBuildInstallerBat(unittest.TestCase):
    def setUp(self):
        self.bat = _read(BUILD_BAT)

    def test_pulls_the_version_from_the_single_source_of_truth(self):
        self.assertIn("updater import APP_VERSION", self.bat)
        self.assertIn('"%ISCC%" /dAppVersion=%VER% PalmDeck.iss', self.bat)

    def test_finds_iscc_where_inno_setup_actually_installs_it(self):
        """Inno Setup 装完**不会**把自己加进 PATH —— 只靠 `where ISCC` 会误报「没装」。

        （这一条是照着 CI 里那段找 ISCC 的逻辑写的，两边找的位置必须一样。）
        """
        self.assertIn(r"Inno Setup 6\ISCC.exe", self.bat)
        self.assertIn("%ProgramFiles(x86)%", self.bat)
        # 真的要跑起来才算「找到」
        self.assertIn('if exist %%p set "ISCC=%%~p"', self.bat)
        # PATH 兜底可以有，但不能是唯一手段
        self.assertIn("where ISCC", self.bat)

    def test_refuses_to_run_without_the_exe(self):
        """先出 exe 再打安装包：顺序错了要在 Windows 上说人话，别丢给 ISCC 报错。"""
        bat = _read(BUILD_BAT)
        self.assertIn("dist\\PalmDeck.exe", bat)
        self.assertIn("pyinstaller packaging\\PalmDeck.spec", bat)


class TestWorkflowShipsAndSmokeTestsTheInstaller(unittest.TestCase):
    """.github/workflows/build-windows.yml 里「软件式」的那半段。"""

    def setUp(self):
        self.wf = _read(WORKFLOW)

    def test_asserts_the_exe_version_resource(self):
        """文件属性是本机（macOS）验不了那部分：这里没有资源编译器。"""
        self.assertIn("(Get-Item dist\\PalmDeck.exe).VersionInfo", self.wf)
        for field in ("ProductName", "FileDescription", "ProductVersion"):
            self.assertIn(field, self.wf)

    def test_compiles_the_installer_with_the_version_from_updater(self):
        self.assertIn("ISCC", self.wf)
        self.assertIn("/dAppVersion=${{ steps.ver.outputs.version }}", self.wf)
        self.assertIn("from updater import APP_VERSION", self.wf,
                      "版本号要从 updater 读，别在 workflow 里再写一处")

    def test_silent_install_smoke_test_covers_the_whole_lifecycle(self):
        """静默装 → 起进程 → 接口有响应 → 卸载 → 自启项没了、配置还在。

        这条是「Windows 上从没验过」这个老缺口里**能自动化**的那部分：
        打包缺模块、装错目录、卸载留下失效自启项 —— 三类问题一次挡住。
        """
        for needle in (
            "/VERYSILENT",
            "/TASKS=autostart",                      # 顺带把 [Registry] 那条也验了
            "$env:PALMDECK_NO_TRAY",                 # 没它托盘会让冒烟飘（见 start.py）
            "$env:PALMDECK_NO_UPDATE",
            "http://127.0.0.1:8080/api/status",
            "unins000.exe",
            r'Join-Path $env:APPDATA "PalmDeck"',    # 卸载后配置目录必须还在
        ):
            self.assertIn(needle, self.wf, "冒烟测试漏了：%s" % needle)
        # 自启项：既断言「装完有」，也断言「卸载后没了」
        self.assertIn("HKCU Run 里没有 PalmDeck", self.wf)
        self.assertIn("卸载后 HKCU Run 里还留着 PalmDeck", self.wf)

    def test_publishes_both_the_exe_and_the_installer(self):
        self.assertIn("dist/PalmDeck.exe", self.wf)
        self.assertIn("dist/PalmDeck-Setup-*.exe", self.wf)
        self.assertIn("needs: test", self.wf, "测试红了不许发版")


class TestNoTraySwitch(unittest.TestCase):
    """`PALMDECK_NO_TRAY`：让「装完能不能启动」在自动化里可验。"""

    def setUp(self):
        self.src = _read(START)

    def test_flag_short_circuits_the_tray(self):
        self.assertIn('os.environ.get("PALMDECK_NO_TRAY")', self.src)
        self.assertLess(self.src.index("PALMDECK_NO_TRAY"), self.src.index("    run_tray()"),
                        "开关必须在 run_tray() 之前判断，否则等于没写")
        self.assertIn("run_headless()", self.src)

    def test_style_matches_the_existing_no_update_switch(self):
        """与 `updater.PALMDECK_NO_UPDATE` 同款式（非空即开），少一套记忆负担。"""
        self.assertIn('os.environ.get("PALMDECK_NO_UPDATE")', _read(UPDATER))

    def test_the_smoke_test_actually_sets_it(self):
        self.assertIn("PALMDECK_NO_TRAY", _read(WORKFLOW))


class TestConsoleOpensAsAnAppWindow(unittest.TestCase):
    """O3-lite：控制台用 Edge/Chrome 的 `--app=` 打开（没有地址栏 ⇒ 像原生窗口）。"""

    def setUp(self):
        self.src = _read(START)

    def test_prefers_an_app_window(self):
        self.assertIn("def _browser_exe()", self.src)
        self.assertIn('f"--app={url}"', self.src)
        self.assertIn('"msedge.exe", "chrome.exe"', self.src)
        self.assertIn(r"CurrentVersion\App Paths", self.src,
                      "也要能从注册表 App Paths 找（装在非默认位置时）")

    def test_falls_back_to_the_default_browser(self):
        """少一个 Edge 不该变成「控制台打不开」—— 每层失败都往下退。"""
        self.assertIn("webbrowser.open(url)", self.src)
        self.assertIn("def open_console(frag", self.src)
        self.assertIn("if os.name != \"nt\":\n        return None", self.src,
                      "非 Windows 直接返回 None，让 webbrowser 接手")

    def test_every_entry_point_goes_through_the_same_function(self):
        """托盘 / 自检 / 重复双击 三个入口都走 open_console，别再各写各的。"""
        self.assertNotIn("webbrowser.open(http_url", self.src)
        self.assertIn('open_console("#doctor")', self.src)
        self.assertIn('pystray.MenuItem("打开控制台", open_console_item', self.src)
        self.assertIn("open_console()", self.lock_loop())

    def lock_loop(self):
        return self.src.split("def lock_command_loop", 1)[1].split("\ndef ", 1)[0]


class TestTrayIconIsTheProductIcon(unittest.TestCase):
    """托盘图标与 exe / 手机是同一个 logo。

    以前托盘是 PIL 自绘的青色方向盘、exe 图标是 App 图标 —— 同一台机器上两个 logo，
    正是「不像一个软件」的症状之一。
    """

    def setUp(self):
        self.src = _read(START)
        self.spec = _read(SPEC)

    def test_tries_the_product_icon_first(self):
        self.assertLess(self.src.index("_product_icon_path()"), self.src.index("ImageDraw"),
                        "自绘是兜底，不该排在产品图标前面")

    def test_product_icon_resolves_in_source_and_in_the_bundle(self):
        """同一段代码要同时服务「源码运行」和「打包后」：靠 sys._MEIPASS 判断。"""
        self.assertIn('getattr(sys, "_MEIPASS", None) or HERE', self.src)
        self.assertIn('os.path.join(base, "packaging", "PalmDeck.ico")', self.src)

    def test_spec_really_bundles_it(self):
        """`icon=` 只把图标写进 exe 资源，**运行时读不到** —— 必须同时进 datas。"""
        self.assertIn('os.path.join(root, "packaging", "PalmDeck.ico"), "packaging"', self.spec)
        datas = [d for d in _run_spec()["datas"] if "PalmDeck.ico" in str(d)]
        self.assertEqual(len(datas), 1, "包里的图标不是恰好一份")
        src, dest = datas[0]
        self.assertTrue(os.path.isfile(src), "spec 指的图标文件不存在")
        self.assertEqual(dest, "packaging", "包内目录要和 start.py 找的相对路径一致")


if __name__ == "__main__":
    unittest.main()
