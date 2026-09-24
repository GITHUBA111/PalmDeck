"""布局存储：iOS App 的组件布局（按模式），由网页控制台读写或 App 回传。

文件：`%APPDATA%\\PalmDeck\\layouts.json`
结构：`{"schema": 1, "layouts": {"heli": [widget...], "drive": [...], "gamepad": [...]}}`

widget 与 iOS `DeckWidget` 对齐：
`{"id": str, "kind": str, "binding": str, "rect": {"x","y","w","h"}, "label": str}`
没有存储的模式表示「用 App 内置默认布局」。
"""

from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Optional

from palmdeck_config import config_dir

SCHEMA = 1
MODES = ("heli", "drive", "gamepad")

KINDS = ("wheel", "slider", "pad", "button", "stick", "hat", "attitude")
BINDINGS = (
    "roll", "pitch", "yaw", "throttle", "brake", "clutch", "look",
    *(f"vjoy{i}" for i in range(1, 17)),
    "gearUp", "gearDown", "fire",
)

MAX_WIDGETS = 64
_MAX_FILE_BYTES = 1_000_000


def layout_path() -> Path:
    return config_dir() / "layouts.json"


def _coerce_rect(raw) -> dict:
    out = {"x": 0.0, "y": 0.0, "w": 0.2, "h": 0.2}
    if not isinstance(raw, dict):
        return out
    for key in ("x", "y", "w", "h"):
        try:
            out[key] = round(float(raw[key]), 4)
        except (TypeError, ValueError, KeyError):
            pass
    # 允许轻微越界（UI 可自行裁），但限制在合理范围
    for key in ("x", "y", "w", "h"):
        out[key] = max(-1.0, min(2.0, out[key]))
    out["w"] = max(0.02, out["w"])
    out["h"] = max(0.02, out["h"])
    return out


def _coerce_widget(raw) -> Optional[dict]:
    if not isinstance(raw, dict):
        return None
    kind = raw.get("kind")
    binding = raw.get("binding")
    if kind not in KINDS or binding not in BINDINGS:
        return None
    wid = raw.get("id")
    if not isinstance(wid, str) or not wid:
        wid = "w" + uuid.uuid4().hex[:8]
    label = raw.get("label")
    if not isinstance(label, str):
        label = ""
    return {
        "id": wid[:64],
        "kind": kind,
        "binding": binding,
        "rect": _coerce_rect(raw.get("rect")),
        "label": label[:32],
    }


def _coerce_layout(raw) -> list:
    if not isinstance(raw, list):
        return []
    out, seen = [], set()
    for item in raw[:MAX_WIDGETS]:
        w = _coerce_widget(item)
        if w is None:
            continue
        if w["id"] in seen:
            w["id"] = "w" + uuid.uuid4().hex[:8]
        seen.add(w["id"])
        out.append(w)
    return out


def _read_raw() -> dict:
    path = layout_path()
    if not path.is_file():
        return {}
    try:
        if path.stat().st_size > _MAX_FILE_BYTES:
            return {}
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    layouts = data.get("layouts")
    return layouts if isinstance(layouts, dict) else {}


def _write_raw(layouts: dict) -> None:
    path = layout_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps({"schema": SCHEMA, "layouts": layouts}, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        tmp.replace(path)
    except OSError:
        pass


def load_layouts() -> dict:
    """返回所有已存储模式的布局（仅合法项）。"""
    raw = _read_raw()
    out = {}
    for mode in MODES:
        if mode in raw:
            out[mode] = _coerce_layout(raw[mode])
    return out


def get_layout(mode: str) -> Optional[list]:
    if mode not in MODES:
        return None
    raw = _read_raw()
    if mode not in raw:
        return None
    return _coerce_layout(raw[mode])


def save_layout(mode: str, layout) -> Optional[list]:
    if mode not in MODES:
        return None
    raw = _read_raw()
    coerced = _coerce_layout(layout)
    raw[mode] = coerced
    _write_raw(raw)
    return coerced


def save_layouts(mapping) -> dict:
    if not isinstance(mapping, dict):
        return load_layouts()
    raw = _read_raw()
    for mode, layout in mapping.items():
        if mode in MODES:
            raw[mode] = _coerce_layout(layout)
    _write_raw(raw)
    return load_layouts()


def replace_layouts(mapping) -> dict:
    """整包替换所有模式布局（导入配置用）：只保留 mapping 里存在的合法模式。

    与 `save_layouts` 的“合并”不同，这里会丢弃未出现的模式，
    以便精确还原导出时的状态。
    """
    if not isinstance(mapping, dict):
        mapping = {}
    raw = {}
    for mode in MODES:
        if mode in mapping:
            raw[mode] = _coerce_layout(mapping[mode])
    _write_raw(raw)
    return load_layouts()


def delete_layout(mode: str) -> bool:
    if mode not in MODES:
        return False
    raw = _read_raw()
    if mode in raw:
        del raw[mode]
        _write_raw(raw)
    return True


def meta() -> dict:
    return {"schema": SCHEMA, "modes": list(MODES), "kinds": list(KINDS), "bindings": list(BINDINGS)}
