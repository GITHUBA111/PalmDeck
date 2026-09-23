## Design Document Review: PalmDeck 座舱：完整虚拟飞行控制器

### Summary
Needs revision. The product freeze is real (one landscape stick, not a later grip/hit-target redesign), and most protocol claims match PD v1 / `packState` / `PalmDeckUdpPlugin`. It is not implementation-ready: the 68px hat cannot fit the specified 44/56px controls, portrait-gate vs motion-pipeline conflict would slam the stick, `awaitModeAck` is summarized in a way that would re-break infantry, and the document’s PR Plan is referenced but not actually specified.

### Issue 1: Hat + fire cluster cannot fit in the frozen 68px row
- **Severity**: critical
- **Section**: Proposed Design §2 (`#hat`), Key Decision 3, Goals (“命中框用 clamp 钉死”)
- **Description**: The design freezes `#hat` at **68px** tall and then specifies five HIG-sized controls inside it:

  ```
           [ ▲ 44 ]
  [ ◀ 44 ] [开火 56] [ ▶ 44 ]
           [ ▼ 44 ]
  ```

  “容器 68px 高，三列居中，列宽 56 / 56 / 56”. A 3-row D-pad with 44px arrows is ≥ 44+44+44 plus gaps (~140px). Even overlapping fire (56px) with up/down (44px) exceeds 68px. Today’s `.hat` is auto-sized (~36×3 + gaps ≈ 116px) via `.heli-mid { grid-template-rows: 1fr auto auto }` in `web/index.html`. Freezing 68px while keeping discrete 44px buttons is not implementable without shrinking below the document’s own floor (“禁止把按钮缩到 40px 以下”).
- **Suggestion**: Pick one and freeze it: (a) a **single** 68×68 hat pad with directional hit-testing plus a 56px fire beside it (true hat, not five buttons), or (b) keep the 5-button cluster and raise `#hat` to ~120px, reducing `#att` (iPhone 14 att is already ~158px after HUD/deck padding, not the stated ~166px). Re-run the thumb-coverage math. Add this as Alternative F; the current Alternatives list never explores packing the hat.
- **Status**: open

### Issue 2: Portrait gate says “send last XY” but the motion pipeline still consumes portrait beta/gamma
- **Severity**: critical
- **Section**: Proposed Design §1 竖屏 flowchart vs §3 体感管道; Risks row “竖屏闸门在飞行中停包”
- **Description**: §1: if already `streaming && live && haveCenter`, `#gate-rotate` “rAF 仍按最后 XY/油门/舵发包”. §3 gate `G` is only `heli && motion && !paused && !touchXY && haveCenter` — **no portrait hold**. On iPhone, rotating to portrait remaps `beta`/`gamma`; if `onOrient`/rAF keep running, the “last frame” is overwritten by a coordinate jump and those values are packed until the user rotates back. That is worse than the failsafe the risk table tries to avoid. Returning to landscape is also missing from the landscape-flip table (only `landscape-primary` ↔ `landscape-secondary`).
- **Suggestion**: Entering the gate must snapshot XY like LOCK (`freeze` + ignore orientation), keep sending that freeze + last throttle/yaw, and on return to landscape run the same invert-aware `recalOnResume` path as a landscape-side flip. Put `portraitGate` on the §3 flowchart and in the §5 state diagram. Safari cannot honor the plist lock; this path is the real product, not a belt-and-suspenders.
- **Status**: open

### Issue 3: `awaitModeAck` “一字不改” omits the infantry stream/UDP contract
- **Severity**: major
- **Section**: Proposed Design §10, §8 步兵, Key Decision 10–11; compared to `docs/PalmDeck-v3-feature-design.md` and `web/index.html`
- **Description**: v3’s helper is explicit:

  ```
  stream:
    if (name !== "infantry") { openUdp(); S.streaming = true }
    // infantry: streaming 保持 false；3× park 用 send(force=true)
  ```

  This document’s §10 reduces that to “停流 → mode JSON → 无 `cockpit_mode` 则旧 Hub 开流 / 有键则匹配或 1s。禁止在 helper 返回前 `openUdp()`.” An implementer copying §10 (or the current `web/index.html` helper) will always set `S.streaming = true` and always `openUdp()` after infantry ack. Current code already does that (`awaitModeAck` `finish()` sets `streaming = true`, then `.then(openUdp)`). The 1Hz heartbeat is also `if (S.mode === "infantry" && S.streaming && S.live)` — if streaming is correctly left false, that interval dies unless rewritten. §8 does say `S.streaming=false` and park ×3 + 1Hz, so the doc contradicts itself.
