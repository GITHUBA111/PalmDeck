# PalmDeck v4 重构设计（Windows 常驻服务 + iOS App）

> 本文件定义 v4 产品边界与落地顺序。与 v3 冲突处以本文件为准；v3 的
> `docs/PalmDeck-v3-feature-design.md` 仅保留「PD v1 22 字节热路径」与
> vJoy/Xbox 轴标度两处，其余（手机 Web 座舱）作废。

## 0. 新的产品定义

只交付两件软件：

1. **Windows 常驻服务**：`PalmDeck.exe`（托盘 + 后台桥接 + 自更新）。
   自带一个**可独立配置的网页控制台**，是全部设置与验证的唯一入口。
2. **iOS App**：唯一手机端。三种控制器形态（飞机 / 开车 / 手柄），
   共用一块通用组件画布，按键由用户自己配。

**明确删除**：手机浏览器 / 加到主屏幕的 Web 座舱（`web/index.html`）。
它不再作为手机入口，也不再由服务端路由给手机。文件暂时保留仅供
Capacitor 打包壳引用，标为 deprecated，后续删除。

---

## 1. Windows 常驻服务 + 网页控制台

### 1.1 控制台是「配置中心 + 监测台 + 验证台」

打开 `http://127.0.0.1:<http>/`（托盘菜单 / 重复双击 exe / 控制台按钮均指向它）。
分页：

| 页 | 内容 |
|---|---|
| **概览** | 虚拟设备/后端/驱动错误、当前模式、连接中的 App、Hz/传输/丢包、本机地址、App 配对（IP + 深链二维码） |
|  | 配对深链：`palmdeck://connect?host=<ip>&http=<http>&ws=<ws>&udp=<udp>`（二维码与「复制配对链接」） |
| **输入监测** | 实时轴条（roll/pitch/yaw/thr/lt/rt/look）、按键位图、帽子、事件流、Hz/延迟；用于「验证 App 发出的每个通道」 |
| **绑定与曲线** | vJoy/Xbox 轴→语义轴映射、按键 alias→按钮号、死区/指数/EMA/反转、轴预设（hotas/fbw）、failsafe |
| **布局** | App 三种模式的默认布局 JSON：查看/编辑/重置，保存后由服务端下发给 App |
| **网络** | host/http/ws/udp 端口、UDP allowlist、beacon/Bonjour 开关（标注「需重启」） |
| **更新** | 当前版本、检查更新、一键自助更新（打包版 Windows） |
| **日志** | 服务端最近日志（内存环形缓冲），支持自动滚动 |

### 1.2 配置持久化

- 路径：`%APPDATA%\PalmDeck\config.json`（`palmdeck_config.py` 已有）。
- 新增写接口 `save_config(patch)`：只接受 `DEFAULTS` 中的键，按默认值类型强转，
  枚举校验后原子写回（`*.tmp` → `replace`）。
- 布局：`%APPDATA%\PalmDeck\layouts.json`，键为 `heli`/`drive`/`gamepad`。

### 1.3 REST API（服务端 `bridge.py`）

| 方法 | 路径 | 作用 |
|---|---|---|
| GET | `/api/status` | 实时状态（已有，扩展 axes/buttons/hat/dropped_udp） |
| GET | `/api/info` | 版本、平台、是否 frozen、路径、`can_self_update` |
| GET | `/api/config` | 当前配置 + 默认值 + `live`/`restart` 键清单 |
| POST | `/api/config` | `{key: value, ...}` 局部更新；可热生效的立即应用，其余提示重启 |
| POST | `/api/mode` | `{"name":"heli|drive|gamepad"}` 切换 App/座舱模式 |
| GET | `/api/logs` | 最近日志行 |
| GET | `/api/layouts` | 所有模式的布局（`?mode=` 取单个）；同时返回 `schema`/`kinds`/`bindings` |
| POST | `/api/layouts` | 保存单个 `{mode, layout}` 或批量 `{layouts:{...}}` |
| DELETE | `/api/layouts?mode=` | 删除某模式覆盖（恢复 App 内置默认） |
| GET | `/api/config/export` | 下载配置包（全部配置 + App 布局），`Content-Disposition` 附件 |
| POST | `/api/config/import` | 导入配置包；校验 `bundle` 版本，返回 `restart_required` |
| GET | `/api/update/check` | 返回远端最新版本或空串 |
| POST | `/api/update/apply` | 下载并自替换重启（仅打包 Windows） |

