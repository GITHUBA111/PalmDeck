"""走查要求「不要再出现任何深色模式」——全仓扫描守卫。

两件东西都可能自己变黑：

1. **iOS 座舱 App**：以前有「外观（跟随系统 / 浅色 / 深色）」开关；
   关掉开关还不够，系统深色模式下 alert / 键盘 / 分享 / Catalyst 菜单栏照样黑，
   所以真正把关的是 `Info.plist` 的 `UIUserInterfaceStyle = Light`。
2. **网页控制台**（`web/host.html`）：本就是一块深底页面。与 App 是同一个产品，
   改成同一套浅色调色板，并显式声明 `color-scheme: light`（不接受系统深色 / 浏览器自动变暗）。

这份扫描管的是「还有没有第二套深色」：色值、开关、`prefers-color-scheme` 都算。
"""

import os
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "mobile", "ios", "App", "App")
WEB = os.path.join(ROOT, "web")


def _read(*parts):
    with open(os.path.join(*parts), encoding="utf-8") as f:
        return f.read()


def _swift_files():
    out = []
    for base, _dirs, files in os.walk(os.path.join(APP, "Native")):
        for name in files:
            if name.endswith(".swift"):
                out.append(os.path.join(base, name))
    return out


def _rel(path):
    return os.path.relpath(path, ROOT)


def _luminance(hex_color):
    """#rrggbb → 相对亮度（0=黑，1=白）。"""
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def _png_rows(path):
    """最小 PNG 解码（8 位灰度/RGB/RGBA，无隔行）→ [(w, h, bpp, 像素字节), ...]。

    只为了量一张 32×32 小图的平均亮度，不值得把 Pillow 拉进来做测试依赖。
    """
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "不是 PNG"
    pos, idat, hdr, palette = 8, [], None, None
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if kind == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        pos += 12 + ln
    w, h, depth, color, comp, filt, interlace = hdr
    assert depth == 8 and interlace == 0, "只支持 8 位非隔行 PNG"
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    raw = zlib.decompress(b"".join(idat))
    stride = w * channels
    rows, prev, off = [], bytearray(stride), 0
    for _ in range(h):
        ft = raw[off]
        line = bytearray(raw[off + 1:off + 1 + stride])
        off += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ft == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ft == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ft == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        rows.append(bytes(line))
        prev = line
    return w, h, color, channels, rows, palette


def png_mean_luminance(path):
    """PNG 的平均相对亮度。先用 `sips` 降到 32px（纯 Python 解 2732×2732 太慢）。"""
    small = tempfile.mktemp(suffix="_small.png")
    try:
        subprocess.run(["sips", "-Z", "32", path, "--out", small],
                       check=True, capture_output=True)
        w, h, color, channels, rows, palette = _png_rows(small)
    finally:
        if os.path.exists(small):
            os.remove(small)
    total, n = 0.0, 0
    for row in rows:
        for x in range(w):
            px = row[x * channels:(x + 1) * channels]
            if color == 3:            # 调色板图：取索引色
                i = px[0] * 3
                r, g, b = palette[i], palette[i + 1], palette[i + 2]
            elif channels >= 3:
                r, g, b = px[0], px[1], px[2]
            else:
                r = g = b = px[0]
            total += _luminance("#%02x%02x%02x" % (r, g, b))
            n += 1
    return total / max(n, 1)