- **Suggestion**: Paste the v3 helper verbatim, including the infantry branch. Specify heartbeat as `send(true)` while `mode==="infantry" && S.live`, independent of `streaming`. Specify `pushPacket(buf, {both:true})` for the ×3 park, 1Hz, and infantry button edges (v3 §传输; today’s `pushPacket` UDP-only returns and never dual-sends). “若尚未落地，座舱 PR 与 v3 PR4 对齐” is not a cockpit contract.
- **Status**: open

### Issue 4: Motion flowchart is internally inconsistent on `haveCenter`
- **Severity**: major
- **Section**: Proposed Design §3 mermaid; Key Decision 5
- **Description**: Node `G` requires `haveCenter?` on the yes path, then the yes path still has `C{"haveCenter?"}` → `ZERO["本帧 S.roll=S.pitch=0，不偷设 center"]`. If `G` already demands `haveCenter`, `ZERO` is dead code and the deliberate change vs today (`onOrient` first frame `S.center={beta,gamma}` at `web/index.html` ~496) is unimplementable from the diagram. CAL “下一帧把当前 `rawBeta/Gamma` 写成 `center`” is also underspecified if no orientation event has arrived yet (`rawBeta` does not exist until the listener fires).
- **Suggestion**: Remove `haveCenter` from `G`. HOLD covers lock / touch / !motion; the MATH path handles `recalOnResume` then `!haveCenter → XY=0`. CAL: if `rawBeta/Gamma` are null, ignore the tap or keep the overlay up; never write `center={0,0}`.
- **Status**: open

### Issue 5: Unique HUD composition does not fit the smallest listed device
- **Severity**: major
- **Section**: Proposed Design §2 HUD; Key Decision 3; 目标机 table (SE 3 667×375)
- **Description**: One 32px row, **禁止换行**, contents `[PALMDECK] [● {device} · {hz}Hz · UDP|WS] [MOT][LOCK][CAL] [飞机][开车][步兵] [⚙]`. Mode chips are “各最小 44×28”. `status.device` today is `vJoy Device #1 + Xbox 360` (`hotas.py` name join). On SE 667 CSS px that line cannot fit without overflow or wrapping. Mode chips at 28px height in a 32px bar also miss HIG 44, while the doc claims 40px is the HIG floor (HIG is 44pt; current 10-keys are already 40px). iPhone 14 750-wide inner might fit only if `connMeta` is truncated — truncation/priority is unspecified.
- **Suggestion**: Freeze a truncation order: e.g. drop brand on narrow widths; `connMeta` = dot + `{hz}Hz` + `UDP|WS` (device name only on reconnect/settings); keep 400ms mode chips. Alternatively raise `--hud-h` to 44px and recompute `#att` on SE (~164px → ~152px). Do not claim “唯一构图” until SE 3 / 14 / 15 Pro Max have a pixel budget that adds up, including `env(safe-area-inset-*)`.
- **Status**: open

