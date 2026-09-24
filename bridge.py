#!/usr/bin/env python3
"""
PalmDeck — phone yoke for PC games.

Creates a virtual joystick on this computer and lets a phone drive it
over the LAN.

    python3 bridge.py
    python3 bridge.py --http 8080 --ws 8765
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import socket
import struct
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Optional

from hotas import Hotas
from palmdeck_config import load_config
import telemetry

def _base_dir() -> str:
    if getattr(sys, "frozen", False):
        return getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


WEB_DIR = os.path.join(_base_dir(), "web")
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
BEACON_PORT = 7774  # 手机监听这个 UDP 端口，自动发现电脑


def _print_qr(text: str) -> None:
    """尽量打印二维码（装了 qrcode 就用；没有就跳过）。"""
    try:
        import qrcode  # type: ignore
    except Exception:
        print(f"   （想要二维码？pip install qrcode 后重启）\n")
        return
    try:
        qr = qrcode.QRCode(border=1)
        qr.add_data(text)
        qr.make()
        qr.print_ascii(invert=True)
    except Exception:
        pass


def zeroconf_register(http_port: int, ws_port: int, udp_port: int) -> None:
    """用 Bonjour(mDNS) 宣告服务：iOS 端最可靠的自动发现方式。"""
    try:
        from zeroconf import ServiceInfo, Zeroconf  # type: ignore
    except Exception:
        log("zeroconf 未安装（可选）：pip install zeroconf 可让 iOS 自动发现更可靠")
        return
    ip = lan_ip() or "127.0.0.1"
    if not _usable_lan(ip):
        log(f"bonjour: 本机无可用局域网 IP（lan_ip={ip}），跳过注册（手机无法连回环地址）")
        return
    try:
        info = ServiceInfo(
            "_palmdeck._udp.local.",
            f"PalmDeck-{ip.replace('.', '-')}._palmdeck._udp.local.",
            addresses=[socket.inet_aton(ip)],
            port=udp_port,
            properties={"ip": ip, "ws": str(ws_port), "udp": str(udp_port),
                        "http": str(http_port)},
            server=f"palmdeck-{ip.replace('.', '-')}.local.",
        )
        zc = Zeroconf()
        zc.register_service(info)
        log(f"bonjour: _palmdeck._udp.local. -> {ip}")
        # 保活
        while True:
            time.sleep(5)
            try:
                zc.update_service(info)
            except Exception:
                pass
    except Exception as e:
        log(f"bonjour 注册失败: {e}")


def beacon_loop(http_port: int, ws_port: int, udp_port: int, interval: float = 1.0) -> None:
    """每秒向局域网广播一次自身信息，手机 App 据此自动发现电脑。"""
    ip = lan_ip() or "127.0.0.1"
    if not _usable_lan(ip):
        log(f"beacon: 本机无可用局域网 IP（{ip}），跳过广播")
        return
    payload = json.dumps({
        "palmdeck": 1,
        "ip": ip,
        "http": http_port,
        "ws": ws_port,
        "udp": udp_port,
        "name": socket.gethostname(),
    }).encode("utf-8")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        while True:
            try:
                sock.sendto(payload, ("255.255.255.255", BEACON_PORT))
            except OSError:
                pass
            time.sleep(interval)
    finally:
        sock.close()


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def _usable_lan(ip: str) -> bool:
    if not ip or ip.startswith("127.") or ip.startswith("169.254."):
        return False
    try:
        a, b = (int(p) for p in ip.split(".")[:2])
    except ValueError:
        return False
    # Clash / Surge fake-ip range — phones cannot reach this.
    if a == 198 and 18 <= b <= 19:
        return False
    return True


def _lan_rank(ip: str) -> int:
    """分值越低越优先：真局域网几乎都是 192.168.* / 10.*；
    172.16-31.* 常是 Docker/WSL/Hyper-V 虚拟网卡，放到最后（手机连不到）。"""
    try:
        a, b = (int(p) for p in ip.split(".")[:2])
    except ValueError:
        return 9
    if a == 192 and b == 168:
        return 0
    if a == 10:
        return 1
    if a == 172 and 16 <= b <= 31:
        return 3
    return 2


def lan_ip() -> str:
    if sys.platform == "darwin":
        for iface in ("en0", "en1"):
            try:
                out = subprocess.check_output(
                    ["ipconfig", "getifaddr", iface],
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=2,
                ).strip()
            except Exception:
                continue
            if _usable_lan(out):
                return out
    # 通用候选（Windows/Linux）：默认路由探测 + 主机名解析 + addrinfo 枚举。
    # 默认路由可能被 Clash/Surge TUN 劫持成 fake-ip，所以多收集几个候选再挑私有网段。
    cands = []
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        cands.append(s.getsockname()[0])
    except OSError:
        pass
    finally:
        s.close()
    try:
        host = socket.gethostname()
        cands.extend(socket.gethostbyname_ex(host)[2])
        for info in socket.getaddrinfo(host, None, socket.AF_INET):
            cands.append(info[4][0])
    except OSError:
        pass
    # 在可用 IP 里挑“最像真局域网”的：192.168.* / 10.* 优先，
    # 172.16-31.*（Docker/WSL/Hyper-V 虚拟网卡）最后，避免手机连到虚拟网卡。
    best, best_rank = "", 9
    seen = set()
    for ip in cands:
        if not _usable_lan(ip) or ip in seen:
            continue
        seen.add(ip)
        r = _lan_rank(ip)
        if r < best_rank:
            best, best_rank = ip, r
    return best or "127.0.0.1"


# Binary stick packet (little-endian, 22 bytes) — FBW-style UDP hot path.
# magic 'PD' | ver u8 | hat u8 | roll,pitch,yaw,look_x,look_y,thr,lt,rt i16 | buttons u16
PKT = struct.Struct("<2sBB8hH")
HAT_NAME = {0: "hat_up", 1: "hat_right", 2: "hat_down", 3: "hat_left"}


class RateMeter:
    def __init__(self) -> None:
        self._n = 0
        self._t = time.monotonic()
        self.hz = 0.0
        self.last: Optional[float] = None

    def tick(self) -> None:
        now = time.monotonic()
        self.last = now
        self._n += 1
        dt = now - self._t
        if dt >= 1.0:
            self.hz = self._n / dt
            self._n = 0
            self._t = now


class Hub:
    def __init__(self, hotas: Optional[Hotas] = None) -> None:
        self.hotas = hotas if hotas is not None else Hotas()
        self.lock = threading.Lock()
        self.listeners: list[Callable[[dict], None]] = []
        self.phones = 0
        self.udp_port = 7773
        self.park_ms = 2.0
        self.stale_warn_ms = 0.35
        self.allow_ttl = 5.0
        self.udp_allowlist = True
        self.failsafe_throttle = "hold"
        self.axis_profile = "hotas"
        self.http_port = 8080
        self.cockpit_mode = "unknown"
        self.mode_owner_ip: Optional[str] = None
        kinds = set() if self.hotas.backend in ("", "none") else set(self.hotas.backend.split("+"))
        self.live_targets: set[str] = set(kinds)
        self.active_ws_ips: set[str] = set()
        self.recent_ws_expiry: dict[str, float] = {}
        self.rate = RateMeter()
        self._btn = 0
        self._hat = 255
        self.last_axes: Optional[dict] = None
        self.last_parked = False
        self.last_udp_mono: Optional[float] = None
        self.last_ws_mono: Optional[float] = None
        self.dropped_udp = 0
        self._error_kind = ""
        driver_err = "" if self.hotas.backend != "none" else "未检测到 vJoy / ViGEm / uinput，游戏里不会出现设备"
        if driver_err:
            self._error_kind = "driver"
        self.telemetry_enabled = False
        self.status = {
            "connected": self.hotas.backend != "none",
            "mode": "pc",
            "device": self.hotas.name,
            "backend": self.hotas.backend,
            "phones": 0,
            "hz": 0.0,
            "udp": 7773,
            "error": driver_err,
            "cockpit_mode": "unknown",
            "axis_profile": "hotas",
            "telemetry": "none",
        }
        log(f"HOTAS backend={self.hotas.backend} · {self.hotas.name}")

    def snapshot_status(self) -> dict:
        with self.lock:
            st = dict(self.status)
            st["phones"] = self.phones
            st["hz"] = round(self.rate.hz, 1)
            st["udp"] = self.udp_port
            st["cockpit_mode"] = self.cockpit_mode
            st["axis_profile"] = self.axis_profile
            st["park_ms"] = int(self.park_ms * 1000)
            st["caps"] = ["failsafe", "profile", "allowlist", "telemetry"]
            st["telemetry"] = telemetry.ACTIVE.name
            last = self.rate.last
            st["last_ms"] = None if last is None else int((time.monotonic() - last) * 1000)
            now = time.monotonic()
            udp_age = None if self.last_udp_mono is None else now - self.last_udp_mono
            ws_age = None if self.last_ws_mono is None else now - self.last_ws_mono
            if udp_age is not None and udp_age < 1.0:
                st["transport"] = "udp"
            elif ws_age is not None and ws_age < 1.0:
                st["transport"] = "ws"
            else:
                st["transport"] = "idle"
            return st

    def broadcast(self, msg: dict) -> None:
        with self.lock:
            listeners = list(self.listeners)
        dead = []
        for fn in listeners:
            try:
                fn(msg)
            except Exception:
                dead.append(fn)
        if dead:
            with self.lock:
                self.listeners = [fn for fn in self.listeners if fn not in dead]

    def set_error(self, kind: str, msg: str) -> None:
        if kind == "failsafe" and self._error_kind == "driver":
            return
        self._error_kind = kind
        self.status["error"] = msg

    def clear_failsafe_error(self) -> None:
        if self._error_kind == "failsafe":
            self._error_kind = "driver" if self.hotas.backend == "none" else ""
            self.status["error"] = (
                "未检测到 vJoy / ViGEm / uinput，游戏里不会出现设备" if self._error_kind == "driver" else ""
            )

    def udp_allowed(self, ip: Optional[str]) -> bool:
        if not self.udp_allowlist:
            return True
        if not ip:
            return False
        if ip in self.active_ws_ips:
            return True
        exp = self.recent_ws_expiry.get(ip)
        return bool(exp and time.monotonic() < exp)

    def owner_ok(self, ip: Optional[str]) -> bool:
        if self.mode_owner_ip is None:
            return True
        if not self.udp_allowlist and self.mode_owner_ip is None:
            return True
        return ip == self.mode_owner_ip

    def note_ws_up(self, ip: str, push: Callable[[dict], None]) -> None:
        with self.lock:
            self.active_ws_ips.add(ip)
            self.phones += 1
            self.status["phones"] = self.phones
            self.listeners.append(push)

    def note_ws_down(self, ip: str, push: Callable[[dict], None]) -> None:
        with self.lock:
            self.active_ws_ips.discard(ip)
            self.recent_ws_expiry[ip] = time.monotonic() + self.allow_ttl
            if push in self.listeners:
                self.listeners.remove(push)
            self.phones = max(0, self.phones - 1)
            self.status["phones"] = self.phones

    def axes(self, msg: dict, ip: Optional[str] = None) -> None:
        with self.lock:
            if not self.owner_ok(ip):
                return
            self._apply_axes_locked(
                roll=float(msg.get("roll") or 0),
                pitch=float(msg.get("pitch") or 0),
                throttle=float(msg.get("throttle") or 0),
                yaw=float(msg.get("yaw") or 0),
                brakes=float(msg.get("brakes") or 0),
                look_x=float(msg.get("look_x") or 0),
                look_y=float(msg.get("look_y") or 0),
                lt=None if msg.get("lt") is None else float(msg["lt"]),
                rt=None if msg.get("rt") is None else float(msg["rt"]),
                src="ws",
            )

    def button(self, name: str, pressed: Optional[bool] = None, ip: Optional[str] = None) -> None:
        with self.lock:
            if not self.owner_ok(ip):
                return
            self.hotas.tap_button(name, pressed)

    def _available_kinds(self) -> set:
        b = self.hotas.backend
        if not b or b == "none":
            return set()
        return set(b.split("+"))

    def live_for_mode(self, mode: str) -> set:
        kinds = self._available_kinds()
        if kinds == {"uinput"}:
            return {"uinput"}
        if mode == "heli":
            if "vjoy" in kinds:
                return {"vjoy"}
            if "vgamepad" in kinds:
                return {"vgamepad"}
            return set(kinds)
        if mode == "drive":
            if "vgamepad" in kinds:
                return {"vgamepad"}
            if "vjoy" in kinds:
                return {"vjoy"}
            return set(kinds)
        if mode == "infantry":
            return set()
        return set(kinds)

    def set_cockpit_mode(self, name: str, ip: Optional[str] = None) -> None:
        if name not in ("heli", "drive", "infantry"):
            return
        with self.lock:
            self.cockpit_mode = name
            self.mode_owner_ip = ip
            self.status["cockpit_mode"] = name
            new_live = self.live_for_mode(name)
            unused = self._available_kinds() - new_live
            if name == "infantry":
                self.park_infantry_all_zero()
            else:
                for kind in unused:
                    self.hotas.park_backend(kind)
            self.live_targets = new_live
        self.broadcast({"type": "status", **self.snapshot_status()})

    def apply_packet(self, raw: bytes, src: str = "udp", ip: Optional[str] = None) -> bool:
        if len(raw) < PKT.size or raw[:2] != b"PD":
            return False
        _magic, ver, hat, roll, pitch, yaw, look_x, look_y, thr, lt, rt, buttons = PKT.unpack(raw[: PKT.size])
        if ver != 1:
            return False
        with self.lock:
            if src == "udp" and not self.udp_allowed(ip):
                self.dropped_udp += 1
                return False
            if not self.owner_ok(ip):
                self.dropped_udp += 1
                return False
            scale = 32767.0
            axes = dict(
                roll=roll / scale,
                pitch=pitch / scale,
                yaw=yaw / scale,
                look_x=look_x / scale,
                look_y=look_y / scale,
                throttle=max(0.0, min(1.0, thr / scale)),
                brakes=max(0.0, min(1.0, lt / scale)),
                lt=max(0.0, min(1.0, lt / scale)),
                rt=max(0.0, min(1.0, rt / scale)),
            )
            infantry = self.cockpit_mode == "infantry"
            if infantry:
                axes = dict(roll=0, pitch=0, yaw=0, look_x=0, look_y=0, throttle=0, brakes=0, lt=0, rt=0)
            analog_idle = infantry and abs(axes["roll"]) + abs(axes["pitch"]) + abs(axes["throttle"]) + abs(axes["rt"]) == 0
            skip = infantry and analog_idle and buttons == self._btn and hat == self._hat
            if not skip:
                btn_targets = None
                if infantry:
                    kinds = self._available_kinds()
                    btn_targets = {"vjoy"} if "vjoy" in kinds else ({"uinput"} if "uinput" in kinds else None)
                    self.hotas.set_axes(
                        **axes,
                        profile=self.axis_profile,
                        targets=btn_targets,
                        mode="infantry",
                    )
                elif self.live_targets:
                    self.hotas.set_axes(
                        **axes,
                        profile=self.axis_profile,
                        targets=self.live_targets,
                        mode=self.cockpit_mode,
                    )
                changed = buttons ^ self._btn
                if changed:
                    for i in range(16):
                        bit = 1 << i
                        if changed & bit:
                            self.hotas.tap_button(f"b{i + 1}", bool(buttons & bit))
                    self._btn = buttons
                if hat != self._hat:
                    if self._hat in HAT_NAME:
                        self.hotas.tap_button(HAT_NAME[self._hat], False)
                    if hat in HAT_NAME:
                        self.hotas.tap_button(HAT_NAME[hat], True)
                    self._hat = hat
            self._mark_live_locked(axes, src)
            return True

    def _apply_axes_locked(
        self,
        roll: float,
        pitch: float,
        throttle: float,
        yaw: float,
        brakes: float,
        look_x: float,
        look_y: float,
        lt: Optional[float],
        rt: Optional[float],
        src: str,
    ) -> None:
        axes = dict(
            roll=roll,
            pitch=pitch,
            throttle=throttle,
            yaw=yaw,
            brakes=brakes,
            look_x=look_x,
            look_y=look_y,
            lt=brakes if lt is None else lt,
            rt=throttle if rt is None else rt,
        )
        self.hotas.set_axes(
            roll=roll,
            pitch=pitch,
            throttle=throttle,
            yaw=yaw,
            brakes=brakes,
            look_x=look_x,
            look_y=look_y,
            lt=lt,
            rt=rt,
            profile=self.axis_profile,
            targets=self.live_targets or None,
            mode=self.cockpit_mode,
        )
        self._mark_live_locked(axes, src)

    def _mark_live_locked(self, axes: dict, src: str) -> None:
        now = time.monotonic()
        self.last_axes = dict(axes)
        self.last_parked = False
        self.clear_failsafe_error()
        self.rate.tick()
        self.status["hz"] = round(self.rate.hz, 1)
        if src == "udp":
            self.last_udp_mono = now
        else:
            self.last_ws_mono = now

    def park_xy_hold_throttle(self) -> None:
        if self.last_axes is None:
            return
        a = dict(self.last_axes)
        a["roll"] = a["pitch"] = a["yaw"] = a["look_x"] = a["look_y"] = 0.0
        if self.failsafe_throttle == "center":
            a["throttle"] = a["lt"] = a["rt"] = 0.0
        elif self.cockpit_mode == "drive":
            pass
        else:
            a["rt"] = 0.0
        self.hotas.set_axes(
            roll=0,
            pitch=0,
            yaw=0,
            look_x=0,
            look_y=0,
            throttle=float(a.get("throttle") or 0),
            brakes=float(a.get("lt") or 0),
            lt=float(a.get("lt") or 0),
            rt=float(a.get("rt") or 0),
            profile=self.axis_profile,
            targets=self.live_targets or None,
            mode=self.cockpit_mode,
        )
        self.hotas.release_all_buttons(xbox=True)
        self.hotas.center_hat()
        self._btn = 0
        self._hat = 255

    def park_infantry_all_zero(self) -> None:
        zeros = dict(roll=0, pitch=0, yaw=0, look_x=0, look_y=0, throttle=0, brakes=0, lt=0, rt=0)
        kinds = self._available_kinds()
        self.hotas.set_axes(**zeros, profile=self.axis_profile, targets=kinds or None, mode="infantry")
        self.hotas.center_hat()
        self._hat = 255
        self.last_axes = dict(zeros)

    def release_buttons_only(self) -> None:
        self.hotas.release_all_buttons(xbox=False)
        self.hotas.center_hat()
        self._btn = 0
        self._hat = 255

    def tick_failsafe(self) -> None:
        with self.lock:
            if self.rate.last is None:
                return
            gap = time.monotonic() - self.rate.last
            if self.phones != 0 or gap <= self.park_ms or self.last_parked:
                return
            if self.cockpit_mode == "infantry":
                self.release_buttons_only()
                self.last_parked = True
                return
            self.park_xy_hold_throttle()
            self.last_parked = True
            self.set_error("failsafe", "手机已离线，杆已回中（油门保持）")


HUB = Hub()


def ws_accept_key(key: str) -> str:
    return base64.b64encode(hashlib.sha1((key + GUID).encode("utf-8")).digest()).decode("ascii")


def ws_encode(text: str) -> bytes:
    raw = text.encode("utf-8")
    n = len(raw)
    if n < 126:
        header = bytes([0x81, n])
    elif n < 65536:
        header = bytes([0x81, 126]) + struct.pack(">H", n)
    else:
        header = bytes([0x81, 127]) + struct.pack(">Q", n)
    return header + raw


def _ws_frame(opcode: int, raw: bytes) -> bytes:
    n = len(raw)
    if n < 126:
        header = bytes([opcode, n])
    elif n < 65536:
        header = bytes([opcode, 126]) + struct.pack(">H", n)
    else:
        header = bytes([opcode, 127]) + struct.pack(">Q", n)
    return header + raw


def recvall(conn: socket.socket, n: int) -> Optional[bytes]:
    buf = bytearray()
    while len(buf) < n:
        try:
            chunk = conn.recv(n - len(buf))
        except OSError:
            return None
        if not chunk:
            return None
        buf.extend(chunk)
    return bytes(buf)


def ws_read_message(conn: socket.socket):
    hdr = recvall(conn, 2)
    if not hdr:
        return None
    opcode = hdr[0] & 0x0F
    masked = bool(hdr[1] & 0x80)
    length = hdr[1] & 0x7F
    if length == 126:
        ext = recvall(conn, 2)
        if not ext:
            return None
        length = struct.unpack(">H", ext)[0]
    elif length == 127:
        ext = recvall(conn, 8)
        if not ext:
            return None
        length = struct.unpack(">Q", ext)[0]
    mask = recvall(conn, 4) if masked else b""
    payload = recvall(conn, length) if length else b""
    if payload is None:
        return None
    if masked and mask:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    if opcode == 0x8:
        return None
    if opcode == 0x9:
        try:
            conn.sendall(bytes([0x8A, 0]))
        except OSError:
            return None
        return ""
    if opcode == 0x2:
        return payload
    if opcode in (0x1, 0x0):
        return payload.decode("utf-8", errors="ignore")
    return ""


class WsClient:
    def __init__(self, conn: socket.socket) -> None:
        self.conn = conn
        self.lock = threading.Lock()

    def send(self, obj: dict) -> None:
        data = ws_encode(json.dumps(obj, ensure_ascii=False))
        with self.lock:
            self.conn.sendall(data)


def handle_ws_client(conn: socket.socket, addr) -> None:
    client = WsClient(conn)
    ip = addr[0]

    def push(msg: dict) -> None:
        client.send(msg)

    HUB.note_ws_up(ip, push)
    log(f"phone {ip} · online {HUB.phones}")
    try:
        client.send(
            {
                "type": "hello",
                "product": "PalmDeck",
                "version": "3.0",
                "udp": HUB.udp_port,
                "axis_profile": HUB.axis_profile,
                "http": HUB.http_port,
                "park_ms": int(HUB.park_ms * 1000),
                "caps": ["failsafe", "profile", "allowlist"],
            }
        )
        client.send({"type": "status", **HUB.snapshot_status()})
        while True:
            raw = ws_read_message(conn)
            if raw is None:
                break
            if not raw:
                continue
            if isinstance(raw, (bytes, bytearray)):
                HUB.apply_packet(raw, src="ws", ip=ip)
                continue
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            kind = msg.get("type")
            if kind == "axes":
                HUB.axes(msg, ip=ip)
            elif kind == "cmd":
                HUB.button(str(msg.get("name") or ""), ip=ip)
            elif kind == "btn":
                HUB.button(str(msg.get("name") or ""), msg.get("down"), ip=ip)
            elif kind == "mode":
                HUB.set_cockpit_mode(str(msg.get("name") or ""), ip=ip)
            elif kind == "ping":
                client.send({"type": "pong", "t": msg.get("t")})
    except Exception as exc:
        log(f"ws error: {exc}")
    finally:
        HUB.note_ws_down(ip, push)
        HUB.broadcast({"type": "status", **HUB.snapshot_status()})
        try:
            conn.close()
        except OSError:
            pass
        log(f"phone left {ip} · online {HUB.phones}")


def accept_ws(host: str, port: int) -> None:
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(16)
    log(f"websocket ws://{host}:{port}")
    while True:
        conn, addr = srv.accept()
        try:
            prelude = b""
            while b"\r\n\r\n" not in prelude:
                chunk = conn.recv(4096)
                if not chunk:
                    raise ConnectionError("empty handshake")
                prelude += chunk
            header_text = prelude.decode("iso-8859-1", errors="ignore")
            key_match = re.search(r"Sec-WebSocket-Key:\s*(\S+)", header_text, re.I)
            if not key_match:
                conn.close()
                continue
            accept = ws_accept_key(key_match.group(1).strip())
            try:
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except OSError:
                pass
            conn.sendall(
                (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                ).encode("ascii")
            )
            threading.Thread(target=handle_ws_client, args=(conn, addr), daemon=True).start()
        except Exception as exc:
            log(f"handshake failed: {exc}")
            try:
                conn.close()
            except OSError:
                pass


class CockpitHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def log_message(self, fmt: str, *args) -> None:
        if "api/status" in (fmt % args):
            return
        log("http " + (fmt % args))

    def do_GET(self):
        if self.path.split("?")[0] == "/api/status":
            body = json.dumps(
                {
                    **HUB.snapshot_status(),
                    "ip": lan_ip(),
                    "http": getattr(self.server, "palm_http", 8080),
                    "ws": getattr(self.server, "palm_ws", 8765),
                },
                ensure_ascii=False,
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path in ("/", "/host", "/host.html"):
            # PC console is host.html; phones use /phone
            if self.path == "/" and self.headers.get("User-Agent", "").lower().find("mobile") >= 0:
                self.path = "/index.html"
            elif self.path in ("/", "/host", "/host.html"):
                self.path = "/host.html"
        return SimpleHTTPRequestHandler.do_GET(self)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()


def telemetry_loop() -> None:
    """定期读取游戏遥测并广播给手机（若开启且来源可用）。"""
    while True:
        time.sleep(1.0 / 30.0)  # 30Hz 姿态足够平滑
        if not HUB.telemetry_enabled:
            continue
        try:
            att = telemetry.poll()
        except Exception as exc:
            log(f"telemetry: {exc}")
            continue
        if att:
            HUB.broadcast({"type": "attitude", **att})


def failsafe_loop() -> None:
    while True:
        time.sleep(0.1)
        try:
            HUB.tick_failsafe()
        except Exception as exc:
            log(f"failsafe: {exc}")


def serve_udp(host: str, port: int) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, port))
    log(f"udp      udp://{host}:{port}")
    while True:
        try:
            data, addr = sock.recvfrom(256)
        except OSError:
            continue
        HUB.apply_packet(data, src="udp", ip=addr[0])


def serve_http(host: str, port: int, ws_port: int) -> None:
    httpd = ThreadingHTTPServer((host, port), CockpitHandler)
    httpd.palm_http = port
    httpd.palm_ws = ws_port
    log(f"console  http://127.0.0.1:{port}/")
    log(f"phone    http://{lan_ip()}:{port}/index.html")
    httpd.serve_forever()


def main(argv: Optional[list] = None) -> None:
    cfg = load_config()
    parser = argparse.ArgumentParser(description="PalmDeck PC yoke")
    parser.add_argument("--host", default=cfg["host"])
    parser.add_argument("--http", type=int, default=cfg["http"])
    parser.add_argument("--ws", type=int, default=cfg["ws"])
    parser.add_argument("--udp", type=int, default=cfg["udp"])
    parser.add_argument("--axis-profile", choices=("hotas", "fbw"), default=cfg["axis_profile"])
    parser.add_argument("--failsafe-throttle", choices=("hold", "center"), default=cfg["failsafe_throttle"])
    parser.add_argument("--open-udp", action="store_true", help="accept UDP from any IP (debug)")
    parser.add_argument("--park-ms", type=int, default=cfg["park_ms"])
    parser.add_argument("--allowlist-ttl-ms", type=int, default=cfg["allowlist_ttl_ms"])
    parser.add_argument("--beacon", action="store_true", default=cfg["beacon"])
    parser.add_argument("--no-beacon", action="store_true", help="关闭 UDP 广播（手机自动发现）")
    parser.add_argument("--no-browser", action="store_true")
    # 游戏遥测（可选）：默认关闭。支持 http-json / udp-json 两种通用来源。
    parser.add_argument("--telemetry", choices=("none", "http", "udp"), default="none",
                        help="游戏遥测来源；默认 none")
    parser.add_argument("--telemetry-url", default="",
                        help="http 来源：定期 GET 该 URL 取 JSON（如 http://127.0.0.1:8111/）")
    parser.add_argument("--telemetry-udp", type=int, default=0,
                        help="udp 来源：监听该本地端口收 JSON 姿态包")
    parser.add_argument("--telemetry-map", default="",
                        help="字段映射，如 roll=state.roll,pitch=state.pitch,yaw=state.heading")
    args = parser.parse_args(argv)
    # 装配遥测源
    fmap = {}
    if args.telemetry_map:
        for pair in args.telemetry_map.split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                fmap[k.strip()] = v.strip()
    if args.telemetry == "http" and args.telemetry_url:
        telemetry.set_source(telemetry.HttpJsonTelemetry(args.telemetry_url, fmap))
        HUB.telemetry_enabled = True
        log(f"telemetry: http {args.telemetry_url}")
    elif args.telemetry == "udp" and args.telemetry_udp:
        telemetry.set_source(telemetry.UdpJsonTelemetry(args.telemetry_udp, fmap))
        HUB.telemetry_enabled = True
        log(f"telemetry: udp :{args.telemetry_udp}")
    else:
        HUB.telemetry_enabled = False
    HUB.udp_port = args.udp
    HUB.http_port = args.http
    HUB.status["udp"] = args.udp
    HUB.park_ms = max(0.2, args.park_ms / 1000.0)
    HUB.allow_ttl = max(0.5, args.allowlist_ttl_ms / 1000.0)
    HUB.failsafe_throttle = args.failsafe_throttle
    HUB.axis_profile = args.axis_profile
    HUB.status["axis_profile"] = args.axis_profile
    if args.open_udp or not cfg["udp_allowlist"]:
        HUB.udp_allowlist = False
        log("UDP allowlist off")
    log(f"axis_profile={HUB.axis_profile}")
    ip = lan_ip() or "127.0.0.1"
    url = f"http://{ip}:{args.http}/"
    backend = HUB.hotas.backend or "none"
    backend_note = {
        "none": "!! 未创建虚拟设备（只做演示，游戏读不到）",
        "": "!! 未创建虚拟设备（只做演示，游戏读不到）",
    }.get(backend, f"OK  {HUB.hotas.name}")

    print(
        f"""