class TestAppIsLightOnly(unittest.TestCase):
    """App 里不该再有主题解析的任何痕迹。"""

    def test_info_plist_pins_light(self):
        plist = _read(APP, "Info.plist")
        self.assertIn("<key>UIUserInterfaceStyle</key>", plist)
        seg = plist.split("<key>UIUserInterfaceStyle</key>", 1)[1]
        self.assertIn("<string>Light</string>", seg.split("<key>", 1)[0],
                      "系统深色会顺着 UIWindow 传进来，必须在这里钉死 Light")

    def test_no_swift_file_parses_a_color_scheme(self):
        bad = []
        for path in _swift_files():
            src = _read(path)
            for token in ("preferredColorScheme", "colorScheme",
                          "Color.pd(", "AppAppearance", "palmAppearance"):
                if token in src:
                    bad.append("%s: %s" % (_rel(path), token))
        self.assertEqual(bad, [], "深色模式又渗进来了：%s" % "; ".join(bad))

    def test_no_appearance_switch_survives(self):
        s = _read(APP, "Native", "Views", "SettingsView.swift")
        for token in ("appearance", "深色", "跟随系统"):
            self.assertNotIn(token, s, "设置里还留着可切深色的入口：%s" % token)

    def test_launch_screen_has_no_forced_dark_color(self):
        sb = _read(APP, "Base.lproj", "LaunchScreen.storyboard")
        self.assertNotIn("appearance=\"dark\"", sb)
        self.assertIn("systemBackgroundColor", sb,
                      "启动页跟随 UIUserInterfaceStyle=Light，不该自己写死颜色")

    @unittest.skipUnless(shutil.which("sips"), "需要 macOS sips 才能量图片亮度")
    def test_splash_image_is_light(self):
        """启动页原来是一张黑底图：每次冷启动都先闪一下黑屏（最显眼的“深色模式”）。"""
        imageset = os.path.join(APP, "Assets.xcassets", "Splash.imageset")
        pngs = [n for n in sorted(os.listdir(imageset)) if n.endswith(".png")]
        self.assertTrue(pngs, "启动页图片没了")
        for name in pngs:
            lum = png_mean_luminance(os.path.join(imageset, name))
            self.assertGreater(lum, 0.6,
                               "%s 平均亮度只有 %.2f：启动页是深底，冷启动会闪黑屏" % (name, lum))


class TestConsoleIsLightOnly(unittest.TestCase):
    """网页控制台：浅色调色板 + 显式声明只浅色。"""

    def setUp(self):
        self.html = _read(WEB, "host.html")

    def _palette(self):
        block = self.html.split(":root {", 1)[1].split("}", 1)[0]
        return dict(re.findall(r"--([\w-]+)\s*:\s*(#[0-9a-fA-F]{3,6})", block))

    def test_surfaces_are_light(self):
        pal = self._palette()
        for name in ("bg", "bg-soft", "card", "card2", "sunken", "track", "accent-soft"):
            self.assertIn(name, pal, "控制台缺 --%s" % name)
            self.assertGreater(_luminance(pal[name]), 0.6,
                               "--%s=%s 是深色面，白底产品里不该出现" % (name, pal[name]))

    def test_text_is_dark_on_light(self):
        pal = self._palette()
        for name in ("text", "muted"):
            self.assertLess(_luminance(pal[name]), 0.5,
                            "--%s=%s 太浅，浅底上看不清" % (name, pal[name]))

    def test_page_declares_light_only(self):
        self.assertIn('<meta name="color-scheme" content="light"', self.html,
                      "没声明 color-scheme，浏览器/系统可能自动变暗")
        self.assertIn("color-scheme: light", self.html)

    def test_old_dark_palette_is_gone(self):
        for old in ("#070b12", "#101826", "#0c1420", "#243044", "#0a1220",
                    "#162033", "#0e2a3a", "#1b2738", "#33445c", "#5a4a1e",
                    "#23543c", "#5c2b28", "#b9c7da"):
            self.assertNotIn(old, self.html, "旧的深色值 %s 还留着" % old)

    def test_no_dark_mode_media_query_in_web(self):
        for name in os.listdir(WEB):
            if name.endswith((".html", ".css", ".js")):
                self.assertNotIn("prefers-color-scheme", _read(WEB, name),
                                 "%s 想跟随系统深色" % name)

    def test_qr_stays_black_on_white(self):
        """二维码必须仍是黑模块白底：反色扫不出来。"""
        self.assertIn('ctx.fillStyle = "#fff"', self.html)
        self.assertIn('ctx.fillStyle = "#000"', self.html)


if __name__ == "__main__":
    unittest.main()
