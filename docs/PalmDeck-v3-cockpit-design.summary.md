# Design summary — PalmDeck 完整虚拟飞行控制器

**Document:** `/var/folders/q3/d10yqchx4h70vctnxc7cyk400000gn/T/grok-hui/grok-design-doc-df190a49.md`  
**Date:** 2026-09-22 · **Status:** Draft  
**Based on:** `web/index.html`, `bridge.py`, `hotas.py`, `docs/PalmDeck-v3-feature-design.md`, `mobile/`

## What was produced

A frozen **phone-cockpit** spec: iPhone as a finished two-hand landscape flight stick, not an MVP that later changes grip or hit targets. Product/UX sections are in Chinese; file paths, protocol fields, and CSS tokens stay English.

HID / PD v1 / `hotas` profile / fire = vJoy 16 / `awaitModeAck` are **not** reopened. Zero additive packet fields.

## Frozen product

- **Metaphor:** the phone body is the stick (tilt → roll/pitch). The center sphere is a PFD-style **stick-position director**, not a world AH and not the primary stick.
- **Grip:** landscape only; thumbs on side rails + lower cluster; instruments live above the lower third.
- **Portrait:** a full-screen gate, never a second layout. Native plist drops Portrait. If already streaming, the gate keeps sending the last frame.
- **Layout:** HUD 32px; rails `clamp(72px, 15vw, 96px)`; 10-button row **85px**; hat+fire **68px**. Aircraft paint later cannot change these.
- **Lock** moves to HUD (holds XY, does not zero). **Calibrate** is a per-cold-start preflight action; XY packed as 0 until then.
- **Connect** is a full-screen PREFLIGHT checklist; failure is full-screen `#reconnect`, not a toast.
- **Throttle:** hold + detents idle / hover 0.42 / max; snap only on release (±0.025); no magnetic pull while dragging.
- **Rudder:** hold by default (`yawSpring=false`); bidirectional fill from center.
- **Drive / infantry:** complete secondary skins of the same app. Drive = wheel + same throttle rail. Infantry = KB/M rest, 60Hz off, 10-key grid stays on the same 85px hits.
- **Attractiveness:** motion/glow/haptic only if it reports stick/connection state. No cyber neon, bounce easing, or ads.

## Key decisions (short)

1. Phone-as-stick; sphere `pointer-events:none` while motion is on.  
2. One landscape composition; portrait is a gate.  
3. Hit targets clamped forever.  
4. Lock in HUD; invert-aware unlock; no recalibrate if locked in background.  
5. Calibrate not persisted.  
6. Connection is preflight, not settings.  
7. Throttle hold + release detents.  
8. Rudder hold default.  
9. Drive/infantry are skins, not a later redesign.  
10. PD v1 unchanged.  
11. Mode switch is a 400ms hold.  
12. Single-file `web/index.html` remains.

**Open questions:** none. Taste forks frozen (`yawSpring=false`, `thrReturnDrive=false`).

## PR build order (same design, not a reduced v1)

1. Deck shell + tokens + landscape gate + static PFD  
2. Motion / lock / cal / detents / haptics  
3. PREFLIGHT + fullscreen reconnect + HUD Hz  
4. Drive wheel + infantry rest  
5. Feel settings + iOS landscape-only plist + docs  

Ship only after PR1–PR5. Do not publish a half deck.