控制面沿用现有 WS JSON：`layouts_get` / `layouts_put`（`{mode, layout}`）↔
服务端回 `{"type":"layouts", "layouts": {...}}`，供 App 在 WS 上拉取/回传。
`hello` 携带 `version: "4.0"`、`modes`、`layout_schema`、`caps` 含 `layouts`。

**配置包格式**（`/api/config/export` ⇄ `/api/config/import`）：
```json
{
  "product": "PalmDeck",
  "bundle": 1,
  "app_version": "4.0.0",
  "exported_at": "2026-09-24T02:28:11Z",
  "config": { ...全部服务配置... },
  "layouts": { "heli": [ ... ], "drive": [ ... ], "gamepad": [ ... ] }
}
```
导入时 `bundle` 必须为 `1`；`config` 未知键丢弃、越界值夹紧；`layouts` **整包替换**
（未出现的模式被清空）；若变动含 `host/http/ws/udp/beacon/bonjour` 则 `restart_required=true`。

### 1.4 模式命名调整（v4）

- `heli`（飞机，飞行控制器）
- `drive`（开车，驾驶控制器）
- `gamepad`（游戏手柄，通用；替换 v3 的 `infantry`/步兵休息屏）

> 兼容：服务端接受 `infantry` 作为 `gamepad` 的别名一段时间。

---

## 2. iOS App

> **E2 续（已落地）**：本节 P4–P6 的「固定皮肤」已**整份删除**（`FlightDeck.swift` /
> `DriveDeck.swift` / `GamepadDeck.swift`）。现在三个模式共用一块通用组件画布
> `WidgetCanvas`；仪表盘作为**只读组件** `panel`（`Views/FlightPanel.swift`）回归，
> 可以摆在画布上，其余控件也都作为**组件**保留（档杆这类整体外观不再内置，
> 按键也不再内置语义）。详见 `docs/PalmDeck-v4-app-interaction.md` §12.6。

三种皮肤，各自对应一类真实硬件，组件库按「真实控件」建模（外观 + 行程 + 回中 + 触感）。

### 2.1 飞行控制器（heli）

- **周期变距杆 Cyclic**（2D，居中，可调曲线）
- **总距杆 Collective**（带止动/怠速位/悬停位，可反转）
- **脚舵 Pedals / 方向舵**（双向，带中位与回中）
- **仪表面板**：PFD 姿态球、扭矩/转速、高度/速度条（显示本机平滑杆位，无游戏遥测回读）
- 武器/系统按键簇、苦力帽

### 2.2 驾驶控制器（drive）

- **方向盘**（多圈，力回馈用触感模拟回正）
- **三踏板**：离合 / 刹车 / 油门（可组合）
- **档杆 / 拨片**：H 档 + 升/降档
- **仪表盘**：转速表 + 车速 + 档位 + 油量/水温
- 中控按键簇、视角触摸板 + **十字键视角**（`hat` → D-pad，按住看、松手回正）

### 2.3 游戏手柄（gamepad）

- Xbox 式布局：ABXY、双摇杆（带回中）、L3/R3、十字键、LB/RB、视图/菜单
  （LT/RT 是模拟轴 `lt`/`rt`，在自定义布局里用滑条；`b9`/`b10` 是摇杆按下，不是扳机）
- 作为通用手柄布局的默认预设（`defaultGamepad()`）；游戏手柄/菜单场景默认用它，
  但**不抢电脑键鼠**（服务端停轴）
- 与飞机 / 开车一样走 `WidgetCanvas`，可拖 / 可改 / 可删

### 2.4 App 交互规格

屏幕/状态机、通用组件画布逐控件交互、触摸手感（抓取增量 / 回中 / 曲线 / 死区 / 灵敏度）、
触觉词汇、设置与持久化键、P7 差距清单，均以 **`PalmDeck-v4-app-interaction.md`** 为准。

