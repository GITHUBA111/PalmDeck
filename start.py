#!/usr/bin/env python3
"""
PalmDeck 桌面守护程序（罗技驱动式：托盘常驻 + 后台桥接 + 自动更新）

打包后只有一个 PalmDeck.exe：
  1. 启动时查 GitHub Release，有新版本就自替换重启
  2. 单实例：重复双击 = 打开已有实例的控制台
  3. 后台线程跑 bridge（vJoy / Xbox 虚拟设备 + 手机服务）
  4. 系统托盘：打开控制台 / 自检… / 检查更新 / 打开日志 / 开机自启 / 退出
  5. 启动自检有故障时气泡提醒一次（缺驱动 / 防火墙 / 端口被占 —— 见 palmdeck_doctor.py）
  6. 无控制台窗口（日志写到 %APPDATA%\\PalmDeck\\palmdeck.log）
"""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))

# 自更新逻辑抽到 updater.py，供托盘（本文件）与网页控制台（bridge.py）共用
from updater import (  # noqa: E402
    APP_VERSION,
    apply_update,
    check_update_status,
    restart_after_update,
)

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
    """已有实例监听锁端口：收到 'open' 就打开控制台。"""
    while _lock_sock is not None:
        try:
            conn, _ = _lock_sock.accept()
            data = conn.recv(16)
            conn.close()
            if data == b"open":
                open_console()
        except OSError:
            return


# ---------------------------------------------------------------- 开机自启
_AUTOSTART_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
_AUTOSTART_NAME = "PalmDeck"


def _exe_path() -> str:
    # frozen（PyInstaller）与非 frozen 都指向当前可执行文件 / 解释器路径
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
def http_url(frag: str = "") -> str:
    try:
        from palmdeck_config import load_config
        return f"http://127.0.0.1:{load_config()['http']}/{frag}"
    except Exception:
        return f"http://127.0.0.1:8080/{frag}"


# 能用 `--app=<url>` 打开的浏览器（Edge 优先：Win10/11 自带）。
# 打开的窗口没有地址栏 / 标签栏 / 后退键，观感接近原生程序 —— 这就是 O3-lite。
_APP_MODE_BROWSERS = ("msedge.exe", "chrome.exe")
_APP_PATHS_KEY = r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
# 注册表被精简 / App Paths 缺失时的兜底位置（相对各环境变量）
_BROWSER_FALLBACKS = (
    ("ProgramFiles(x86)", r"Microsoft\Edge\Application\msedge.exe"),
    ("ProgramFiles", r"Microsoft\Edge\Application\msedge.exe"),
    ("ProgramFiles", r"Google\Chrome\Application\chrome.exe"),
    ("ProgramFiles(x86)", r"Google\Chrome\Application\chrome.exe"),
    ("LOCALAPPDATA", r"Google\Chrome\Application\chrome.exe"),
)


def _browser_exe() -> "str | None":
    """找一个能用应用窗口模式打开的浏览器；找不到返回 None（退回默认浏览器）。"""
    if os.name != "nt":
        return None
    # 1) App Paths：不管装在哪儿都能查到（微软官方推荐的发现方式）
    try:
        import winreg
        for name in _APP_MODE_BROWSERS:
            for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
                try:
                    with winreg.OpenKey(hive, f"{_APP_PATHS_KEY}\\{name}") as k:
                        path, _ = winreg.QueryValueEx(k, None)
                    if path and os.path.isfile(path):
                        return path
                except OSError:
                    continue
    except Exception:
        pass
    # 2) 常见安装位置
    for env, tail in _BROWSER_FALLBACKS:
        base = os.environ.get(env)
        if base:
            path = os.path.join(base, tail)
            if os.path.isfile(path):
                return path
    # 3) PATH 里能找到也行
    import shutil
    for name in _APP_MODE_BROWSERS:
        found = shutil.which(name)
        if found:
            return found
    return None


