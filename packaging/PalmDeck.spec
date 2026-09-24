# -*- mode: python ; coding: utf-8 -*-
# 在 Windows 上打包：
#   pip install pyinstaller pyvjoy zeroconf qrcode pystray Pillow
#   pyinstaller packaging/PalmDeck.spec
#
# 入口是 start.py（罗技驱动式守护程序：托盘 + 自动更新 + 后台桥接），
# bridge 作为模块被它 import。
#
# 注意：vgamepad 不通过 pip 安装（那个包的 setup.py 会在安装时跑 msiexec 卡死），
# 而是内置在 vendor/vgamepad，下面用 hiddenimports + datas 手工收进来。

from PyInstaller.utils.hooks import collect_all
import os

root = os.path.abspath(os.path.join(SPECPATH, ".."))

hiddenimports = [
    "bridge",
    "hotas",
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
    icon=None,
)
