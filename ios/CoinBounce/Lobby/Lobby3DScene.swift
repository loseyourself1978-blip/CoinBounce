import SceneKit
import SwiftUI
import UIKit

// MARK: - v12.9 大厅的 3D 场景（SceneKit）
/// 一个赌场大厅：会反光的地面、铺红毯的台阶和舞台、墙上四扇发光的拱门（每扇门里飘着那个游戏的立体标志）、
/// 上面一块带灯泡的招牌。相机很慢地左右晃，真机上还跟着手机的倾斜动，前景和后墙有视差。
/// 顶栏、兔女郎和气泡仍然是 SwiftUI，叠在这个画面上面；四扇门的点按区域也是 SwiftUI 的透明按钮（位置从这里投影出来）。
final class Lobby3DScene: NSObject, SCNSceneRendererDelegate {
    struct Door {
        let screen: AppRouter.Screen
        let identifier: String
        let title: String
        let tint: UIColor
        let x: Float
    }

    /// 回大厅时复用同一个场景（搭一次要几十毫秒，还要编译着色器）
    static let shared = Lobby3DScene()

    static let doorWidth: Float = 0.82, doorSpacing: Float = 0.92
    static let stageHeight: Float = 1.2, stageDepth: Float = 2.2
    static let doorRect: Float = 1.35            // 拱门直的那一段的高度；上面再加半径 doorWidth/2 的半圆
    static var doorTop: Float { stageHeight + doorRect + doorWidth / 2 }
    static let plateY: Float = 3.2
    static let signCenterY: Float = 4.32, signHeight: Float = 1.1, signWidth: Float = 3.5
    static let cameraHeight: Float = 1.6
    static let fov: CGFloat = 50

    let doors: [Door]
    let scene = SCNScene()
    let cameraNode = SCNNode()
    weak var view: SCNView?

    /// 第一帧画出来了（主线程回调；SwiftUI 这时把 3D 画面淡入）
    var onFirstFrame: (() -> Void)?
    private(set) var hasRendered = false
    var reduceMotion = false

    private(set) var cameraDistance: Float = 9.6
    private var bulbA = SCNMaterial(), bulbB = SCNMaterial()
    private var bulbPhase = -1
    private var emblems: [SCNNode] = []
    private let lock = NSLock()
    private var tiltX: Float = 0, tiltY: Float = 0
    private var frames = 0
    private var fpsWindow: TimeInterval = 0

