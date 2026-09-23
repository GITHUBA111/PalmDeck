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

import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))

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


def main() -> None:
    os.chdir(HERE)
    print()
    print("=" * 46)
    print("   PalmDeck 掌舵舱 · 一键启动")
    print("=" * 46)
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
