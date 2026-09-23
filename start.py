#!/usr/bin/env python3
"""
PalmDeck 一键启动器（自己玩专用）

双击 start.py 即可：
  1. 检查 Python 依赖（缺了就自动装）
  2. 检查虚拟手柄后端（pyvjoy / vgamepad）
  3. 启动 bridge.py
  4. 打印手机连接地址

不想看命令行就双击 start.bat。
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

# 打包进 exe 的本地版本号；发新版时同步改这里 + 打 tag vX.Y.Z
APP_VERSION = "0.3.0"

# vgamepad 内置在 vendor/（详见 hotas.py 顶部注释），无需 pip 安装
if not getattr(sys, "frozen", False):
    _vendor = os.path.join(HERE, "vendor")
    if os.path.isdir(_vendor) and _vendor not in sys.path:
        sys.path.insert(0, _vendor)


def pip_install(*pkgs: str) -> bool:
    for pkg in pkgs:
        try:
            print(f"  安装 {pkg} …")
            subprocess.check_call(
                [sys.executable, "-m", "pip", "install", "--quiet", pkg],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception:
            print(f"  ! {pkg} 安装失败（可稍后手动装）")
            return False
    return True


def ensure_deps() -> None:
    print("[1/3] 检查依赖 …")
    # 基础：标准库足够。虚拟设备后端按平台推荐。
    if os.name == "nt":
        try:
            import vgamepad  # noqa: F401
            print("  OK  vgamepad（内置，虚拟 Xbox 手柄）")
        except Exception:
            print("  ! vgamepad 加载失败（检查 vendor/ 是否完整）")
        try:
            import pyvjoy  # noqa: F401
            print("  OK  pyvjoy（虚拟摇杆）")
        except Exception:
            pip_install("pyvjoy")
    else:
        print("  （非 Windows：按需安装 evdev / vgamepad）")
    # 二维码（可选，装了就打印）
    try:
        import qrcode  # noqa: F401
    except Exception:
        pip_install("qrcode")
    # Bonjour 自动发现（强烈建议：iOS 端靠它发现电脑）
    try:
        import zeroconf  # noqa: F401
        print("  OK  zeroconf（Bonjour 自动发现）")
    except Exception:
        pip_install("zeroconf")
    print()


GITHUB_API = "https://api.github.com/repos/GITHUBA111/PalmDeck/releases/latest"
GITHUB_EXE = "https://github.com/GITHUBA111/PalmDeck/releases/latest/download/PalmDeck.exe"


def _ver_tuple(v: str) -> tuple:
    try:
        return tuple(int(x) for x in v.lstrip("vV").split(".")[:3])
    except Exception:
        return (0, 0, 0)


def check_update() -> str:
    """返回远端最新版本号（如 0.3.1）；无更新/离线/出错返回空串。"""
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


def main() -> None:
    os.chdir(HERE)
    print()
    print("=" * 46)
    print("   PalmDeck 掌舵舱 · 一键启动")
    print("=" * 46)
    # 自动更新：仅 Windows 打包版（源码运行不自我替换）
    if getattr(sys, "frozen", False) and os.name == "nt":
        newver = check_update()
        if newver:
            print(f"\n  发现新版本 v{newver}（当前 v{APP_VERSION}），自动更新中…")
            if apply_update(newver):
                print("  更新完成，正在重启。")
                subprocess.Popen(
                    ["cmd", "/c", "update.bat"],
                    cwd=os.path.dirname(os.path.abspath(sys.executable)),
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
                os._exit(0)
            else:
                print("  自动更新失败，继续用当前版本。")
        else:
            print(f"  （v{APP_VERSION} · 已是最新）")
    ensure_deps()
    print("[2/3] 启动电脑端 …")
    print("[3/3] 手机连同一 Wi-Fi，App 里点连接或自动发现")
    print()
    time.sleep(0.5)
    try:
        subprocess.call([sys.executable, os.path.join(HERE, "bridge.py")])
    except KeyboardInterrupt:
        pass
    print("\n已退出。按回车关闭。")
    try:
        input()
    except EOFError:
        pass


if __name__ == "__main__":
    main()