    /// 四扇门的定义（x 由 layout 排）
    static var allDoors: [Door] {
        [
            Door(screen: .pusher, identifier: "doorPusher", title: String(localized: "Coin Pusher"),
                 tint: UIColor(red: 1.0, green: 0.74, blue: 0.2, alpha: 1), x: 0),
            Door(screen: .roulette, identifier: "doorRoulette", title: String(localized: "Roulette"),
                 tint: UIColor(red: 0.2, green: 0.85, blue: 0.45, alpha: 1), x: 0),
            Door(screen: .pinball, identifier: "doorPachinko", title: String(localized: "Pinball"),
                 tint: UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1), x: 0),
            Door(screen: .slots, identifier: "doorSlots", title: String(localized: "Slots"),
                 tint: UIColor(red: 0.95, green: 0.35, blue: 0.8, alpha: 1), x: 0),
        ]
    }

    /// 把要显示的门左右对称地排开。门少的时候间距放宽一点，不然两扇门挤在正中间
    static func layout(_ shown: [Door]) -> [Door] {
        let n = shown.count
        let dx = doorSpacing * (n <= 2 ? 1.5 : 1)
        return shown.enumerated().map { i, d in
            Door(screen: d.screen, identifier: d.identifier, title: d.title, tint: d.tint, x: (Float(i) - Float(n - 1) / 2) * dx)
        }
    }

    private override init() {
        doors = Self.layout(Self.allDoors.filter { AppRouter.isAvailable($0.screen) })
        super.init()
        let t0 = CACurrentMediaTime()
        buildLights()
        buildHall()
        buildSign()
        for d in doors { buildDoor(d) }
        placeCamera(sway: .zero)
        NSLog("LOBBY3D_BUILD ms=%.0f", (CACurrentMediaTime() - t0) * 1000)
    }

    // MARK: 材质
    private static func pbr(_ color: UIColor, metal: CGFloat, rough: CGFloat, emission: UIColor? = nil, intensity: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let emission {
            m.emission.contents = emission
            m.emission.intensity = intensity
        }
        return m
    }
    private static let goldColor = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1)
    private lazy var gold = Self.pbr(Self.goldColor, metal: 1, rough: 0.24)
    private lazy var chrome = Self.pbr(UIColor(white: 0.93, alpha: 1), metal: 1, rough: 0.1)

    private func box(_ w: Float, _ h: Float, _ d: Float, at p: SCNVector3, _ m: SCNMaterial, chamfer: CGFloat = 0, into parent: SCNNode) {
        let n = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: chamfer))
        n.geometry!.firstMaterial = m
        n.position = p
        parent.addChildNode(n)
    }

    // MARK: 灯光、相机
    private func buildLights() {
        scene.background.contents = UIColor(red: 0.07, green: 0.01, blue: 0.03, alpha: 1)
        let on = VisualFX.enabled
        let cam = SCNCamera()
        cam.fieldOfView = Self.fov
        cam.projectionDirection = .vertical
        cam.zNear = 0.2
        cam.zFar = 80
        cam.wantsHDR = on
        if on {
            cam.wantsExposureAdaptation = false
            cam.exposureOffset = VisualFX.exposureOffset
            cam.whitePoint = VisualFX.whitePoint
            cam.bloomThreshold = VisualFX.bloomThreshold
            cam.bloomIntensity = VisualFX.lowTier ? VisualFX.bloomIntensity : VisualFX.bloomIntensity * 1.4
            cam.bloomBlurRadius = VisualFX.lowTier ? 4 : 6
            cam.bloomIterationCount = VisualFX.lowTier ? 1 : 2
            cam.bloomIterationSpread = 0.5
            cam.contrast = VisualFX.contrast
            cam.saturation = VisualFX.saturation
            cam.vignettingIntensity = 0.55
            cam.vignettingPower = 1.1
        }
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)

        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 130
        amb.light!.color = UIColor(red: 1, green: 0.9, blue: 0.82, alpha: 1)
        scene.rootNode.addChildNode(amb)
        // 主光：从前上方照向后墙，立柱、门框、标志都在墙上投下影子
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 300
        key.light!.color = UIColor(red: 1, green: 0.93, blue: 0.82, alpha: 1)
        key.light!.castsShadow = !VisualFX.lowTier
        key.light!.shadowMode = .deferred
        key.light!.shadowColor = UIColor.black.withAlphaComponent(0.55)
        key.light!.shadowRadius = 6
        key.light!.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light!.orthographicScale = 7
        key.light!.zNear = 1
        key.light!.zFar = 30
        key.position = SCNVector3(-2.2, 7.5, 8)
        key.look(at: SCNVector3(0, 2, 0))
        scene.rootNode.addChildNode(key)
        scene.lightingEnvironment.contents = on ? PusherScene3D.sharedCasinoEnvironment : PusherScene3D.environmentImage()
        scene.lightingEnvironment.intensity = on ? VisualFX.environmentIntensity * 0.32 : 0.7
    }

    /// 相机离后墙多远：左右要放得下四扇门和两根壁柱，上面招牌不能钻到顶栏下面
    func fit(viewSize: CGSize, topInset: CGFloat) {
        guard viewSize.width > 10, viewSize.height > 10 else { return }
        let t = Float(tan(Self.fov * .pi / 360))
        let aspect = Float(viewSize.width / viewSize.height)
        let halfWidth = 1.5 * Self.doorSpacing + Self.doorWidth / 2 + 0.26
        let dH = halfWidth / (t * aspect)
        let topFrac = Float(topInset / viewSize.height)
        // 招牌的金框比牌面大一圈，又比后墙靠前（近大远小），多留一点
        let signTop = Self.signCenterY + Self.signHeight / 2 + 0.32
        let dV = (signTop - Self.cameraHeight) / (t * max(0.3, 1 - 2 * topFrac))
        cameraDistance = max(dH, dV)
        placeCamera(sway: .zero)
    }

    private func placeCamera(sway: SIMD2<Float>) {
        cameraNode.simdPosition = SIMD3(sway.x, Self.cameraHeight + sway.y, cameraDistance)
        // 不低头也不抬头（竖线保持竖直），只跟着左右晃一点点偏航
        cameraNode.look(at: SCNVector3(sway.x * 0.35, Self.cameraHeight + sway.y, 0))
    }

    func attach(onFirstFrame: @escaping () -> Void) {
        self.onFirstFrame = onFirstFrame
        hasRendered = false
        attachedAt = CACurrentMediaTime()
    }
    private var attachedAt: CFTimeInterval = 0

    /// 真机的倾斜（MotionParallax 的偏移，约 ±4）
    func setTilt(_ offset: CGSize) {
        lock.lock()
        tiltX = Float(offset.width) / 4
        tiltY = Float(offset.height) / 4
        lock.unlock()
    }

    // MARK: 大厅：后墙、地面、舞台、台阶、红毯、壁柱、礼宾柱
    private func buildHall() {
        let fixed = SCNNode()
        // 后墙
        let wallM = Self.pbr(.white, metal: 0, rough: 0.85)
        wallM.diffuse.contents = Self.wallTexture()
        wallM.diffuse.wrapS = .repeat
        wallM.diffuse.wrapT = .repeat
        wallM.diffuse.contentsTransform = SCNMatrix4MakeScale(14, 10, 1)
        let wall = SCNNode(geometry: SCNPlane(width: 14, height: 10))
        wall.geometry!.firstMaterial = wallM
        wall.position = SCNVector3(0, 5, 0)
        fixed.addChildNode(wall)
        // 墙上的两道金线和踢脚
        box(14, 0.07, 0.06, at: SCNVector3(0, 3.58, 0.03), gold, into: fixed)
        box(14, 0.1, 0.08, at: SCNVector3(0, 5.25, 0.04), gold, into: fixed)
        box(14, 0.12, 0.05, at: SCNVector3(0, Self.stageHeight + 0.06, 0.025), Self.pbr(UIColor(red: 0.25, green: 0.1, blue: 0.04, alpha: 1), metal: 0, rough: 0.4), into: fixed)

        // 舞台：上面是亮漆的深色木地板，正面是红丝绒
        let h = Self.stageHeight, d = Self.stageDepth
        let woodTop = Self.pbr(UIColor(red: 0.22, green: 0.09, blue: 0.05, alpha: 1), metal: 0, rough: 0.25)
        woodTop.clearCoat.contents = 1.0
        woodTop.clearCoatRoughness.contents = 0.08
        let velvet = Self.pbr(.white, metal: 0, rough: 0.95)
        velvet.diffuse.contents = Self.velvetTexture()
        velvet.diffuse.wrapS = .repeat
        velvet.diffuse.contentsTransform = SCNMatrix4MakeScale(10, 1, 1)
        let stage = SCNBox(width: 14, height: CGFloat(h), length: CGFloat(d), chamferRadius: 0)
        // SCNBox 的面：前、右、后、左、上、下
        stage.materials = [velvet, velvet, velvet, velvet, woodTop, woodTop]
        let stageNode = SCNNode(geometry: stage)
        stageNode.position = SCNVector3(0, h / 2, d / 2)
        fixed.addChildNode(stageNode)
        box(14, 0.07, 0.07, at: SCNVector3(0, h - 0.02, d + 0.01), gold, chamfer: 0.02, into: fixed)
        box(14, 0.05, 0.05, at: SCNVector3(0, 0.05, d + 0.02), gold, chamfer: 0.015, into: fixed)

        // 台阶（中间），铺着红毯；红毯一直铺到镜头前
        let carpet = Self.pbr(UIColor(red: 0.62, green: 0.05, blue: 0.12, alpha: 1), metal: 0, rough: 0.9)
        let stepW: Float = 1.3
        for i in 0..<3 {
            let top = h - Float(i + 1) * 0.3
            let depth = Float(i + 1) * 0.32
            box(stepW, top, depth, at: SCNVector3(0, top / 2, d + depth / 2), carpet, into: fixed)
            box(stepW + 0.04, 0.035, 0.035, at: SCNVector3(0, top, d + depth), gold, chamfer: 0.01, into: fixed)
        }
        let runner = SCNNode(geometry: SCNPlane(width: CGFloat(stepW), height: 12))
        runner.geometry!.firstMaterial = carpet
        runner.eulerAngles.x = -.pi / 2
        runner.position = SCNVector3(0, 0.012, d + 0.96 + 6)
        fixed.addChildNode(runner)
        for sx in [-1.0, 1.0] as [Float] {
            let edge = SCNNode(geometry: SCNPlane(width: 0.06, height: 12))
            edge.geometry!.firstMaterial = gold
            edge.eulerAngles.x = -.pi / 2
            edge.position = SCNVector3(sx * (stepW / 2 - 0.06), 0.014, d + 0.96 + 6)
            fixed.addChildNode(edge)
        }

        // 壁柱（贴着后墙，画面两边各露半根）
        let half = 1.5 * Self.doorSpacing + Self.doorWidth / 2 + 0.26
        for sx in [-1.0, 1.0] as [Float] {
            let x = sx * half
            let shaft = SCNNode(geometry: SCNCylinder(radius: 0.17, height: 8.5))
            shaft.geometry!.firstMaterial = gold
            shaft.position = SCNVector3(x, h + 4.25, 0.1)
            fixed.addChildNode(shaft)
            box(0.5, 0.2, 0.5, at: SCNVector3(x, h + 0.1, 0.12), gold, chamfer: 0.03, into: fixed)
            box(0.44, 0.12, 0.44, at: SCNVector3(x, h + 0.26, 0.12), gold, chamfer: 0.03, into: fixed)
        }

        // 红毯两边的礼宾柱和丝绒绳（前景，离镜头近，视差最大）
        let rope = Self.pbr(UIColor(red: 0.7, green: 0.05, blue: 0.12, alpha: 1), metal: 0, rough: 0.8)
        for sx in [-1.0, 1.0] as [Float] {
            let x = sx * (stepW / 2 + 0.22)
            let zs: [Float] = [d + 1.5, d + 3.3]
            for z in zs {
                let post = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.95))
                post.geometry!.firstMaterial = gold
                post.position = SCNVector3(x, 0.475, z)
                fixed.addChildNode(post)
                let cap = SCNSphere(radius: 0.07)
                cap.segmentCount = 16
                cap.firstMaterial = gold
                let capNode = SCNNode(geometry: cap)
                capNode.position = SCNVector3(x, 0.98, z)
                fixed.addChildNode(capNode)
                let foot = SCNNode(geometry: SCNCylinder(radius: 0.14, height: 0.03))
                foot.geometry!.firstMaterial = gold
                foot.position = SCNVector3(x, 0.015, z)
                fixed.addChildNode(foot)
            }
            // 绳子：两段直的，中间低一点（下垂）
            let mid = (zs[0] + zs[1]) / 2
            for (za, zb, ya, yb) in [(zs[0], mid, Float(0.9), Float(0.7)), (mid, zs[1], Float(0.7), Float(0.9))] {
                let len = hypot(zb - za, yb - ya)
                let seg = SCNNode(geometry: SCNCylinder(radius: 0.022, height: CGFloat(len)))
                seg.geometry!.firstMaterial = rope
                seg.simdPosition = SIMD3(x, (ya + yb) / 2, (za + zb) / 2)
                seg.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(SIMD3(0, yb - ya, zb - za)))
                fixed.addChildNode(seg)
            }
        }
        scene.rootNode.addChildNode(fixed)

        // 地面：深色的菱形地毯纹，能照出门和招牌的光
        let floor = SCNFloor()
        floor.reflectivity = VisualFX.enabled ? 0.32 : 0
        floor.reflectionFalloffEnd = 5
        floor.reflectionResolutionScaleFactor = VisualFX.lowTier ? 0.35 : 0.6
        let floorM = Self.pbr(.white, metal: 0, rough: 0.5)
        floorM.diffuse.contents = Self.floorTexture()
        floorM.diffuse.wrapS = .repeat
        floorM.diffuse.wrapT = .repeat
        floorM.diffuse.contentsTransform = SCNMatrix4MakeScale(1.1, 1.1, 1)
        floor.firstMaterial = floorM
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
    }

    // MARK: 招牌
    private func buildSign() {
        let cy = Self.signCenterY, w = Self.signWidth, h = Self.signHeight
        let sign = SCNNode()
        sign.position = SCNVector3(0, cy, 0.14)
        let lacquer = Self.pbr(UIColor(red: 0.36, green: 0.03, blue: 0.14, alpha: 1), metal: 0.1, rough: 0.45)
        lacquer.clearCoat.contents = 0.35
        lacquer.clearCoatRoughness.contents = 0.3
        box(w, h, 0.16, at: SCNVector3(0, 0, 0), lacquer, chamfer: 0.08, into: sign)
        box(w + 0.14, h + 0.14, 0.1, at: SCNVector3(0, 0, -0.04), gold, chamfer: 0.1, into: sign)
        // 字：金色的大标题 + 粉色的小标题（自己发光，泛光会把它晕开）
        let text = SCNNode(geometry: SCNPlane(width: CGFloat(w - 0.3), height: CGFloat(h - 0.3)))
        let img = Self.signTexture(title: String(localized: "COIN BOUNCE"), subtitle: String(localized: "CASINO"))
        let tm = SCNMaterial()
        tm.lightingModel = .constant
        tm.diffuse.contents = img
        tm.emission.contents = img
        tm.emission.intensity = 0.25
        tm.blendMode = .alpha
        text.geometry!.firstMaterial = tm
        text.position = SCNVector3(0, 0, 0.085)
        sign.addChildNode(text)
        // 一圈灯泡，两组交替亮
        bulbA = Self.pbr(.white, metal: 0, rough: 0.3, emission: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), intensity: 1.9)
        bulbB = Self.pbr(.white, metal: 0, rough: 0.3, emission: UIColor(red: 1, green: 0.4, blue: 0.7, alpha: 1), intensity: 0.5)
        let ga = SCNSphere(radius: 0.035); ga.segmentCount = 10; ga.firstMaterial = bulbA
        let gb = SCNSphere(radius: 0.035); gb.segmentCount = 10; gb.firstMaterial = bulbB
        let bulbs = SCNNode()
        let count = 18
        for i in 0..<count {
            let x = -w / 2 + 0.16 + (w - 0.32) * Float(i) / Float(count - 1)
            for sy in [-1.0, 1.0] as [Float] {
                let n = SCNNode(geometry: (i % 2 == 0) == (sy > 0) ? ga : gb)
                n.position = SCNVector3(x, sy * (h / 2 - 0.09), 0.09)
                bulbs.addChildNode(n)
            }
        }
        sign.addChildNode(bulbs)
        scene.rootNode.addChildNode(sign)
    }

    // MARK: 一扇门：金色拱形门框 + 发光的门洞 + 立体标志 + 名牌 + 一盏带颜色的灯
    private func buildDoor(_ door: Door) {
        let w = CGFloat(Self.doorWidth), rectH = CGFloat(Self.doorRect), r = w / 2
        let node = SCNNode()
        node.position = SCNVector3(door.x, Self.stageHeight, 0)

        // 门洞里的光（拱形的发光贴图，贴在墙上）
        let glowH = rectH + r
        let glow = SCNNode(geometry: SCNPlane(width: w, height: glowH))
        let img = Self.doorGlowTexture(tint: door.tint)
        let gm = SCNMaterial()
        gm.lightingModel = .constant
        gm.diffuse.contents = img
        gm.emission.contents = img
        gm.emission.intensity = 0.12
        gm.blendMode = .alpha
        glow.geometry!.firstMaterial = gm
        glow.position = SCNVector3(0, Float(glowH / 2), 0.015)
        node.addChildNode(glow)

        // 门框：外拱减内拱，挤出一点厚度
        let t: CGFloat = 0.075
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -r - t, y: 0))
        path.addLine(to: CGPoint(x: -r - t, y: rectH))
        path.addArc(withCenter: CGPoint(x: 0, y: rectH), radius: r + t, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: r + t, y: 0))
        path.addLine(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: r, y: rectH))
        path.addArc(withCenter: CGPoint(x: 0, y: rectH), radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: -r, y: 0))
        path.close()
        path.flatness = 0.005
        let frame = SCNShape(path: path, extrusionDepth: 0.16)
        frame.chamferRadius = 0.02
        frame.firstMaterial = gold
        let frameNode = SCNNode(geometry: frame)
        frameNode.position = SCNVector3(0, 0, 0.08)
        node.addChildNode(frameNode)
        // 门槛
        box(Float(w + 2 * t) + 0.06, 0.05, 0.3, at: SCNVector3(0, 0.025, 0.15), gold, chamfer: 0.015, into: node)

        // 名牌（门上方）
        let plate = SCNNode(geometry: SCNPlane(width: 0.84, height: 0.26))
        let pm = SCNMaterial()
        pm.lightingModel = .constant
        let pimg = Self.plateTexture(title: door.title)
        pm.diffuse.contents = pimg
        pm.emission.contents = pimg
        pm.emission.intensity = 0.05
        pm.blendMode = .alpha
        plate.geometry!.firstMaterial = pm
        plate.position = SCNVector3(0, Self.plateY - Self.stageHeight, 0.05)
        node.addChildNode(plate)

        // 立体标志：飘在门洞前面，慢慢上下浮动
        let emblem = SCNNode()
        emblem.position = SCNVector3(0, Float(rectH) * 0.62, 0.42)
        switch door.screen {
        case .pusher: buildCoins(in: emblem)
        case .roulette: buildWheel(in: emblem)
        case .slots: buildReels(in: emblem)
        default: buildPinball(in: emblem)
        }
        let bob = SCNAction.sequence([.moveBy(x: 0, y: 0.06, z: 0, duration: 1.6), .moveBy(x: 0, y: -0.06, z: 0, duration: 1.6)])
        bob.timingMode = .easeInEaseOut
        emblem.runAction(.repeatForever(bob))
        node.addChildNode(emblem)
        emblems.append(emblem)

        // 带颜色的灯：照亮标志，也在舞台地板上洒一片颜色
        let light = SCNNode()
        light.light = SCNLight()
        light.light!.type = .omni
        light.light!.color = door.tint
        light.light!.intensity = 55
        light.light!.attenuationStartDistance = 0.8
        light.light!.attenuationEndDistance = 3.2
        light.position = SCNVector3(0, Float(rectH) * 0.8, 1.5)
        node.addChildNode(light)

        scene.rootNode.addChildNode(node)
    }

    /// 点了哪扇门：标志弹一下
    func pulse(_ screen: AppRouter.Screen) {
        guard let i = doors.firstIndex(where: { $0.screen == screen }), i < emblems.count else { return }
        let e = emblems[i]
        e.runAction(.sequence([.scale(to: 1.25, duration: 0.08), .scale(to: 1.0, duration: 0.18)]))
    }

    // MARK: 四个标志
    /// 推币机：三枚自转的金币
    private func buildCoins(in parent: SCNNode) {
        let face = Self.pbr(.white, metal: 1, rough: 0.22)
        face.diffuse.contents = Self.coinTexture()
        let edge = Self.pbr(Self.goldColor, metal: 1, rough: 0.3)
        for (i, p) in [(-0.15, -0.12), (0.15, -0.12), (0.0, 0.14)].enumerated() {
            let c = SCNCylinder(radius: 0.16, height: 0.04)
            c.radialSegmentCount = 36
            c.materials = [edge, face, face]
            let coin = SCNNode(geometry: c)
            // 立起来（面朝镜头），再绕竖直轴自转
            coin.eulerAngles.x = .pi / 2
            let spin = SCNNode()
            spin.position = SCNVector3(Float(p.0), Float(p.1), Float(i) * 0.05)
            spin.addChildNode(coin)
            spin.eulerAngles.y = Float(i) * 0.9
            spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4.5 + Double(i) * 0.7)))
            parent.addChildNode(spin)
        }
    }

    /// 轮盘：斜着的小转盘，一直在转
    private func buildWheel(in parent: SCNNode) {
        let tiltNode = SCNNode()
        tiltNode.eulerAngles.x = 1.05
        let spin = SCNNode()
        let disc = SCNCylinder(radius: 0.27, height: 0.035)
        disc.radialSegmentCount = 48
        let faceM = Self.pbr(.white, metal: 0, rough: 0.45)
        // 贴图里白字、亮色多，HDR 下容易过曝成一片：压暗一点
        faceM.multiply.contents = UIColor(white: 0.5, alpha: 1)
        var tf = SCNMatrix4Identity
        tf.m11 = 0; tf.m21 = -0.88; tf.m41 = 0.94
        tf.m12 = -0.88; tf.m22 = 0; tf.m42 = 0.94
        faceM.diffuse.contentsTransform = tf
        wheelFaceMaterial = faceM
        let wood = Self.pbr(UIColor(red: 0.3, green: 0.14, blue: 0.06, alpha: 1), metal: 0, rough: 0.35)
        disc.materials = [wood, faceM, wood]
        spin.addChildNode(SCNNode(geometry: disc))
        let rim = SCNTorus(ringRadius: 0.285, pipeRadius: 0.028)
        rim.ringSegmentCount = 48
        rim.firstMaterial = wood
        spin.addChildNode(SCNNode(geometry: rim))
        let ring = SCNTorus(ringRadius: 0.262, pipeRadius: 0.008)
        ring.ringSegmentCount = 48
        ring.firstMaterial = gold
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = SCNVector3(0, 0.022, 0)
        spin.addChildNode(ringNode)
        let knob = SCNSphere(radius: 0.04)
        knob.firstMaterial = gold
        let knobNode = SCNNode(geometry: knob)
        knobNode.position = SCNVector3(0, 0.05, 0)
        spin.addChildNode(knobNode)
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 9)))
        tiltNode.addChildNode(spin)
        // 一颗停在转盘上的小白球（不跟着转）
        let ball = SCNSphere(radius: 0.022)
        ball.firstMaterial = Self.pbr(UIColor(white: 0.97, alpha: 1), metal: 0, rough: 0.2)
        let ballNode = SCNNode(geometry: ball)
        ballNode.position = SCNVector3(0.17, 0.04, 0.08)
        tiltNode.addChildNode(ballNode)
        parent.addChildNode(tiltNode)
    }
    private var wheelFaceMaterial: SCNMaterial?

    /// 轮盘标志的贴图要在主线程用 SwiftUI 渲染：视图建好以后调一次
    @MainActor
    func loadWheelFaceIfNeeded() {
        guard let m = wheelFaceMaterial, !(m.diffuse.contents is UIImage) else { return }
        if let img = RouletteWheel3D.faceImage(size: 512) { m.diffuse.contents = img }
    }

    /// 弹球台：一颗蘑菇柱、两块挡板、一颗上下弹的钢珠
    private func buildPinball(in parent: SCNNode) {
        let pink = UIColor(red: 1, green: 0.3, blue: 0.7, alpha: 1)
        let base = SCNNode(geometry: SCNCylinder(radius: 0.105, height: 0.09))
        base.geometry!.firstMaterial = Self.pbr(UIColor(white: 0.55, alpha: 1), metal: 0.1, rough: 0.4)
        let cap = SCNNode(geometry: SCNCylinder(radius: 0.14, height: 0.045))
        let capM = Self.pbr(UIColor(red: 0.75, green: 0.12, blue: 0.45, alpha: 1), metal: 0.2, rough: 0.3, emission: pink, intensity: 0.22)
        capM.clearCoat.contents = 1.0
        cap.geometry!.firstMaterial = capM
        cap.position = SCNVector3(0, 0.065, 0)
        let star = SCNNode(geometry: SCNPlane(width: 0.2, height: 0.2))
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = Self.image(128, 128, opaque: false) { _ in
            Self.drawCentered("★", size: 104, color: UIColor(white: 1, alpha: 0.95), in: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
        sm.blendMode = .alpha
        star.geometry!.firstMaterial = sm
        star.eulerAngles.x = -.pi / 2
        star.position = SCNVector3(0, 0.024, 0)
        cap.addChildNode(star)
        let bumper = SCNNode()
        bumper.addChildNode(base)
        bumper.addChildNode(cap)
        // 立起来，帽子朝镜头
        bumper.eulerAngles.x = .pi / 2 - 0.35
        bumper.position = SCNVector3(0, 0.2, -0.05)
        parent.addChildNode(bumper)
        let red = Self.pbr(UIColor(red: 0.92, green: 0.1, blue: 0.2, alpha: 1), metal: 0.1, rough: 0.25)
        red.clearCoat.contents = 1.0
        for sx in [-1.0, 1.0] as [Float] {
            let flipper = SCNNode(geometry: SCNCapsule(capRadius: 0.035, height: 0.26))
            flipper.geometry!.firstMaterial = red
            // 胶囊的轴沿 Y：放倒成一个 V 字的一边
            flipper.eulerAngles.z = sx * (.pi / 2 - 0.5)
            flipper.position = SCNVector3(sx * 0.15, -0.22, 0.05)
            parent.addChildNode(flipper)
        }
        let ball = SCNSphere(radius: 0.06)
        ball.segmentCount = 24
        ball.firstMaterial = chrome
        let ballNode = SCNNode(geometry: ball)
        ballNode.position = SCNVector3(0.02, -0.12, 0.12)
        let up = SCNAction.moveBy(x: -0.05, y: 0.22, z: 0, duration: 0.55)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0.05, y: -0.22, z: 0, duration: 0.55)
        down.timingMode = .easeIn
        ballNode.runAction(.repeatForever(.sequence([up, down])))
        parent.addChildNode(ballNode)
    }

    /// 老虎机：金色机壳里三只各转各的滚筒
    private func buildReels(in parent: SCNNode) {
        box(0.6, 0.36, 0.12, at: SCNVector3(0, 0, -0.06), gold, chamfer: 0.04, into: parent)
        box(0.52, 0.27, 0.02, at: SCNVector3(0, 0, 0.005), Self.pbr(UIColor(white: 0.05, alpha: 1), metal: 0.2, rough: 0.5), into: parent)
        let strip = Self.reelStripTexture()
        for i in 0..<3 {
            let c = SCNCylinder(radius: 0.115, height: 0.15)
            c.radialSegmentCount = 36
            let side = Self.pbr(.white, metal: 0, rough: 0.5)
            side.diffuse.contents = strip
            side.multiply.contents = UIColor(white: 0.55, alpha: 1)
            let capM = Self.pbr(UIColor(white: 0.8, alpha: 1), metal: 0.6, rough: 0.3)
            c.materials = [side, capM, capM]
            let drum = SCNNode(geometry: c)
            // 轴放成左右方向（绕 Z 转 90°）；外面套一个节点绕 X 滚
            drum.eulerAngles.z = .pi / 2
            let roll = SCNNode()
            roll.position = SCNVector3(Float(i - 1) * 0.168, 0, 0.02)
            roll.addChildNode(drum)
            roll.eulerAngles.x = Float(i) * 1.3
            roll.runAction(.repeatForever(.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 5.5 + Double(i) * 1.4)))
            parent.addChildNode(roll)
        }
    }

    // MARK: 每帧（渲染线程）：相机慢慢晃、灯泡交替亮
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        let tx = tiltX, ty = tiltY
        lock.unlock()
        var sway = SIMD2<Float>(tx * 0.28, ty * 0.12)
        if !reduceMotion {
            sway.x += 0.16 * Float(sin(time * 0.45))
            sway.y += 0.05 * Float(sin(time * 0.31))
        }
        placeCamera(sway: sway)
        let phase = Int(time / 0.5) % 2
        if phase != bulbPhase {
            bulbPhase = phase
            bulbA.emission.intensity = phase == 0 ? 1.9 : 0.4
            bulbB.emission.intensity = phase == 0 ? 0.4 : 1.9
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        frames += 1
        if fpsWindow == 0 { fpsWindow = time }
        if time - fpsWindow >= 2 {
            NSLog("LOBBY3D_STATS fps=%.1f", Double(frames) / (time - fpsWindow))
            frames = 0
            fpsWindow = time
        }
        guard !hasRendered else { return }
        hasRendered = true
        NSLog("LOBBY3D_FIRST_FRAME ms=%.0f", (CACurrentMediaTime() - attachedAt) * 1000)
        DispatchQueue.main.async { [weak self] in self?.onFirstFrame?() }
    }

    /// 招牌在视图里的位置（3D 画面出来之前，SwiftUI 先在这里画一块 2D 的招牌顶着）
    func signRect() -> CGRect {
        guard let view else { return .zero }
        placeCamera(sway: .zero)
        // 节点的改动要等事务提交才生效：马上提交，不然投影用的还是上一个相机位置
        SCNTransaction.flush()
        let hw = Self.signWidth / 2 + 0.07, hh = Self.signHeight / 2 + 0.07
        let a = view.projectPoint(SCNVector3(-hw, Self.signCenterY + hh, 0.2))
        let b = view.projectPoint(SCNVector3(hw, Self.signCenterY - hh, 0.2))
        return CGRect(x: CGFloat(min(a.x, b.x)), y: CGFloat(min(a.y, b.y)), width: CGFloat(abs(b.x - a.x)), height: CGFloat(abs(b.y - a.y)))
    }

    // MARK: 门在视图里的位置（SwiftUI 的透明按钮用）
    /// 每扇门（含上面的名牌）在视图里的外接框；相机不晃时的位置
    func doorRects() -> [CGRect] {
        guard let view else { return [] }
        placeCamera(sway: .zero)
        SCNTransaction.flush()
        let hw = Self.doorWidth / 2 + 0.08
        return doors.map { d in
            var xs: [CGFloat] = [], ys: [CGFloat] = []
            for (x, y) in [(d.x - hw, Self.stageHeight), (d.x + hw, Self.stageHeight), (d.x - hw, Self.plateY + 0.14), (d.x + hw, Self.plateY + 0.14)] {
                let p = view.projectPoint(SCNVector3(x, y, 0.1))
                xs.append(CGFloat(p.x)); ys.append(CGFloat(p.y))
            }
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }

    // MARK: 贴图（全部用代码画）
    private static func image(_ w: CGFloat, _ h: CGFloat, opaque: Bool, _ draw: (CGContext) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = opaque
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { draw($0.cgContext) }
    }

    private static func text(_ s: String, size: CGFloat, color: UIColor, kern: CGFloat = 0) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: size, weight: .black)
        let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
        return NSAttributedString(string: s, attributes: [.font: rounded, .foregroundColor: color, .kern: kern])
    }

    /// 字太宽就按比例缩小，画在 rect 正中。shadow：先在右下偏一点画一遍深色的（当描边用；
    /// 直接描边的话，粗体汉字笔画重叠的内部轮廓会露出来）
    private static func drawCentered(_ s: String, size: CGFloat, color: UIColor, shadow: UIColor? = nil, kern: CGFloat = 0, in rect: CGRect) {
        var fitted = size
        var sz = text(s, size: fitted, color: color, kern: kern).size()
        if sz.width > rect.width {
            fitted = size * rect.width / sz.width
            sz = text(s, size: fitted, color: color, kern: kern).size()
        }
        let origin = CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2)
        if let shadow {
            let d = max(2, fitted * 0.035)
            text(s, size: fitted, color: shadow, kern: kern).draw(at: CGPoint(x: origin.x + d, y: origin.y + d))
        }
        text(s, size: fitted, color: color, kern: kern).draw(at: origin)
    }

    /// 后墙：深红色竖条纹 + 很淡的金色菱形暗花（一格 1 米，平铺）
    static func wallTexture() -> UIImage {
        image(256, 256, opaque: true) { c in
            UIColor(red: 0.36, green: 0.045, blue: 0.11, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor(red: 0.29, green: 0.03, blue: 0.09, alpha: 1).setFill()
            for i in 0..<4 { c.fill(CGRect(x: CGFloat(i) * 64, y: 0, width: 32, height: 256)) }
            c.setStrokeColor(UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 0.13).cgColor)
            c.setLineWidth(1.5)
            for (x, y) in [(64.0, 64.0), (192.0, 64.0), (0.0, 192.0), (128.0, 192.0), (256.0, 192.0)] {
                c.move(to: CGPoint(x: x, y: y - 22))
                c.addLine(to: CGPoint(x: x + 14, y: y))
                c.addLine(to: CGPoint(x: x, y: y + 22))
                c.addLine(to: CGPoint(x: x - 14, y: y))
                c.closePath()
            }
            c.strokePath()
        }
    }

    /// 舞台正面的红丝绒：竖向的褶皱
    static func velvetTexture() -> UIImage {
        image(128, 128, opaque: true) { c in
            let colors = [UIColor(red: 0.5, green: 0.04, blue: 0.1, alpha: 1).cgColor, UIColor(red: 0.3, green: 0.02, blue: 0.06, alpha: 1).cgColor,
                          UIColor(red: 0.5, green: 0.04, blue: 0.1, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 128, y: 0), options: [])
        }
    }

    /// 地面：深色底 + 金色菱形格
    static func floorTexture() -> UIImage {
        image(256, 256, opaque: true) { c in
            UIColor(red: 0.2, green: 0.02, blue: 0.07, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor(red: 0.27, green: 0.03, blue: 0.09, alpha: 1).setFill()
            c.move(to: CGPoint(x: 128, y: 0))
            c.addLine(to: CGPoint(x: 256, y: 128))
            c.addLine(to: CGPoint(x: 128, y: 256))
            c.addLine(to: CGPoint(x: 0, y: 128))
            c.closePath()
            c.fillPath()
            c.setStrokeColor(UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 0.3).cgColor)
            c.setLineWidth(3)
            c.move(to: CGPoint(x: 128, y: 0))
            c.addLine(to: CGPoint(x: 256, y: 128))
            c.addLine(to: CGPoint(x: 128, y: 256))
            c.addLine(to: CGPoint(x: 0, y: 128))
            c.closePath()
            c.strokePath()
        }
    }

    /// 门洞里的光：拱形以内从上到下由亮变暗，中间一团光和几道光芒；拱形以外透明
    static func doorGlowTexture(tint: UIColor) -> UIImage {
        let w: CGFloat = 256, h: CGFloat = 256 * CGFloat((doorRect + doorWidth / 2) / doorWidth)
        return image(w, h, opaque: false) { c in
            let r = w / 2
            let arch = UIBezierPath()
            arch.move(to: CGPoint(x: 0, y: h))
            arch.addLine(to: CGPoint(x: 0, y: r))
            arch.addArc(withCenter: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
            arch.addLine(to: CGPoint(x: w, y: h))
            arch.close()
            c.addPath(arch.cgPath)
            c.clip()
            let space = CGColorSpaceCreateDeviceRGB()
            var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            tint.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            let dark = UIColor(red: rr * 0.12, green: gg * 0.12, blue: bb * 0.14, alpha: 1)
            let mid = UIColor(red: rr * 0.55, green: gg * 0.55, blue: bb * 0.55, alpha: 1)
            let g = CGGradient(colorsSpace: space, colors: [mid.cgColor, dark.cgColor, UIColor.black.cgColor] as CFArray, locations: [0, 0.7, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
            let center = CGPoint(x: r, y: h * 0.4)
            c.setFillColor(tint.withAlphaComponent(0.1).cgColor)
            for i in 0..<12 {
                let a0 = Double(i) / 12 * 2 * .pi, a1 = a0 + 0.14
                c.move(to: center)
                c.addLine(to: CGPoint(x: center.x + cos(a0) * 600, y: center.y + sin(a0) * 600))
                c.addLine(to: CGPoint(x: center.x + cos(a1) * 600, y: center.y + sin(a1) * 600))
                c.closePath()
            }
            c.fillPath()
            let halo = CGGradient(colorsSpace: space, colors: [UIColor.white.withAlphaComponent(0.75).cgColor, tint.withAlphaComponent(0.55).cgColor, tint.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0, 0.3, 1])!
            c.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: w * 0.62, options: [])
        }
    }

    /// 名牌：深色胶囊 + 金边 + 白字
    static func plateTexture(title: String) -> UIImage {
        image(512, 160, opaque: false) { c in
            let rect = CGRect(x: 6, y: 6, width: 500, height: 148)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 74)
            UIColor(red: 0.08, green: 0.01, blue: 0.03, alpha: 0.92).setFill()
            path.fill()
            c.setStrokeColor(goldColor.cgColor)
            c.setLineWidth(7)
            c.addPath(path.cgPath)
            c.strokePath()
            drawCentered(title, size: 78, color: .white, in: rect.insetBy(dx: 36, dy: 10))
        }
    }

    /// 招牌的字：上面金色大字，下面粉色小字
    static func signTexture(title: String, subtitle: String) -> UIImage {
        image(1024, 256, opaque: false) { _ in
            drawCentered(title, size: 132, color: UIColor(red: 1, green: 0.86, blue: 0.42, alpha: 1), shadow: UIColor(red: 0.25, green: 0.08, blue: 0, alpha: 1), kern: 2,
                         in: CGRect(x: 30, y: 6, width: 964, height: 160))
            drawCentered(subtitle, size: 64, color: UIColor(red: 1, green: 0.5, blue: 0.75, alpha: 1), shadow: UIColor(red: 0.2, green: 0, blue: 0.1, alpha: 1), kern: 14,
                         in: CGRect(x: 30, y: 168, width: 964, height: 80))
        }
    }

    /// 金币的面：一圈边 + 一颗星
    static func coinTexture() -> UIImage {
        image(256, 256, opaque: true) { c in
            let space = CGColorSpaceCreateDeviceRGB()
            let g = CGGradient(colorsSpace: space, colors: [UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1).cgColor, UIColor(red: 0.95, green: 0.68, blue: 0.15, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 110, y: 100), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 150, options: [.drawsAfterEndLocation])
            c.setStrokeColor(UIColor(red: 0.75, green: 0.45, blue: 0.05, alpha: 1).cgColor)
            c.setLineWidth(10)
            c.strokeEllipse(in: CGRect(x: 22, y: 22, width: 212, height: 212))
            // 五角星
            let star = UIBezierPath()
            for i in 0..<10 {
                let a = Double(i) * .pi / 5 - .pi / 2
                let rad: Double = i % 2 == 0 ? 78 : 34
                let p = CGPoint(x: 128 + cos(a) * rad, y: 128 + sin(a) * rad)
                if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
            }
            star.close()
            UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).setFill()
            star.fill()
            c.setStrokeColor(UIColor(red: 0.75, green: 0.45, blue: 0.05, alpha: 1).cgColor)
            c.setLineWidth(5)
            c.addPath(star.cgPath)
            c.strokePath()
        }
    }

    /// 滚筒的带子：四个图案绕一圈。贴在圆柱侧面时图的横向是绕圈的方向，所以每个图案转 90° 画
    static func reelStripTexture() -> UIImage {
        image(512, 128, opaque: true) { c in
            UIColor(white: 0.96, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 512, height: 128))
            let glyphs: [(String, UIColor)] = [("7", UIColor(red: 0.85, green: 0.05, blue: 0.15, alpha: 1)), ("★", UIColor(red: 0.95, green: 0.65, blue: 0.1, alpha: 1)),
                                               ("7", UIColor(red: 0.85, green: 0.05, blue: 0.15, alpha: 1)), ("♥", UIColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1))]
            for (i, g) in glyphs.enumerated() {
                let s = text(g.0, size: 92, color: g.1)
                let sz = s.size()
                c.saveGState()
                c.translateBy(x: CGFloat(i) * 128 + 64, y: 64)
                c.rotate(by: .pi / 2)
                s.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2))
                c.restoreGState()
                c.setFillColor(UIColor(white: 0.75, alpha: 1).cgColor)
                c.fill(CGRect(x: CGFloat(i) * 128 - 1, y: 0, width: 2, height: 128))
            }
        }
    }
}

