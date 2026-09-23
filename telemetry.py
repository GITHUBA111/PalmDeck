"""游戏遥测读取（可选）。

默认无遥测。若游戏支持数据输出，实现一个 TelemetrySource 并注册即可，
bridge 会定期调用 `poll()` 拿到飞机真实姿态，通过 WebSocket 广播给手机，
手机端「3D 显示源 = 游戏遥测」时用真实姿态驱动 3D 模型。

统一输出格式（所有来源都归一化到这里）：
    {"roll": -1..1, "pitch": -1..1, "yaw": -1..1, "valid": true, "source": "name"}
角度约定与手机端杆位一致：roll/pitch/yaw 都是 [-1,1]（满舵 = ±1），
手机端再乘各自满舵角度（90°/90°/180°）。
"""

from __future__ import annotations

import json
import socket
import threading
import time
import urllib.request
from typing import Optional


class TelemetrySource:
    """遥测来源基类。子类实现 poll() 返回姿态 dict 或 None。"""

    name = "none"

    def start(self) -> None:
        pass

    def stop(self) -> None:
        pass

    def poll(self) -> Optional[dict]:
        return None


class NoTelemetry(TelemetrySource):
    name = "none"


class HttpJsonTelemetry(TelemetrySource):
    """通用 HTTP-JSON 遥测：定期 GET 一个 URL，从 JSON 里取 roll/pitch/yaw。
    类似 War Thunder 的 http://localhost:8111/ 风格。

    --telemetry-url http://127.0.0.1:8111/
    --telemetry-map roll=state.roll,pitch=state.pitch,yaw=state.heading
    """

    name = "http"

    def __init__(self, url: str, field_map: Optional[dict] = None) -> None:
        self.url = url
        self.field_map = field_map or {}

    def poll(self) -> Optional[dict]:
        try:
            with urllib.request.urlopen(self.url, timeout=0.3) as r:
                data = json.loads(r.read().decode("utf-8", "ignore"))
        except Exception:
            return None
        return _extract(data, self.field_map, self.name)


class UdpJsonTelemetry(TelemetrySource):
    """通用 UDP-JSON 遥测：监听本地端口，收 JSON 包。
    --telemetry-udp 49000
    """

    name = "udp"

    def __init__(self, port: int, field_map: Optional[dict] = None) -> None:
        self.port = port
        self.field_map = field_map or {}
        self._sock: Optional[socket.socket] = None
        self._latest: Optional[dict] = None
        self._run = False
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        self._run = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._run = False
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass

    def _loop(self) -> None:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("0.0.0.0", self.port))
            s.settimeout(0.5)
            self._sock = s
        except OSError:
            return
        while self._run:
            try:
                data, _ = s.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                obj = json.loads(data.decode("utf-8", "ignore"))
            except Exception:
                continue
            out = _extract(obj, self.field_map, self.name)
            if out:
                self._latest = out

    def poll(self) -> Optional[dict]:
        return self._latest


def _extract(data: dict, field_map: dict, source: str) -> Optional[dict]:
    """从 JSON 里按映射取 roll/pitch/yaw，并归一到 [-1,1]。
    映射值形如 'state.roll'（点路径）或直接 'roll'。取值假定已是 [-1,1] 或角度。
    """
    def get(path: str):
        cur = data
        for part in path.split("."):
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                return None
        return cur

    def pick(key: str):
        p = field_map.get(key, key)
        v = get(p)
        if v is None:
            return None
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    roll = pick("roll")
    pitch = pick("pitch")
    yaw = pick("yaw")
    if roll is None and pitch is None and yaw is None:
        return None
    return {
        "roll": _norm(roll),
        "pitch": _norm(pitch),
        "yaw": _norm(yaw),
        "valid": True,
        "source": source,
    }


def _norm(v: Optional[float]) -> float:
    """归一到 [-1,1]：若绝对值 > 1 认为是角度，按 90° 归一。"""
    if v is None:
        return 0.0
    x = float(v)
    if abs(x) > 1.0:
        x = x / 90.0
    return max(-1.0, min(1.0, x))


# 当前活动的遥测源（由 bridge 装配）
ACTIVE: TelemetrySource = NoTelemetry()
LAST: Optional[dict] = None
_lock = threading.Lock()


def set_source(src: TelemetrySource) -> None:
    global ACTIVE
    ACTIVE = src
    try:
        src.start()
    except Exception:
        pass


def poll() -> Optional[dict]:
    global LAST
    out = ACTIVE.poll()
    if out is not None:
        with _lock:
            LAST = out
    return out


def latest() -> Optional[dict]:
    with _lock:
        return LAST
