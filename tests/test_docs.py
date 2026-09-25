"""文档守卫：现状文档里写的结构，必须在代码里真的成立。

踩过的坑（两次都不小）：

1. `docs/README.md` 的 `Views/` 那行一直写着「浅/深双主题 + `AppAppearance` + `.palmAppearance()`」，
   而深色模式**早就整份删了**（「只浅色」一轮）。索引文档是新人第一份读物，
   它说还有双主题，新人就会去找 `AppAppearance` —— 找不到，然后开始怀疑自己。
2. 同一份文档写着设置侧栏「7 项」，而后来的「只浅色」把「外观」删成了 6 项。
   数字类描述最容易漂，因为改代码的人不会去 grep 文档里的数字。

所以这里不测「文档写得通不通顺」，只测**可验证的事实**：

- 现状文档（`docs/README.md` / 根 `README.md` / `使用说明.txt`）里**不得**把
  已删除的 API 当成还活着 —— 提到可以，但同一行必须写明是「删除 / 不再 / 已移除」。
  历史方案文档（light-only / redesign / TODO …）不在范围内：它们写的就是「当时是什么」。
- 文档里枚举的设置分类，必须与 `SettingsView.swift` 的 `SettingsCategory` **逐项同序**。
- 文档里说的组件数「N 类组件」，必须等于 `Widgets.swift` 里 `WidgetKind` 的 case 数。
"""

import ast
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
IOS = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native")

# 描述「现在这个产品长什么样」的文档 —— 它们说错了就是产品说错了
CURRENT_DOCS = (
    os.path.join(ROOT, "docs", "README.md"),
    os.path.join(ROOT, "README.md"),
    os.path.join(ROOT, "使用说明.txt"),
)

# 已经整份删掉的符号（深色模式 + 固定皮肤 + 遥测）。历史方案文档里可以出现。
DELETED_APIS = (
    "AppAppearance", "palmAppearance", "Color.pd(",
    "FlightDeck", "DriveDeck", "GamepadDeck", "telemetry",
)

# 同一行出现这些词，就算「已经说明它没了」，不算说谎
DELETION_MARKERS = ("删除", "不再", "不得", "已移除", "没有", "禁止", "已清", "清掉", "去掉")

# 判「有没有说明它没了」只看符号周围这么宽的上下文。
# 不能只看整行：索引文档有些行是整段话，一行里几乎总会碰巧出现「删除」之类的词
# （比如「可拖 / 缩放 / 删除」的组件描述），整行匹配就会把谎言放过去。
WINDOW = 120


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _swift_cases(src, enum_name):
    """从 `enum X: String, CaseIterable` 里取出 case 名（按声明顺序）。"""
    body = re.search(r"enum %s\b[^{]*\{(.*?)\n\}" % re.escape(enum_name), src, re.S)
    if body is None:
        return None
    out = []
    for line in body.group(1).splitlines():
        line = line.split("//", 1)[0].strip()
        m = re.match(r"case ([a-zA-Z][\w, ]*)$", line)
        if m:
            out += [c.strip() for c in m.group(1).split(",") if c.strip()]
    return out


def _settings_category_titles(src):
    """`case .connection: return "连接"` → ['连接', ...]（按枚举声明顺序）。"""
    return re.findall(r'case \.\w+: return "([^"]+)"', src.split("var symbol", 1)[0])


class TestCurrentDocsDoNotClaimDeletedApis(unittest.TestCase):
    def test_no_deleted_api_is_described_as_alive(self):
        for path in CURRENT_DOCS:
            if not os.path.exists(path):
                continue
            text = _read(path)
            for api in DELETED_APIS:
                for m in re.finditer(re.escape(api), text):
                    lo = max(0, m.start() - WINDOW)
                    ctx = text[lo:m.end() + WINDOW]
                    if any(mark in ctx for mark in DELETION_MARKERS):
                        continue
                    self.fail(
                        "%s:%d 提到已删除的 `%s`，但读起来像它还在：\n…%s…"
                        % (os.path.relpath(path, ROOT),
                           text[:m.start()].count("\n") + 1, api, ctx.replace("\n", " ")))