/// SwiftUI 包装
struct Lobby3DView: UIViewRepresentable {
    let topInset: CGFloat
    let reduceMotion: Bool
    let onLayout: () -> Void
    let onFirstFrame: () -> Void

    final class FitView: SCNView {
        var onLayout: ((CGSize) -> Void)?
        private var last: CGSize = .zero
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != last, bounds.width > 0 { last = bounds.size; onLayout?(bounds.size) }
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let v = FitView()
        let s = Lobby3DScene.shared
        s.reduceMotion = reduceMotion
        // 每次回大厅都是一个新视图：它的第一帧出来时再通知一次
        s.attach(onFirstFrame: onFirstFrame)
        v.onLayout = { size in
            s.fit(viewSize: size, topInset: topInset)
            onLayout()
        }
        v.scene = s.scene
        s.view = v
        v.delegate = s
        v.pointOfView = s.cameraNode
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = VisualFX.lowTier ? 30 : 60
        v.antialiasingMode = VisualFX.lowTier ? .none : .multisampling2X
        v.backgroundColor = UIColor(red: 0.07, green: 0.01, blue: 0.03, alpha: 1)
        v.isUserInteractionEnabled = false
        s.loadWheelFaceIfNeeded()
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        Lobby3DScene.shared.reduceMotion = reduceMotion
        Lobby3DScene.shared.onFirstFrame = onFirstFrame
    }
}