### 2.5 布局与绑定来源

- 默认布局：App 内置（`LayoutStore.defaults(mode:)`）；服务端存储的覆盖优先生效。
- 服务端布局存 `%APPDATA%\PalmDeck\layouts.json`，schema 见下（`palmdeck_layouts.py`）。
- App 可本地覆盖（编辑模式），可「从电脑拉取」/「上传当前模式到电脑」。
- App 存储键：`palmdeck_widgets_v10`（按模式字典）。
- 布局 schema：
  ```json
  {
    "schema": 1,
    "layouts": {
      "heli": [ { "id": str, "kind": str, "binding": str,
                  "rect": {"x":num,"y":num,"w":num,"h":num}, "label": str } ]
    }
  }
  ```
  `kind` ∈ `wheel|slider|pad|button|stick|hat|attitude`；
  `binding` ∈ `roll|pitch|yaw|throttle|brake|clutch|look|vjoy1..vjoy16|gearUp|gearDown|fire`。

---

## 3. 落地顺序（每阶段可独立验收）

- **P1（本阶段）**：服务端配置存储 + REST API + 自更新模块化 + 新版网页控制台
  （概览/监测/配置/更新/日志）。App 端不动，仍按 PD v1 包通信。
- **P2**：模式改名 `gamepad` + 兼容层；`/api/mode` 在控制台可点。
- **P3**：布局 schema + `/api/layouts` 读写；App 拉取/覆盖/回传。
- **P4（已完成）**：iOS 飞行控制器皮肤（Cyclic/Collective/Pedals/仪表）。
- **P5（已完成）**：iOS 驾驶控制器皮肤（方向盘/三踏板/档杆/仪表盘）。
- **P6（已完成）**：iOS 游戏手柄皮肤；删除 `web/index.html` 与手机 Web 入口。

---

## 4. 实施状态

### P0 — 版本号语义（已完成）

两个号分工不同，但**主版本必须一致**（`tests/test_version.py` 守卫）：

| 常量 | 位置 | 值 | 用途 |
|---|---|---|---|
| `APP_VERSION` | `updater.py:22` | `4.0.0` | 发版号：托盘 / 网页 / 自更新比较基准 |
| `PROTOCOL_VERSION` | `bridge.py:234` | `4.0` | 写入 `hello.version`，App 据此告警 |
| `MARKETING_VERSION` | `project.pbxproj` | `4.0` | iOS 「设置 → 关于 → App 版本」 |

- 修掉的原状：`APP_VERSION` 停在 `0.3.2`，而 `hello.version` 写着 `4.0` ——
  控制台自报 v0.3.2、自更新基准也是 0.3.2，发版忘了改就**推不出更新**。
- 设置 → 关于新增「电脑端版本」（取 `hello.version`）；与 App 主版本不一致时橙色告警。

### P1（已完成）

- **自更新模块化**：新增 `updater.py`（`APP_VERSION`/`can_self_update`/`check_update`/
  `apply_update`/`restart_after_update`）；`start.py` 改为 `from updater import ...`。
- **配置存储**：`palmdeck_config.py` 重写 —— `save_config(patch)` 校验/强转/原子写回；
  清理死键 `stale_warn_ms`/`release_xbox_on_infantry`，新增 `bonjour`；`live`/`restart` 分栏。
- **REST API**：`bridge.CockpitHandler` 新增 `do_POST` 与 `/api/info`、`/api/config`
  （GET+POST）、`/api/mode`、`/api/logs`、`/api/update/check`、`/api/update/apply`；
  `/api/status` 增加 `axes`/`buttons`/`hat`/`dropped_udp`；日志进内存环形缓冲 `_LOG_RING`。
- **路由**：`/`、`/host`、`/host.html` 一律 `host.html`（不再按 mobile UA 分流到 `index.html`）。
- **beacon/bonjour**：由配置决定（`beacon`/`bonjour` + `--no-beacon`/`--no-bonjour`），不再是「永远广播」。
- **网页控制台**：`web/host.html` 重建为分页控制台（概览/输入监测/配置/布局/更新/日志）。
- **测试**：新增 `tests/test_config.py`、`tests/test_console_api.py`（共 43 项通过）。

