// PalmDeck 拖拽吸附纯逻辑测试（不依赖 XCTest / 宿主 App）
//
// 由 tests/test_ios_snap.py 用 swiftc 编译并运行。
//
// 画布统一取 W=1000 / H=500（点），这样「归一化数字 ↔ 点」心算就能换算：
//   x = 0.4  → 400pt；w = 0.2 → 200pt；阈值 7pt、最小可见 40pt。
// 断言里不出现被测函数以外的推导（吸附距离、夹取边界都是手算的常量）。

import Foundation

var checks = 0
var failures: [String] = []

func expect(_ cond: Bool, _ msg: String) {
    checks += 1
    if !cond { failures.append(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ tol: Double = 1e-9, _ msg: String) {
    checks += 1
    if !(abs(a - b) <= tol) {
        failures.append("\(msg)：得到 \(a)，期望 \(b)（容差 \(tol)）")
    }
}

let W = 1000.0
let H = 500.0
let canvas = (w: W, h: H)

func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Snap.Rect {
    Snap.Rect(x: x, y: y, w: w, h: h)
}

// MARK: - 基本：不动、尺寸不变

func testFarFromEverythingDoesNotMove() {
    let r = Snap.drag(box(0.42, 0.42, 0.1, 0.1), others: [], canvas: canvas)
    expectClose(r.rect.x, 0.42, 1e-12, "离所有候选线都远 → x 不动")
    expectClose(r.rect.y, 0.42, 1e-12, "y 不动")
    expect(r.guideX == nil && r.guideY == nil, "没吸上就不该画线")
}

func testSizeIsNeverTouched() {
    let r = Snap.drag(box(0.4, 0.4, 0.23, 0.17), others: [box(0.4, 0.4, 0.2, 0.2)], canvas: canvas)
    expectClose(r.rect.w, 0.23, 1e-12, "吸附不改宽")
    expectClose(r.rect.h, 0.17, 1e-12, "吸附不改高")
}

// MARK: - 画布三条线

func testSnapsToCanvasCenterX() {
    // w=200pt，放 395pt ⇒ 中心 495，离画布中线 500 差 5pt
    // （y 取 0.42 是为了离横中线远一点，免得两个轴一起吸上）
    let r = Snap.drag(box(0.395, 0.42, 0.2, 0.1), others: [], canvas: canvas)
    expectClose(r.rect.x, 0.4, 1e-12, "中心吸到画布中线 → x 从 0.395 变 0.4")
    expectClose(r.guideX ?? -1, 0.5, 1e-12, "竖线画在中线")
    expect(r.guideY == nil, "y 没吸上")
}

func testSnapsToCanvasLeftEdgeX() {
    let r = Snap.drag(box(0.004, 0.4, 0.1, 0.1), others: [], canvas: canvas)
    expectClose(r.rect.x, 0.0, 1e-12, "左边缘吸到画布左边")
    expectClose(r.guideX ?? -1, 0.0, 1e-12, "竖线画在 0")
}

func testSnapsToCanvasRightEdgeViaRightAnchor() {
    // w=100pt，放 895pt ⇒ 右边缘 995，离画布右边 1000 差 5pt
    let r = Snap.drag(box(0.895, 0.4, 0.1, 0.1), others: [], canvas: canvas)
    expectClose(r.rect.x, 0.9, 1e-12, "右边缘吸到画布右边")
    expectClose(r.guideX ?? -1, 1.0, 1e-12, "竖线画在 1000")
}

func testSnapsToCanvasCenterYOnly() {
    // h=50pt，放 222pt ⇒ 中心 247，离画布横中线 250 差 3pt；x 取 0.42，离所有线都远
    let r = Snap.drag(box(0.42, 0.444, 0.1, 0.1), others: [], canvas: canvas)
    expectClose(r.rect.y, 0.45, 1e-12, "中心吸到画布横中线")
    expectClose(r.guideY ?? -1, 0.5, 1e-12, "横线画在中线")
    expect(r.guideX == nil, "x 没吸上（两轴独立）")
    expectClose(r.rect.x, 0.42, 1e-12, "x 不该被 y 的吸附带动")
}

func testCenterNeverSnapsToSomebodyElsesEdge() {
    // 别的框左边缘 300、中心 400；本框中心 396（离对方的**边** 300 很远，离中心 400 差 4pt）
    // 中心就该吸中心（400），绝不该被对方的边缘拉走
    let other = box(0.3, 0.7, 0.2, 0.2)      // 左 300 / 中心 400 / 右 500
    let r = Snap.drag(box(0.196, 0.4, 0.4, 0.1), others: [other], canvas: canvas)  // 中心 396
    expectClose(r.rect.x, 0.2, 1e-12, "中心吸对方中心（396 → 400）")
    expectClose(r.guideX ?? -1, 0.4, 1e-12, "线画在 400")
}

// MARK: - 与其它组件对齐

func testSnapsToAnotherWidgetsLeftEdge() {
    let other = box(0.3, 0.7, 0.2, 0.1)
    let r = Snap.drag(box(0.302, 0.4, 0.1, 0.1), others: [other], canvas: canvas)
    expectClose(r.rect.x, 0.3, 1e-12, "左边缘吸到另一个组件的左边缘")
    expectClose(r.guideX ?? -1, 0.3, 1e-12, "竖线画在 300")
}

func testSnapsToAnotherWidgetsCenter() {
    // 其它件中心 550（left 500 / center 550 / right 600）；本件 w=400pt，中心 548
    let other = box(0.5, 0.2, 0.1, 0.2)
    let r = Snap.drag(box(0.348, 0.4, 0.4, 0.1), others: [other], canvas: canvas)
    expectClose(r.rect.x, 0.35, 1e-12, "中心吸到对方中心线")
    expectClose(r.guideX ?? -1, 0.55, 1e-12, "竖线画在 550")
}

func testNearestCandidateWins() {
    // 两个左边缘：190 与 200；本件左边缘 188 ⇒ 应该吸 190（差 2pt），不是 200
    let a = box(0.2, 0.7, 0.1, 0.1)
    let b = box(0.19, 0.9, 0.1, 0.1)
    let r = Snap.drag(box(0.188, 0.4, 0.1, 0.1), others: [a, b], canvas: canvas)
    expectClose(r.rect.x, 0.19, 1e-12, "吸最近的那条（190 而不是 200）")
    expectClose(r.guideX ?? -1, 0.19, 1e-12, "线画在 190")
}

func testBothAxesSnapTogether() {
    let other = box(0.5, 0.6, 0.2, 0.1)
    // x：左边缘 502 → 吸 500（画布中线）；y：上边缘 303 → 吸 300（对方上边缘）
    let r = Snap.drag(box(0.502, 0.606, 0.2, 0.1), others: [other], canvas: canvas)
    expectClose(r.rect.x, 0.5, 1e-12, "x 吸画布中线")
    expectClose(r.rect.y, 0.6, 1e-12, "y 吸对方上边缘")
    expect(r.guideX != nil && r.guideY != nil, "两个轴都该有线")
}

// MARK: - 阈值

func testThresholdIsSevenPoints() {
    let hit = Snap.drag(box(0.007, 0.4, 0.2, 0.1), others: [], canvas: canvas)
    expectClose(hit.rect.x, 0.0, 1e-12, "正好 7pt 要吸")

    let miss = Snap.drag(box(0.0076, 0.4, 0.2, 0.1), others: [], canvas: canvas)
    expectClose(miss.rect.x, 0.0076, 1e-12, "7.6pt 不该吸")
    expect(miss.guideX == nil, "没吸上就没有线")
}

func testSnapCanBeSwitchedOff() {
    let r = Snap.drag(box(0.004, 0.4, 0.1, 0.1), others: [], canvas: canvas, snap: false)
    expectClose(r.rect.x, 0.004, 1e-12, "关掉吸附后只夹取、不吸")
    expect(r.guideX == nil, "关掉吸附就不该有线")
}

// MARK: - 夹取：不许拖丢

func testClampKeepsFortyPointsOnTheLeft() {
    // w=200pt：左侧最多出去 160pt，还得留 40pt
    let r = Snap.drag(box(-0.5, 0.4, 0.2, 0.1), others: [], canvas: canvas)
    expectClose(r.rect.x, -0.16, 1e-12, "往左拖到底 = -160pt（留 40pt 可见）")
}

func testClampKeepsFortyPointsOnTheRight() {
    let r = Snap.drag(box(1.5, 0.4, 0.1, 0.1), others: [], canvas: canvas)
    expectClose(r.rect.x, 0.96, 1e-12, "往右拖到底 = 960pt（留 40pt 可见）")
}

func testClampKeepsSmallWidgetFullyInside() {
    // w=20pt < 40pt：两边都不许出去
    let left = Snap.drag(box(-0.5, 0.4, 0.02, 0.1), others: [], canvas: canvas)
    expectClose(left.rect.x, 0.0, 1e-12, "小件不能出左边界")
    let right = Snap.drag(box(1.5, 0.4, 0.02, 0.1), others: [], canvas: canvas)
    expectClose(right.rect.x, 0.98, 1e-12, "小件不能出右边界")
}

func testClampHandlesOversizedWidget() {
    // w=1500pt > 画布 1000pt：区间仍是可动的（不是两端相等）
    let left = Snap.drag(box(-2, 0.4, 1.5, 0.1), others: [], canvas: canvas)
    expectClose(left.rect.x, -1.46, 1e-12, "超大件左边到底 = -(1500-40)")
    let right = Snap.drag(box(2, 0.4, 1.5, 0.1), others: [], canvas: canvas)
    expectClose(right.rect.x, 0.96, 1e-12, "超大件右边到底 = 1000-40")
}

func testClampOnTheYAxisToo() {
    let r = Snap.drag(box(0.4, -1, 0.1, 0.2), others: [], canvas: canvas)
    expectClose(r.rect.y, -0.12, 1e-12, "竖直方向同样留 40pt（h=100pt）")
}

func testClampWinsOverSnapAndDropsTheGuide() {
    // 夹取把落点拉回来之后，实际边缘已经不在那条线上了 —— 线必须撤掉，
    // 否则屏幕上会出现「线在 -170、组件却在 -160」的假对齐。
    let other = box(-0.17, 0.4, 0.05, 0.1)
    let r = Snap.drag(box(-0.165, 0.4, 0.2, 0.1), others: [other], canvas: canvas)
    expectClose(r.rect.x, -0.16, 1e-12, "先吸到 -170、再被夹回 -160")
    expect(r.guideX == nil, "夹取改掉了落点 → 这条线不能再画")
}

// MARK: - 退化输入

func testZeroCanvasIsInert() {
    let r = Snap.drag(box(0.4, 0.4, 0.1, 0.1), others: [], canvas: (w: 0, h: 0))
    expectClose(r.rect.x, 0.4, 1e-12, "画布还没量出来（0）→ 原样返回，不能变成 NaN")
    expectClose(r.rect.y, 0.4, 1e-12, "y 同理")
    expect(r.rect.x.isNaN == false, "x 不能是 NaN")
}

func testClampToCanvasHelper() {
    let r = Snap.clampToCanvas(box(1.5, 1.5, 0.1, 0.1), canvas: canvas)
    expectClose(r.x, 0.96, 1e-12, "clampToCanvas 右边界")
    expectClose(r.y, 0.92, 1e-12, "clampToCanvas 下边界（h=50pt）")
    expectClose(r.w, 0.1, 1e-12, "不改尺寸")
    let zero = Snap.clampToCanvas(box(1.5, 1.5, 0.1, 0.1), canvas: (w: 0, h: 0))
    expectClose(zero.x, 1.5, 1e-12, "画布为 0 时原样返回")
}

// MARK: - 跑

testFarFromEverythingDoesNotMove()
testSizeIsNeverTouched()
testSnapsToCanvasCenterX()
testSnapsToCanvasLeftEdgeX()
testSnapsToCanvasRightEdgeViaRightAnchor()
testSnapsToCanvasCenterYOnly()
testSnapsToAnotherWidgetsLeftEdge()
testSnapsToAnotherWidgetsCenter()
testCenterNeverSnapsToSomebodyElsesEdge()
testNearestCandidateWins()
testBothAxesSnapTogether()
testThresholdIsSevenPoints()
testSnapCanBeSwitchedOff()
testClampKeepsFortyPointsOnTheLeft()
testClampKeepsFortyPointsOnTheRight()
testClampKeepsSmallWidgetFullyInside()
testClampHandlesOversizedWidget()
testClampOnTheYAxisToo()
testClampWinsOverSnapAndDropsTheGuide()
testZeroCanvasIsInert()
testClampToCanvasHelper()

if failures.isEmpty {
    print("OK  \(checks) checks passed")
    exit(0)
} else {
    print("FAILED  \(failures.count)/\(checks)")
    for f in failures.prefix(40) { print("  ✗ \(f)") }
    exit(1)
}
