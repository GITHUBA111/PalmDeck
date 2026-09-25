#!/usr/bin/env python3
"""从 iOS 的 1024×1024 产品图标生成 Windows 用的多尺寸 `PalmDeck.ico`。

为什么要**入库**而不是打包时生成：PyInstaller 的 `icon=` 要一个真文件，
而在 CI 里为了一张图标去 pip 装 Pillow，等于给发版链路多加一个可失败的步骤。
图标几乎不会变，入库最省事。改了源 PNG 就重跑本脚本。

需要 Pillow（Windows 打包环境本来就有：托盘画图用的就是它）：

    python packaging/make_icon.py
"""

from __future__ import annotations

import os
import sys

# 源图就是 App 图标（1024×1024），保证 Windows 与手机上长得一样
SRC = os.path.join(
    "mobile", "ios", "App", "App", "Assets.xcassets",
    "AppIcon.appiconset", "AppIcon-512@2x.png",
)
DST = os.path.join("packaging", "PalmDeck.ico")

# 16=任务栏/文件列表小图标，32=桌面，48=中等图标，256=大图标/预览
SIZES = (16, 24, 32, 48, 64, 128, 256)


def main() -> int:
    try:
        from PIL import Image
    except ImportError:
        print("需要 Pillow：python -m pip install Pillow", file=sys.stderr)
        return 1

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(root, SRC)
    dst = os.path.join(root, DST)
    if not os.path.isfile(src):
        print("找不到源图：%s" % SRC, file=sys.stderr)
        return 1

    im = Image.open(src).convert("RGBA")
    # Pillow 的 ICO 存法会对每个尺寸自己做 LANCZOS 缩放：
    # ≤64 存 BMP 帧、256 存 PNG 帧 —— 正是 Windows 期望的组合。
    im.save(dst, format="ICO", sizes=[(s, s) for s in SIZES])
    print("写入 %s（%d 字节，尺寸 %s）"
          % (DST, os.path.getsize(dst), "/".join(str(s) for s in SIZES)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
