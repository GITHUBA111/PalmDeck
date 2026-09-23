# -*- mode: python ; coding: utf-8 -*-
# 在 Windows 上打包：
#   pip install pyinstaller pyvjoy zeroconf qrcode
#   pyinstaller packaging/PalmDeck.spec
#
# 注意：vgamepad 不通过 pip 安装（那个包的 setup.py 会在安装时跑 msiexec 卡死），
# 而是内置在 vendor/vgamepad，下面用 hiddenimports + datas 手工收进来。

from PyInstaller.utils.hooks import collect_all
import os

root = os.path.abspath(os.path.join(SPECPATH, ".."))

hiddenimports = [
    "hotas",
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
for pkg in ("pyvjoy", "zeroconf", "qrcode"):
    try:
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    except Exception:
        pass

a = Analysis(
    [os.path.join(root, "bridge.py")],
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
    console=True,
    icon=None,
)