### Issue 6: Rollout cites PR1–PR5 but the document never lists them
- **Severity**: major
- **Section**: Rollout Plan (“主干上的座舱 PR 按下面顺序”; “本文件 PR1–PR5 全部合入后才…发”)
- **Description**: The writer summary has a 5-step build order (deck shell → motion/detents → PREFLIGHT → drive/infantry → settings/plist). The design doc says “按下面顺序” and then has **no PR table** — no files, no dependencies, no “what lands vs what must not change hit targets”. That is exactly the failure mode the intro forbids (shipping PR1 as a different App). Without an in-doc plan, a reviewer cannot verify it is the same design vs a reduced v1. Tests are also absent: v3 had A1–A26; this cockpit change (`haveCenter` no longer auto-set, portrait gate, 400ms mode, detents, yaw fill) has no acceptance matrix.
- **Suggestion**: Copy the five PRs into the document with files (`web/index.html`, `Info.plist`, `ios-Info.plist.additions`, `manifest.webmanifest`, `tests/test_pack_state.py` + new cases). Each PR must leave `--rail-w` / 85px / 68px (once Issue 1 is fixed) unchanged. Add a short A-matrix: portrait-while-streaming freeze, CAL-before-XY, lock-vs-`endAtt`, detent snap-on-up-only, 400ms mode, infantry `streaming===false`, A26 old Hub, landscape-left vs right notch.
- **Status**: open

### Issue 7: Drive / infantry skins are not fully specified as secondary skins
- **Severity**: major
- **Section**: Proposed Design §8; Key Decision 9; API / `#settings`
- **Description**: Direction is right (same `#app`, CSS skins, keep 85px grid for infantry shortcuts). Gaps that would force a later redesign:
  1. **Drive `#thrCol` grid** — heli column is label + detents + track; drive adds a **56px** brake at the bottom. No `grid-template-rows` for that. Reusing one DOM node (recommended) vs today’s separate `#drvThr`/`#colTrack` is not wired.
  2. **HUD MOT / LOCK / CAL in non-heli** — PREFLIGHT always demands CAL; again-open “当次仍要校准” even if `palmdeck_cfg.mode==="drive"`. Drive XY is a spring wheel (`attachStick` zeros on release); CAL/LOCK/MOT are heli-only in §3 (`onOrient` returns). Unspecified: disable those HUD buttons, or no-op, or they zero the wheel.
  3. **Drive wheel filtering** — `send()` always applies `shape(..., dz=0.06)` and EMA 0.45 to `roll/pitch`. A steering wheel with expo 1.35 is a feel fork that was not decided.
  4. **Infantry HUD Hz** — 1Hz heartbeat makes `status.hz` ~1, so §9 paints Hz **red** the entire rest mode (`<20` → `--warn`).
  5. **Settings** — `palmdeck_cfg` adds `yawSpring` / `thrReturnDrive` but `#settings` is only “手感与按钮标签”. No control list, defaults in the panel, or drive-only enablement of `thrReturnDrive`.
  6. **Mode-switch clears** — “清 look/hat/XY；不清油门”; drive additionally `yaw=0`. Current `web/index.html` ~381 also zeros `yaw`/`lt`/`rt` but not `hat` (stays last POV). Infantry→heli would restore a leftover local yaw if it is not cleared. Not tabulated per transition.
- **Suggestion**: Add a per-skin HUD enablement table, a drive `#thrCol` grid (label 16 / track 1fr / brake 56), an explicit “drive stick uses the same `shape`/EMA as heli, yes/no”, infantry Hz display (`—` or hide), settings field list, and a 3×3 mode-enter clear table (heli/drive/infantry × throttle, yaw, XY, hat, look, rt, lt, btnMask).
- **Status**: open

### Issue 8: Detent / center “tap targets” are not hittable as specified
- **Severity**: major
- **Section**: Proposed Design §2 左列油门 / 右列舵; §4 点刻度
- **Description**: HVR / IDLE / MAX and yaw 0 replace `#btnHover` / `#btnYawCenter` (today real buttons under the tracks). Spec shows 11px labels beside the rail (`0.42 ├─ HVR`). A text tick is not a 40px control. If the tick sits on the track, a tap is a drag and will not “立即写入该止动” until `pointerup` snap (±0.025), which is a different gesture. Rail width is only `clamp(72px, 15vw, 96px)` with 8px insets — no room for a 44px side chip plus a 44px handle.
- **Suggestion**: Give each detent a documented ≥40px hit rect that does not start a drag (e.g. right-edge chips, or a 16px label column inside `--rail-w` and a narrower track). Double-tap-to-center on yaw needs a move threshold so a slow drag is not a double-tap.
- **Status**: open

