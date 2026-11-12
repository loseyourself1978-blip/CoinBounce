import SceneKit
import SwiftUI
import UIKit

// MARK: - v12.5 弹子机 3D 画面（SceneKit；物理和经济仍是 PachinkoPhysics / PachinkoGame，这里只画）
/// 台面坐标 (x 0…1, y 0…1.25, y 向上) → 世界坐标：X = (x − 0.5)·W，Y = (y − 0.625)·W，台面正面 Z = 0。
/// 台面整体往后仰一点（上边远、下边近），像真机照片；相机按视图尺寸把整台机器放进画面（SE 也完整）。
/// 灯光、HDR、泛光、赌场环境图和推币机一样（VisualFX、PusherScene3D.casinoEnvironmentImage）。
final class Pachinko3DScene: NSObject, SCNSceneRendererDelegate {
    static let W: Float = 10
    /// 台面后仰角（弧度）
    static let tilt: Float = -0.16
    /// 机器外框（世界单位）：台面 10 × 12.5，四周框
    static let frameSide: Float = 0.75, frameTop: Float = 0.9, frameBottom: Float = 1.3

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let root = SCNNode()           // 后仰的整台机器
    private let ballRoot = SCNNode()
    private let fxRoot = SCNNode()
    private weak var game: PachinkoGame?
    weak var view: SCNView?

    private var ballNodes: [SCNNode] = []
    private var shadowNodes: [SCNNode] = []
    private var petalNodes: [SCNNode] = []
    private var wingNodes: [SCNNode] = []
    private var attackerDoor = SCNNode()
    private var attackerGlow = SCNNode()
    private var boardMaterial = SCNMaterial()
    private var bulbA = SCNMaterial(), bulbB = SCNMaterial()
    private var shownWings: Bool?, shownAttacker: Bool?, shownTulips: [Bool] = [], shownMode: PachinkoMode?
    private var sparkPool: [SCNNode] = []
    private var sparkIndex = 0
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var bulbPhase = false
    private var bulbClock = 0.0
    private var nailWindowStart: CFTimeInterval = 0
    private var nailSounds = 0
    private var lowTier: Bool { VisualFX.lowTier }

    /// LCD 在视图里的位置（SwiftUI 把数字盘叠在这里）
    var onLCDRect: ((CGRect) -> Void)?
    /// 落袋：视图坐标 + 金额（SwiftUI 飘「+N」）
    var onPayout: ((CGPoint, Int) -> Void)?
    /// 帧率统计（每秒一次）
    private(set) var fps: Double = 0
    private var frames = 0
    private var fpsWindow: CFTimeInterval = 0
    private let statsLock = NSLock()

    init(game: PachinkoGame) {
        self.game = game
        super.init()
        buildScene()
        buildMachine()
        game.onPocket = { [weak self] p, b in self?.pocketHit(p, b) }
        game.onNailHit = { [weak self] v, x, y in self?.nailHit(speed: v, x: x, y: y) }
    }

    deinit { displayLink?.invalidate() }

    // MARK: 坐标
    static func world(_ x: Double, _ y: Double, z: Float = 0) -> SCNVector3 {
        SCNVector3(Float(x - 0.5) * W, Float(y - 0.625) * W, z)
    }

    // MARK: 灯光、材质、相机（同推币机）
    private func buildScene() {
        scene.background.contents = nil
        let cam = SCNCamera()
        cam.fieldOfView = 26
        cam.projectionDirection = .vertical
        cam.zNear = 1
        cam.zFar = 200
        let on = VisualFX.enabled
        cam.wantsHDR = on
        if on {
            cam.wantsExposureAdaptation = false
            cam.exposureOffset = VisualFX.exposureOffset
            cam.whitePoint = VisualFX.whitePoint
            cam.bloomThreshold = VisualFX.bloomThreshold
            cam.bloomIntensity = lowTier ? VisualFX.bloomIntensity * 0.8 : VisualFX.bloomIntensity * 1.3
            cam.bloomBlurRadius = lowTier ? 4 : 6
            cam.bloomIterationCount = lowTier ? 1 : 2
            cam.bloomIterationSpread = 0.4
            cam.contrast = VisualFX.contrast
            cam.saturation = VisualFX.saturation
        }
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 520
        key.eulerAngles = SCNVector3(-0.55, -0.35, 0)
        scene.rootNode.addChildNode(key)
        // 高光灯：左上前方，钢珠和铜钉上的一点亮光
        let spec = SCNNode()
        spec.light = SCNLight()
        spec.light!.type = .omni
        spec.light!.intensity = 500
        spec.light!.color = UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)
        spec.position = SCNVector3(-6, 9, 14)
        scene.rootNode.addChildNode(spec)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 220
        scene.rootNode.addChildNode(amb)
        scene.lightingEnvironment.contents = on ? PusherScene3D.casinoEnvironmentImage(width: lowTier ? 512 : 1024) : PusherScene3D.environmentImage()
        scene.lightingEnvironment.intensity = on ? VisualFX.environmentIntensity : 1.6

