"""Virtual devices for PalmDeck. Can drive vJoy and Xbox 360 at the same time."""

from __future__ import annotations

import os
import subprocess
import sys
from typing import Optional

# vgamepad 已内置到 vendor/（纯 Python + DLL）。PyPI 上那个包会在 pip 安装时
# 自动跑 ViGEmBus 的 msiexec 安装程序，导致安装/构建卡死，所以改走本地副本。
if not getattr(sys, "frozen", False):
    _vendor = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")
    if os.path.isdir(_vendor) and _vendor not in sys.path:
        sys.path.insert(0, _vendor)


def _clamp(v: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return lo if v < lo else hi if v > hi else v


def remap_vjoy(
    profile: str,
    roll: float,
    pitch: float,
    throttle: float,
    yaw: float,
    left_t: float,
    look_x: float,
    look_y: float,
) -> dict:
    """vJoy axis values in [-1, 1]. Unknown profile logs as hotas."""
    if profile != "fbw":
        profile = "hotas"
    if profile == "fbw":
        return {
            "x": roll,
            "y": -pitch,
            "z": yaw,
            "rz": 0.0,
            "sl0": throttle * 2 - 1,
            "rx": look_x,
            "ry": -look_y,
        }
    return {
        "x": roll,
        "y": -pitch,
        "z": throttle * 2 - 1,
        "rz": yaw,
        "sl0": left_t * 2 - 1,
        "rx": look_x,
        "ry": -look_y,
    }


class Hotas:
    def __init__(self) -> None:
        self._devs: list[tuple] = []
        self._try_vjoy()
        self._try_vgamepad()
        self._try_uinput()
        if not self._devs:
            self.backend = "none"
            self.name = "未创建虚拟设备（演示）"
        else:
            kinds = [d[0] for d in self._devs]
            self.backend = "+".join(kinds)
            names = []
            if "vjoy" in kinds:
                names.append("vJoy Device #1")
            if "vgamepad" in kinds:
                names.append("Xbox 360")
            if "uinput" in kinds:
                names.append("PalmDeck HOTAS")
            self.name = " + ".join(names)
        self._vjoy_fire = False
        self._xbox_fire = False

    def _try_vjoy(self) -> None:
        try:
            import pyvjoy
        except Exception:
            return
        if not self._open_vjoy(pyvjoy):
            self._autoconfig_vjoy()
            self._open_vjoy(pyvjoy)

    def _open_vjoy(self, pyvjoy) -> bool:
        try:
            dev = pyvjoy.VJoyDevice(1)
            center = 0x4000
            for hid in (
                getattr(pyvjoy, "HID_USAGE_X", 0x30),
                getattr(pyvjoy, "HID_USAGE_Y", 0x31),
                getattr(pyvjoy, "HID_USAGE_Z", 0x32),
                getattr(pyvjoy, "HID_USAGE_RX", 0x33),
                getattr(pyvjoy, "HID_USAGE_RY", 0x34),
                getattr(pyvjoy, "HID_USAGE_RZ", 0x35),
                getattr(pyvjoy, "HID_USAGE_SL0", 0x36),
            ):
                try:
                    dev.set_axis(hid, center)
                except Exception:
                    pass
            self._devs.append(("vjoy", pyvjoy, dev))
            return True
        except Exception:
            return False

    def _autoconfig_vjoy(self) -> None:
        if sys.platform != "win32":
            return
        exe = None
        for path in (
            r"C:\Program Files\vJoy\x64\vJoyConfig.exe",
            r"C:\Program Files\vJoy\x86\vJoyConfig.exe",
            r"C:\Program Files (x86)\vJoy\x64\vJoyConfig.exe",
            r"C:\Program Files (x86)\vJoy\x86\vJoyConfig.exe",
        ):
            if os.path.isfile(path):
                exe = path
                break
        if not exe:
            return
        try:
            subprocess.run([exe, "enable", "on"], check=False, timeout=8, capture_output=True)
            subprocess.run(
                [exe, "1", "-f", "-a", "X", "Y", "Z", "Rx", "Ry", "Rz", "Sl0", "-b", "16", "-p", "1"],
                check=False,
                timeout=8,
                capture_output=True,
            )
        except Exception:
            return

    def _try_vgamepad(self) -> None:
        try:
            import vgamepad as vg
        except Exception:
            return
        try:
            pad = vg.VX360Gamepad()
            pad.reset()
            pad.update()
            self._devs.append(("vgamepad", vg, pad))
        except Exception:
            return

    def _try_uinput(self) -> None:
        if self._devs:
            return
        try:
            from evdev import AbsInfo, UInput, ecodes
        except Exception:
            return
        try:
            absinfo = AbsInfo(value=0, min=-1000, max=1000, fuzz=0, flat=20, resolution=0)
            cap = {
                ecodes.EV_ABS: [
                    (ecodes.ABS_X, absinfo),
                    (ecodes.ABS_Y, absinfo),
                    (ecodes.ABS_Z, absinfo),
                    (ecodes.ABS_RX, absinfo),
                    (ecodes.ABS_RY, absinfo),
                    (ecodes.ABS_RZ, absinfo),
                    (ecodes.ABS_BRAKE, AbsInfo(0, 0, 1000, 0, 0, 0)),
                    (ecodes.ABS_THROTTLE, AbsInfo(0, 0, 1000, 0, 0, 0)),
                ],
                ecodes.EV_KEY: [
                    ecodes.BTN_SOUTH, ecodes.BTN_EAST, ecodes.BTN_WEST, ecodes.BTN_NORTH,
                    ecodes.BTN_TL, ecodes.BTN_TR, ecodes.BTN_SELECT, ecodes.BTN_START,
                    ecodes.BTN_THUMBL, ecodes.BTN_THUMBR,
                ],
            }
            ui = UInput(cap, name="PalmDeck", vendor=0xF00D, product=0x0001)
            self._devs.append(("uinput", ecodes, ui))
        except Exception:
            return

    @staticmethod
    def _vjoy_axis(v: float) -> int:
        return max(1, min(0x8000, int(round((_clamp(v) + 1.0) * 16384))))

    def set_axes(
        self,
        roll: float = 0,
        pitch: float = 0,
        throttle: float = 0,
        yaw: float = 0,
        brakes: float = 0,
        look_x: float = 0,
        look_y: float = 0,
        lt: Optional[float] = None,
        rt: Optional[float] = None,
        profile: str = "hotas",
        targets: Optional[set] = None,
        mode: str = "unknown",
    ) -> None:
        roll, pitch = _clamp(roll), _clamp(pitch)
        yaw = _clamp(yaw)
        look_x, look_y = _clamp(look_x), _clamp(look_y)
        throttle = _clamp(throttle, 0.0, 1.0)
        brakes = _clamp(brakes, 0.0, 1.0)
        left_t = brakes if lt is None else _clamp(float(lt), 0.0, 1.0)
        right_t = throttle if rt is None else _clamp(float(rt), 0.0, 1.0)
        kinds = {d[0] for d in self._devs}
        if targets is None:
            want = set(kinds)
        else:
            want = set(targets) & kinds
            if not want and kinds == {"uinput"}:
                want = {"uinput"}
        if profile not in ("hotas", "fbw"):
            profile = "hotas"
        mapped = remap_vjoy(profile, roll, pitch, throttle, yaw, left_t, look_x, look_y)
        fire = right_t > 0.5
        heli_degraded = mode == "heli" and "vjoy" not in want and "vgamepad" in want
        xbox_rt = throttle if heli_degraded else right_t
        xbox_fire = (right_t > 0.5) if heli_degraded else False
        for kind, lib, dev in self._devs:
            if kind not in want:
                continue
            if kind == "vjoy":
                pyvjoy = lib
                dev.set_axis(getattr(pyvjoy, "HID_USAGE_X", 0x30), self._vjoy_axis(mapped["x"]))
                dev.set_axis(getattr(pyvjoy, "HID_USAGE_Y", 0x31), self._vjoy_axis(mapped["y"]))
                dev.set_axis(getattr(pyvjoy, "HID_USAGE_Z", 0x32), self._vjoy_axis(mapped["z"]))
                dev.set_axis(getattr(pyvjoy, "HID_USAGE_RX", 0x33), self._vjoy_axis(mapped["rx"]))
                dev.set_axis(getattr(pyvjoy, "HID_USAGE_RY", 0x34), self._vjoy_axis(mapped["ry"]))
                dev.set_axis(getattr(pyvjoy, "HID_USAGE_RZ", 0x35), self._vjoy_axis(mapped["rz"]))
                dev.set_axis(getattr(pyvjoy, "HID_USAGE_SL0", 0x36), self._vjoy_axis(mapped["sl0"]))
                if mode == "heli" and fire != self._vjoy_fire:
                    try:
                        dev.set_button(16, 1 if fire else 0)
                    except Exception:
                        pass
                    self._vjoy_fire = fire
            elif kind == "vgamepad":
                dev.left_joystick_float(x_value_float=roll, y_value_float=-pitch)
                dev.right_joystick_float(x_value_float=look_x if look_x or look_y else yaw, y_value_float=-look_y)
                dev.right_trigger_float(value_float=xbox_rt)
                dev.left_trigger_float(value_float=left_t)
                if heli_degraded and xbox_fire != self._xbox_fire:
                    vg = lib
                    btn = getattr(vg.XUSB_BUTTON, "XUSB_GAMEPAD_B")
                    if xbox_fire:
                        dev.press_button(button=btn)
                    else:
                        dev.release_button(button=btn)
                    self._xbox_fire = xbox_fire
                dev.update()
            elif kind == "uinput":
                ecodes = lib
                dev.write(ecodes.EV_ABS, ecodes.ABS_X, int(roll * 1000))
                dev.write(ecodes.EV_ABS, ecodes.ABS_Y, int(-pitch * 1000))
                dev.write(ecodes.EV_ABS, ecodes.ABS_RX, int(look_x * 1000))
                dev.write(ecodes.EV_ABS, ecodes.ABS_RY, int(-look_y * 1000))
                dev.write(ecodes.EV_ABS, ecodes.ABS_THROTTLE, int(throttle * 1000))
                dev.write(ecodes.EV_ABS, ecodes.ABS_RZ, int(yaw * 1000))
                dev.write(ecodes.EV_ABS, ecodes.ABS_BRAKE, int(left_t * 1000))
                dev.syn()

    def park_backend(self, kind: str) -> None:
        zeros = dict(roll=0, pitch=0, yaw=0, look_x=0, look_y=0, throttle=0, brakes=0, lt=0, rt=0)
        self.set_axes(**zeros, targets={kind}, mode="unknown")
        if kind == "vjoy":
            self.release_all_buttons(xbox=False)
            self.center_hat()
            self._vjoy_fire = False
        elif kind == "vgamepad":
            for k, lib, dev in self._devs:
                if k != "vgamepad":
                    continue
                vg = lib
                for token in (
                    "A", "B", "X", "Y", "LEFT_SHOULDER", "RIGHT_SHOULDER",
                    "BACK", "START", "LEFT_THUMB", "RIGHT_THUMB",
                    "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
                ):
                    try:
                        dev.release_button(button=getattr(vg.XUSB_BUTTON, "XUSB_GAMEPAD_" + token))
                    except Exception:
                        pass
                try:
                    dev.update()
                except Exception:
                    pass
            self._xbox_fire = False

    X360 = {
        "a": "A", "jump": "A", "b1": "A",
        "b": "B", "crouch": "B", "b2": "B",
        "x": "X", "reload": "X", "interact": "X", "b3": "X",
        "y": "Y", "b4": "Y",
        "lb": "LEFT_SHOULDER", "lean_l": "LEFT_SHOULDER", "b5": "LEFT_SHOULDER",
        "rb": "RIGHT_SHOULDER", "lean_r": "RIGHT_SHOULDER", "b6": "RIGHT_SHOULDER",
        "back": "BACK", "b7": "BACK",
        "start": "START", "b8": "START",
        "l3": "LEFT_THUMB", "sprint": "LEFT_THUMB", "b9": "LEFT_THUMB",
        "r3": "RIGHT_THUMB", "ping": "RIGHT_THUMB", "b10": "RIGHT_THUMB",
        "dup": "DPAD_UP", "hat_up": "DPAD_UP",
        "ddown": "DPAD_DOWN", "voice": "DPAD_DOWN", "hat_down": "DPAD_DOWN",
        "dleft": "DPAD_LEFT", "hat_left": "DPAD_LEFT",
        "dright": "DPAD_RIGHT", "hat_right": "DPAD_RIGHT",
    }
    VJOY_BTN = {
        "b1": 1, "brakes": 1, "a": 1, "jump": 1,
        "b2": 2, "next_camera": 2, "view": 2, "b": 2, "crouch": 2,
        "b3": 3, "ap_toggle": 3, "x": 3, "reload": 3, "interact": 3,
        "b4": 4, "reverse": 4, "y": 4,
        "b5": 5, "spoilers_in": 5, "lb": 5, "lean_l": 5,
        "b6": 6, "spoilers": 6, "spoilers_out": 6, "rb": 6, "lean_r": 6,
        "b7": 7, "flaps_up": 7, "back": 7,
        "b8": 8, "flaps_down": 8, "start": 8, "pushback": 8,
        "b9": 9, "parking_brake": 9, "l3": 9, "sprint": 9,
        "b10": 10, "gear": 10, "r3": 10, "ping": 10, "landing_lights": 10,
        "dup": 11, "hat_up": 11,
        "ddown": 12, "voice": 12, "hat_down": 12,
        "dleft": 13, "hat_left": 13,
        "dright": 14, "hat_right": 14,
        # 开车模式扩展按钮（vJoy 11–16）。飞行时 11–14 归 hat，开车时 hat 不发，可复用为普通键。
        "b11": 11, "b12": 12, "b13": 13, "b14": 14, "b15": 15, "b16": 16,
    }
    VJOY_POV = {"hat_up": 0, "hat_right": 1, "hat_down": 2, "hat_left": 3}

    def tap_button(self, alias: str, pressed: Optional[bool] = None) -> None:
        alias = (alias or "").lower()
        down = True if pressed is None else bool(pressed)
        for kind, lib, dev in self._devs:
            if kind == "vjoy":
                pov = self.VJOY_POV.get(alias)
                if pov is not None:
                    try:
                        dev.set_disc_pov(1, pov if down else -1)
                    except Exception:
                        pass
                    if pressed is None:
                        try:
                            dev.set_disc_pov(1, -1)
                        except Exception:
                            pass
                idx = self.VJOY_BTN.get(alias)
                if not idx:
                    continue
                dev.set_button(idx, 1 if down else 0)
                if pressed is None:
                    dev.set_button(idx, 0)
            elif kind == "vgamepad":
                token = self.X360.get(alias)
                if not token:
                    continue
                vg = lib
                btn = getattr(vg.XUSB_BUTTON, "XUSB_GAMEPAD_" + token)
                if down:
                    dev.press_button(button=btn)
                else:
                    dev.release_button(button=btn)
                dev.update()
                if pressed is None:
                    dev.release_button(button=btn)
                    dev.update()
            elif kind == "uinput":
                ecodes = lib
                mapping = {
                    "a": ecodes.BTN_SOUTH, "jump": ecodes.BTN_SOUTH,
                    "b": ecodes.BTN_EAST, "crouch": ecodes.BTN_EAST,
                    "x": ecodes.BTN_WEST, "reload": ecodes.BTN_WEST, "interact": ecodes.BTN_WEST,
                    "y": ecodes.BTN_NORTH, "lb": ecodes.BTN_TL, "rb": ecodes.BTN_TR,
                    "back": ecodes.BTN_SELECT, "start": ecodes.BTN_START,
                    "l3": ecodes.BTN_THUMBL, "sprint": ecodes.BTN_THUMBL,
                    "r3": ecodes.BTN_THUMBR, "ping": ecodes.BTN_THUMBR,
                }
                code = mapping.get(alias)
                if not code:
                    continue
                dev.write(ecodes.EV_KEY, code, 1 if down else 0)
                if pressed is None:
                    dev.syn()
                    dev.write(ecodes.EV_KEY, code, 0)
                dev.syn()

    def release_all_buttons(self, xbox: bool = True) -> None:
        for kind, lib, dev in self._devs:
            if kind == "vjoy":
                for i in range(1, 17):
                    try:
                        dev.set_button(i, 0)
                    except Exception:
                        pass
                try:
                    dev.set_disc_pov(1, -1)
                except Exception:
                    pass
            elif kind == "vgamepad" and xbox:
                vg = lib
                for token in (
                    "A", "B", "X", "Y", "LEFT_SHOULDER", "RIGHT_SHOULDER",
                    "BACK", "START", "LEFT_THUMB", "RIGHT_THUMB",
                    "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT",
                ):
                    try:
                        dev.release_button(button=getattr(vg.XUSB_BUTTON, "XUSB_GAMEPAD_" + token))
                    except Exception:
                        pass
                try:
                    dev.update()
                except Exception:
                    pass
            elif kind == "uinput":
                ecodes = lib
                for code in (
                    ecodes.BTN_SOUTH, ecodes.BTN_EAST, ecodes.BTN_WEST, ecodes.BTN_NORTH,
                    ecodes.BTN_TL, ecodes.BTN_TR, ecodes.BTN_SELECT, ecodes.BTN_START,
                    ecodes.BTN_THUMBL, ecodes.BTN_THUMBR,
                ):
                    try:
                        dev.write(ecodes.EV_KEY, code, 0)
                    except Exception:
                        pass
                try:
                    dev.syn()
                except Exception:
                    pass

    def center_hat(self) -> None:
        for kind, _lib, dev in self._devs:
            if kind == "vjoy":
                try:
                    dev.set_disc_pov(1, -1)
                except Exception:
                    pass
