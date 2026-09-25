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
import urllib.error
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


# ---- 「检查更新」的结论 ----------------------------------------------------
# 以前只有一个空串表示「没有新版」，于是三种完全不同的情况 —— 「真的是最新」
# 「连不上 GitHub」「仓库根本没发过 Release」—— 在界面上长得一模一样：
# 玩家点「检查更新」，得到的是一句可能是假话的「已是最新版本」。
# 现在把结论和原因分开带出来（`reason` 给机器判，`message` 直接给人看）。
UPD_UPDATE = "update"          # 有新版本，latest 非空
UPD_CURRENT = "current"        # 检查成功，确实已是最新
UPD_DISABLED = "disabled"      # PALMDECK_NO_UPDATE：主动关掉的
UPD_NO_RELEASE = "no_release"  # 仓库还没有任何 Release（GitHub 404）
UPD_OFFLINE = "offline"        # 网络不通 / 被限流 / 返回不可解析


def _upd(ok: bool, reason: str, message: str, latest: str = "") -> dict:
    return {"ok": ok, "reason": reason, "message": message,
            "current": APP_VERSION, "latest": latest}


def check_update_status() -> dict:
    """检查更新，并把「为什么是这个结论」一起带回来。

    `ok` 表示**检查本身**是否成功完成（不是「有没有新版」）；
    `reason` 见上面的 UPD_* 常量；`message` 是可直接显示的中文。
    """
    cur = APP_VERSION
    if os.environ.get("PALMDECK_NO_UPDATE"):
        return _upd(False, UPD_DISABLED, f"已关闭更新检查（当前 v{cur}）")
    try:
        req = urllib.request.Request(
            GITHUB_API,
            headers={"User-Agent": "PalmDeck", "Accept": "application/vnd.github+json"},
        )
        with urllib.request.urlopen(req, timeout=8) as r:
            tag = str(json.loads(r.read().decode("utf-8", "replace")).get("tag_name", ""))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return _upd(False, UPD_NO_RELEASE,
                        f"仓库还没有发布过版本，暂时无法检查（当前 v{cur}）")
        return _upd(False, UPD_OFFLINE,
                    f"检查失败：GitHub 返回 {e.code}（当前 v{cur}）")
    except Exception as e:
        return _upd(False, UPD_OFFLINE,
                    f"检查失败：连不上 GitHub（{type(e).__name__}）（当前 v{cur}）")

    latest = tag.lstrip("vV")
    if _ver_tuple(latest) == (0, 0, 0):
        # tag_name 拿不到或不是版本号：不能猜成「已是最新」
        return _upd(False, UPD_OFFLINE,
                    f"检查失败：远端 tag「{tag}」不是版本号（当前 v{cur}）")
    if _ver_tuple(latest) > _ver_tuple(cur):
        return _upd(True, UPD_UPDATE, f"发现新版本 v{latest}（当前 v{cur}）", latest)
    return _upd(True, UPD_CURRENT, f"已是最新（当前 v{cur}）")


def check_update() -> str:
    """返回远端最新版本号（如 4.1.0）；无更新/离线/出错返回空串。

    想看「为什么」就用 `check_update_status()` —— 这个方法只保留老契约。
    """
    return check_update_status()["latest"]


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
