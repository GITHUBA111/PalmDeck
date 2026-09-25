#!/usr/bin/env python3
"""PalmDeck Windows 端「自检」—— 唯一的环境体检真相源。

产品化的那一环：**服务自己说自己缺什么，并一键修**。

托盘（`start.py`）、网页控制台（`bridge.py` 的 `/api/doctor`）、安装脚本
（`setup_windows.bat`）、命令行（`python palmdeck_doctor.py --json`）四处都调这里，
不再各写一遍 `sc query` / `New-NetFirewallRule` / 端口常量。

设计约束（见 `docs/PalmDeck-v4-windows-product.md`）：

- **不 import bridge**（bridge 会 import 本模块，会成环；且 bridge 拉进 hotas/设备依赖）。
  运行期才知道的东西（后端名、设备名、本机 IP、监听是否起来）由调用方通过
  `extra` 传进来；命令行单独跑时这些项报 `info`。
- **非 Windows 不报错**：驱动 / 防火墙在 macOS / Linux 上报 `info`「仅 Windows 需要」，
  这样开发机上能跑同一份报告。
- 所有 Windows 专属调用都 `try/except` 兜底 —— 拿不到状态不能等于「有问题」。
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

from palmdeck_config import BEACON_PORT, config_path, load_config
from updater import APP_VERSION

# ---------------------------------------------------------------- 常量

VJOY_URL = "https://github.com/jshafer817/vJoy/releases/latest"
VIGEM_URL = "https://github.com/nefarius/ViGEmBus/releases/latest"
PYTHON_URL = "https://www.python.org/downloads/"

# 防火墙规则的 DisplayName 前缀；`PalmDeck TCP 8080` 这样拼。
RULE_PREFIX = "PalmDeck"

# 依赖 → (import 名, pip 名, 干什么用的, 只在 Windows 需要?)
DEPENDENCIES = (
    ("qrcode", "qrcode", "控制台的配对二维码", False),
    ("zeroconf", "zeroconf", "Bonjour 自动发现（App 免手填 IP）", False),
    ("pyvjoy", "pyvjoy", "飞行模拟：虚拟摇杆（vJoy）", True),
    ("vgamepad", None, "开车：虚拟 Xbox 手柄（已内置 vendor/）", True),
    ("pystray", "pystray", "系统托盘常驻", True),
    ("PIL", "Pillow", "托盘图标绘制", True),
)

LEVELS = ("ok", "warn", "error", "info")


# ---------------------------------------------------------------- 小工具

def _is_windows() -> bool:
    return os.name == "nt"


def _run(cmd: list, timeout: float = 8.0):
    """跑一个命令，返回 (returncode, stdout+stderr)。失败返回 (None, 原因)。"""
    try:
        p = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0) if _is_windows() else 0,
        )
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as exc:  # 找不到 powershell / 超时 / 权限
        return None, str(exc)


def _powershell(script: str, timeout: float = 10.0):
    return _run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script], timeout)


def _is_admin() -> bool:
    if not _is_windows():
        return False
    try:
        import ctypes
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def _check(**kw) -> dict:
    """造一条检查结果。必须带 id / level / title。"""
    return {
        "id": kw["id"],
        "level": kw["level"],
        "title": kw["title"],
        "detail": kw.get("detail", ""),
        "fix": kw.get("fix", ""),
        "fix_label": kw.get("fix_label", ""),
    }


# ---------------------------------------------------------------- 各检查项

def firewall_ports() -> list:
    """要放行的端口 —— **从配置读**，不再写死在 bat 里。

    返回 `[(协议, 端口, 用途)]`。改控制台端口 → 自检页与一键放行自动跟着变。
    """
    cfg = load_config()
    return [
        ("TCP", int(cfg["http"]), "控制台（浏览器配置页）"),
        ("TCP", int(cfg["ws"]), "控制台实时通道（WebSocket）"),
        ("UDP", int(cfg["udp"]), "手机输入（60Hz 热路径）"),
        ("UDP", int(BEACON_PORT), "自动发现广播（手机找电脑）"),
    ]


def rule_name(proto: str, port: int) -> str:
    return f"{RULE_PREFIX} {proto} {port}"


def firewall_rules() -> list:
    """当前已存在的 PalmDeck 放行规则名（非 Windows / 拿不到 → 空表）。"""
    if not _is_windows():
        return []
    rc, out = _powershell(
        "$r = Get-NetFirewallRule -DisplayName '" + RULE_PREFIX +
        "*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName;"
        " if ($r) { $r -join \"`n\" }"
    )
    if rc is None:
        return []
    return [ln.strip() for ln in (out or "").splitlines() if ln.strip().startswith(RULE_PREFIX)]


def _check_firewall() -> dict:
    wanted = [rule_name(p, n) for p, n, _ in firewall_ports()]
    if not _is_windows():
        return _check(id="firewall", level="info", title="防火墙放行",
                      detail="仅 Windows 需要（当前系统不用管）")
    have = firewall_rules()
    missing = [n for n in wanted if n not in have]
    portlist = "、".join(f"{p} {n}" for p, n, _ in firewall_ports())
    if not missing:
        return _check(id="firewall", level="ok", title="防火墙已放行",
                      detail=f"{portlist}（{len(wanted)} 条规则）")
    return _check(
        id="firewall", level="warn", title="防火墙没放行（手机多半连不上）",
        detail=f"缺 {len(missing)} 条：{'、'.join(missing)}。需要管理员权限，会弹一个授权窗口。",
        fix="firewall", fix_label="一键放行",
    )


def _check_python() -> dict:
    v = "%d.%d.%d" % sys.version_info[:3]
    if sys.version_info >= (3, 9):
        return _check(id="python", level="ok", title="Python 解释器", detail=f"v{v}")
    return _check(id="python", level="warn", title="Python 版本偏低",
                  detail=f"当前 v{v}，建议 3.9+（打包版 exe 不需要 Python）",
                  fix="python", fix_label="打开下载页")


def _check_deps() -> list:
    import importlib.util

    out = []
    for mod, pipname, why, win_only in DEPENDENCIES:
        cid = "dep." + mod.lower()
        if win_only and not _is_windows():
            out.append(_check(id=cid, level="info", title=f"依赖 {mod}",
                              detail=f"{why}（仅 Windows 需要）"))
            continue
        try:
            found = importlib.util.find_spec(mod) is not None
        except Exception:
            found = False
        if found:
            out.append(_check(id=cid, level="ok", title=f"依赖 {mod}", detail=why))
        elif pipname is None:
            out.append(_check(id=cid, level="warn", title=f"依赖 {mod} 缺失",
                              detail=f"{why}；它在 vendor/ 里，重新解压完整 zip 即可"))
        else:
            out.append(_check(
                id=cid, level="warn", title=f"依赖 {mod} 缺失", detail=why,
                fix=cid, fix_label="安装",
            ))
    return out


def _check_backend(extra: dict) -> dict:
    if not extra:
        return _check(id="backend", level="info", title="虚拟手柄设备",
                      detail="服务运行时会报出（命令行自检拿不到）")
    backend = str(extra.get("backend") or "none")
    device = str(extra.get("device") or "—")
    if backend in ("", "none"):
        return _check(id="backend", level="error", title="没有虚拟手柄设备",
                      detail="游戏里不会出现设备。看下面「驱动」两条：vJoy（飞机）"
                             "和 ViGEmBus（开车）至少装一个，装完要重启。")
    return _check(id="backend", level="ok", title="虚拟手柄设备", detail=f"{device}（{backend}）")


def _check_drivers() -> list:
    out = []
    for cid, svc, title, why, url in (
        ("driver.vjoy", "vjoy", "驱动 vJoy", "飞行模拟的虚拟摇杆（HOTAS）", VJOY_URL),
        ("driver.vigembus", "ViGEmBus", "驱动 ViGEmBus", "开车 / 普通游戏的虚拟 Xbox 手柄", VIGEM_URL),
    ):
        if not _is_windows():
            out.append(_check(id=cid, level="info", title=title,
                              detail=f"{why}（仅 Windows 需要）"))
            continue
        rc, out_s = _run(["sc", "query", svc])
        installed = rc == 0 and "RUNNING" in (out_s or "").upper()
        if installed:
            out.append(_check(id=cid, level="ok", title=title, detail=why))
        else:
            out.append(_check(
                id=cid, level="warn", title=f"没装 {title.replace('驱动 ', '')}",
                detail=f"{why}。装完**重启电脑**一次；只想玩其中一种可以忽略另一条。",
                fix=cid, fix_label="打开下载页",
            ))
    return out


def _check_listeners(extra: dict) -> list:
    """监听端口有没有真的起来（端口被别的软件占了 → WS/UDP 悄悄死掉）。"""
    if not extra:
        return [_check(id="listener", level="info", title="监听端口",
                       detail="服务运行时会报出（命令行自检拿不到）")]
    listeners = extra.get("listeners") or {}
    if not listeners:
        return [_check(id="listener", level="info", title="监听端口",
                       detail="服务还在启动中，稍后刷新")]
    labels = {"http": "控制台", "ws": "控制台实时通道", "udp": "手机输入"}
    out = []
    for name, label in labels.items():
        state = listeners.get(name)
        if state is None:
            out.append(_check(id=f"listener.{name}", level="info", title=label,
                              detail="启动中…"))
        elif state.get("ok"):
            out.append(_check(id=f"listener.{name}", level="ok", title=label,
                              detail=f"监听 {state.get('addr') or '—'}"))
        else:
            out.append(_check(
                id=f"listener.{name}", level="error",
                title=f"{label}没起来（端口被占？）",
                detail=f"{state.get('error') or '未知原因'}。"
                       f"换个端口：控制台「配置」页改完保存，然后重启服务。",
            ))
    return out


def _check_lan(extra: dict) -> dict:
    ip = str((extra or {}).get("ip") or "")
    if not ip:
        return _check(id="lan", level="info", title="局域网地址",
                      detail="服务运行时会报出（命令行自检拿不到）")
    if ip.startswith("127.") or ip in ("0.0.0.0", ""):
        return _check(id="lan", level="warn", title="没连上局域网",
                      detail="只看到回环地址 —— 电脑没连 Wi-Fi / 网线？"
                             "手机和电脑必须在同一个网络里。")
    return _check(id="lan", level="ok", title="局域网地址", detail=ip)


# ---------------------------------------------------------------- 报告

def checks(extra: dict | None = None) -> list:
    extra = dict(extra or {})
    out = [_check_python()]
    out.append(_check_backend(extra))
    out += _check_drivers()
    out += _check_deps()
    out += _check_listeners(extra)
    out.append(_check_firewall())
    out.append(_check_lan(extra))
    return out


def report(extra: dict | None = None) -> dict:
    items = checks(extra)
    summary = {lvl: 0 for lvl in LEVELS}
    for it in items:
        summary[it["level"]] = summary.get(it["level"], 0) + 1
    return {
        "app": "PalmDeck",
        "version": APP_VERSION,
        "platform": sys.platform,
        "windows": _is_windows(),
        "config_path": str(config_path()),
        "ports": [{"proto": p, "port": n, "why": why} for p, n, why in firewall_ports()],
        "ok": summary.get("error", 0) == 0,
        "summary": summary,
        "checks": items,
    }


# ---------------------------------------------------------------- 修复

def _elevate(args: list) -> bool:
    """以管理员身份重跑自己（只 Windows）。成功把 UAC 窗口推出去 = True。"""
    if not _is_windows():
        return False
    try:
        import ctypes
        if getattr(sys, "frozen", False):
            exe, params = sys.executable, subprocess.list2cmdline(args)
        else:
            exe = sys.executable
            params = subprocess.list2cmdline([os.path.abspath(__file__)] + args)
        rc = ctypes.windll.shell32.ShellExecuteW(None, "runas", exe, params, None, 1)
        return int(rc) > 32
    except Exception:
        return False


def allow_firewall() -> dict:
    """真正加/刷新防火墙规则（需要管理员）。幂等：先删同名再加。"""
    if not _is_windows():
        return {"ok": False, "message": "仅 Windows 需要放行防火墙"}
    protos = firewall_ports()
    lines = [f"Get-NetFirewallRule -DisplayName '{RULE_PREFIX}*' -ErrorAction SilentlyContinue"
             " | Remove-NetFirewallRule -ErrorAction SilentlyContinue;"]
    for proto, port, why in protos:
        lines.append(
            f"New-NetFirewallRule -DisplayName '{rule_name(proto, port)}'"
            f" -Description '{RULE_PREFIX}: {why}' -Direction Inbound -Action Allow"
            f" -Protocol {proto} -LocalPort {port} -Profile Any | Out-Null;"
        )
    lines.append("'OK'")
    rc, out = _powershell(" ".join(lines), timeout=30.0)
    ok = rc == 0 and "OK" in (out or "")
    msg = "已放行 " + "、".join(f"{p} {n}" for p, n, _ in protos) if ok else \
          f"放行失败：{(out or '').strip()[:200] or '未知错误（没给管理员权限？）'}"
    if not ok:
        _message_box(msg)
    return {"ok": ok, "message": msg}


def _message_box(msg: str, title: str = "PalmDeck 自检") -> None:
    """提权子进程里出错了，得让用户看见（那个黑框一闪就没）。"""
    if not _is_windows():
        return
    try:
        import ctypes
        ctypes.windll.user32.MessageBoxW(None, msg, title, 0x30)
    except Exception:
        pass


def fix(fix_id: str, extra: dict | None = None) -> dict:
    """一键修复。返回 `{ok, message, needs_recheck}`。"""
    import webbrowser

    if fix_id == "firewall":
        if not _is_windows():
            return {"ok": False, "message": "仅 Windows 需要放行防火墙"}
        if _is_admin():
            res = allow_firewall()
            return {**res, "needs_recheck": True}
        if _elevate(["--firewall"]):
            return {"ok": True, "needs_recheck": True,
                    "message": "已弹出管理员授权窗口，点「是」后自动重新体检"}
        return {"ok": False, "message": "提权失败（UAC 被拒绝？）。"
                                        "可以手动以管理员身份运行 PalmDeck 后再点一次。"}

    if fix_id == "driver.vjoy":
        webbrowser.open(VJOY_URL)
        return {"ok": True, "needs_recheck": True,
                "message": "已打开 vJoy 下载页。装完记得重启电脑，然后回来重新体检。"}

    if fix_id == "driver.vigembus":
        webbrowser.open(VIGEM_URL)
        return {"ok": True, "needs_recheck": True,
                "message": "已打开 ViGEmBus 下载页。装完记得重启电脑，然后回来重新体检。"}

    if fix_id == "python":
        webbrowser.open(PYTHON_URL)
        return {"ok": True, "message": "已打开 Python 下载页（安装时记得勾「Add to PATH」）"}

    if fix_id.startswith("dep."):
        mod = fix_id.split(".", 1)[1]
        pipname = next((p for m, p, _w, _o in DEPENDENCIES if m.lower() == mod), None)
        if pipname is None:
            return {"ok": False, "message": f"{mod} 在 vendor/ 里，重新解压完整 zip 即可"}
        cmd = [sys.executable, "-m", "pip", "install", pipname]
        if _is_windows():
            # 用新控制台窗口跑 —— 让用户看到 pip 的输出，而不是黑箱
            try:
                subprocess.Popen(["cmd", "/c", "start", "", "cmd", "/k",
                                  subprocess.list2cmdline(cmd)])
                return {"ok": True, "needs_recheck": True,
                        "message": f"已在新窗口里安装 {pipname}，装完关掉那个窗口再刷新"}
            except Exception as exc:
                return {"ok": False, "message": f"安装失败：{exc}"}
        return {"ok": False, "message": "请手动运行：" + subprocess.list2cmdline(cmd)}

    return {"ok": False, "message": "这一项没有自动修复，按上面的说明手动处理"}


# ---------------------------------------------------------------- CLI

def _format_text(rep: dict) -> str:
    icon = {"ok": "[OK]", "warn": "[! ]", "error": "[X ]", "info": "[i ]"}
    lines = [f"PalmDeck v{rep['version']} 自检 · {rep['platform']}"]
    for it in rep["checks"]:
        lines.append(f"  {icon.get(it['level'], '[?]')} {it['title']}"
                     + (f" — {it['detail']}" if it["detail"] else ""))
    s = rep["summary"]
    lines.append(f"\n  正常 {s.get('ok', 0)} · 提醒 {s.get('warn', 0)} · "
                 f"故障 {s.get('error', 0)} · 说明 {s.get('info', 0)}")
    if s.get("error"):
        lines.append("  有故障项：看上面的 [X]，按提示修复后重跑。")
    elif s.get("warn"):
        lines.append("  有提醒项：不影响启动，但可能影响手机连接或某个游戏。")
    else:
        lines.append("  一切正常：去手机上打开座舱 App。")
    return "\n".join(lines)


def main(argv: list | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    if "--firewall" in argv:
        res = allow_firewall()
        print(res["message"])
        return 0 if res["ok"] else 1

    rep = report()
    if "--json" in argv:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
    else:
        print(_format_text(rep))
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
