"""Single PalmDeck config schema. Frozen exe writes beside APPDATA, never _MEIPASS.

`load_config()` 读；`save_config(patch)` 校验后原子写回。网页控制台通过
bridge 的 `/api/config` 调用这里。
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

DEFAULTS = {
    # 网络（改动需重启）
    "host": "0.0.0.0",
    "http": 8080,
    "ws": 8765,
    "udp": 7773,
    "udp_allowlist": True,
    "allowlist_ttl_ms": 5000,
    "beacon": True,
    "bonjour": True,
    # 轴 / 设备（可热生效）
    "axis_profile": "hotas",
    "failsafe_throttle": "hold",
    "park_ms": 2000,
}

# 可在运行中热生效的键（其余改动提示重启）
LIVE_KEYS = ("axis_profile", "failsafe_throttle", "udp_allowlist", "allowlist_ttl_ms", "park_ms")
# 需要重启才能生效的键
RESTART_KEYS = ("host", "http", "ws", "udp", "beacon", "bonjour")

_ENUMS = {
    "axis_profile": ("hotas", "fbw"),
    "failsafe_throttle": ("hold", "center"),
}


def config_dir() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "PalmDeck"
    if os.name == "nt":
        root = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        return Path(root) / "PalmDeck"
    return Path.home() / ".config" / "PalmDeck"


def config_path() -> Path:
    return config_dir() / "config.json"


def _coerce(key: str, default, val):
    """按默认值类型强转；无法转换或不在 schema 内返回 default。"""
    if isinstance(default, bool):
        if isinstance(val, bool):
            return val
        if isinstance(val, (int, float)):
            return bool(val)
        if isinstance(val, str):
            return val.strip().lower() in ("1", "true", "yes", "on", "是")
        return default
    if isinstance(default, int) and not isinstance(default, bool):
        if isinstance(val, bool):
            return default
        try:
            return int(val)
        except (TypeError, ValueError):
            return default
    if isinstance(default, str):
        return val if isinstance(val, str) else default
    return val if type(val) is type(default) else default


def _validate(data: dict) -> dict:
    for key, allowed in _ENUMS.items():
        if data.get(key) not in allowed:
            data[key] = DEFAULTS[key]
    for key in ("http", "ws", "udp"):
        try:
            data[key] = max(1, min(65535, int(data[key])))
        except (TypeError, ValueError, KeyError):
            data[key] = DEFAULTS[key]
    try:
        data["park_ms"] = max(200, int(data["park_ms"]))
    except (TypeError, ValueError, KeyError):
        data["park_ms"] = DEFAULTS["park_ms"]
    try:
        data["allowlist_ttl_ms"] = max(500, int(data["allowlist_ttl_ms"]))
    except (TypeError, ValueError, KeyError):
        data["allowlist_ttl_ms"] = DEFAULTS["allowlist_ttl_ms"]
    if not isinstance(data.get("host"), str) or not data["host"]:
        data["host"] = DEFAULTS["host"]
    return data


def load_config() -> dict:
    data = dict(DEFAULTS)
    path = config_path()
    if not path.is_file():
        return data
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return data
    if not isinstance(raw, dict):
        return data
    for key, default in DEFAULTS.items():
        if key not in raw:
            continue
        data[key] = _coerce(key, default, raw[key])
    return _validate(data)


def save_config(patch: dict) -> dict:
    """把 patch 合并进 config.json（忽略未知键），返回生效后的完整配置。"""
    data = load_config()
    if isinstance(patch, dict):
        for key, val in patch.items():
            if key not in DEFAULTS:
                continue
            data[key] = _coerce(key, DEFAULTS[key], val)
    data = _validate(data)
    path = config_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass
    return data
