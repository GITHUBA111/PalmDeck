"""Single PalmDeck config schema. Frozen exe writes beside APPDATA, never _MEIPASS."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

DEFAULTS = {
    "axis_profile": "hotas",
    "http": 8080,
    "ws": 8765,
    "udp": 7773,
    "host": "0.0.0.0",
    "stale_warn_ms": 350,
    "park_ms": 2000,
    "failsafe_throttle": "hold",
    "udp_allowlist": True,
    "allowlist_ttl_ms": 5000,
    "beacon": False,
    "release_xbox_on_infantry": False,
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
        val = raw[key]
        if type(val) is type(default) or (isinstance(default, bool) and isinstance(val, bool)):
            data[key] = val
        elif isinstance(default, int) and isinstance(val, (int, float)) and not isinstance(val, bool):
            data[key] = int(val)
    if data["axis_profile"] not in ("hotas", "fbw"):
        data["axis_profile"] = "hotas"
    if data["failsafe_throttle"] not in ("hold", "center"):
        data["failsafe_throttle"] = "hold"
    return data