        root.eulerAngles = SCNVector3(Self.tilt, 0, 0)
        scene.rootNode.addChildNode(root)
        root.addChildNode(ballRoot)
        root.addChildNode(fxRoot)
    }

    private static func pbr(_ color: UIColor, metal: CGFloat, rough: CGFloat, emission: UIColor? = nil, emissionIntensity: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let emission {
            m.emission.contents = emission
            m.emission.intensity = emissionIntensity
        }
        return m
    }

    static let brass = UIColor(red: 0.92, green: 0.72, blue: 0.34, alpha: 1)
    static let chrome = UIColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1)
    static let neonPink = UIColor(red: 1.0, green: 0.25, blue: 0.65, alpha: 1)
    static let neonCyan = UIColor(red: 0.2, green: 0.95, blue: 1.0, alpha: 1)
    static let neonGold = UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1)

    // MARK: 机器
    private func buildMachine() {
        typealias B = PachinkoBoard
        let W = Self.W
        let board = game?.physics.board ?? PachinkoBoard()

        // 台面：亮漆底板（清漆层反射环境）
        boardMaterial = Self.pbr(.white, metal: 0, rough: 0.55)
        boardMaterial.diffuse.contents = Self.boardArt(mode: .normal)
        boardMaterial.clearCoat.contents = 0.22
        boardMaterial.clearCoatRoughness.contents = 0.2
        boardMaterial.multiply.contents = UIColor(white: 0.55, alpha: 1)
        // 底板自己微微发光（液晶和霓虹的反光），不靠环境图把它照亮成灰色
        boardMaterial.emission.contents = Self.boardArt(mode: .normal)
        boardMaterial.emission.intensity = 0.5
        let plate = SCNNode(geometry: SCNBox(width: CGFloat(W), height: CGFloat(W * 1.25), length: 0.4, chamferRadius: 0))
        plate.geometry!.materials = [boardMaterial]
        plate.position = SCNVector3(0, 0, -0.2)
        root.addChildNode(plate)

        // 外框：红色亮漆 + 金边 + 灯泡（和推币机的柜子一个风格）
        let lacquer = Self.pbr(UIColor(red: 0.55, green: 0.04, blue: 0.1, alpha: 1), metal: 0.1, rough: 0.3)
        lacquer.clearCoat.contents = 1.0
        lacquer.clearCoatRoughness.contents = 0.08
        let gold = Self.pbr(Self.neonGold, metal: 1, rough: 0.22)
        let hw = W / 2, hh = W * 1.25 / 2
        let fs = Self.frameSide, ft = Self.frameTop, fb = Self.frameBottom
        let frame = SCNNode()
        func box(_ w: Float, _ h: Float, _ d: Float, _ p: SCNVector3, _ m: SCNMaterial, chamfer: CGFloat = 0.12) {
            let n = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: chamfer))
            n.geometry!.firstMaterial = m
            n.position = p
            frame.addChildNode(n)
        }
        box(fs, W * 1.25 + ft + fb, 1.4, SCNVector3(-hw - fs / 2, (ft - fb) / 2, 0.2), lacquer)
        box(fs, W * 1.25 + ft + fb, 1.4, SCNVector3(hw + fs / 2, (ft - fb) / 2, 0.2), lacquer)
        box(W, ft, 1.4, SCNVector3(0, hh + ft / 2, 0.2), lacquer)
        box(W, fb, 1.6, SCNVector3(0, -hh - fb / 2, 0.3), lacquer)
        // 金色内边
        box(0.12, W * 1.25, 0.2, SCNVector3(-hw - 0.02, 0, 0.92), gold, chamfer: 0.05)
        box(0.12, W * 1.25, 0.2, SCNVector3(hw + 0.02, 0, 0.92), gold, chamfer: 0.05)
        box(W + 0.16, 0.12, 0.2, SCNVector3(0, hh + 0.02, 0.92), gold, chamfer: 0.05)
        box(W + 0.16, 0.12, 0.2, SCNVector3(0, -hh - 0.02, 0.92), gold, chamfer: 0.05)
        // 下框上的镀铬托盘沿
        box(W * 0.8, 0.18, 0.5, SCNVector3(0, -hh - fb * 0.55, 1.15), Self.pbr(Self.chrome, metal: 1, rough: 0.12), chamfer: 0.08)
        root.addChildNode(frame.flattenedClone())

        // 灯泡：两组交替闪（只换两个共享材质的发光强度）
        bulbA = Self.pbr(.white, metal: 0, rough: 0.3, emission: Self.neonGold, emissionIntensity: 2.2)
        bulbB = Self.pbr(.white, metal: 0, rough: 0.3, emission: Self.neonPink, emissionIntensity: 0.6)
        let bulbGeoA = SCNSphere(radius: 0.15); bulbGeoA.segmentCount = 10; bulbGeoA.firstMaterial = bulbA
        let bulbGeoB = SCNSphere(radius: 0.15); bulbGeoB.segmentCount = 10; bulbGeoB.firstMaterial = bulbB
        var k = 0
        func bulb(_ x: Float, _ y: Float) {
            let n = SCNNode(geometry: k % 2 == 0 ? bulbGeoA : bulbGeoB)
            n.position = SCNVector3(x, y, 0.95)
            root.addChildNode(n)
            k += 1
        }
        let sideCount = lowTier ? 12 : 16
        for i in 0..<sideCount {
            let y = -hh - fb * 0.4 + (W * 1.25 + fb * 0.4 + ft * 0.5) * Float(i) / Float(sideCount - 1)
            bulb(-hw - fs / 2, y)
            bulb(hw + fs / 2, y)
        }
        for i in 1..<(lowTier ? 9 : 12) {
            bulb(-hw + W * Float(i) / Float(lowTier ? 9 : 12), hh + ft / 2)
        }

        // 拱顶导轨（镀铬）：外半径 0.495、内半径 0.47，两侧墙接到底
        let rail = UIBezierPath()
        let rO = CGFloat(0.495 * Double(W)), rI = CGFloat(B.archRadius * Double(W))
        let cy = CGFloat((B.archCenterY - 0.625) * Double(W))
        let wl = CGFloat((B.wallLeft - 0.5) * Double(W)), bottom = CGFloat(-0.625 * Double(W))
        rail.move(to: CGPoint(x: -rO, y: bottom))
        rail.addLine(to: CGPoint(x: -rO, y: cy))
        rail.addArc(withCenter: CGPoint(x: 0, y: cy), radius: rO, startAngle: .pi, endAngle: 0, clockwise: false)
        rail.addLine(to: CGPoint(x: rO, y: bottom))
        rail.addLine(to: CGPoint(x: -wl, y: bottom))
        rail.addLine(to: CGPoint(x: -wl, y: cy))
        rail.addArc(withCenter: CGPoint(x: 0, y: cy), radius: rI, startAngle: 0, endAngle: .pi, clockwise: true)
        rail.addLine(to: CGPoint(x: wl, y: bottom))
        rail.close()
        rail.flatness = 0.02
        let railShape = SCNShape(path: rail, extrusionDepth: 0.35)
        railShape.chamferRadius = 0.05
        railShape.firstMaterial = Self.pbr(Self.chrome, metal: 1, rough: 0.1)
        let railNode = SCNNode(geometry: railShape)
        railNode.position = SCNVector3(0, 0, 0.18)
        root.addChildNode(railNode)

        // 钉子：铜色小圆柱 + 圆帽，合成一个节点
        let nailMat = Self.pbr(Self.brass, metal: 1, rough: 0.2)
        let pins = SCNNode()
        for n in board.nails where n.kind == .nail || n.kind == .drawnOnly {
            let r = CGFloat(n.r) * CGFloat(W)
            let c = SCNCylinder(radius: r, height: 0.42)
            c.radialSegmentCount = lowTier ? 8 : 12
            c.firstMaterial = nailMat
            let pin = SCNNode(geometry: c)
            pin.eulerAngles.x = .pi / 2
            pin.position = Self.world(n.x, n.y, z: 0.21)
            pins.addChildNode(pin)
            let cap = SCNSphere(radius: r * 1.25)
            cap.segmentCount = 8
            cap.firstMaterial = nailMat
            let capNode = SCNNode(geometry: cap)
            capNode.scale = SCNVector3(1, 1, 0.5)
            capNode.position = Self.world(n.x, n.y, z: 0.42)
            pins.addChildNode(capNode)
        }
        root.addChildNode(pins.flattenedClone())

        // 线段：道钉、墙、液晶罩、底板
        let rods = SCNNode()
        let chromeMat = Self.pbr(Self.chrome, metal: 1, rough: 0.15)
        let hood = Self.pbr(.black, metal: 0.3, rough: 0.3, emission: Self.neonPink, emissionIntensity: 1.6)
        for s in board.segments {
            let a = Self.world(s.x1, s.y1), b = Self.world(s.x2, s.y2)
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 0.01 else { continue }
            let thick = max(Float(s.r) * W, s.zone == .housing ? 0.07 : 0.05)
            let g = SCNBox(width: CGFloat(len + thick), height: CGFloat(thick * 2), length: s.zone == .housing ? 0.5 : 0.35, chamferRadius: CGFloat(thick * 0.9))
            g.firstMaterial = s.zone == .housing ? hood : chromeMat
            let n = SCNNode(geometry: g)
            n.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, s.zone == .housing ? 0.25 : 0.18)
            n.eulerAngles.z = atan2(dy, dx)
            rods.addChildNode(n)
        }
        root.addChildNode(rods.flattenedClone())

        // 液晶：内凹的发光屏（数字盘由 SwiftUI 叠在上面）
        let lw = Float(B.lcdX1 - B.lcdX0) * W, lh = Float(B.lcdY1 - B.lcdY0) * W
        let lc = Self.world((B.lcdX0 + B.lcdX1) / 2, (B.lcdY0 + B.lcdY1) / 2)
        let screen = SCNNode(geometry: SCNPlane(width: CGFloat(lw), height: CGFloat(lh)))
        screen.geometry!.firstMaterial = Self.pbr(.black, metal: 0, rough: 0.2, emission: UIColor(red: 0.2, green: 0.08, blue: 0.45, alpha: 1), emissionIntensity: 1.0)
        screen.position = SCNVector3(lc.x, lc.y, 0.02)
        root.addChildNode(screen)

        // 口：始动口（青色霓虹杯）、郁金香杯、袖口金环、ワープ品红环、アウト口
        let neonCyan = Self.pbr(.black, metal: 0.2, rough: 0.3, emission: Self.neonCyan, emissionIntensity: 1.8)
        let neonPinkM = Self.pbr(.black, metal: 0.2, rough: 0.3, emission: Self.neonPink, emissionIntensity: 1.6)
        let goldRing = Self.pbr(Self.neonGold, metal: 1, rough: 0.2, emission: Self.neonGold, emissionIntensity: 0.4)
        func torus(_ x: Double, _ y: Double, _ r: Float, _ m: SCNMaterial) {
            let t = SCNTorus(ringRadius: CGFloat(r), pipeRadius: 0.06)
            t.ringSegmentCount = 24; t.pipeSegmentCount = 8
            t.firstMaterial = m
            let n = SCNNode(geometry: t)
            n.eulerAngles.x = .pi / 2
            n.position = Self.world(x, y, z: 0.12)
            root.addChildNode(n)
        }
        for sgn in [-1.0, 1.0] {
            torus(sgn < 0 ? B.warpX : 1 - B.warpX, B.warpY, Float(B.warpRadius) * W * 1.4, neonPinkM)
            torus(sgn < 0 ? B.sideX : 1 - B.sideX, B.sideY, Float(B.sideRadius) * W * 1.25, goldRing)
            let tx = sgn < 0 ? B.tulipX : 1 - B.tulipX
            let cup = SCNNode(geometry: SCNBox(width: 0.44, height: 0.26, length: 0.5, chamferRadius: 0.08))
            cup.geometry!.firstMaterial = Self.pbr(UIColor(red: 0.95, green: 0.3, blue: 0.5, alpha: 1), metal: 0.3, rough: 0.25, emission: Self.neonPink, emissionIntensity: 0.5)
            cup.position = Self.world(tx, B.tulipY - 0.017, z: 0.25)
            root.addChildNode(cup)
        }
        let start = SCNNode(geometry: SCNBox(width: CGFloat(B.startHalfWidth * 2 + 0.014) * CGFloat(W), height: CGFloat(B.startY1 - B.startY0) * CGFloat(W), length: 0.5, chamferRadius: 0.05))
        start.geometry!.firstMaterial = neonCyan
        start.position = Self.world(0.5, (B.startY0 + B.startY1) / 2, z: 0.25)
        root.addChildNode(start)
        let out = SCNNode(geometry: SCNCylinder(radius: 0.42, height: 0.1))
        out.geometry!.firstMaterial = Self.pbr(.black, metal: 0.5, rough: 0.4)
        out.eulerAngles.x = .pi / 2
        out.scale = SCNVector3(1.1, 1, 0.35)
        out.position = Self.world(0.5, B.outY + 0.012, z: 0.02)
        root.addChildNode(out)

        // 翼片（可开合）
        let wingMat = Self.pbr(Self.neonGold, metal: 1, rough: 0.2, emission: Self.neonGold, emissionIntensity: 0.3)
        wingNodes = [-1.0, 1.0].map { sgn in
            let pivot = SCNNode()
            pivot.position = Self.world(0.5 + sgn * (B.startHalfWidth + 0.004), B.startY1, z: 0.25)
            let blade = SCNNode(geometry: SCNBox(width: 0.08, height: 0.32, length: 0.4, chamferRadius: 0.03))
            blade.geometry!.firstMaterial = wingMat
            blade.position = SCNVector3(0, 0.16, 0)
            pivot.addChildNode(blade)
            root.addChildNode(pivot)
            return pivot
        }

        // 大入赏口：底边铰接的门，打开时向前翻，露出发光内腔
        let ax0 = B.attackerX0, ay0 = B.attackerY0, ay1 = B.attackerY1
        let aw = Float(1 - 2 * ax0) * W, ah = Float(ay1 - ay0) * W
        attackerGlow = SCNNode(geometry: SCNPlane(width: CGFloat(aw), height: CGFloat(ah)))
        attackerGlow.geometry!.firstMaterial = Self.pbr(.black, metal: 0, rough: 0.5, emission: UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1), emissionIntensity: 0)
        attackerGlow.position = Self.world(0.5, (ay0 + ay1) / 2, z: 0.01)
        root.addChildNode(attackerGlow)
        attackerDoor = SCNNode()
        attackerDoor.position = Self.world(0.5, ay0, z: 0.2)
        let door = SCNNode(geometry: SCNBox(width: CGFloat(aw), height: CGFloat(ah), length: 0.1, chamferRadius: 0.04))
        door.geometry!.firstMaterial = Self.pbr(Self.chrome, metal: 1, rough: 0.18)
        door.position = SCNVector3(0, ah / 2, 0)
        attackerDoor.addChildNode(door)
        root.addChildNode(attackerDoor)

        // 郁金香花瓣（开合时换位置）
        let petalMat = Self.pbr(UIColor(red: 1, green: 0.55, blue: 0.72, alpha: 1), metal: 0.1, rough: 0.3, emission: Self.neonPink, emissionIntensity: 0.4)
        for n in board.nails where n.kind == .petal {
            let s = SCNSphere(radius: CGFloat(n.r) * CGFloat(W) * 1.5)
            s.segmentCount = 10
            s.firstMaterial = petalMat
            let p = SCNNode(geometry: s)
            p.scale = SCNVector3(1, 1.4, 1)
            p.position = Self.world(n.x, n.y, z: 0.25)
            root.addChildNode(p)
            petalNodes.append(p)
        }

        // 风车：四叶青色转子
        let bladeMat = Self.pbr(Self.neonCyan, metal: 0.3, rough: 0.3, emission: Self.neonCyan, emissionIntensity: 0.6)
        for n in board.nails where n.kind == .windmill {
            let rotor = SCNNode()
            rotor.position = Self.world(n.x, n.y, z: 0.3)
            let r = Float(n.r) * W * 1.7
            for i in 0..<4 {
                let b = SCNNode(geometry: SCNBox(width: CGFloat(r * 2), height: CGFloat(r * 0.32), length: 0.06, chamferRadius: 0.02))
                b.geometry!.firstMaterial = bladeMat
                b.eulerAngles.z = Float(i) * .pi / 4
                rotor.addChildNode(b)
            }
            rotor.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: n.x < 0.5 ? -.pi * 2 : .pi * 2, duration: 1.4)))
            root.addChildNode(rotor)
        }

        // 玻璃：只留一道很淡的斜向反光带（整块透明玻璃会把台面照灰）
        let sheen = SCNNode(geometry: SCNPlane(width: CGFloat(W * 1.6), height: CGFloat(W * 0.35)))
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = Self.sheenImage()
        sm.blendMode = .add
        sm.writesToDepthBuffer = false
        sheen.geometry!.firstMaterial = sm
        sheen.eulerAngles.z = 0.6
        sheen.position = SCNVector3(-W * 0.12, W * 0.3, 0.85)
        sheen.renderingOrder = 10
        root.addChildNode(sheen)

        // 火花池（撞钉）
        let sparkMat = Self.pbr(.white, metal: 0, rough: 1, emission: Self.neonGold, emissionIntensity: 3)
        for _ in 0..<10 {
            let s = SCNSphere(radius: 0.08); s.segmentCount = 6; s.firstMaterial = sparkMat
            let n = SCNNode(geometry: s)
            n.opacity = 0
            fxRoot.addChildNode(n)
            sparkPool.append(n)
        }
        syncParts(force: true)
    }

    // MARK: 相机：整台机器放进视图（宽或高哪个先满按哪个）
    func fit(viewSize: CGSize) {
        guard viewSize.width > 10, viewSize.height > 10 else { return }
        let W = Self.W
        let contentW = W + 2 * Self.frameSide + 0.3
        let contentH = (W * 1.25 + Self.frameTop + Self.frameBottom) * cos(Self.tilt) + 0.3
        let fovV = Float(26.0 * .pi / 180)
        let aspect = Float(viewSize.width / viewSize.height)
        let dV = (contentH / 2) / tan(fovV / 2)
        let dH = (contentW / 2) / (tan(fovV / 2) * aspect)
        let d = max(dV, dH) + 1.4
        let centerY = (Self.frameTop - Self.frameBottom) / 2 * cos(Self.tilt)
        cameraNode.position = SCNVector3(0, centerY - 0.2, d)
        cameraNode.look(at: SCNVector3(0, centerY, 0))
        reportLCD()
    }

    /// 台面坐标 → 视图坐标
    func project(_ x: Double, _ y: Double, z: Float = 0.3) -> CGPoint? {
        guard let view else { return nil }
        let p = root.convertPosition(Self.world(x, y, z: z), to: nil)
        let s = view.projectPoint(p)
        return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
    }

    func reportLCD() {
        typealias B = PachinkoBoard
        DispatchQueue.main.async { [weak self] in
            guard let self, let a = self.project(B.lcdX0, B.lcdY1, z: 0.02), let b = self.project(B.lcdX1, B.lcdY0, z: 0.02),
                  let c = self.project(B.lcdX0, B.lcdY0, z: 0.02), let d = self.project(B.lcdX1, B.lcdY1, z: 0.02) else { return }
            let xs = [a.x, b.x, c.x, d.x], ys = [a.y, b.y, c.y, d.y]
            self.onLCDRect?(CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
        }
    }

    // MARK: 每帧（主线程 display link：推进游戏、同步节点）
    func start() {
        guard displayLink == nil else { return }
        lastTick = nil
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private var ticks = 0
    @objc private func tick(_ link: CADisplayLink) {
        ticks += 1
        if ticks == 3 || ticks == 30 { reportLCD() }
        let now = link.timestamp
        let dt = lastTick.map { now - $0 } ?? 0
        lastTick = now
        guard let game else { return }
        game.update(dt)
        syncBalls(game.balls)
        syncParts(force: false)
        bulbClock += dt
        let period = game.machine.phase == .play ? 0.5 : 0.18
        if bulbClock >= period {
            bulbClock = 0
            bulbPhase.toggle()
            bulbA.emission.intensity = bulbPhase ? 2.2 : 0.5
            bulbB.emission.intensity = bulbPhase ? 0.5 : 2.2
        }
    }

    private lazy var ballGeometry: SCNSphere = {
        let s = SCNSphere(radius: CGFloat(PachinkoConstants.ballRadius) * CGFloat(Self.W))
        s.segmentCount = lowTier ? 16 : 24
        // 镀铬钢珠：金属反射环境图 + 一点自发光托住暗部（台面很暗，纯反射会显得发灰）
        let m = Self.pbr(UIColor(white: 1, alpha: 1), metal: 1, rough: 0.12, emission: UIColor(white: 0.55, alpha: 1), emissionIntensity: 0.35)
        s.firstMaterial = m
        return s
    }()
    private lazy var shadowGeometry: SCNPlane = {
        let r = CGFloat(PachinkoConstants.ballRadius) * CGFloat(Self.W) * 2.6
        let p = SCNPlane(width: r, height: r)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.blobShadowImage()
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        p.firstMaterial = m
        return p
    }()

    private func syncBalls(_ balls: [PachinkoBall]) {
        let rb = Float(PachinkoConstants.ballRadius) * Self.W
        while ballNodes.count < balls.count {
            let n = SCNNode(geometry: ballGeometry)
            ballRoot.addChildNode(n)
            ballNodes.append(n)
            let s = SCNNode(geometry: shadowGeometry)
            s.renderingOrder = -1
            ballRoot.addChildNode(s)
            shadowNodes.append(s)
        }
        for i in 0..<ballNodes.count {
            if i < balls.count {
                let b = balls[i]
                let p = Self.world(b.x, b.y, z: rb + 0.02)
                ballNodes[i].isHidden = false
                ballNodes[i].position = p
                shadowNodes[i].isHidden = false
                shadowNodes[i].position = SCNVector3(p.x + 0.05, p.y - 0.12, 0.012)
            } else {
                ballNodes[i].isHidden = true
                shadowNodes[i].isHidden = true
            }
        }
    }

    private func syncParts(force: Bool) {
        guard let game else { return }
        let mc = game.machine
        let wings = mc.wingsOpen, atk = mc.attackerOpen
        let tulips = game.physics.board.tulipOpen
        if force || wings != shownWings {
            shownWings = wings
            for (i, w) in wingNodes.enumerated() {
                let sgn: Float = i == 0 ? 1 : -1
                w.runAction(.rotateTo(x: 0, y: 0, z: CGFloat(wings ? sgn * 0.75 : 0), duration: force ? 0 : 0.15))
            }
        }
        if force || atk != shownAttacker {
            shownAttacker = atk
            attackerDoor.runAction(.rotateTo(x: CGFloat(atk ? 1.25 : 0), y: 0, z: 0, duration: force ? 0 : 0.25))
            attackerGlow.geometry?.firstMaterial?.emission.intensity = atk ? 2.5 : 0
        }
        if force || tulips != shownTulips {
            shownTulips = tulips
            let petals = game.physics.board.nails.filter { $0.kind == .petal }
            for (i, n) in petals.enumerated() where i < petalNodes.count {
                petalNodes[i].runAction(.move(to: Self.world(n.x, n.y, z: 0.25), duration: force ? 0 : 0.12))
            }
        }
        let mode = mc.phase == .play ? mc.mode : .normal
        if force || mode != shownMode {
            shownMode = mode
            boardMaterial.diffuse.contents = Self.boardArt(mode: mode)
            boardMaterial.emission.contents = Self.boardArt(mode: mode)
        }
    }

    // MARK: 特效
    private func nailHit(speed: Double, x: Double, y: Double) {
        let now = CACurrentMediaTime()
        if now - nailWindowStart > 0.06 { nailWindowStart = now; nailSounds = 0 }
        if nailSounds < 4 {
            nailSounds += 1
            AudioManager.shared.play(speed > 1.2 ? .pkNail3 : (speed > 0.6 ? .pkNail2 : .pkNail1))
        }
        guard speed > 0.6 else { return }
        let s = sparkPool[sparkIndex]
        sparkIndex = (sparkIndex + 1) % sparkPool.count
        s.removeAllActions()
        s.position = Self.world(x, y, z: 0.45)
        s.opacity = 1
        s.scale = SCNVector3(0.6, 0.6, 0.6)
        s.runAction(.group([.scale(to: 1.5, duration: 0.12), .fadeOut(duration: 0.14)]))
    }

    private func pocketHit(_ p: PachinkoPocket, _ b: PachinkoBall) {
        let amount: Int
        switch p {
        case .start: amount = PachinkoConstants.startPayout
        case .tulipLeft, .tulipRight: amount = PachinkoConstants.tulipPayout
        case .side: amount = PachinkoConstants.sidePayout
        case .attacker: amount = PachinkoConstants.attackerPayout
        case .out, .stuck: return
        }
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.25, pipeRadius: 0.04))
        ring.geometry!.firstMaterial = Self.pbr(.black, metal: 0, rough: 1, emission: Self.neonGold, emissionIntensity: 3)
        ring.eulerAngles.x = .pi / 2
        ring.position = Self.world(b.x, b.y, z: 0.3)
        fxRoot.addChildNode(ring)
        ring.runAction(.sequence([.group([.scale(to: 2.6, duration: 0.35), .fadeOut(duration: 0.35)]), .removeFromParentNode()]))
        if let pt = project(b.x, b.y) { onPayout?(pt, amount) }
    }

    // MARK: 帧率（渲染线程）
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        statsLock.lock(); defer { statsLock.unlock() }
        frames += 1
        if fpsWindow == 0 { fpsWindow = time }
        if time - fpsWindow >= 2 {
            fps = Double(frames) / (time - fpsWindow)
            frames = 0
            fpsWindow = time
            let balls = game?.ballsInFlight ?? 0
            NSLog("PACHINKO_STATS fps=%.1f balls=%d lowTier=%d", fps, balls, VisualFX.lowTier ? 1 : 0)
        }
    }

    // MARK: 贴图（代码生成）
    static func sheenImage() -> UIImage {
        let size = CGSize(width: 256, height: 64)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.07).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 64), options: [])
        }
    }

    static func blobShadowImage() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.black.withAlphaComponent(0.55).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }

    private static var artCache: [PachinkoMode: UIImage] = [:]
    /// 台面画：深色底 + 从液晶放射的金线 + 星点 + 底部的霓虹弧。ST 品红、时短青色
    static func boardArt(mode: PachinkoMode) -> UIImage {
        if let c = artCache[mode] { return c }
        let size = CGSize(width: 512, height: 640)
        let (top, bottom): (UIColor, UIColor) = {
            switch mode {
            case .normal: return (UIColor(red: 0.12, green: 0.1, blue: 0.36, alpha: 1), UIColor(red: 0.03, green: 0.04, blue: 0.14, alpha: 1))
            case .st: return (UIColor(red: 0.5, green: 0.06, blue: 0.4, alpha: 1), UIColor(red: 0.16, green: 0.02, blue: 0.14, alpha: 1))
            case .jitan: return (UIColor(red: 0.04, green: 0.34, blue: 0.44, alpha: 1), UIColor(red: 0.02, green: 0.08, blue: 0.14, alpha: 1))
            }
        }()
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 256, y: 200), startRadius: 0, endCenter: CGPoint(x: 256, y: 260), endRadius: 460, options: [.drawsAfterEndLocation])
            // 放射金线
            c.setStrokeColor(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 0.12).cgColor)
            c.setLineWidth(2)
            for i in 0..<36 {
                let a = Double(i) / 36 * 2 * .pi
                c.move(to: CGPoint(x: 256, y: 250))
                c.addLine(to: CGPoint(x: 256 + cos(a) * 600, y: 250 + sin(a) * 600))
            }
            c.strokePath()
            // 星点
            var seed = PachinkoRandom(seed: 42)
            for _ in 0..<140 {
                let x = seed.uniform() * 512, y = seed.uniform() * 640, r = 0.6 + seed.uniform() * 1.6
                c.setFillColor(UIColor(white: 1, alpha: 0.15 + seed.uniform() * 0.35).cgColor)
                c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            // 底部霓虹弧（大入赏口一带）
            c.setStrokeColor(UIColor(red: 1, green: 0.3, blue: 0.65, alpha: 0.35).cgColor)
            c.setLineWidth(5)
            c.addArc(center: CGPoint(x: 256, y: 760), radius: 300, startAngle: .pi * 1.18, endAngle: .pi * 1.82, clockwise: false)
            c.strokePath()
        }
        artCache[mode] = img
        return img
    }
}

/// SwiftUI 包装
struct Pachinko3DView: UIViewRepresentable {
    let scene3D: Pachinko3DScene

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
        let s = scene3D
        v.onLayout = { size in s.fit(viewSize: size) }
        v.scene = s.scene
        s.view = v
        v.delegate = s
        v.pointOfView = s.cameraNode
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.antialiasingMode = VisualFX.lowTier ? .none : .multisampling2X
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isUserInteractionEnabled = false
        #if DEBUG
        v.showsStatistics = ProcessInfo.processInfo.arguments.contains("-debugSceneStats")
        #endif
        s.start()
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: ()) {
        (uiView.delegate as? Pachinko3DScene)?.stop()
    }
}