### Issue 9: Protocol restatement is mostly correct, with two stale or incomplete claims
- **Severity**: major
- **Section**: Proposed Design §10; API / Interface Changes; Background “v3 把电脑侧…钉死了”
- **Description**: Verified against code:
  - `PKT = struct.Struct("<2sBB8hH")` 22 bytes, `ver=1` — matches `bridge.py` and `packState()`.
  - Truth table `rt_out` / `thr_out` / `lt_out` — matches `web/index.html` 217–219 and `tests/test_pack_state.py`.
  - Default `hotas`: Z=throttle, Rz=yaw, Y=`-pitch` — matches `hotas.remap_vjoy`.
  - Fire `rt>0.5` → vJoy button 16 on heli — matches `hotas.py` ~225–230.
  - Drive brake `b2` + `S.lt` — matches `hold()`.
  - Plugin methods `open/send/close` only; idle timer in plugin not `SceneDelegate` — matches `PalmDeckUdpPlugin.swift` / `SceneDelegate.swift`.
  - `NSMotionUsageDescription` string — exact match in `Info.plist`.
  - Portrait in plist — `UISupportedInterfaceOrientations` and `~ipad` still include Portrait; `ios-Info.plist.additions` still lists Portrait. Deleting it is a real required change.
  Incomplete/stale:
  - `pushPacket` `both:true` not specified as cockpit work (Issue 3).
  - “`packageClassList` 仍是发布阻断（v3 PR6）” is stale: both `mobile/capacitor.config.json` and `mobile/ios/App/App/capacitor.config.json` already contain `"PalmDeckUdpPlugin"`. Do not send implementers to re-litigate v3 PR6 instead of the plist orientation edit.
  - JSON: “`btn` / `axes` 新座舱不发” vs leftover `hold()` path that still `ws.send({type:"btn",...})` for non-`bN`/hat names. Delete that branch in this design.
- **Suggestion**: Keep “zero additive PD fields”. Replace the `awaitModeAck` paraphrase with the v3 snippet. Strike the empty-`packageClassList` blocker or mark it done. Explicitly delete JSON `btn`/`axes` from `hold()`.
- **Status**: open

### Issue 10: Key Decisions miss two forks the rest of the spec depends on
- **Severity**: major
- **Section**: Key Decisions (1–13)
- **Description**: The 13 decisions do freeze the product as a finished stick (no “v1 then move lock / add portrait / three aircraft decks”). Missing decisions that would otherwise get relitigated mid-PR:
  - Portrait-while-streaming is **LOCK-like freeze**, not “keep `onOrient` live” (Issue 2).
  - Infantry `awaitModeAck` leaves `streaming=false` and does not `openUdp` (Issue 3).
  - Hat interaction model: 5 buttons vs one pad (Issue 1).
  - MOT is listed as 关/开/无权限 but there is no decision on **how to turn MOT off** (today `#btnMotion` only enables). Turning it off re-enables ball `pointer-events` per KD1 — a flight hazard if it is a short tap next to LOCK.
- **Suggestion**: Add KD14–16: portrait freeze; infantry stream latch; MOT off = 400ms hold or a settings toggle, not a 28px tap. Resolve hat in KD3 with an interaction model, not only a pixel number.
- **Status**: open

### Issue 11: Alternatives are fair on product forks, silent on the packing problem
- **Severity**: minor
- **Section**: Alternatives Considered A–E
- **Description**: A (touch stick as primary), B (portrait reflow), C (springs as default), D (connection sheet), E (three aircraft decks) are the right rejected forks and match user constraints. They do not examine: compact hat vs taller hat; 32px vs 44px HUD; CSS PFD vs a static director; `contentInset: automatic` in Capacitor (would double-count `env(safe-area-inset-*)` against `#app` padding — `mobile/capacitor.config.json` currently sets `contentInset: "automatic"`). Those are the trades that actually threaten the frozen numbers.
- **Suggestion**: Add Alternative F (hat pad vs 5 buttons) and G (HUD 32 vs 44). State Capacitor `contentInset: "never"` (or equivalent) so safe-area is applied once, as §1 requires.
- **Status**: open

