#!/usr/bin/env python3
"""
PalmDeck 桌面守护程序（罗技驱动式：托盘常驻 + 后台桥接 + 自动更新）

打包后只有一个 PalmDeck.exe：
  1. 启动时查 GitHub Release，有新版本就自替换重启
  2. 单实例：重复双击 = 打开已有实例的控制台
  3. 后台线程跑 bridge（vJoy / Xbox 虚拟设备 + 手机服务）
  4. 系统托盘：打开控制台 / 检查更新 / 开机自启 / 退出
  5. 无控制台窗口（日志写到 %APPDATA%\\PalmDeck\\palmdeck.log）
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

# 打包进 exe 的本地版本号；发新版时同步改这里 + 打 tag vX.Y.Z
APP_VERSION = "0.3.2"

GITHUB_API = "https://api.github.com/repos/GITHUBA111/PalmDeck/releases/latest"
GITHUB_EXE = "https://github.com/GITHUBA111/PalmDeck/releases/latest/download/PalmDeck.exe"

# 单实例锁（同时充当"重复双击→打开控制台"的命令通道）
LOCK_HOST, LOCK_PORT = "127.0.0.1", 47800
_lock_sock: "socket.socket | None" = None

# vgamepad 内置在 vendor/（详见 hotas.py 顶部注释），无需 pip 安装
if not getattr(sys, "frozen", False):
    _vendor = os.path.join(HERE, "vendor")
    if os.path.isdir(_vendor) and _vendor not in sys.path:
        sys.path.insert(0, _vendor)


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def appdata_dir() -> str:
    if os.name == "nt":
        return os.environ.get("APPDATA") or os.path.join(os.path.expanduser("~"), "AppData", "Roaming")
    return os.path.expanduser("~")


def redirect_stdio() -> None:
    """无控制台打包（console=False）时 stdout/stderr 是 None，重定向到日志文件。"""
    if not getattr(sys, "frozen", False):
        return
    try:
        log_dir = os.path.join(appdata_dir(), "PalmDeck")
        os.makedirs(log_dir, exist_ok=True)
        f = open(os.path.join(log_dir, "palmdeck.log"), "a", encoding="utf-8", buffering=1)
        sys.stdout = f
        sys.stderr = f
    except Exception:
        pass


# ---------------------------------------------------------------- 依赖
def pip_install(*pkgs: str) -> bool:
    for pkg in pkgs:
        try:
            log(f"  安装 {pkg} …")
            subprocess.check_call(
                [sys.executable, "-m", "pip", "install", "--quiet", pkg],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception:
            log(f"  ! {pkg} 安装失败（可稍后手动装）")
            return False
    return True


def ensure_deps() -> None:
    """源码运行时按需装依赖；打包版依赖已内置，跳过 pip。"""
    if getattr(sys, "frozen", False):
        return
    log("[依赖] 检查 …")
    if os.name == "nt":
        try:
            import vgamepad  # noqa: F401
            log("  OK  vgamepad（内置，虚拟 Xbox 手柄）")
        except Exception:
            log("  ! vgamepad 加载失败（检查 vendor/ 是否完整）")
        try:
            import pyvjoy  # noqa: F401
            log("  OK  pyvjoy（虚拟摇杆）")
        except Exception:
            pip_install("pyvjoy")
        # 托盘（Windows 桌面守护程序核心）
        try:
            import pystray  # noqa: F401
            import PIL  # noqa: F401
            log("  OK  pystray+PIL（系统托盘）")
        except Exception:
            pip_install("pystray", "Pillow")
    try:
        import qrcode  # noqa: F401
    except Exception:
        pip_install("qrcode")
    try:
        import zeroconf  # noqa: F401
        log("  OK  zeroconf（Bonjour 自动发现）")
    except Exception:
        pip_install("zeroconf")


# ---------------------------------------------------------------- 自动更新
def _ver_tuple(v: str) -> tuple:
    try:
        return tuple(int(x) for x in v.lstrip("vV").split(".")[:3])
    except Exception:
        return (0, 0, 0)


def check_update() -> str:
    """返回远端最新版本号（如 0.4.0）；无更新/离线/出错返回空串。"""
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


# ---------------------------------------------------------------- 单实例 + 命令通道
def acquire_single_instance() -> bool:
    """绑定回环端口。成功=首个实例；失败=已有实例在跑。"""
    global _lock_sock
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((LOCK_HOST, LOCK_PORT))
        s.listen(1)
        _lock_sock = s
        return True
    except OSError:
        return False


def notify_existing() -> bool:
    """通知已有实例打开控制台（重复双击 exe 的体验）。"""
    try:
        c = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        c.settimeout(2)
        c.connect((LOCK_HOST, LOCK_PORT))
        c.sendall(b"open")
        c.close()
        return True
    except OSError:
        return False


def lock_command_loop() -> None:
    """已有实例监听锁端口：收到 'open' 就打开浏览器控制台。"""
    import webbrowser
    while _lock_sock is not None:
        try:
            conn, _ = _lock_sock.accept()
            data = conn.recv(16)
            conn.close()
            if data == b"open":
                webbrowser.open(http_url())
        except OSError:
            return


# ---------------------------------------------------------------- 开机自启
_AUTOSTART_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
_AUTOSTART_NAME = "PalmDeck"


def _exe_path() -> str:
    if getattr(sys, "frozen", False):
        return sys.executable
    return sys.executable


def autostart_enabled() -> bool:
    if os.name != "nt":
        return False
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, _AUTOSTART_KEY, 0, winreg.KEY_READ) as k:
            winreg.QueryValueEx(k, _AUTOSTART_NAME)
            return True
    except Exception:
        return False


def set_autostart(enable: bool) -> None:
    if os.name != "nt":
        return
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, _AUTOSTART_KEY, 0, winreg.KEY_SET_VALUE)
        if enable:
            winreg.SetValueEx(key, _AUTOSTART_NAME, 0, winreg.REG_SZ, f'"{_exe_path()}"')
        else:
            try:
                winreg.DeleteValue(key, _AUTOSTART_NAME)
            except FileNotFoundError:
                pass
    except Exception as e:
        log(f"开机自启设置失败: {e}")


# ---------------------------------------------------------------- 托盘
def http_url() -> str:
    try:
        from palmdeck_config import load_config
        return f"http://127.0.0.1:{load_config()['http']}/"
    except Exception:
        return "http://127.0.0.1:8080/"


def make_icon_image():
    """用 PIL 画一个方向盘图标（无外部图片依赖）。"""
    from PIL import Image, ImageDraw
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cyan = (80, 200, 255, 255)
    d.ellipse([8, 8, 56, 56], outline=cyan, width=5)          # 外圈
    d.ellipse([25, 25, 39, 39], fill=cyan)                    # 中心毂
    d.line([32, 32, 32, 10], fill=cyan, width=4)              # 上辐条
    d.line([32, 32, 13, 47], fill=cyan, width=4)              # 左下辐条
    d.line([32, 32, 51, 47], fill=cyan, width=4)              # 右下辐条
    return img


def start_bridge() -> None:
    import bridge
    try:
        # argv 是不含程序名的参数列表（argparse 惯例）；守护程序用默认配置即可
        bridge.main(argv=[])
    except SystemExit:
        pass
    except Exception as e:
        log(f"bridge 异常退出: {e!r}（详见日志；可尝试退出后重新双击）")


def run_headless() -> None:
    log("（托盘不可用，无界面运行；结束进程即退出）")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass


def run_tray() -> None:
    try:
        import pystray
    except Exception as e:
        log(f"托盘不可用（{e}）")
        run_headless()
        return

    def open_console(icon, item):  # noqa: ANN001
        import webbrowser
        webbrowser.open(http_url())

    def open_log(icon, item):  # noqa: ANN001
        p = os.path.join(appdata_dir(), "PalmDeck", "palmdeck.log")
        try:
            os.startfile(p)  # type: ignore[attr-defined]  # Windows 专用
        except Exception:
            pass

    def check_update_manual(icon, item):  # noqa: ANN001
        newver = check_update()
        if newver:
            icon.notify(f"发现新版本 v{newver}，正在下载…", "PalmDeck")
            if apply_update(newver):
                icon.notify("更新完成，即将重启", "PalmDeck")
                restart_after_update()
            else:
                icon.notify("更新下载失败，请稍后再试", "PalmDeck")
        else:
            icon.notify(f"已是最新版本 v{APP_VERSION}", "PalmDeck")

    def toggle_autostart(icon, item):  # noqa: ANN001
        set_autostart(not autostart_enabled())

    def quit_app(icon, item):  # noqa: ANN001
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem("打开控制台", open_console, default=True),
        pystray.MenuItem("检查更新", check_update_manual),
        pystray.MenuItem("打开日志", open_log),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("开机自启", toggle_autostart,
                         checked=lambda item: autostart_enabled()),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("退出", quit_app),
    )
    icon = pystray.Icon("PalmDeck", make_icon_image(), "PalmDeck 掌舵舱", menu)
    try:
        icon.run()
    except Exception as e:
        log(f"托盘运行失败（{e}），转无界面模式")
        run_headless()


# ---------------------------------------------------------------- main
def main() -> None:
    redirect_stdio()
    log(f"PalmDeck 守护程序 v{APP_VERSION} 启动")

    # 1. 自动更新（仅 Windows 打包版，源码运行不自我替换）
    if getattr(sys, "frozen", False) and os.name == "nt":
        newver = check_update()
        if newver:
            log(f"发现新版本 v{newver}（当前 v{APP_VERSION}），自动更新…")
            if apply_update(newver):
                log("更新完成，正在重启")
                restart_after_update()
            else:
                log("自动更新失败，继续用当前版本")

    ensure_deps()

    # 2. 单实例
    if not acquire_single_instance():
        log("已有实例在运行，通知其打开控制台后退出")
        notify_existing()
        return

    # 3. 启动 bridge（后台线程）
    log("启动桥接（vJoy / Xbox 虚拟设备 + 手机服务）…")
    threading.Thread(target=start_bridge, daemon=True).start()
    threading.Thread(target=lock_command_loop, daemon=True).start()

    # 4. 托盘常驻
    run_tray()


if __name__ == "__main__":
    main()