### P2（已完成）— 模式改名 `gamepad` + 兼容层

- 服务端 `MODES=("heli","drive","gamepad")`；`canonical_mode()` 把旧值 `infantry` 映射到
  `gamepad`（`set_cockpit_mode`、WS `mode`、`/api/mode` 均先归一化）。
- `live_for_mode("gamepad")`→空集，`park_gamepad_all_zero()`（原 `park_infantry…`）。
- iOS：`CockpitMode.infantry` → `.gamepad`（label「手柄」），`CockpitMode.parse()` 兼容旧
  UserDefaults；`Packet.swift`/`CockpitView.swift` 同步。
- 旧手机 Web 座舱（发 `infantry`）仍可用（别名）。

### P3（已完成）— 布局 schema + 读写 + App 拉取/回传

- 新增 `palmdeck_layouts.py`：`layouts.json` 存储，`save_layout(s)`/`get_layout`/
  `delete_layout`/`load_layouts`，含 kind/binding 白名单与 rect 归一化、原子写回。
- REST：`/api/layouts` GET/POST/DELETE；WS：`layouts_get`/`layouts_put`。
- 控制台新增「布局」页（选模式→拉取/编辑 JSON/保存/重置）。
- iOS `LayoutStore` 改为按模式字典（v10），`defaults(mode:)`+`defaultGamepad()`，
  `applyServer(raw:)`/`upload(mode:via:)`；设置页新增「从电脑拉取布局」「上传当前模式到电脑」。

### P4（已完成）— iOS 飞行控制器皮肤

- 新增 `Native/Views/FlightDeck.swift`：
  - `CollectiveLever` 总距杆（竖直拉杆 + IDLE/FLY/MAX 卡位 + 百分比读数）；
  - `CyclicControl` 周期变距杆（真机握把 + 行程十字 + 松手回中）；
  - `RudderPedals` 尾桨踏板（左右踏板联动单偏航轴 + 回中）；
  - `ArcGauge` / `BarGauge` 仪表盘 + `AttitudeBall` 组成 PFD（COLL/TRQ 弧表、
    ROLL/PITCH/YAW 双极条）；
  - `DeckButton` 硬件按键簇（开火/投弹/起落架/灯光/悬停/视角，复用 vJoy 语义）。
- `CockpitView` 中 `heli` 模式改用 `FlightDeckView`（固定硬件布局）；`drive`/`gamepad`
  仍用可编辑组件画布；设置页在飞行模式下隐藏布局编辑（改提示固定皮肤）。
- `App.xcodeproj/project.pbxproj` 注册 `FlightDeck.swift`；`xcodebuild -sdk iphonesimulator` 构建通过。

### P5（已完成）— iOS 驾驶控制器皮肤

- 新增 `Native/Views/DriveDeck.swift`：
  - `Tachometer` 转速表（270° 刻度 + 红线 + 指针，中央显示档位/车速）；
  - `DashPanel` 中控仪表盘（转速 + 油门/刹车/离合/转向液位条）；
  - `DrivePedals` 三踏板（离合/刹车/油门，独立按压保持）；
  - `GearLever` 序列式档杆（竖向闸口，换位发升/降档脉冲 b6/b5）；
  - 复用 `SteeringWheel`、`LookPad`、`DeckButton` 组成方向盘 + 视角板 + 中控按键簇。
- `CockpitView` 中 `drive` 模式改用 `DriveDeck`（固定硬件布局）；此时 `heli`/`drive`
  均为硬件皮肤，仅 `gamepad` 保留可编辑组件画布。
- 清理死状态 `ControllerState.drivePage`（无任何引用）。
- `App.xcodeproj/project.pbxproj` 注册 `DriveDeck.swift`；模拟器构建通过。

### P6（已完成）— iOS 游戏手柄皮肤 + 删除手机 Web 座舱

