#!/usr/bin/env python3
"""PalmDeck 自更新：检查 GitHub Release、下载 exe、自替换重启。

从 start.py 抽出，供托盘（start.py）与网页控制台（bridge.py）共用。
只有打包后的 Windows exe 才能自替换；源码运行只检查不替换。
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request

# 发版版本号（唯一来源）。托盘、网页控制台、自更新比较都用它。
#
# 与 bridge.PROTOCOL_VERSION 的关系：**主版本号必须相同**。
#   APP_VERSION    = 发版号      → "4.0.0"  → 用户看到的 / 自更新比较的
#   PROTOCOL_VERSION = 协议/hello 号 → "4.0"    → 写入 hello 帧，App 侧据此协商
# 两者分开是因为：改协议不一定发版（内部迭代），但对外不能出现“程序 v4.0 说协议 3.2”
# 这种自相矛盾。不一致会被 tests/test_version.py 拦下。
#
# 发新版时同步改这里 + 打 tag vX.Y.Z（例如 v4.0.0）。
APP_VERSION = "4.0.0"

GITHUB_API = "https://api.github.com/repos/GITHUBA111/PalmDeck/releases/latest"
GITHUB_EXE = "https://github.com/GITHUBA111/PalmDeck/releases/latest/download/PalmDeck.exe"


def can_self_update() -> bool:
    """只有打包后的 Windows exe 能自替换；其余情况只允许检查更新。"""
    return getattr(sys, "frozen", False) and os.name == "nt"


def _ver_tuple(v: str) -> tuple:
    try:
        return tuple(int(x) for x in v.lstrip("vV").split(".")[:3])
    except Exception:
        return (0, 0, 0)


def check_update() -> str:
    """返回远端最新版本号（如 4.1.0）；无更新/离线/出错返回空串。"""
    if os.environ.get("PALMDECK_NO_UPDATE"):
        return ""
    try:
        req = urllib.request.Request(
            GITHUB_API,
            headers={"User-Agent": "PalmDeck", "Accept": "application/vnd.github+json"},
        )
        with urllib.request.urlopen(req, timeout=8) as r:
            tag = str(json.loads(r.read().decode("utf-8", "replace")).get("tag_name", ""))
        latest = tag.lstrip("vV")
        if _ver_tuple(latest) > _ver_tuple(APP_VERSION):
            return latest
    except Exception:
        pass
    return ""


def apply_update(_newver: str) -> bool:
    """下载新版 exe 到同目录 .new，写 update.bat 自替换重启。"""
    exe_dir = os.path.dirname(os.path.abspath(sys.executable))
    new = os.path.join(exe_dir, "PalmDeck.exe.new")
    bat = os.path.join(exe_dir, "update.bat")
    try:
        req = urllib.request.Request(GITHUB_EXE, headers={"User-Agent": "PalmDeck"})
        total = 0
        with urllib.request.urlopen(req, timeout=120) as r, open(new, "wb") as f:
            while True:
                chunk = r.read(65536)
                if not chunk:
                    break
                f.write(chunk)
                total += len(chunk)
        if total < 1_000_000:  # 防下到 HTML 错误页
            os.remove(new)
            return False
        with open(bat, "w", encoding="ascii") as f:
            f.write(
                "@echo off\r\n"
                ":loop\r\n"
                "timeout /t 1 /nobreak >nul\r\n"
                'tasklist /fi "IMAGENAME eq PalmDeck.exe" 2>nul | find /i "PalmDeck.exe" >nul && goto loop\r\n'
                'del /q "%~dp0PalmDeck.exe"\r\n'
                'move /y "%~dp0PalmDeck.exe.new" "%~dp0PalmDeck.exe"\r\n'
                'start "" "%~dp0PalmDeck.exe"\r\n'
                'del /q "%~dp0update.bat"\r\n'
            )
        return True
    except Exception:
        try:
            os.remove(new)
        except Exception:
            pass
        return False


def restart_after_update() -> None:
    exe_dir = os.path.dirname(os.path.abspath(sys.executable))
    subprocess.Popen(
        ["cmd", "/c", "update.bat"], cwd=exe_dir,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    os._exit(0)
