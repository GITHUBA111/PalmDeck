#!/usr/bin/env python3
"""把 Windows 电脑端打包成一个可分发 zip（在任意系统上运行）。"""
from __future__ import annotations

import os
import shutil
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))

FILES = [
    "bridge.py",
    "hotas.py",
    "telemetry.py",
    "palmdeck_config.py",
    "start.py",
    "start.bat",
    "setup_windows.bat",
    "build_exe.bat",
    "requirements.txt",
    "README.md",
    "使用说明.txt",
    os.path.join("packaging", "PalmDeck.spec"),
]
DIRS = ["web"]

OUT_DIR = os.path.join(HERE, "_palmdeck_win", "PalmDeck")
ZIP_PATH = os.path.join(HERE, "PalmDeck-Windows.zip")


def main() -> None:
    if os.path.isdir(OUT_DIR):
        shutil.rmtree(OUT_DIR)
    os.makedirs(OUT_DIR)

    for rel in FILES:
        src = os.path.join(HERE, rel)
        dst = os.path.join(OUT_DIR, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        print(f"  + {rel}")

    for rel in DIRS:
        src = os.path.join(HERE, rel)
        dst = os.path.join(OUT_DIR, rel)
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns(".DS_Store"))
        n = sum(len(f) for _, _, f in os.walk(dst))
        print(f"  + {rel}/ ({n} files)")

    if os.path.exists(ZIP_PATH):
        os.remove(ZIP_PATH)
    with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(os.path.join(HERE, "_palmdeck_win")):
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, os.path.join(HERE, "_palmdeck_win"))
                zf.write(full, rel)

    size = os.path.getsize(ZIP_PATH) / 1024 / 1024
    print(f"\n打包完成：{ZIP_PATH}  ({size:.1f} MB)")
    print("把这个 zip 拷到 Windows 电脑，解压后双击 setup_windows.bat")


if __name__ == "__main__":
    main()
