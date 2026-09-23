from __future__ import annotations


class FakeHotas:
    def __init__(self) -> None:
        self.backend = "vjoy+vgamepad"
        self.name = "fake"
        self.axes: dict = {}
        self.buttons: list = []
        self.released_xbox: list = []
        self.calls: list = []
        self.profile = "hotas"
        self.targets = None
        self.mode = "unknown"

    def set_axes(self, profile="hotas", targets=None, mode="unknown", **kw) -> None:
        self.axes = dict(kw)
        self.profile = profile
        self.targets = set(targets) if targets else None
        self.mode = mode
        self.calls.append(("axes", dict(kw), profile, self.targets, mode))

    def park_backend(self, kind: str) -> None:
        self.calls.append(("park", kind))

    def tap_button(self, name, pressed=None) -> None:
        self.buttons.append((name, pressed))

    def release_all_buttons(self, xbox: bool = True) -> None:
        self.released_xbox.append(xbox)
        self.buttons.append(("release_all", xbox))

    def center_hat(self) -> None:
        self.buttons.append(("hat", None))
