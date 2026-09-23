# -*- mode: python ; coding: utf-8 -*-
# 在 Windows 上打包：
#   pip install pyinstaller pyvjoy vgamepad zeroconf qrcode
#   pyinstaller packaging/PalmDeck.spec

from PyInstaller.utils.hooks import collect_all
import os

root = os.path.abspath(os.path.join(SPECPATH, ".."))

hiddenimports = ["hotas"]
datas = [(os.path.join(root, "web"), "web")]
binaries = []

# 这些后端都是函数内 try/except 动态 import，PyInstaller 静态扫描会漏，
# 必须显式 collect_all 才能打进 exe（缺了 exe 会 backend=none）。
for pkg in ("pyvjoy", "vgamepad", "zeroconf", "qrcode"):
    try:
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    except Exception:
        pass

a = Analysis(
    [os.path.join(root, "bridge.py")],
    pathex=[root],
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
