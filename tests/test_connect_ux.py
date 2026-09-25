"""连接体验守卫：连不上要有出口。

两条产品规矩，用源码对账（XCTest 跑不了整棵 SwiftUI 视图层）：

1. **App 侧**：连不上电脑时**不能无限重连**——尝试次数有上限，
   且用户在「连接中」随时能点「取消」。三个入口（座舱顶栏 / 起飞页 /
   设置页）都要给出口。方案 `docs/PalmDeck-v4-connect-cancel.md`。
2. **控制台侧**：「输入监测」页不能 1Hz 慢轮询，否则实时轴条看起来
   一秒一跳，被误当成链路延迟。方案 `docs/PalmDeck-v4-monitor-live.md`。
"""

import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = os.path.join(ROOT, "mobile", "ios", "App", "App", "Native")


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
        return f.read()


def _ios(*parts):
    with open(os.path.join(IOS, *parts), encoding="utf-8") as f:
        return f.read()


class TestConnectHasAnEscapeHatch(unittest.TestCase):
    """连不上 → 要么点「取消」，要么自己停在「重试」。"""

    @classmethod
    def setUpClass(cls):
        cls.ctrl = _ios("Model", "CockpitController.swift")
        cls.cockpit = _ios("Views", "CockpitView.swift")
        cls.preflight = _ios("Views", "PreflightView.swift")
        cls.settings = _ios("Views", "SettingsView.swift")

    # ---- 状态机 ----

    def test_reconnect_attempts_are_capped(self):
        self.assertIn("private let maxAttempts =", self.ctrl)
        body = self.ctrl.split("private func scheduleReconnect", 1)[1]
        self.assertIn("guard retry < maxAttempts else", body,
                      "没有上限的重连 = 用户永远卡在转圈里")
        self.assertIn("connectFailed = true", body, "放弃时要给界面一个「重试」信号")

    def test_auto_reconnect_does_not_reset_the_counter(self):
        """回归：自动重连路径一旦走「公共 connect」，`retry` 会被清零，
        上限和退避都永远不生效（变成无限重连）。
        """
        body = self.ctrl.split("func reconnect()", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("retry = 0", body,
                         "重连内部再清零 retry，上限永远到不了")
        self.assertNotIn("connect(host:", body,
                         "重连要走 open()，不能走会把 retry 清零的公共 connect()")
        self.assertIn("open(host:", body)
        # 整个控制器里 retry 只应在「用户主动发起」和「握手成功」两处清零
        resets = [ln.strip() for ln in self.ctrl.splitlines()
                  if "retry = 0" in ln and "var retry" not in ln]
        self.assertEqual(len(resets), 2,
                         "retry 清零点变多了，先确认没把重连路径也算进去：%r" % resets)

    def test_both_disconnect_paths_share_the_cap(self):
        close = self.ctrl.split("private func handleClose", 1)[1] \
                       .split("private func handleConnectTimeout", 1)[0]
        timeout = self.ctrl.split("private func handleConnectTimeout", 1)[1] \
                          .split("private func scheduleReconnect", 1)[0]
        self.assertIn("scheduleReconnect(", close, "意外断线重连要走有上限的调度")
        self.assertIn("scheduleReconnect(", timeout, "连接超时重连也要走有上限的调度")

    def test_cancel_connect_stops_everything(self):
        body = self.ctrl.split("func cancelConnect()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("autoReconnect = false", body, "取消失败后不能还偷偷重连")
        self.assertIn("net.disconnect()", body, "要真的把 8s 超时 / 套接字拆掉")
        self.assertIn("state.link = .idle", body)

    def test_a_new_connect_clears_the_failure_state(self):
        body = self.ctrl.split("func connect(host: String, ws: UInt16, udp: UInt16)", 1)[1]
        body = body.split("func reconnect()", 1)[0]
        self.assertIn("connectFailed = false", body, "手动「重试」要把失败态清掉")
        self.assertIn("retry = 0", body)

    # ---- 三个入口 ----

    def test_cockpit_chip_cancels_while_connecting(self):
        chip = self.cockpit.split("private func connectionChip", 1)[1]
        self.assertIn("if s.link == .connecting { ctrl.cancelConnect() }", chip,
                      "顶栏「一键连接」在连接中再点应该是取消，不是又发一次")
        self.assertIn('return "取消连接"', self.cockpit)

    def test_preflight_button_cancels_while_connecting(self):
        self.assertIn('if s.link == .connecting { return "取消" }', self.preflight,
                      "起飞页按钮不能是禁用的「…」——那是死路")
        btn = self.preflight.split("private var statusButton", 1)[1] \
                            .split("private var statusButtonTitle", 1)[0]
        self.assertIn("ctrl.cancelConnect()", btn)
        self.assertIn("ctrl.connectFailed", self.preflight, "失败后要给「重试」")

    def test_settings_has_cancel_and_retry_rows(self):
        self.assertIn('Label("取消连接", systemImage: "xmark.circle")', self.settings)
        self.assertIn("ctrl.cancelConnect()", self.settings)
        self.assertIn(r'Label("重试连接 \(ctrl.savedHostForUI)"', self.settings)


class TestMonitorRefreshesFast(unittest.TestCase):
    """输入监测页要比 1Hz 快，否则轴条一秒一跳，像链路延迟。"""

    @classmethod
    def setUpClass(cls):
        cls.html = _read("web", "host.html")

    def test_monitor_tab_has_a_fast_poll(self):
        self.assertIn("function setMonitorFast(on)", self.html)
        self.assertIn("setInterval(tick, 100)", self.html, "监测页要 10Hz 轮询")
        self.assertIn('setMonitorFast(name === "monitor")', self.html, "切到监测页才加速")

    def test_slow_tick_stands_down_while_fast_runs(self):
        self.assertIn("setInterval(() => { if (!monitorFast) tick(); }, 1000);", self.html,
                      "快轮询在跑时慢轮询不要再发一份")

    def test_ticks_do_not_pile_up(self):
        body = self.html.split("let tickBusy", 1)[1].split("async function tick()", 1)[1]
        self.assertIn("if (tickBusy) return;", body,
                      "10Hz 下服务端卡住会堆几百个在途请求")

    def test_last_ms_is_labeled_as_packet_age(self):
        self.assertIn("上包", self.html,
                      "last_ms 是包间隔 / 挂机时长，写成裸 `ms` 会被当成延迟")


class TestLongActionsHaveAnEscapeHatch(unittest.TestCase):
    """控制台的长请求不能无限期「点了没反应」。

    方案 `docs/PalmDeck-v4-console-busy.md`。
    """

    @classmethod
    def setUpClass(cls):
        cls.html = _read("web", "host.html")

    def test_api_has_a_timeout_and_a_busy_helper(self):
        self.assertIn("function busy(btn, label, on)", self.html)
        self.assertIn("new AbortController()", self.html, "fetch 要有可中断的 signal")
        self.assertIn("ctl.abort()", self.html)
        self.assertIn("请求超时", self.html)

    def test_apply_update_is_busy_and_bounded(self):
        body = self.html.split('$("applyUp").onclick', 1)[1].split("};", 1)[0]
        self.assertIn('busy($("applyUp"), "下载中…", true)', body)
        self.assertIn("180000", body, "下载最坏 120s，客户端超时要盖过它")
        self.assertIn('$("applyUp").disabled = !info.can_self_update || !LATEST', body,
                      "退出忙碌后要按「真有新版」重算 disabled，不能无脑点亮")
        self.assertIn('$("latestVer").innerHTML = prev', body,
                      "失败/超时要还原版本号，否则永远停在「下载中…」")

    def test_check_and_save_are_busy(self):
        for btn, label in (("checkUp", "检查中…"), ("saveCfg", "保存中…"),
                           ("layoutSave", "保存中…")):
            self.assertIn('busy($("%s"), "%s", true)' % (btn, label), self.html)

    def test_doctor_endpoints_get_a_longer_timeout(self):
        self.assertIn('api("/api/doctor", undefined, 60000)', self.html)
        self.assertIn("}, 60000);", self.html, "自检修复可能跑几十秒 PowerShell")


class TestDiscoveryRescan(unittest.TestCase):
    """首轮没搜到要能重搜，不用退出重进。

    方案 `docs/PalmDeck-v4-discovery-rescan.md`。
    """

    @classmethod
    def setUpClass(cls):
        cls.disc = _ios("Model", "Discovery.swift")
        cls.pre = _ios("Views", "PreflightView.swift")

    def test_restart_clears_and_starts_again(self):
        body = self.disc.split("func restart()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("stop()", body)
        self.assertIn("found = []", body, "重搜要先清掉旧结果，否则永远显示上一次的")
        self.assertIn("start()", body)

    def test_old_six_second_timeout_cannot_overwrite_a_fresh_search(self):
        """回归：上一轮的 6s 兜底会在重搜后立刻把状态改成「没搜到电脑」。"""
        self.assertIn("searchGen += 1", self.disc)
        body = self.disc.split("func start()", 1)[1]
        self.assertIn("self.searchGen == gen", body,
                      "兜底定时器要认「这一轮」，否则重搜后马上显示失败")

    def test_preflight_has_a_rescan_button(self):
        self.assertIn('Text("重新搜索")', self.pre)
        self.assertIn("discovery.restart()", self.pre)