+----------------------------------------------+
|   PalmDeck  掌舵舱 · 手机就是摇杆             |
+----------------------------------------------+
   虚拟设备 : {backend_note}
   局域网IP : {ip}
   手机地址 : {url}
   自动发现 : 已广播 (手机 App 可自动找到本机)

   手机端：App 里点“连接”，或自动发现后一键连。
   游戏端：控制器设置里绑定上面这只虚拟设备。
   保持本窗口开着。Ctrl+C 退出。
"""
    )
    _print_qr(url)
    threading.Thread(target=serve_http, args=(args.host, args.http, args.ws), daemon=True).start()
    threading.Thread(target=accept_ws, args=(args.host, args.ws), daemon=True).start()
    threading.Thread(target=serve_udp, args=(args.host, args.udp), daemon=True).start()
    threading.Thread(target=failsafe_loop, daemon=True).start()
    threading.Thread(target=telemetry_loop, daemon=True).start()
    # 始终广播，方便手机自动发现（--no-beacon 可关）
    if not args.no_beacon:
        threading.Thread(target=beacon_loop,
                         args=(args.http, args.ws, args.udp), daemon=True).start()
        threading.Thread(target=zeroconf_register,
                         args=(args.http, args.ws, args.udp), daemon=True).start()
        log(f"beacon: UDP :{BEACON_PORT} + bonjour (手机可自动发现)")
    if not args.no_browser:
        import webbrowser

        def _open():
            time.sleep(0.4)
            webbrowser.open(f"http://127.0.0.1:{args.http}/")

        threading.Thread(target=_open, daemon=True).start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
