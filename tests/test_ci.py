"""CI 自检：发版前必须跑测试。

背景：`.github/workflows/build-windows.yml` 原来只做 `pyinstaller` 打包，
**一个测试都不跑** —— 每次打 tag 发版都是裸奔：测试红绿与 exe 无关，
回归只会在玩家机器上暴露。

所以把「发版工作流必须先过测试」变成一条守卫测试：
- 有独立的 `test` job，跑 `python -m unittest`；
- `build`（出 exe / 发 Release）`needs: test` —— 测试红了就不出 exe。

同时守卫 `docs/windows-acceptance-checklist.md`（G4 真机验收清单，见 `docs/TODO.md`）：
它得在、被 `docs/README.md` 收录，**而且里面点名的检查项 id / 界面文案 / 命令
必须在代码里真的存在** —— 真机验收往往只有一次机会，一条对不上的步骤就会让整轮走查白跑。
"""

import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

WORKFLOW = os.path.join(ROOT, ".github", "workflows", "build-windows.yml")
CHECKLIST = os.path.join(ROOT, "docs", "windows-acceptance-checklist.md")
DOCS_README = os.path.join(ROOT, "docs", "README.md")
DOCTOR = os.path.join(ROOT, "palmdeck_doctor.py")
START = os.path.join(ROOT, "start.py")
BRIDGE = os.path.join(ROOT, "bridge.py")
HOST_HTML = os.path.join(ROOT, "web", "host.html")
PROFILES = os.path.join(ROOT, "docs", "PalmDeck-v4-game-profiles.md")
SPEC = os.path.join(ROOT, "packaging", "PalmDeck.spec")
VERSION_INFO = os.path.join(ROOT, "packaging", "version_info.py")
IOS = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native")


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


class TestReleaseWorkflowRunsTests(unittest.TestCase):
    def setUp(self):
        self.wf = _read(WORKFLOW)

    def test_workflow_exists(self):
        self.assertTrue(os.path.isfile(WORKFLOW))

    def test_has_a_test_job_running_unittest(self):
        self.assertIn("python -m unittest discover -s tests -q", self.wf,
                      "发版工作流必须跑测试")
        # job 名就叫 test，下一行断言 build 依赖它
        self.assertRegex(self.wf, r"(?m)^  test:")

    def test_build_needs_test(self):
        self.assertIn("needs: test", self.wf,
                      "测试没过就不该出 exe（build 要 needs: test）")

    def test_still_builds_and_releases(self):
        """别为了加测试把打包 / 发版弄丢了。"""
        self.assertIn("pyinstaller", self.wf)
        self.assertIn("startsWith(github.ref, 'refs/tags/')", self.wf)
        self.assertIn("dist/PalmDeck.exe", self.wf)

    def test_tag_must_match_app_version(self):
        """发版 tag 必须等于 `updater.APP_VERSION`，不一致就拦住。

        自更新比的是「Release 的 tag」与「exe 里的 APP_VERSION」：tag 打成
        `v0.3.3` 却装着自报 `4.0.0` 的 exe，所有人都会被判成「已是最新」——
        **静默地永远收不到更新**（这正是「点了检查更新没反应」的根因之一）。
        光比对不报错等于没拦，所以必须 `throw`。
        """
        self.assertIn("校验 tag 与 APP_VERSION 一致", self.wf,
                      "工作流缺少 tag↔APP_VERSION 守卫")
        self.assertIn("github.ref_name", self.wf)
        self.assertIn("steps.ver.outputs.version", self.wf,
                      "tag 要与读出来的 APP_VERSION 比，而不是另写一个字面量")
        self.assertRegex(self.wf, r"if \(\$tag -ne \$v\)\s*\{\s*throw",
                         "tag 不一致时必须 throw，否则等于没拦")

    def test_triggers_on_pull_request(self):
        """PR 也该跑——不然只有打 tag 才发现红。"""
        self.assertIn("pull_request", self.wf)

    def test_artifact_is_the_setup_only(self):
        """Artifacts 只传安装包（单个文件 ⇒ Actions 页直接给单文件下载）。

        传两个文件 GitHub 会把上传物打成 zip（下载多一步解压）；而 PalmDeck.exe
        那份在 Release 里本就有裸的 —— 它真正的用途是自动更新的直链，
        不在 Artifacts。
        """
        block = self.wf.split("upload-artifact", 1)[1].split("if-no-files-found", 1)[0]
        self.assertIn("PalmDeck-Setup-*.exe", block)
        self.assertNotIn("dist/PalmDeck.exe", block,
                         "Artifacts 里别放第二个文件，否则下载又变成 zip")

    def test_release_still_ships_both_assets(self):
        """Release 仍必须两份：exe 是自动更新直链（名字写死），安装包给首次安装。"""
        block = self.wf.split("发布 Release", 1)[1]
        self.assertIn("dist/PalmDeck.exe", block)
        self.assertIn("dist/PalmDeck-Setup-*.exe", block)

    def test_outcome_and_diagnostics_go_to_a_branch(self):
        """结果与诊断写回 `ci-diag` 分支（绿也写，好让 git 能判红绿）。

        job 日志要 admin（403）；REST API 匿名额度 60/h、又和整个 NAT 出口共用，
        一查就爆。只有 git 是稳的 —— 所以每次构建都要留下这条分支，
        否则红了就只能干看着。
        """
        self.assertIn("ci-diag", self.wf, "构建结果没写回分支，红了拿不到证据")
        self.assertRegex(self.wf, r"(?m)^      - name: .+\n        if: always\(\)",
                         "回写结果/诊断的步骤必须挂 if: always()（红绿都写）")