def open_console(frag: str = "") -> None:
    """打开网页控制台：优先 Edge/Chrome 的**应用窗口**（无地址栏），否则用默认浏览器。

    绝不让「没装 Edge」变成「控制台打不开」—— 所以每一层失败都往下退。
    """
    url = http_url(frag)
    exe = _browser_exe()
    if exe:
        try:
            # 别用 webbrowser：它可能当成普通标签页打开，也拿不到 --app
            subprocess.Popen([exe, f"--app={url}"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except Exception as e:
            log(f"应用窗口打开失败（{e}），改用默认浏览器")
    import webbrowser
    webbrowser.open(url)


def _product_icon_path() -> str:
    """打包后图标在 sys._MEIPASS，源码运行在仓库里 —— 相对路径两边一样。"""
    base = getattr(sys, "_MEIPASS", None) or HERE
    return os.path.join(base, "packaging", "PalmDeck.ico")


def make_icon_image():
    """托盘图标：优先用**产品图标**（与 exe / 手机同一个），取不到才退回自绘方向盘。

    以前托盘是 PIL 画的一个青色方向盘，跟 exe 图标不是同一个视觉 ——
    同一台电脑上出现两个 logo，正是「不像一个软件」的症状之一。
    自绘这条路保留着：源码目录里没生成 .ico 时也不至于托盘空白。
    """
    try:
        from PIL import Image
        path = _product_icon_path()
        if os.path.isfile(path):
            # .ico 里最大那帧是 256，直接缩到托盘尺寸
            return Image.open(path).convert("RGBA").resize((64, 64), Image.LANCZOS)
    except Exception as e:
        log(f"产品图标不可用（{e}），托盘退回自绘图标")
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


def notify_doctor(icon) -> None:  # noqa: ANN001
    """启动后如果自检有故障，气泡提醒一次（别让用户自己发现“游戏里没设备”）。"""
    time.sleep(2.5)  # 等 bridge 把设备 / 监听探完
    try:
        import bridge
        import palmdeck_doctor as doctor
        rep = doctor.report(bridge.doctor_extra())
    except Exception:
        return
    bad = [c for c in rep["checks"] if c["level"] == "error"]
    if not bad:
        return
    try:
        icon.notify(f"{bad[0]['title']} —— 点托盘图标 → 自检…", "PalmDeck")
    except Exception:
        pass


def run_tray() -> None:
    try:
        import pystray
    except Exception as e:
        log(f"托盘不可用（{e}）")
        run_headless()
        return

    def open_console_item(icon, item):  # noqa: ANN001
        open_console()

    def open_doctor(icon, item):  # noqa: ANN001
        open_console("#doctor")

    def open_log(icon, item):  # noqa: ANN001
        p = os.path.join(appdata_dir(), "PalmDeck", "palmdeck.log")
        try:
            os.startfile(p)  # type: ignore[attr-defined]  # Windows 专用
        except Exception:
            pass

    def check_update_manual(icon, item):  # noqa: ANN001
        st = check_update_status()
        # 结果**同时**写日志：Windows 的通知气泡可能被系统静默（专注助手 / 通知关了），
        # 只靠 notify 的话玩家点了「检查更新」会感觉「没反应」。日志里永远查得到。
        log("更新检查：" + st["message"])
        if st["reason"] == "update":
            icon.notify(st["message"] + "，正在下载…", "PalmDeck")
            if apply_update(st["latest"]):
                icon.notify("更新完成，即将重启", "PalmDeck")
                restart_after_update()
            else:
                icon.notify("更新下载失败，请稍后再试", "PalmDeck")
        else:
            icon.notify(st["message"], "PalmDeck")

    def toggle_autostart(icon, item):  # noqa: ANN001
        set_autostart(not autostart_enabled())

    def quit_app(icon, item):  # noqa: ANN001
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem("打开控制台", open_console_item, default=True),
        pystray.MenuItem("自检…", open_doctor),
        pystray.MenuItem("检查更新", check_update_manual),
        pystray.MenuItem("打开日志", open_log),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("开机自启", toggle_autostart,
                         checked=lambda item: autostart_enabled()),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("退出", quit_app),
    )
    icon = pystray.Icon("PalmDeck", make_icon_image(), f"PalmDeck v{APP_VERSION} — 掌舵舱", menu)
    threading.Thread(target=notify_doctor, args=(icon,), daemon=True).start()
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
        st = check_update_status()
        if st["reason"] == "update":
            log(st["message"] + "，自动更新…")
            if apply_update(st["latest"]):
                log("更新完成，正在重启")
                restart_after_update()
            else:
                log("自动更新失败，继续用当前版本")
        elif not st["ok"]:
            # 「为什么这次没更新」也留一条：排查「收不到更新」时全靠它
            log("启动时跳过自动更新：" + st["message"])

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

    # 4. 托盘常驻。CI / 无人值守可用 PALMDECK_NO_TRAY=1 跳过（与 PALMDECK_NO_UPDATE 同款式）：
    # 没这个开关，「装完能启动吗」在自动化里没法验 —— 托盘会让冒烟测试飘。
    if os.environ.get("PALMDECK_NO_TRAY"):
        log("PALMDECK_NO_TRAY 已设：不启动托盘，无界面运行")
        run_headless()
        return
    run_tray()


if __name__ == "__main__":
    main()
