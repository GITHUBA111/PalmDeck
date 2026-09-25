# -*- mode: python ; coding: utf-8 -*-
# 在 Windows 上打包：
#   pip install pyinstaller pyvjoy zeroconf qrcode pystray Pillow
#   pyinstaller packaging/PalmDeck.spec
#
# 入口是 start.py（罗技驱动式守护程序：托盘 + 自动更新 + 后台桥接），
# bridge 作为模块被它 import。
#
# exe 的图标与「属性 → 详细信息」在下面 EXE(...) 里给出：
#   icon=packaging/PalmDeck.ico（多尺寸，源图是 iOS 的产品图标）
#   version=...（由 updater.APP_VERSION 现场拼出，不手抄版本号）
#
# 注意：vgamepad 不通过 pip 安装（那个包的 setup.py 会在安装时跑 msiexec 卡死），
# 而是内置在 vendor/vgamepad，下面用 hiddenimports + datas 手工收进来。

from PyInstaller.utils.hooks import collect_all
import importlib.util
import os

root = os.path.abspath(os.path.join(SPECPATH, ".."))


def _load_by_path(name, *parts):
    """按文件路径加载模块，**绝不动 sys.path**。

    为什么不干脆 `sys.path.insert(0, root)`：仓库根下就有一个 `packaging/`
    目录（本文件就在里面），把它放进 sys.path 就多出一个叫 `packaging` 的
    命名空间包候选 —— 而 PyInstaller 自己要用 PyPI 的 `packaging`。
    “构建结果取决于导入顺序”这种事不该出现在发版路径上。
    需要告诉 PyInstaller 去哪儿找模块用下面的 `pathex=`（那才是正经入口）。
    """
    spec = importlib.util.spec_from_file_location(name, os.path.join(*parts))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# 版本号唯一来源是 updater.APP_VERSION；图标与版本资源的说明见 packaging/version_info.py。
APP_VERSION = _load_by_path("palmdeck_updater", root, "updater.py").APP_VERSION
_vi = _load_by_path("palmdeck_version_info", SPECPATH, "version_info.py")

# 版本资源写到 build/（gitignore 的中间产物）—— 每次打包按 APP_VERSION 重新拼，
# 所以「程序 v4.0.0 而文件属性写 3.9」这种事不可能发生。
#
# 为什么挑 build/ 这么个名字容易被 `--clean` 抹掉的地方？两个都查过了：
#  1. `--clean` 在**执行 spec 之前**就把 workpath 清空（PyInstaller `build_main.build()`
#     ：先 remove_tree，第 1213 行才 `exec(code, spec_namespace)`），所以写在 spec 里的
#     这个文件不会被打扫到；
#  2. 而且真正的 workpath 是 `build/PalmDeck/`（`workpath = join(workpath, specnm)`），
#     这里写的 `build/version_info.txt` 根本不在被清的那层里。
# 这样它既不会被误提交（`build/` 已 gitignore），也不会被自己的打包参数删掉。
_version_file = os.path.join(root, "build", "version_info.txt")
_vi.write(_version_file, APP_VERSION)

hiddenimports = [
    "bridge",
    "hotas",
    # 这两个是 v4 新增的 bridge 依赖（配置 / 布局 / 自更新）。
    # Analysis 通常会顺着 start.py→bridge.py 找到，但显式列出更保险：
    # 漏了的话打出来的 exe 一启动就 ImportError。
    "palmdeck_config",
    "palmdeck_layouts",
    # 自检（bridge 与 start.py 都 import）
    "palmdeck_doctor",
    "updater",
    # 系统托盘（Windows 后端动态 import，需显式收进来）
    "pystray._win32",
    # vendored vgamepad（vendor/ 在 pathex 里）
    "vgamepad",
    "vgamepad.win",
    "vgamepad.win.virtual_gamepad",
    "vgamepad.win.vigem_client",
    "vgamepad.win.vigem_commons",
]
datas = [
    (os.path.join(root, "web"), "web"),
    # 托盘图标要能**在运行时读到**（`icon=` 只把图标写成 exe 的资源，不会进包）：
    # start.py 的 _product_icon_path() 按 `packaging/PalmDeck.ico` 找 ——
    # 源码运行是仓库里的那个路径，打包后是 sys._MEIPASS 下的同名路径。
    (os.path.join(root, "packaging", "PalmDeck.ico"), "packaging"),
    # vgamepad 用 ctypes 按相对路径加载 ViGEmClient.dll，必须原样放进包目录
    (
        os.path.join(root, "vendor", "vgamepad", "win", "vigem", "client", "x64", "ViGEmClient.dll"),
        "vgamepad/win/vigem/client/x64",
    ),
    (
        os.path.join(root, "vendor", "vgamepad", "win", "vigem", "client", "x86", "ViGEmClient.dll"),
        "vgamepad/win/vigem/client/x86",
    ),
]
binaries = []

# 这些后端是函数内 try/except 动态 import，PyInstaller 静态扫描会漏，需显式 collect_all
for pkg in ("pyvjoy", "zeroconf", "qrcode", "pystray"):
    try:
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    except Exception:
        pass

a = Analysis(
    [os.path.join(root, "start.py")],
    pathex=[root, os.path.join(root, "vendor")],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="PalmDeck",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    icon=os.path.join(root, "packaging", "PalmDeck.ico"),
    version=_version_file,
)
