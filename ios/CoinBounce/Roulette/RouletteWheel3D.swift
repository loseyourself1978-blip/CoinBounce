import SceneKit
import SwiftUI
import UIKit

// MARK: - v12.9 轮盘的 3D 转盘（SceneKit）
/// 和 2D 的 RouletteWheelView 同一套输入（开转时刻、起始角度、开出的号码），角度和球的位置都来自 RouletteSpinMath，
/// 所以结果、时长、咔嗒声的时机都不变，只是画法换成了立体的：木碗、金边、会转的转子、格子之间的金属隔片、中心的转塔、滚动的象牙球。
final class RouletteWheel3D: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    weak var view: SCNView?

    private let rotor = SCNNode()
    private let ball = SCNNode()
    private var displayLink: CADisplayLink?

    private var spinStart: Date?
    private var wheelStart = 0.0
    private var result: Int?

    /// 球的半径（转盘半径 = 1）
    static let ballRadius: CGFloat = 0.047
    /// 转子的半径（2D 画法里号码圈画到 0.88）
    static let rotorRadius: CGFloat = 0.88

    override init() {
        super.init()
        build()
        layout(time: RouletteSpinMath.duration, spinning: false)
    }

    deinit { displayLink?.invalidate() }

    private static func pbr(_ color: UIColor, metal: CGFloat, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        return m
    }

    /// 2D 的转子画（号码圈、格子、中心）渲染成贴图。只在主线程调
    @MainActor
    static func faceImage(size: CGFloat = 2048) -> UIImage? {
        let renderer = ImageRenderer(content: RouletteWheelFace().frame(width: size, height: size))
        renderer.scale = 1
        return renderer.uiImage
    }
    private static var cachedFace: UIImage?

    /// v13 木纹贴图（桃花心木）：深浅交替的细条纹加几道大的色带，代码画的
    static let woodImage: UIImage = {
        let size = CGSize(width: 1024, height: 1024)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let g = ctx.cgContext
            UIColor(red: 0.36, green: 0.13, blue: 0.06, alpha: 1).setFill()
            g.fill(CGRect(origin: .zero, size: size))
            var seed: UInt64 = 20261121
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 100000) / 100000
            }
            // 大的色带
            for _ in 0..<26 {
                let y = rnd() * 1024, h = 20 + rnd() * 70
                UIColor(red: 0.16, green: 0.04, blue: 0.02, alpha: 0.10 + rnd() * 0.22).setFill()
                g.fill(CGRect(x: 0, y: y, width: 1024, height: h))
            }
            // 细纹：略微弯曲的线
            for _ in 0..<420 {
                let y = rnd() * 1024, amp = rnd() * 7, ph = rnd() * 6.28
                let dark = rnd() < 0.7
                (dark ? UIColor(red: 0.10, green: 0.02, blue: 0.01, alpha: 0.10 + rnd() * 0.25)
                      : UIColor(red: 0.72, green: 0.34, blue: 0.14, alpha: 0.06 + rnd() * 0.16)).setStroke()
                g.setLineWidth(0.6 + rnd() * 1.8)
                g.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x <= 1024 {
                    g.addLine(to: CGPoint(x: x, y: y + sin(x / 160 + ph) * amp))
                    x += 32
                }
                g.strokePath()
            }
        }
    }()

    private func build() {
        scene.background.contents = nil
        let on = VisualFX.enabled
        let cam = SCNCamera()
        cam.fieldOfView = 36
        cam.projectionDirection = .vertical
        cam.zNear = 0.1
        cam.zFar = 50
        cam.wantsHDR = on
        if on {
            cam.wantsExposureAdaptation = false
            cam.exposureOffset = VisualFX.exposureOffset
            cam.whitePoint = VisualFX.whitePoint
            cam.bloomThreshold = VisualFX.bloomThreshold
            cam.bloomIntensity = VisualFX.bloomIntensity
            cam.bloomBlurRadius = 4
            cam.contrast = VisualFX.contrast
            cam.saturation = VisualFX.saturation
        }
        cameraNode.camera = cam
        // v13：从正上方看下去（hj：斜着放不好观看）。正圆的转盘，0 号在上；留一点透视，转塔和木边还是立体的
        cameraNode.position = SCNVector3(0, 3.95, 0)
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 700
        key.light!.castsShadow = !VisualFX.lowTier
        key.light!.shadowMode = .deferred
        key.light!.shadowColor = UIColor.black.withAlphaComponent(0.5)
        key.light!.shadowRadius = 5
        key.light!.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light!.orthographicScale = 3
        key.light!.zNear = 0.1
        key.light!.zFar = 20
        key.position = SCNVector3(-1.2, 4, 1.6)
        key.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(key)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 260
        scene.rootNode.addChildNode(amb)
        scene.lightingEnvironment.contents = on ? PusherScene3D.sharedCasinoEnvironment : PusherScene3D.environmentImage()
        scene.lightingEnvironment.intensity = on ? VisualFX.environmentIntensity * 0.8 : 1.4

        let gold = Self.pbr(UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1), metal: 1, rough: 0.22)
        func woodMaterial(tint: UIColor, repeatS: Float, repeatT: Float) -> SCNMaterial {
            let m = Self.pbr(.white, metal: 0, rough: 0.32)
            m.diffuse.contents = Self.woodImage
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatS, repeatT, 1)
            m.multiply.contents = tint
            m.clearCoat.contents = 1.0
            m.clearCoatRoughness.contents = 0.08
            return m
        }
        let wood = woodMaterial(tint: UIColor(white: 0.85, alpha: 1), repeatS: 3, repeatT: 1)
        let track = woodMaterial(tint: UIColor(red: 1.0, green: 0.86, blue: 0.72, alpha: 1), repeatS: 2, repeatT: 0.6)
        track.diffuse.intensity = 1.35

        // 不动的部分：底、球道、木碗的边、金线、8 颗菱形钉
        let fixed = SCNNode()
        let base = SCNNode(geometry: SCNCylinder(radius: 1.12, height: 0.06))
        base.geometry!.firstMaterial = wood
        base.position = SCNVector3(0, -0.035, 0)
        fixed.addChildNode(base)
        let lane = SCNTube(innerRadius: Self.rotorRadius, outerRadius: 1.06, height: 0.05)
        lane.radialSegmentCount = 72
        lane.firstMaterial = track
        let laneNode = SCNNode(geometry: lane)
        laneNode.position = SCNVector3(0, 0.045, 0)
        fixed.addChildNode(laneNode)
        let rim = SCNTorus(ringRadius: 1.075, pipeRadius: 0.085)
        rim.ringSegmentCount = 72
        rim.pipeSegmentCount = 16
        rim.firstMaterial = wood
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, 0.07, 0)
        fixed.addChildNode(rimNode)
        for (r, y, pipe) in [(1.0, 0.105, 0.012), (1.155, 0.075, 0.012)] {
            let t = SCNTorus(ringRadius: CGFloat(r), pipeRadius: CGFloat(pipe))
            t.ringSegmentCount = 72
            t.firstMaterial = gold
            let n = SCNNode(geometry: t)
            n.position = SCNVector3(0, Float(y), 0)
            fixed.addChildNode(n)
        }
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi + .pi / 8
            // 横竖交替的菱形挡块
            let along = i % 2 == 0
            let stud = SCNNode(geometry: SCNPyramid(width: along ? 0.045 : 0.12, height: 0.035, length: along ? 0.12 : 0.045))
            stud.geometry!.firstMaterial = gold
            stud.position = SCNVector3(sin(a) * 0.97, 0.068, -cos(a) * 0.97)
            stud.eulerAngles.y = -a
            fixed.addChildNode(stud)
        }
        scene.rootNode.addChildNode(fixed.flattenedClone())

        // 转子：贴着号码圈的圆盘 + 格子之间的金属隔片 + 中心的木锥和金色转塔
        let R = Self.rotorRadius
        let disc = SCNCylinder(radius: R, height: 0.03)
        disc.radialSegmentCount = 72
        let faceM = Self.pbr(.white, metal: 0, rough: 0.35)
        faceM.clearCoat.contents = 0.6
        faceM.clearCoatRoughness.contents = 0.15
        // 贴图是整张 2D 转子画，号码圈只画到 0.88：放大到正好铺满圆盘
        // 圆柱顶面的贴图坐标和世界坐标的关系（实测）：图的上边朝 +X、右边朝 −Z（是镜像的）。
        // 要的是上边（0 号）朝远处 −Z、右边朝 +X，所以把 u、v 对调并各自翻转：(u, v) → (1 − v, 1 − u)，
        // 再绕中心缩到 0.88。合起来：u′ = 0.94 − 0.88·v，v′ = 0.94 − 0.88·u
        var tf = SCNMatrix4Identity
        tf.m11 = 0; tf.m21 = -0.88; tf.m41 = 0.94
        tf.m12 = -0.88; tf.m22 = 0; tf.m42 = 0.94
        faceM.diffuse.contentsTransform = tf
        faceM.diffuse.wrapS = .clamp
        faceM.diffuse.wrapT = .clamp
        faceMaterial = faceM
        disc.materials = [wood, faceM, wood]
        let discNode = SCNNode(geometry: disc)
        discNode.position = SCNVector3(0, 0.035, 0)
        rotor.addChildNode(discNode)

        let parts = SCNNode()
        let n = RouletteTable.pocketCount
        let slot = 2 * Float.pi / Float(n)
        let r0 = Float(R) * 0.52 / 0.88, r1 = Float(R) * 0.74 / 0.88
        for i in 0..<n {
            let a = (Float(i) + 0.5) * slot
            let fret = SCNNode(geometry: SCNBox(width: 0.008, height: 0.04, length: CGFloat(r1 - r0), chamferRadius: 0.002))
            fret.geometry!.firstMaterial = gold
            let rm = (r0 + r1) / 2
            fret.position = SCNVector3(sin(a) * rm, 0.065, -cos(a) * rm)
            fret.eulerAngles.y = -a
            parts.addChildNode(fret)
        }
        for (r, pipe) in [(r0, 0.014), (r1, 0.009)] {
            let t = SCNTorus(ringRadius: CGFloat(r), pipeRadius: CGFloat(pipe))
            t.ringSegmentCount = 72
            t.firstMaterial = gold
            let ring = SCNNode(geometry: t)
            ring.position = SCNVector3(0, 0.06, 0)
            parts.addChildNode(ring)
        }
        let cone = SCNCone(topRadius: 0.1, bottomRadius: CGFloat(r0) - 0.01, height: 0.16)
        cone.radialSegmentCount = 48
        cone.firstMaterial = track
        let coneNode = SCNNode(geometry: cone)
        coneNode.position = SCNVector3(0, 0.13, 0)
        parts.addChildNode(coneNode)
        let turret = SCNNode(geometry: SCNCylinder(radius: 0.075, height: 0.14))
        turret.geometry!.firstMaterial = gold
        turret.position = SCNVector3(0, 0.27, 0)
        parts.addChildNode(turret)
        let knob = SCNSphere(radius: 0.085)
        knob.segmentCount = 24
        knob.firstMaterial = gold
        let knobNode = SCNNode(geometry: knob)
        knobNode.position = SCNVector3(0, 0.38, 0)
        parts.addChildNode(knobNode)
        // 转塔上的四根把手：圆柱的轴原来沿 Y，用四元数直接转到辐条方向（嵌套节点在合并网格时会丢掉父节点的旋转）
        for k in 0..<4 {
            let a = Float(k) * .pi / 2 + .pi / 4
            let d = simd_float3(sin(a), 0, -cos(a))
            let arm = SCNNode(geometry: SCNCylinder(radius: 0.02, height: 0.4))
            arm.geometry!.firstMaterial = gold
            arm.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: d)
            arm.simdPosition = d * 0.2 + simd_float3(0, 0.27, 0)
            parts.addChildNode(arm)
            let tip = SCNSphere(radius: 0.035)
            tip.segmentCount = 12
            tip.firstMaterial = gold
            let tipNode = SCNNode(geometry: tip)
            tipNode.simdPosition = d * 0.4 + simd_float3(0, 0.27, 0)
            parts.addChildNode(tipNode)
        }
        rotor.addChildNode(parts.flattenedClone())
        scene.rootNode.addChildNode(rotor)

        // 象牙球
        let sphere = SCNSphere(radius: Self.ballRadius)
        sphere.segmentCount = 24
        let ivory = Self.pbr(UIColor(white: 0.97, alpha: 1), metal: 0, rough: 0.18)
        ivory.clearCoat.contents = 1.0
        ivory.emission.contents = UIColor(white: 0.25, alpha: 1)
        sphere.firstMaterial = ivory
        ball.geometry = sphere
        ball.castsShadow = true
        scene.rootNode.addChildNode(ball)
    }

    private var faceMaterial: SCNMaterial?

    /// 贴图要在主线程用 SwiftUI 渲染：视图建好以后调一次
    @MainActor
    func loadFaceIfNeeded() {
        if Self.cachedFace == nil { Self.cachedFace = Self.faceImage() }
        if let img = Self.cachedFace, faceMaterial?.diffuse.contents == nil || !(faceMaterial?.diffuse.contents is UIImage) {
            faceMaterial?.diffuse.contents = img
        }
    }

    // MARK: 输入（和 RouletteWheelView 一样）
    func apply(spinStart: Date?, wheelStart: Double, result: Int?) {
        self.spinStart = spinStart
        self.wheelStart = wheelStart
        self.result = result
        if spinStart != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.preferredFramesPerSecond = 60
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            view?.isPlaying = true
        } else {
            displayLink?.invalidate()
            displayLink = nil
            layout(time: RouletteSpinMath.duration, spinning: false)
            // 停着的时候不用一直画：再画几帧（保证停下的样子画出来了）就暂停，省电
            lock.lock()
            idleFrames = 6
            lock.unlock()
            view?.isPlaying = true
        }
    }

    private let lock = NSLock()
    private var idleFrames = 6

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        idleFrames -= 1
        let pause = idleFrames == 0
        lock.unlock()
        guard pause else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.spinStart == nil else { return }
            self.view?.isPlaying = false
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let start = spinStart else { return }
        let t = min(RouletteSpinMath.duration, max(0, Date().timeIntervalSince(start)))
        layout(time: t, spinning: true)
    }

    /// 转子的角度、球的位置。角度是「从正上方（远处）顺时针」，和 2D 画法一致
    private func layout(time t: Double, spinning: Bool) {
        let wheel = spinning ? RouletteSpinMath.wheelAngle(at: t, start: wheelStart) : wheelStart
        rotor.eulerAngles.y = Float(-wheel)
        guard let result else {
            ball.isHidden = true
            return
        }
        ball.isHidden = false
        let a = spinning ? RouletteSpinMath.ballAngle(at: t, wheelStart: wheelStart, result: result)
            : wheelStart + RouletteSpinMath.pocketAngle(index: RouletteTable.pocketIndex(of: result))
        let r = spinning ? RouletteSpinMath.ballRadius(at: t) : RouletteSpinMath.pocketRadius
        ball.position = Self.ballPosition(angle: a, radius: r)
    }

    /// 球心的位置：半径大（在球道上）时高一点，滑进格子时落到转子面上
    static func ballPosition(angle a: Double, radius r: Double) -> SCNVector3 {
        let k = min(1, max(0, (r - RouletteSpinMath.pocketRadius) / (RouletteSpinMath.trackRadius - RouletteSpinMath.pocketRadius)))
        let y = 0.05 + Double(ballRadius) + 0.03 * k
        return SCNVector3(Float(sin(a) * r), Float(y), Float(-cos(a) * r))
    }
}

/// SwiftUI 包装：参数和 RouletteWheelView 一样
struct RouletteWheel3DView: UIViewRepresentable {
    let spinStart: Date?
    let wheelStart: Double
    let result: Int?

    final class Coordinator {
        let wheel = RouletteWheel3D()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        let w = context.coordinator.wheel
        v.scene = w.scene
        v.pointOfView = w.cameraNode
        v.antialiasingMode = VisualFX.lowTier ? .none : .multisampling4X
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isUserInteractionEnabled = false
        v.preferredFramesPerSecond = 60
        v.delegate = w
        w.view = v
        w.loadFaceIfNeeded()
        w.apply(spinStart: spinStart, wheelStart: wheelStart, result: result)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.wheel.apply(spinStart: spinStart, wheelStart: wheelStart, result: result)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.wheel.stop()
    }
}