class TestWindowsAcceptanceChecklist(unittest.TestCase):
    """G4 真机验收清单：文件在、内容真、被 docs 索引收录。"""

    def setUp(self):
        self.doc = _read(CHECKLIST)

    def test_exists(self):
        self.assertTrue(os.path.isfile(CHECKLIST))

    def test_covers_the_known_blind_spots(self):
        # 这台清单存在的理由就是这些从没在真 Windows 上验过的东西
        for needle in ("vJoy", "ViGEmBus", "joy.cpl", "自检", "failsafe",
                       "WARDOGS", "欧洲卡车模拟", "熄火锁"):
            self.assertIn(needle, self.doc, f"清单应覆盖「{needle}」")

    def test_registered_in_docs_readme(self):
        self.assertIn("windows-acceptance-checklist.md", _read(DOCS_README),
                      "新文档要进 docs/README.md 的索引，否则没人找得到")


class TestChecklistMatchesTheCode(unittest.TestCase):
    """清单里点名的东西必须在代码里真的存在。

    真机验收往往只有一次机会（要在别的机器、插着真手机、装着游戏）。
    清单里写一个不存在的检查项 id、一句已经改过的界面文案、
    或者一个删掉的章节号，走查的人会卡在那儿怀疑自己——而不是怀疑清单。
    """

    # §2 要求逐条对着看的自检项 id
    DOCTOR_IDS = ("python", "backend", "driver.vjoy", "driver.vigembus",
                  "firewall", "listener.http", "listener.ws", "listener.udp", "lan")

    def setUp(self):
        self.doc = _read(CHECKLIST)
        self.doctor = _read(DOCTOR)

    def test_doctor_ids_named_in_checklist_exist(self):
        """真跑一遍 doctor，把它**真会输出**的 id 与清单里点名的对一下。

        （不能用正则搪数据：`driver.vjoy` / `listener.http` 都是拼出来的 id。）
        """
        import palmdeck_doctor as doc

        extra = {
            "backend": "vjoy", "device": "vJoy Device", "ip": "192.168.1.5",
            "listeners": {n: {"ok": True, "addr": "0.0.0.0:1"}
                          for n in ("http", "ws", "udp")},
        }
        emitted = {c["id"] for c in doc.checks(extra)} | {c["id"] for c in doc.checks()}
        for cid in self.DOCTOR_IDS:
            # 要求写成反引号代码跨度：光靠子串会让 `driver.vjoy2` 也算命中 `driver.vjoy`
            self.assertRegex(self.doc, r"`%s`" % re.escape(cid),
                             "清单 §2 应该点名自检项 `%s`" % cid)
            self.assertIn(cid, emitted, "清单写了 %s，但 doctor 不会输出这个 id" % cid)

    def test_failsafe_message_quoted_in_checklist_exists(self):
        self.assertIn("手机已离线，杆已回中（油门保持）", _read(BRIDGE),
                      "清单 §6 引用的 failsafe 文案与代码对不上")

    def test_tray_menu_labels_quoted_in_checklist_exist(self):
        start = _read(START)
        for label in ("自检…", "开机自启"):
            self.assertIn(label, self.doc)
            self.assertIn('pystray.MenuItem("%s"' % label, start,
                          "清单提到的托盘菜单项「%s」在 start.py 里不存在" % label)
    def test_console_tabs_quoted_in_checklist_exist(self):
        self.assertIn("更新", self.doc)
        self.assertIn('data-tab="update"', _read(HOST_HTML),
                      "清单 §7 提到控制台「更新」页，但网页里没有这个 tab")

    def test_referenced_doc_sections_exist(self):
        for sec in re.findall(r"§(\d+\.\d+)", self.doc):
            self.assertRegex(_read(PROFILES), r"(?m)^#+ %s " % re.escape(sec),
                             "清单引用了 §%s，但 game-profiles.md 里没这一节" % sec)

    def test_doctor_command_quoted_in_checklist_is_real(self):
        """清单说「命令行 `python palmdeck_doctor.py` 加 `--json`」—— 这两个参数得真在。"""
        self.assertIn("python palmdeck_doctor.py", self.doc)
        self.assertIn("--json", self.doc)
        self.assertIn('"--json" in argv', self.doctor,
                      "doctor 没有 --json 开关，清单 §2 给的命令是错的")

    def test_doctor_json_endpoint_quoted_in_checklist_exists(self):
        """清单让人用 `/api/doctor` 留证据 —— 这个路由得真在。

        验收机是只装 exe 的干净机器，没有 Python；能拿到完整 JSON 报告的就只有这个路由。
        """
        self.assertIn("/api/doctor", self.doc)
        self.assertIn('if path == "/api/doctor":', _read(BRIDGE),
                      "清单说的 /api/doctor 在 bridge.py 里不存在")

    def test_icon_and_version_step_in_checklist_exists(self):
        """图标 / 版本资源只能靠真机看（macOS 上没资源编译器、也没 PyInstaller）。

        清单说「文件版本 = 托盘 tooltip 里的版本号」，靠的就是 `updater.APP_VERSION`
        一处真相源；两边都得真存在。
        """
        self.assertIn("属性 → 详细信息", self.doc)
        # 托盘悬停显示的标题就是 `PalmDeck v<APP_VERSION> — 掌舵舱`（start.py 里那个 f-string），
        # 清单让人拿它当基准去比「文件版本」，两边都得真在
        self.assertRegex(_read(START), r"PalmDeck v\{APP_VERSION\}",
                         "start.py 里托盘标题不再拼 APP_VERSION，清单的基准就没了")
        # 清单让走查者核的三个字段 ↔ 版本资源里真写进去的三个键：
        #   产品名称 = ProductName / 文件版本 = FileVersion / 文件说明 = FileDescription
        # （只装了 exe 的机器上没 Python，看到的就是这三个键的值）
        for label, key in (("产品名称", "ProductName"),
                           ("文件版本", "FileVersion"),
                           ("文件说明", "FileDescription")):
            self.assertIn(label, self.doc, "清单漏了「%s」这个要核的字段" % label)
            self.assertIn("'%s'" % key, _read(VERSION_INFO),
                          "清单要人核「%s」（%s），但版本资源里没写这个键" % (label, key))

    def test_checklist_does_not_promise_a_nonexistent_exe_flag(self):
        """`start.py` 不认 `--doctor` 之类的参数，也没实现过。

        踩过：清单里写过 `PalmDeck.exe --doctor`，而 exe 的入口是 `start.py` ——
        真机上一敲就报错，走查的人会以为是环境问题。
        """
        self.assertNotIn("PalmDeck.exe --", self.doc,
                         "exe 没有命令行子命令，别在清单里写")
        for flag in ("--doctor", "--firewall", "--json"):
            self.assertNotIn("PalmDeck.exe %s" % flag, self.doc)
        # 两个真实入口得写着：控制台自检页 + 托盘菜单
        self.assertIn("自检页", self.doc)
        self.assertIn("托盘菜单", self.doc)

    def test_app_ui_strings_quoted_in_checklist_exist(self):
        """清单 §4 引用的 App 侧文案（重连提示 / 底栏「链路」）得真存在。"""
        for needle, rel in (("连接断开，重连中…", "Model/CockpitController.swift"),
                            ("链路", "Views/CockpitView.swift"),
                            ("熄火锁", "Views/CockpitView.swift"),
                            ("遥控器双杆", "Views/Layout.swift")):
            self.assertIn(needle, self.doc, "清单应该提到「%s」" % needle)
            self.assertIn(needle, _read(os.path.join(IOS, rel)),
                          "清单提到的「%s」在 %s 里找不到" % (needle, rel))

    def test_invert_keys_quoted_in_checklist_exist(self):
        """清单 §5 让人去改 `invX/invY/invYaw/invColl` —— 这四个键名得都在。"""
        self.assertIn("invX/invY/invYaw/invColl", self.doc)
        state = _read(os.path.join(IOS, "Model", "ControllerState.swift"))
        for key in ("invX", "invY", "invYaw", "invColl"):
            self.assertIn("var %s" % key, state, "%s 不是真的可调轴反向" % key)

    def test_collective_detent_values_match_the_app(self):
        """清单 §5 让人去游戏里对「悬停点落在第几格」—— 引用的止动点数值必须与代码一致。"""
        widgets = os.path.join(IOS, "Views", "Widgets.swift")
        src = _read(widgets)
        m = re.search(r"detents: isCollective \? \[([^\]]*)\]", src)
        self.assertIsNotNone(m, "Widgets.swift 里的总距止动点写法变了，本测试需同步")
        values = [v.strip() for v in m.group(1).split(",")]
        self.assertEqual(values, ["0.0", "0.42", "1.0"])
        self.assertIn("0.0, 0.42, 1.0", self.doc,
                      "清单里写的止动点数值与 Widgets.swift 对不上")
        # 正文里那句「0% / 42% / 100%」也得跟着代码走（不然改了代码、文案成谎话）
        pct = " / ".join("%g%%" % (float(v) * 100) for v in values)
        self.assertIn(pct, self.doc, "清单正文的止动百分比应与代码一致（%s）" % pct)

    def test_throttle_hold_still_defaults_to_locked(self):
        """清单 §6 让人验「冷启动总距输出为 0」—— 这条靠 `throttleHold` 默认 true。"""
        state = _read(os.path.join(IOS, "Model", "ControllerState.swift"))
        self.assertIn("var throttleHold: Bool = true", state)
        self.assertIn("throttleHold", self.doc)


if __name__ == "__main__":
    unittest.main()