class TestSettingsCategoriesMatchTheCode(unittest.TestCase):
    def setUp(self):
        self.src = _read(os.path.join(IOS, "Views", "SettingsView.swift"))
        self.titles = _settings_category_titles(self.src)

    def test_code_has_the_expected_categories(self):
        self.assertEqual(self.titles, ["连接", "预设", "布局", "操纵与手感", "触觉", "帮助"])

    def test_docs_enumerating_the_sidebar_match_the_code(self):
        """文档里那行「双栏：A / B / C …」必须与代码逐项同序（含数量）。"""
        doc = _read(os.path.join(ROOT, "docs", "PalmDeck-v4-app-interaction.md"))
        m = re.search(r"双栏：([^）]*)）", doc)
        self.assertIsNotNone(m, "交互文档里的设置页那行没找到，本测试需同步")
        listed = [p.strip() for p in m.group(1).split("/")]
        self.assertEqual(listed, self.titles,
                         "文档写的设置分类与 SettingsView.swift 对不上（删了分类要同步这行）")

    def test_appearance_category_is_gone(self):
        """深色模式删除后，「外观」不再是一个分类 —— 源码里不该再有任何痕迹。

        （文档里还能提到它，比如「P9 删「外观」后为 6 项」；那种历史表述由
        `test_no_deleted_api_is_described_as_alive` 管，这里只管代码。）
        """
        self.assertNotIn("appearance", self.src.lower())
        self.assertNotIn("palmdeck_appearance", self.src)


class TestWidgetKindCountInDocsMatchesCode(unittest.TestCase):
    def test_docs_widget_count_matches_the_enum(self):
        kinds = _swift_cases(_read(os.path.join(IOS, "Views", "Widgets.swift")), "WidgetKind")
        self.assertIsNotNone(kinds, "WidgetKind 的写法变了，本测试需同步")
        doc = _read(os.path.join(ROOT, "docs", "README.md"))
        m = re.search(r"(\d+) 类组件：([^。]*)", doc)
        self.assertIsNotNone(m, "docs/README.md 里那句「N 类组件」没找到，本测试需同步")
        self.assertEqual(int(m.group(1)), len(kinds),
                         "文档写「%s 类组件」，而 WidgetKind 有 %d 个 case" % (m.group(1), len(kinds)))
        self.assertEqual([p.strip() for p in m.group(2).split("/")], [
            "方向盘", "滑条", "触摸板", "按键", "摇杆", "总距-尾桨杆", "苦力帽", "姿态球", "仪表盘",
        ], "组件清单每一项也该对得上（顺序与 `WidgetKind` 声明序一致）")


class TestDocTestCountsMatchTheCode(unittest.TestCase):
    """文档里「

    `TestX`（N 条）」的 N，必须等于那个类里真的有几个 `def test_`。
    这类数字最容易漂：加了一条测试没人会回头改文档里的数字，
    而读文档的人会拿它当「覆盖面」的依据。

    **不算**「N 条断言」（那是 assert 数，循环生成，数不出来）。
    """

    CLAIM = re.compile(r"(Test\w+)`（(\d+) 条")
    FILE_ROW = re.compile(r"^\| `tests/([\w.]+\.py)`")
    FILE_CLAIM = re.compile(r"（(\d+) 条")

    def _counts(self):
        """tests/*.py 里每个类 / 每个文件的 `def test_` 数。"""
        per_class, per_file = {}, {}
        for name in sorted(os.listdir(os.path.join(ROOT, "tests"))):
            if not name.endswith(".py"):
                continue
            tree = ast.parse(_read(os.path.join(ROOT, "tests", name)))
            total = 0
            for node in tree.body:
                if isinstance(node, ast.ClassDef):
                    n = sum(1 for b in node.body
                            if isinstance(b, ast.FunctionDef) and b.name.startswith("test_"))
                    total += n
                    if n:
                        per_class[node.name] = n
            per_file[name] = total
        return per_class, per_file

    def test_class_counts_in_docs_match_the_code(self):
        per_class, _ = self._counts()
        for path in CURRENT_DOCS + tuple(
                os.path.join(ROOT, "docs", f)
                for f in sorted(os.listdir(os.path.join(ROOT, "docs"))) if f.endswith(".md")):
            where = os.path.relpath(path, ROOT)
            for m in self.CLAIM.finditer(_read(path)):
                name, claimed = m.group(1), int(m.group(2))
                self.assertIn(name, per_class, "%s 提到的 %s 不存在" % (where, name))
                self.assertEqual(claimed, per_class[name],
                                 "%s 说 `%s` 有 %d 条，实际 %d 条"
                                 % (where, name, claimed, per_class[name]))

    def test_file_counts_in_the_docs_table_match_the_code(self):
        _, per_file = self._counts()
        for path in CURRENT_DOCS:
            for line in _read(path).splitlines():
                row = self.FILE_ROW.match(line)
                if not row:
                    continue
                m = self.FILE_CLAIM.search(line)
                if not m:
                    continue
                name, claimed = row.group(1), int(m.group(1))
                self.assertIn(name, per_file, "文档列了不存在的 %s" % name)
                self.assertEqual(claimed, per_file[name],
                                 "%s 表格说 %s 有 %d 条，实际 %d 条"
                                 % (os.path.relpath(path, ROOT), name, claimed, per_file[name]))


if __name__ == "__main__":
    unittest.main()
