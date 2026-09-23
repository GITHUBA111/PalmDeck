import SwiftUI
import SceneKit
import QuartzCore
import UIKit

/// 3D 直升机姿态视图（SceneKit）。机身绕三轴旋转，主/尾旋翼持续自转。
final class HelicopterSceneCoordinator {
    let scene = SCNScene()
    private var heliRoot = SCNNode()
    private var mainRotor = SCNNode()
    private var tailRotor = SCNNode()

    // 自驱动刷新：不依赖 SwiftUI，保证与 60Hz 数据同步
    weak var state: ControllerState?
    private var link: CADisplayLink?

    // 材质（向座舱主题靠拢：深蓝灰机身 + 青色识别条纹）
    private let bodyMat = HelicopterSceneCoordinator.mat(UIColor(red: 0.42, green: 0.52, blue: 0.64, alpha: 1), metal: 0.62, rough: 0.32)
    private let bellyMat = HelicopterSceneCoordinator.mat(UIColor(red: 0.16, green: 0.22, blue: 0.30, alpha: 1), metal: 0.5, rough: 0.42)
    private let darkMat = HelicopterSceneCoordinator.mat(UIColor(red: 0.08, green: 0.12, blue: 0.17, alpha: 1), metal: 0.4, rough: 0.5)
    private let glassMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.08, green: 0.30, blue: 0.46, alpha: 1)
        m.metalness.contents = 0.7
        m.roughness.contents = 0.10
        m.transparency = 0.90
        return m
    }()
    private let bladeMat = HelicopterSceneCoordinator.mat(UIColor(red: 0.20, green: 0.28, blue: 0.38, alpha: 1), metal: 0.55, rough: 0.45)
    private let accentMat = HelicopterSceneCoordinator.mat(UIColor(red: 0.20, green: 0.82, blue: 1.00, alpha: 1), metal: 0.25, rough: 0.4)

    init() { build()
        let l = CADisplayLink(target: self, selector: #selector(onFrame))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    deinit { link?.invalidate() }

    @objc private func onFrame() {
        guard let s = state else { return }
        // 按显示来源选数据：本地杆位 或 游戏遥测
        apply(roll: s.displayRoll, pitch: s.displayPitch, yaw: s.displayYaw)
    }

    private static func mat(_ c: UIColor, metal: CGFloat, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.metalness.contents = metal
        m.roughness.contents = rough
        return m
    }

    private func geo(_ g: SCNGeometry, _ m: SCNMaterial) -> SCNNode {
        g.firstMaterial = m
        return SCNNode(geometry: g)
    }

    private func build() {
        scene.background.contents = HelicopterSceneCoordinator.skyTexture()

        // 相机：略微俯视的 3/4 视角
        let cam = SCNNode()
        let c = SCNCamera()
        c.fieldOfView = 38
        c.zNear = 0.1
        c.zFar = 100
        cam.camera = c
        // 从机尾后上方俯视（追尾视角）：机头（+Z）朝屏幕远方（上方）
        cam.position = SCNVector3(0, 4.2, -5.6)
        cam.look(at: SCNVector3(0, 0.1, 0.3))
        scene.rootNode.addChildNode(cam)

        // 光照
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1300
        key.position = SCNVector3(4, 5, 5)
        key.look(at: SCNVector3(0, 0, 0))   // 从右前上方照向直升机
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 700
        rim.light?.color = UIColor(red: 0.65, green: 0.78, blue: 0.98, alpha: 1)
        rim.position = SCNVector3(-5, 2, -3)
        rim.look(at: SCNVector3(0, 0, 0))   // 左后方补光
        scene.rootNode.addChildNode(rim)

        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.intensity = 550
        amb.light?.color = UIColor(red: 0.62, green: 0.72, blue: 0.92, alpha: 1)
        scene.rootNode.addChildNode(amb)

        buildFuselage()
        buildTail()
        buildRotors()
        buildGear()

        scene.rootNode.addChildNode(heliRoot)
        buildGround()
    }

    // MARK: 地面网格 + 停机坪（模拟器参考系）
    private func buildGround() {
        // 大面积参考网格（平躺平面 + 程序化网格纹理）
        let ground = SCNNode(geometry: SCNPlane(width: 64, height: 64))
        let gm = SCNMaterial()
        gm.lightingModel = .constant
        gm.diffuse.contents = HelicopterSceneCoordinator.gridTexture()
        gm.transparency = 0.7
        gm.isDoubleSided = true
        ground.geometry?.firstMaterial = gm
        ground.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        ground.position = SCNVector3(0, -1.02, 0)
        scene.rootNode.addChildNode(ground)

        // 中心停机坪标记（微弱青色方区）
        let pad = SCNNode(geometry: SCNPlane(width: 3.2, height: 3.2))
        let pm = SCNMaterial()
        pm.lightingModel = .constant
        pm.diffuse.contents = UIColor(red: 0.20, green: 0.70, blue: 0.95, alpha: 1)
        pm.transparency = 0.14
        pm.isDoubleSided = true
        pad.geometry?.firstMaterial = pm
        pad.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        pad.position = SCNVector3(0, -1.015, 0)
        scene.rootNode.addChildNode(pad)

        // 机身地面阴影（径向渐变，增强地面接触感）
        let shadow = SCNNode(geometry: SCNPlane(width: 3.6, height: 3.6))
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = HelicopterSceneCoordinator.shadowTexture()
        sm.isDoubleSided = true
        shadow.geometry?.firstMaterial = sm
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, -1.005, 0)
        scene.rootNode.addChildNode(shadow)
    }

    /// 程序化网格纹理（青色细线 + 深底）
    private static func gridTexture() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: 0.03, green: 0.06, blue: 0.10, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setStrokeColor(UIColor(red: 0.22, green: 0.72, blue: 0.95, alpha: 0.55).cgColor)
            c.setLineWidth(2)
            let step: CGFloat = 32
            var x: CGFloat = 0
            while x <= size.width { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            c.strokePath()
        }
    }

    /// 机身地面阴影（径向渐变：中心深 → 边缘透明）
    private static func shadowTexture() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0, green: 0, blue: 0, alpha: 0.60).cgColor,
                          UIColor(red: 0, green: 0, blue: 0, alpha: 0.0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawRadialGradient(grad,
                    startCenter: CGPoint(x: size.width/2, y: size.height/2), startRadius: 0,
                    endCenter: CGPoint(x: size.width/2, y: size.height/2), endRadius: size.width/2,
                    options: [])
            }
        }
    }

    /// 天空渐变（顶部深、底部微亮，模拟地平线）
    private static func skyTexture() -> UIImage {
        let size = CGSize(width: 64, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.02, green: 0.05, blue: 0.10, alpha: 1).cgColor,
                          UIColor(red: 0.10, green: 0.22, blue: 0.36, alpha: 1).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(grad,
                    start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    // MARK: 机身
    private func buildFuselage() {
        // 主舱（椭球，略长）
        let body = geo(SCNSphere(radius: 0.5), bodyMat)
        body.scale = SCNVector3(0.82, 0.88, 1.65)
        heliRoot.addChildNode(body)

        // 机腹（下侧，深色）
        let belly = geo(SCNSphere(radius: 0.5), bellyMat)
        belly.scale = SCNVector3(0.78, 0.58, 1.58)
        belly.position = SCNVector3(0, -0.16, 0.02)
        heliRoot.addChildNode(belly)

        // 机鼻（前伸）
        let nose = geo(SCNSphere(radius: 0.42), bodyMat)
        nose.scale = SCNVector3(0.70, 0.62, 0.85)
        nose.position = SCNVector3(0, -0.02, 0.92)
        heliRoot.addChildNode(nose)

        // 座舱玻璃（前上方）
        let glass = geo(SCNSphere(radius: 0.40), glassMat)
        glass.scale = SCNVector3(0.78, 0.70, 0.95)
        glass.position = SCNVector3(0, 0.13, 0.62)
        heliRoot.addChildNode(glass)

        // 机顶发动机罩
        let engine = geo(SCNSphere(radius: 0.40), bodyMat)
        engine.scale = SCNVector3(0.72, 0.55, 0.95)
        engine.position = SCNVector3(0, 0.45, 0.05)
        heliRoot.addChildNode(engine)

        // 进气口（深色）
        let intake = geo(SCNCylinder(radius: 0.11, height: 0.06), darkMat)
        intake.position = SCNVector3(0.26, 0.52, 0.30)
        intake.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        heliRoot.addChildNode(intake)

        // 侧面青色识别条纹（主题色）
        let stripe = geo(SCNBox(width: 1.02, height: 0.06, length: 1.3, chamferRadius: 0.02), accentMat)
        stripe.position = SCNVector3(0, -0.02, 0.05)
        stripe.scale = SCNVector3(0.86, 1, 1)
        heliRoot.addChildNode(stripe)
    }

    // MARK: 尾部
    private func buildTail() {
        // 尾梁（两段：近粗远细）
        let t1 = geo(SCNCylinder(radius: 0.13, height: 1.1), bodyMat)
        t1.position = SCNVector3(0, 0.10, -1.25)
        t1.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        heliRoot.addChildNode(t1)

        let t2 = geo(SCNCylinder(radius: 0.09, height: 0.9), bodyMat)
        t2.position = SCNVector3(0, 0.16, -2.1)
        t2.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        heliRoot.addChildNode(t2)

        // 垂尾（上翘）
        let fin = geo(SCNBox(width: 0.08, height: 0.55, length: 0.42, chamferRadius: 0.03), bodyMat)
        fin.position = SCNVector3(0, 0.40, -2.5)
        fin.eulerAngles = SCNVector3(-0.35, 0, 0)
        heliRoot.addChildNode(fin)

        // 平尾（小翼）
        let stab = geo(SCNBox(width: 0.7, height: 0.05, length: 0.22, chamferRadius: 0.02), bodyMat)
        stab.position = SCNVector3(0, 0.20, -2.25)
        heliRoot.addChildNode(stab)

        // 尾桨毂
        let hub = geo(SCNCylinder(radius: 0.07, height: 0.10), darkMat)
        hub.position = SCNVector3(0.12, 0.42, -2.62)
        hub.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        heliRoot.addChildNode(hub)

        // 尾桨（3 片）
        tailRotor.position = SCNVector3(0.17, 0.42, -2.62)
        tailRotor.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        for i in 0..<3 {
            let b = geo(SCNBox(width: 0.03, height: 0.60, length: 0.06, chamferRadius: 0.01), bladeMat)
            b.eulerAngles = SCNVector3(0, 0, Float(i) * (2 * Float.pi / 3))
            tailRotor.addChildNode(b)
        }
        heliRoot.addChildNode(tailRotor)
    }

    // MARK: 旋翼
    private func buildRotors() {
        // 桨毂
        let hub = geo(SCNCylinder(radius: 0.12, height: 0.16), darkMat)
        hub.position = SCNVector3(0, 0.74, 0.05)
        heliRoot.addChildNode(hub)

        // 主旋翼（4 片）
        mainRotor.position = SCNVector3(0, 0.82, 0.05)  // 桨叶较长、盘很淡
        for i in 0..<4 {
            let b = geo(SCNBox(width: 3.0, height: 0.035, length: 0.22, chamferRadius: 0.02), bladeMat)
            // 轻微下垂 + 桨叶扭转
            b.eulerAngles = SCNVector3(0, Float(i) * Float.pi / 2, 0)
            b.position = SCNVector3(0, 0, 0)
            // 用旋转把桨叶均匀分布（绕 Y）
            let holder = SCNNode()
            holder.eulerAngles = SCNVector3(0, Float(i) * Float.pi / 2, 0)
            holder.addChildNode(b)
            mainRotor.addChildNode(holder)
        }
        heliRoot.addChildNode(mainRotor)

        // 旋翼盘（半透明）
        let discMat = SCNMaterial()
        discMat.lightingModel = .constant
        discMat.diffuse.contents = UIColor(red: 0.20, green: 0.82, blue: 1.00, alpha: 1)
        discMat.transparency = 0.05
        let disc = SCNNode(geometry: SCNCylinder(radius: 1.7, height: 0.004))
        disc.geometry?.firstMaterial = discMat
        disc.position = SCNVector3(0, 0.82, 0.05)
        heliRoot.addChildNode(disc)

        // 自转
        mainRotor.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.30)))
        tailRotor.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.10)))
    }

    // MARK: 起落架
    private func buildGear() {
        for x in [-0.42, 0.42] {
            // 支柱
            let strut = geo(SCNCylinder(radius: 0.035, height: 0.55), darkMat)
            strut.position = SCNVector3(Float(x), -0.55, 0.15)
            strut.eulerAngles = SCNVector3(0.12, 0, Float(x > 0 ? -0.18 : 0.18))
            heliRoot.addChildNode(strut)
            let strut2 = strut.clone()
            strut2.position = SCNVector3(Float(x), -0.55, -0.55)
            heliRoot.addChildNode(strut2)
            // 滑橇
            let skid = geo(SCNCylinder(radius: 0.045, height: 1.7), darkMat)
            skid.position = SCNVector3(Float(x), -0.82, -0.20)
            skid.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
            heliRoot.addChildNode(skid)
        }
    }

    /// 应用姿态（roll/pitch/yaw ∈ [-1,1]）
    func apply(roll: Double, pitch: Double, yaw: Double) {
        // 注意相机在 -Z 向 +Z 看，世界 X 与屏幕左右相反，因此 roll 用 +r（右拖→右滚）
        // 满杆 = 90°（视觉直观）：roll 绕 Z，pitch 绕 X，yaw 绕 Y 最多 180°
        let halfPi = Float.pi / 2
        let y = Float(yaw * .pi)        // 转向 ±180°
        let r = Float(roll) * halfPi    // 左右倾：满杆 90°
        let p = Float(pitch) * halfPi   // 前后倾：满杆 90°
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        heliRoot.eulerAngles = SCNVector3(p, y, r)
        SCNTransaction.commit()
    }
}

struct HelicopterSceneView: UIViewRepresentable {
    @ObservedObject var state: ControllerState

    func makeCoordinator() -> HelicopterSceneCoordinator {
        let c = HelicopterSceneCoordinator()
        c.state = state
        return c
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.scene
        v.backgroundColor = UIColor(red: 0.07, green: 0.12, blue: 0.19, alpha: 1)
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false
        v.isPlaying = true
        v.preferredFramesPerSecond = 60
        v.autoenablesDefaultLighting = false
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.state = state   // 仅绑定引用，不再每帧推 transform
    }
}
