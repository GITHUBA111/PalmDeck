#!/usr/bin/env python3
"""把 Windows 电脑端打包成一个可分发 zip（在任意系统上运行）。"""
from __future__ import annotations

import ast
import os
import shutil
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))

# 真正的入口（spec 打包 start.py，start.py 又 import bridge）
ENTRYPOINTS = ("start.py", "bridge.py")

FILES = [
    "bridge.py",
    "hotas.py",
    "palmdeck_config.py",
    "palmdeck_layouts.py",
    "updater.py",
    "start.py",
    "start.bat",
    "setup_windows.bat",
    "build_exe.bat",
    "requirements.txt",
    "README.md",
    "使用说明.txt",
    os.path.join("packaging", "PalmDeck.spec"),
]
DIRS = ["web", "vendor"]

OUT_DIR = os.path.join(HERE, "_palmdeck_win", "PalmDeck")
ZIP_PATH = os.path.join(HERE, "PalmDeck-Windows.zip")


def local_modules() -> set:
    """入口脚本 import 到的同目录模块。

    用 ast 静态扫，不真的 import —— 真 import 需要 pyvjoy/vgamepad 等
    Windows 专有依赖，而本脚本要在任意系统上跑。

    为什么需要它：`FILES` 是手写的，v4 加了 palmdeck_layouts.py / updater.py
    但忘了往这里加，打出来的 zip 在 Windows 上一启动就 ImportError。
    下面 `verify()` 会在打包前直接拦下来。
    """
    available = {
        os.path.splitext(f)[0]
        for f in os.listdir(HERE)
        if f.endswith(".py") and f != os.path.basename(__file__)
    }
    found = set()
    for entry in ENTRYPOINTS:
        with open(os.path.join(HERE, entry), encoding="utf-8") as fh:
            tree = ast.parse(fh.read(), filename=entry)
        for node in ast.walk(tree):
            names = []
            if isinstance(node, ast.Import):
                names = [a.name.split(".")[0] for a in node.names]
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                names = [node.module.split(".")[0]]
            for n in names:
                if n in available:
                    found.add(n)
    return found


def verify() -> None:
    """打包前自检：入口 import 的每个同目录模块都必须在 FILES 里。"""
    missing = sorted(
        m + ".py" for m in local_modules() if m + ".py" not in FILES
    )
    if missing:
        raise SystemExit(
            "打包清单缺文件：" + "、".join(missing) + "\n"
            "这些是 start.py / bridge.py 直接 import 的同目录模块，"
            "漏掉的话 Windows 端一启动就 ImportError。请补进 FILES。"
        )
    for rel in FILES:
        if not os.path.exists(os.path.join(HERE, rel)):
            raise SystemExit(f"打包清单里的文件不存在：{rel}")


def main() -> None:
    verify()
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
