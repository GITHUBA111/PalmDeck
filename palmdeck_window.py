"""O3-full：把网页控制台放进 PalmDeck 自己的窗口（Windows + pywebview / WebView2）。

设计见 `docs/PalmDeck-v4-native-window.md`。这里只做三件事：

1. 探测「真窗口能不能开」：非 Windows / 没装 `pywebview` / 没有 WebView2 Runtime → 不能；
2. 建窗 + 接线：**关闭 = 隐藏回托盘**、**退出 = 销毁**、**几何落盘**；
3. 给托盘一个手柄：`show()` / `quit()`。

**不变量**：任何一层不可用，调用方都能退回 O3-lite（应用窗口 / 默认浏览器）——
`available()` 之外，`open()` 也返回 bool，绝不出现「窗口打不开」。
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from palmdeck_config import config_dir

TITLE = "PalmDeck"
DEFAULT_W, DEFAULT_H = 1000, 720
# 罗技驱动那种窗口不会小于这个：再小三栏（左导航 + 内容 + 状态条）就挤了
MIN_W, MIN_H = 760, 480
GEOMETRY_FILE = "window.json"

# WebView2 Runtime 的 EdgeUpdate client GUID（微软文档里的固定值，不随版本变）
_WEBVIEW2_CLIENT = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"


# ---------------------------------------------------------------- 可用性探测
def platform_ok() -> bool:
    """本方案只对 Windows 开：macOS/Linux 继续走 O3-lite。"""
    return os.name == "nt"


def webview_importable() -> bool:
    try:
        import webview  # noqa: F401
        return True
    except Exception:
        return False


def webview2_installed() -> bool:
    """查 WebView2 Runtime 是否在（Win11 自带；Win10 装 Edge/Office 一般也有）。

    查不到不等于一定不能跑（pywebview 可能有别的后端），但按「查不到就先别用真窗口」
    处理最稳 —— 宁可用 O3-lite，也不要在玩家面前弹一个白框。
    """
    if os.name != "nt":
        return False
    try:
        import winreg
    except Exception:
        return False
    relative = r"Microsoft\EdgeUpdate\Clients\%s" % _WEBVIEW2_CLIENT
    candidates = (
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\%s" % relative),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\%s" % relative),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\%s" % relative),
    )
    for hive, subkey in candidates:
        try:
            with winreg.OpenKey(hive, subkey) as k:
                pv, _ = winreg.QueryValueEx(k, "pv")
            if pv and pv != "0.0.0.0":
                return True
        except OSError:
            continue
    return False


def unavailable_reason() -> str:
    """空串 = 可用；否则是**给人看**的「为什么没上真窗口」（写进日志用）。"""
    if not platform_ok():
        return "非 Windows 平台"
    if not webview_importable():
        return "没装 pywebview"
    if not webview2_installed():
        return "缺 WebView2 Runtime"
    return ""


def available() -> bool:
    return unavailable_reason() == ""


# ---------------------------------------------------------------- 几何持久化
def geometry_path() -> Path:
    # 与 config.json 同目录：卸载保留 %APPDATA%\PalmDeck ⇒ 几何跨更新存活
    return config_dir() / GEOMETRY_FILE


def _clean_geometry(raw) -> "dict | None":
    """越界 / 太小 / 缺字段 = 丢弃（换了显示器不至于把窗口开在屏幕外）。"""
    if not isinstance(raw, dict):
        return None
    try:
        w, h = int(raw["w"]), int(raw["h"])
        x, y = int(raw["x"]), int(raw["y"])
    except (KeyError, TypeError, ValueError):
        return None
    if w < MIN_W or h < MIN_H:
        return None
    if abs(x) > 20000 or abs(y) > 20000:  # 允许负（多显示器在左），但不许离谱
        return None
    return {"w": w, "h": h, "x": x, "y": y}


def load_geometry(path: "Path | None" = None) -> "dict | None":
    p = path or geometry_path()
    try:
        raw = json.loads(Path(p).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return _clean_geometry(raw)


def save_geometry(win, path: "Path | None" = None) -> "dict | None":
    """从窗口读几何并原子写盘；窗口不支持读几何就安静跳过。"""
    try:
        g = {"w": int(win.width), "h": int(win.height),
             "x": int(win.x), "y": int(win.y)}
    except Exception:
        return None
    g = _clean_geometry(g)
    if not g:
        return None
    p = Path(path or geometry_path())
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(g), encoding="utf-8")
        tmp.replace(p)
    except OSError:
        return None
    return g


# ---------------------------------------------------------------- 窗口手柄
class WindowHost:
    """一个窗口的一生：open() → start()（阻塞）→ 托盘的 show()/quit()。

    线程约定：`open()` / `start()` 在**主线程**（pywebview 要求）；
    `show()` / `quit()` 由**托盘线程**调用。
    """

    def __init__(self, url: str, log=None, geo_file=None):
        self.url = url
        self._log = log or (lambda msg: None)
        self._geo_file = geo_file  # None = 默认 %APPDATA%\PalmDeck\window.json
        self._window = None
        self._quitting = False
        self._failed = False

    # ---- 主线程 ----
    def open(self) -> bool:
        """建窗 + 接线事件。False = 建不出来，调用方退回 O3-lite（此时没占用任何资源）。"""
        try:
            import webview
        except Exception as e:
            self._log(f"真窗口不可用（import webview 失败：{e}）")
            return False
        g = load_geometry(self._geo_file)
        kwargs = {"title": TITLE, "url": self.url, "min_size": (MIN_W, MIN_H)}
        if g:
            kwargs.update(width=g["w"], height=g["h"], x=g["x"], y=g["y"])
        else:
            kwargs.update(width=DEFAULT_W, height=DEFAULT_H)
        try:
            win = webview.create_window(**kwargs)
        except Exception as e:
            self._log(f"真窗口创建失败（{e}）")
            return False
        self._window = win
        try:
            win.events.closing += self._on_closing
        except Exception as e:
            self._log(f"真窗口事件接线失败（{e}）")
        return True

    def start(self) -> None:
        """进入 GUI 消息循环（阻塞）。异常不外泄 —— 退回由调用方按 `alive` 判断。"""
        try:
            import webview
            webview.start()
        except Exception as e:
            self._failed = True
            self._window = None
            self._log(f"真窗口启动失败，改用应用窗口/浏览器（{e}）")

    # ---- 托盘线程 ----
    def show(self, frag: str = "") -> bool:
        """显示已有窗口（可带 `#doctor` 之类直达）。False = 没窗口，让调用方走 O3-lite。"""
        win = self._window
        if win is None:
            return False
        try:
            win.show()
            try:
                win.restore()
            except Exception:
                pass
            if frag:
                win.evaluate_js("location.hash=%s" % json.dumps(frag))
            return True
        except Exception as e:
            self._log(f"唤出真窗口失败，改用应用窗口/浏览器（{e}）")
            return False

    def quit(self) -> None:
        """真正退出：放行关闭 + 销毁窗口（GUI 循环随之返回）。"""
        self._quitting = True
        win = self._window
        if win is not None:
            try:
                win.destroy()
            except Exception:
                pass

    @property
    def quitting(self) -> bool:
        return self._quitting

    @property
    def alive(self) -> bool:
        return self._window is not None

    # ---- 事件 ----
    def _on_closing(self) -> bool:
        """× = 最小化回托盘：存几何 → 隐藏 → **返回 False 取消真正关闭**。"""
        win = self._window
        if win is None:
            return True
        save_geometry(win, self._geo_file)
        if self._quitting:
            return True  # 退出流程：放行，让 GUI 循环结束
        try:
            win.hide()
        except Exception:
            # 隐藏都不支持就别拦着：允许关掉，托盘继续跑（进程不退）
            self._window = None
            return True
        return False