- 新增 `Native/Views/GamepadDeck.swift`：Xbox 式手柄（左摇杆 / 右摇杆 `LookPad` /
  十字键 `HatPad` / ABXY 菱形 / LB·RB / LT·RT / 视图·菜单）。
- `CockpitView` 中 `gamepad` 模式默认渲染 `GamepadDeck`；开关 `palmdeck_gamepad_custom`
  （设置页/「布局」按钮）可切回自定义组件画布，保留 P3 的布局同步能力。
- 删除手机 Web 座舱：`web/index.html` + `web/manifest.webmanifest`
  （`bridge.py` 早已只服务 `host.html`；`qrcode.js` 保留供控制台配对二维码）。
- `App.xcodeproj/project.pbxproj` 注册 `GamepadDeck.swift`；模拟器构建通过。

---

### P7（已完成）— App 交互加固

- 手感参数（灵敏度 / 死区 / 轴反向 / 摇杆回中 / 方向盘满舵·回正）改为 `@Published` +
  `UserDefaults` 持久化；`sensX/sensY` 接入发送曲线（`tickSmoothing`）。
- 设置新增「手感」分组（灵敏度 X/Y、死区滑条）与「触觉反馈」总开关（`palmdeck_haptics`）。
- 触觉新增：总距越过 IDLE/FLY/MAX 卡位、脚舵/方向盘过中位 `select()`。
- 连接加固：5s `ping` 心跳；`hello` 端口协商（`ws`/`udp`）；Bonjour 读 TXT 端口；
  发现列表把 `ws/udp` 传给 `connect(host:ws:udp:)`。
- 开车档位持久化（`palmdeck_gear`）。
- **布局模板**（保存 / 切换 / 还原）：每模式 12 个命名快照，内置「默认」即还原点；
  `清空`/`恢复默认`/`应用模板` 前压撤销槽；整表替换递增 `revision` 重建画布。
- 详情见 `PalmDeck-v4-app-interaction.md` §7/§9/§11。

### P7.6（已完成）— 布局模板

- 存储：`palmdeck_layout_templates_v1` / `palmdeck_layout_undo_v1`；`LayoutStore.revision`。
- UI：设置 → 布局 → **模板**段（点行切换 / 左滑重命名·删除 / `✓` 当前）；
  组件库条右侧「存为模板」。
- **App 本地专有**：不进协议、不进 `layouts.json`、不进 `/api/config/export`。
- 修掉一个真 bug：`WidgetCanvas` 的 `.overlay(.topTrailing)` 编辑按钮被组件库条盖住（死 UI）。

---

### G1（已完成）— 手感参数按模式分键

- 修掉的 bug：七个手感参数（灵敏度 X/Y、死区、四个反向）此前是**三个模式共用一份**，
  为飞机调出的 `dz=0.06` 一直跟着赛车走（ETS2 自带死区，叠上去就是中位多一段死行程）。
- `palmdeck_dz` → `palmdeck_dz.heli` / `.drive` / `.gamepad`（其余同理）；
  旧的全局键启动时一次性迁移到三个模式并删除（`Model/ShapingKeys.swift`）。
- 迁移**不改变任何手感**（三个模式拿到同一个旧值）；已有新键的不覆盖。
- `ControllerState(shapingStore:)` 存储可注入 —— 测试跑真对象但不碰真实 `UserDefaults`。
- `CockpitController.setMode` 改走 `state.applyMode(m)`（只赋 `state.mode` 会跳过参数重读）。
- 设置里两个分组的标题与脚注都标出**当前模式**。
- 详情见 `PalmDeck-v4-app-interaction.md` §12、`PalmDeck-v4-game-profiles.md` §3.3。

---

## 5. 不变量（不得破坏）

- 热路径包：`PKT = struct.Struct("<2sBB8hH")`（22 字节，little-endian），
  magic `PD`，ver `1`。字段顺序 `roll,pitch,yaw,look_x,look_y,thr,lt,rt`。
- vJoy 轴标度 `_vjoy_axis` → `[1, 0x8000]`，中点 `0x4000`。
- 手机离线 failsafe、UDP allowlist、mode owner 语义。
