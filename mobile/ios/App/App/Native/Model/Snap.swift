import Foundation

/// 拖动一个框时的「吸附 + 不跑丢」纯几何。
///
/// 拆出来是为了能脱离 SwiftUI 单测（`tests/ios/SnapTests.swift`，swiftc 直跑）：
/// 「吸哪条线、吸多近、至少留多少在画布里」是规则，不该藏在手势回调里。
/// 坐标一律是**归一化**的（相对画布 0~1），与 `WRect` 同构但**不依赖** `Views/`。
///
/// 调用约定：`others` 必须**不含**正在拖的那个框（由调用方过滤），
/// 否则自己会被自己吸住，怎么拖都不动。
enum Snap {
    /// 归一化矩形
    struct Rect: Equatable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    /// 吸附结果：落点 + 需要画的对齐线（归一化；nil = 这个轴没吸上）
    struct Outcome: Equatable {
        var rect: Rect
        var guideX: Double?
        var guideY: Double?
    }

    /// 吸附阈值（点）。小于这个距离才吸 —— 太大就变成「怎么拖都粘住」。
    static let threshold: Double = 7

    /// 夹取：任何情况下至少留这么多点（≈ 一根手指）在画布里。
    /// 组件被拖出画布后 `✕`/缩放手柄都可能看不见，只能整表回滚才能救 —— 这个死胡同不该存在。
    static let minVisible: Double = 40

    /// 拖动落点 = 先吸附（可选）再夹取（必做）。
    ///
    /// - `canvas`: 画布尺寸（点）。为 0 时退化为「不吸、不夹」，不崩。
    static func drag(_ moving: Rect,
                     others: [Rect],
                     canvas: (w: Double, h: Double),
                     snap: Bool = true) -> Outcome {
        let W = canvas.w, H = canvas.h
        // 画布还没量出来（0）：原样返回，别做除法（0/0 = NaN 会把 rect 写坏）
        guard W > 0, H > 0 else { return Outcome(rect: moving, guideX: nil, guideY: nil) }
        let pw = moving.w * W, ph = moving.h * H
        var x0 = moving.x * W, y0 = moving.y * H

        var guideX: Double?
        var guideY: Double?

        if snap {
            // 边缘只和边缘对、中心只和中心对（**不跨类**）：
            // 把本框的「中心」吸到别的框的「边」上，看着就是歪的，
            // 而且会把本来想做的「边对边」顶掉（亲测：两个同宽滑条并排时会被中心-右边缘抢走）。
            let edgeX = [0, W] + others.flatMap { o -> [Double] in
                [o.x * W, (o.x + o.w) * W]
            }
            if let hit = nearest([(edgeX, [x0, x0 + pw]),
                                  ([W / 2] + others.map { ($0.x + $0.w / 2) * W },
                                   [x0 + pw / 2])]) {
                x0 += hit.delta
                guideX = hit.line / W
            }

            let edgeY = [0, H] + others.flatMap { o -> [Double] in
                [o.y * H, (o.y + o.h) * H]
            }
            if let hit = nearest([(edgeY, [y0, y0 + ph]),
                                  ([H / 2] + others.map { ($0.y + $0.h / 2) * H },
                                   [y0 + ph / 2])]) {
                y0 += hit.delta
                guideY = hit.line / H
            }
        }

        x0 = clamp(x0, lo: -max(0, pw - minVisible), hi: W - min(pw, minVisible))
        y0 = clamp(y0, lo: -max(0, ph - minVisible), hi: H - min(ph, minVisible))

        // 夹取把落点拉回来以后，实际边缘可能已经不在那条线上了 —— 那就别画，
        // 否则屏幕上会出现「线在一边、组件在另一边」的假对齐。
        if let g = guideX, !touches(line: g * W, anchors: [x0, x0 + pw / 2, x0 + pw]) {
            guideX = nil
        }
        if let g = guideY, !touches(line: g * H, anchors: [y0, y0 + ph / 2, y0 + ph]) {
            guideY = nil
        }

        return Outcome(rect: Rect(x: x0 / W, y: y0 / H, w: moving.w, h: moving.h),
                       guideX: guideX, guideY: guideY)
    }

    /// 就地把归一化坐标夹回「至少留 minVisible 在画布内」。
    /// 拖动之外（例如以后接缩放、或服务端下发了一份越界布局）也能用。
    static func clampToCanvas(_ r: Rect, canvas: (w: Double, h: Double)) -> Rect {
        let W = canvas.w, H = canvas.h
        guard W > 0, H > 0 else { return r }
        let pw = r.w * W, ph = r.h * H
        return Rect(x: clamp(r.x * W, lo: -max(0, pw - minVisible), hi: W - min(pw, minVisible)) / W,
                    y: clamp(r.y * H, lo: -max(0, ph - minVisible), hi: H - min(ph, minVisible)) / H,
                    w: r.w, h: r.h)
    }

    // MARK: - 私有

    private struct Hit {
        let delta: Double
        let line: Double
    }

    /// 候选线里离任一锚点最近的那条（距离 > threshold 视为没吸上）。
    /// 平手时取「组序 → 候选序 → 锚点序」更靠前的，保证结果稳定可复现。
    private static func nearest(_ groups: [(cands: [Double], anchors: [Double])]) -> Hit? {
        var best: Hit?
        for group in groups {
            for c in group.cands {
                for a in group.anchors {
                    let d = c - a
                    if abs(d) > threshold { continue }
                    if best == nil || abs(d) < abs(best!.delta) {
                        best = Hit(delta: d, line: c)
                    }
                }
            }
        }
        return best
    }

    private static func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
        // lo 可能大于 hi（框比画布还大 / 画布为 0）：这时以 lo 为准，别来回横跳
        min(max(v, lo), max(lo, hi))
    }

    /// 吸住的边是否真的落在这条线上（夹取会改落点，所以画线前要复验一遍）。
    private static func touches(line: Double, anchors: [Double], eps: Double = 0.5) -> Bool {
        anchors.contains { abs($0 - line) <= eps }
    }
}
