# PalmDeck v4 · 脚舵 / 视角 松手立即回正

> 走查反馈：**松手立即回正** —— 明确指 **脚舵**（yaw 滑条）和 **视角**（触摸板）。
> 只动 `Views/Controls.swift` 两个 View，不加设置项、不动协议 / 存储。

---

## 1. 目标

- **脚舵（`slider` + `yaw`）**：松手 → **立刻**回中（现在**根本不回**，停在原地）。
- **视角（`LookPad`）**：松手 → **立刻**回正（现在有约 1.5s 的指数尾巴，很黏）。
- 摇杆 / 周期杆、方向盘的行为**不变**（它们已经有各自合理的回中方式）。

## 2. 现状与证据（源码）

| 控件 | 代码 | 实际行为 |
|---|---|---|
| 脚舵 `BipolarSlider` | `onEnded`: `if abs(value) <= 0.08 { value = 0 }` | 满舵松手**留在原地**，只有靠近中心才吸 0 |
| 视角 `LookPad` | `onEnded` → `startReturn()`：60Hz，`k = min(1, 3.0·dt)` ≈ 0.05/帧 | 半衰 ≈ 0.23s、**尾巴 ≈ 1.5s** |
| 周期杆 `StickControl` | `onEnded` → `startReturn(speed: 4.5)` | 平滑回中（≈0.3s）——**本轮不动** |

**文档已经和代码分家**：`docs/PalmDeck-v4-app-interaction.md` §4.2 写的是

> 摇杆 / 周期杆 / 脚舵：松手后用 60Hz 定时器按指数逼近 0（不是瞬跳）……

即「脚舵本该回中」，但 `BipolarSlider` 没有实现（v3 规格里滑条默认是「pointerup 不回 0」，
移植到 SwiftUI 时只搬了「≤0.08 吸 0」这一半）。所以脚舵这条是**文案承诺了、行为没跟上**。

## 3. 方案

### 3.1 脚舵：`BipolarSlider` 松手瞬回中

```swift
.onEnded { _ in
    onTouch?(false)
    grabX = 0; grabValue = 0
    value = 0            // ← 自回中轴：松手立即回正（删掉原来的 ≤0.08 吸附）
}
```

**为什么不做成开关**：这个 View 只服务 `roll / pitch / yaw` 三根轴 —— 会「保持」的
（`throttle / brake / clutch / rt`）在 `WidgetView` 里走的是 `UniSlider`。
这三根都是自回中轴（和周期杆同一类），所以直接回中，不给假选项。

### 3.2 视角：`LookPad` 松手瞬回正

- `onEnded` 里去 `60Hz` 定时器，直接 `lookX = 0; lookY = 0`。
- 删掉 `returnSpeed` 参数与 `timer / lastTick / startReturn / stopReturn`（`returnSpeed` 无调用方，是死参数）。

### 3.3 与 §4.2「不是瞬跳」的差异（有意）

§4.2 原文是「摇杆 / 周期杆 / 脚舵……不是瞬跳」。本轮按走查要求改成：

| 控件 | 新规格 |
|---|---|
| 周期杆（摇杆）`StickControl` | **不变**：60Hz 平滑回中（0.004 归零） |
| 脚舵 `BipolarSlider` | **瞬回 0** |
| 视角 `LookPad` | **瞬回 0** |
| 方向盘 `SteeringWheel` | **不变**：按 `wheelReturnSpeed` 回正 |

**线上值仍然平滑**：脚舵写的是 `s.yaw`，发送前过 `tickSmoothing()` 的 `kYaw = 0.5`
（≈80ms 收尾），所以 UDP 上不会出现断崖；`look` 本来就是直发，瞬回即瞬时。

## 4. 影响面

| 文件 | 改动 |
|---|---|
| `Views/Controls.swift` | `BipolarSlider.onEnded` 瞬回；`LookPad` 去定时器 / 瞬回 / 删死参数 |
| `tests/test_deck_bindings.py` | 新增 `TestInstantRecenter` |
| `PalmDeck-v4-app-interaction.md` | §4.2 回中表按上表重写 |

**不动**：`ControllerState` / `WidgetView` 的轴路由 / `stickReturn` / `wheelReturnSpeed` /
协议 / 存储键 / 默认布局。

## 5. 验证方式

- 源码守卫 `TestInstantRecenter`：脚舵 `onEnded` 必须是 `value = 0`（且不再有 `≤0.08`）；
  视角 `onEnded` 必须是 `lookX = 0`；视角里不能再出现 `Timer` / `returnSpeed`；
  摇杆的 `startReturn(speed: 4.5)` 仍在（没被顺手改掉）。
- `xcodebuild`（Catalyst + iOS Simulator）零警告；`python3 -m unittest` 全绿。
- **限制**：本机 pi 的 bash 拿不到辅助功能权限，合成「按下 → 拖动 → 抬起」发不出去
  （见上一轮 `PalmDeck-v4-connect-banner-stable.md`），所以 `onEnded` 只能靠源码守卫 +
  逻辑推理验证，不能真机点。

## 6. 边界与不做

- 不做「按轴分别配置松手回中 / 保持」——会多一个假选项；要「保持」的轴用 `UniSlider`。
- 不给摇杆 / 方向盘加「瞬回」选项（走查只点了脚舵、视角）。
- 不新增任何存储键；`BipolarSlider` 的 `centerLabel` 死参数保持原样（本轮不扩大范围）。