### Issue 12: Several implementable details are still underspecified
- **Severity**: minor
- **Section**: §4 springs, §5 MOT, §6 tokens, §7 PREFLIGHT, §9 Hz
- **Description**:
  - `thrReturnDrive` `*0.28` / `yawSpring` `*0.22` have no epsilon or “snap to 0 below 0.01”; “约 120ms” is ~10% remaining at 60Hz, not arrival.
  - `--throttle-fill: #2a8f9e` vs table “青 `--pfd-cyan` 油门填充” disagree.
  - PREFLIGHT IP on SE landscape: keyboard covers most of 375px height; no scroll/sticky-field rule. “横屏键盘可用” is not a layout.
  - 400ms mode hold: no pointer-cancel, move-off, or re-entrancy while `awaitModeAck` is already in flight (today’s click handler is not re-entrant-safe either).
  - iPhone 14 att height: 369 − 32 HUD − 14 deck pad − 85 − 68 − 12 gaps ≈ **158px**, not “~166px”. Small, but this document is selling frozen pixels.
  - No offline path: step 7 requires `S.live`, so a phone without the Hub cannot even show the deck (today the sheet can be dismissed). Fine if intentional; say so.
- **Suggestion**: Add epsilon, one token for throttle fill, PREFLIGHT `overflow:auto` with IP field above the keyboard, mode-hold state (ignore a second hold until ack settles), and correct the att-height table from a real `clamp` pass.
- **Status**: open

### Issue 13: Operability of infantry and mode timeout is weaker than v3’s console contract
- **Severity**: minor
- **Section**: Observability; §9 Hz colors
- **Description**: HUD Hz copies console thresholds (≥55 green, 20–55 amber, <20 red). That is correct for heli/drive 60Hz. Infantry 1Hz and `awaitModeAck`’s 1s timeout (`MODE TIMEOUT` 1.2s then still stream) will look like a red failure during the designed rest state. `transport` fallback (`udpReady` → UDP else WS) is sound and matches `pushPacket`. No per-frame `console.log` is correct.
- **Suggestion**: Hz coloring applies only when `S.streaming`; infantry shows `HOLD` / `KB` instead of a red `1Hz`. Keep mode-timeout amber as specified.
- **Status**: open

### Strengths
- The document actually freezes a **finished flight controller**: one landscape grip, one aircraft hit-target set, paint-only future skins, portrait as a gate, PRs as construction order in intent. That matches the product ask; it is not an MVP-then-redesign.
- Pain-point table is grounded in real code: `#app` `grid-template-rows: auto auto 1fr`, portrait media query, `#btnPause` 54×54 on the ball, `#sheet` `place-items:end`, `setVert` bottom-fill on signed yaw, `applyAtt` only gated by `paused` (so motion+touch fight via `S.touchXY`), Info.plist still listing Portrait.
- Motion constants (38°/sens, expo 1.35, dz 0.06, EMA 0.45/0.50, look dz 0.05, 12ms send, invert-aware unlock) match `web/index.html` and v3; unlocking without `invY` is correctly forbidden.
- PD v1 zero-increment, `packState` truth table, fire = vJoy 16, hat+look dual-write, `PalmDeckUdpPlugin` method freeze, and “do not park on the phone” are the right protocol boundary.
- Throttle hold + release-only detents (±0.025, no magnetic drag) and default `yawSpring=false` are internally consistent with helicopter collective and with today’s `attachThr(..., "yaw", true)`.
- Visual system (tokens, 6px instrument radius, no neon/bounce/ads, motion only if it reports state) is specific enough to implement a PFD-style director rather than another cyber sheet.
- Drive-as-wheel + infantry-as-KB/M rest, keeping the 85px 10-key geometry for vJoy shortcuts, correctly refuses to drop the PC game line or to invent a phone WASD.
- Risks table already catches notch-eating-the-rail and plist-portrait-leak; those remain valid once Issues 1–2 are fixed.
