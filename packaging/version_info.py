"""生成 PyInstaller 的**版本资源**（exe「属性 → 详细信息」里那几行）。

为什么要有这个文件：`packaging/PalmDeck.spec` 里 `EXE(...)` 的 `version=`
需要一个「内容是一个 `VSVersionInfo(...)` 表达式」的文本文件，
而那个表达式是由 **PyInstaller 的命名空间** `eval` 的 ——
也就是说**文件里不能写 import**，只能是个裸表达式。

所以分工是：本模块负责把裸表达式**拼出来**（纯字符串，不 import PyInstaller，
因此 macOS 上就能测），spec 负责调用它、把结果交给 `EXE(version=...)`。

版本号**只有一个来源**：`updater.APP_VERSION`（`tests/test_version.py` 守着它与
`bridge.PROTOCOL_VERSION` 的主版本一致）。本模块只接收它，从不自己写版本号 ——
否则「程序 v4.0.0 的文件属性写着 3.9」这种事迟早发生。
"""

from __future__ import annotations

import os

# `040904B0` = 语言 0x0409(en-US) + 代码页 0x04B0(Unicode)；VarFileInfo 的
# Translation 必须与之一致，否则资源管理器读不出这些字符串。
_LANG, _CODEPAGE = 1033, 1200
_STRING_TABLE = "040904B0"

# 注意：整体是一个**表达式**（不是赋值语句），PyInstaller 会 eval 它。
_TEMPLATE = """\
VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=%(ver)s,
    prodvers=%(ver)s,
    mask=0x3f,
    flags=0x0,
    OS=0x40004,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0),
  ),
  kids=[
    StringFileInfo([
      StringTable(
        u'%(table)s',
        [
          StringStruct(u'CompanyName', u'%(company)s'),
          StringStruct(u'FileDescription', u'%(desc)s'),
          StringStruct(u'FileVersion', u'%(version)s'),
          StringStruct(u'InternalName', u'PalmDeck'),
          StringStruct(u'OriginalFilename', u'PalmDeck.exe'),
          StringStruct(u'ProductName', u'%(product)s'),
          StringStruct(u'ProductVersion', u'%(version)s'),
        ],
      )
    ]),
    VarFileInfo([VarStruct(u'Translation', [%(lang)d, %(codepage)d])]),
  ],
)
"""

# 文件属性里「产品名称」/「说明」的文案（面向用户，与托盘/说明书一致）
PRODUCT = "PalmDeck"
DESCRIPTION = "PalmDeck — 手机当杆的电脑端服务"


def version_tuple(version: str) -> tuple:
    """`"4.0.0"` → `(4, 0, 0, 0)`。定长 4 段：Windows 资源要求四段。"""
    parts = []
    for piece in version.lstrip("vV").split(".")[:4]:
        try:
            parts.append(int(piece))
        except ValueError:
            parts.append(0)
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts)


def render(version: str) -> str:
    """拼出可直接交给 `EXE(version=...)` 的文本。"""
    ver = version_tuple(version)
    return _TEMPLATE % {
        "ver": "(%s)" % ", ".join(str(n) for n in ver),
        "version": version,
        "table": _STRING_TABLE,
        "company": PRODUCT,
        "product": PRODUCT,
        "desc": DESCRIPTION,
        "lang": _LANG,
        "codepage": _CODEPAGE,
    }


def write(dst: str, version: str) -> str:
    """把版本资源写进 `dst`（spec 里指向 `build/`，那是 gitignore 的中间产物）。"""
    parent = os.path.dirname(os.path.abspath(dst))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(render(version))
    return dst
