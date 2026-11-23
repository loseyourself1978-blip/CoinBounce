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
    /// v12.6 机器外框（世界单位）：台面 10 × 12.5；右边多一条发射轨道，上面是灯牌，下面是装拉杆的面板。
    /// 灯牌和面板的高度按屏幕比例定（Layout），整台机器把屏幕撑满
    static let leftEdge: Float = -5.45, rightEdge: Float = 5.95
    static let laneInner: Float = 4.95, laneOuter: Float = 5.40, laneWall: Float = 5.55
    static let slotLeft: Float = 4.78
    static var contentCenterX: Float { (leftEdge + rightEdge) / 2 }
    static var contentWidth: Float { rightEdge - leftEdge + 0.3 }

    struct Layout: Equatable {
        var top: Float = 1.8
        var bottom: Float = 4.4
        /// 整台机器在屏幕上的宽高比
        var aspect: CGFloat {
            CGFloat(Pachinko3DScene.contentWidth / ((12.5 + top + bottom) * cos(Pachinko3DScene.tilt) + 0.3))
        }
        /// 按可用区域的比例分配灯牌和面板的高度
        static func fitting(_ size: CGSize) -> Layout {
            guard size.width > 10, size.height > 10 else { return Layout() }
            let wantH = Pachinko3DScene.contentWidth * Float(size.height / size.width)
            let spare = wantH - 12.5 - 0.3
            let bottom = min(6.8, max(4.6, spare * 0.74))
            let top = min(2.6, max(1.5, spare - bottom))
            return Layout(top: top, bottom: bottom)
        }
    }
    let layout: Layout
    private var frameTop: Float { layout.top }
    private var frameBottom: Float { layout.bottom }

    /// SwiftUI 叠在机器上的几块区域（视图坐标）
    struct Rects: Equatable {
        var lcd = CGRect.zero, marquee = CGRect.zero, apron = CGRect.zero, plunger = CGRect.zero
    }

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
    // v12.6
    private var plungerRoot = SCNNode()
    private var springRings: [SCNNode] = []
    private var knobNode = SCNNode()
    private var waitingBall = SCNNode()
    private var flapNode = SCNNode()
    private var flapOpen = false
    private var catcherNode = SCNNode()
    private var shownPull: Double = 0
    private var flashUntil: CFTimeInterval = 0
    private var sparkPool: [SCNNode] = []
    private var sparkIndex = 0
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var bulbPhase = false
    private var bulbClock = 0.0
    private var nailWindowStart: CFTimeInterval = 0
    private var nailSounds = 0
    private var lowTier: Bool { VisualFX.lowTier }

    /// 液晶、灯牌、面板、拉杆在视图里的位置（SwiftUI 把数字盘、水果灯、按钮叠在这些位置上）
    var onRects: ((Rects) -> Void)?
    /// 落袋：视图坐标 + 金额（SwiftUI 飘「+N」）
    var onPayout: ((CGPoint, Int) -> Void)?
    /// 帧率统计（每秒一次）
    private(set) var fps: Double = 0
    private var frames = 0
    private var fpsWindow: CFTimeInterval = 0
    private let statsLock = NSLock()

    /// 从创建到第一帧画出来的时间（首次进入的等待，PACHINKO_FIRST_FRAME）
    private let createdAt = CACurrentMediaTime()
    private var firstFrameLogged = false

    /// game = nil：大厅里后台预热用（只搭场景、编译着色器，不接游戏）
    init(game: PachinkoGame?, layout: Layout = Layout()) {
        self.game = game
        self.layout = layout
        super.init()
        buildScene()
        buildMachine()
        if game != nil { NSLog("PACHINKO_BUILD ms=%.0f", (CACurrentMediaTime() - createdAt) * 1000) }
        game?.onPocket = { [weak self] p, b in self?.pocketHit(p, b) }
        game?.onNailHit = { [weak self] v, x, y in self?.nailHit(speed: v, x: x, y: y) }
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
        scene.lightingEnvironment.contents = on ? PusherScene3D.sharedCasinoEnvironment : PusherScene3D.environmentImage()
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
        boardMaterial.multiply.contents = UIColor(white: 0.62, alpha: 1)
        // 底板自己微微发光（液晶和霓虹的反光），不靠环境图把它照亮成灰色
        boardMaterial.emission.contents = Self.boardArt(mode: .normal)
        boardMaterial.emission.intensity = 0.62
        let plate = SCNNode(geometry: SCNBox(width: CGFloat(W), height: CGFloat(W * 1.25), length: 0.4, chamferRadius: 0))
        plate.geometry!.materials = [boardMaterial]
        plate.position = SCNVector3(0, 0, -0.2)
        root.addChildNode(plate)

        // v12.6 外框：红色亮漆 + 金边 + 灯泡。上面灯牌，下面面板（右边留一条装拉杆的槽），右边是发射轨道
        let lacquer = Self.pbr(UIColor(red: 0.55, green: 0.04, blue: 0.1, alpha: 1), metal: 0.1, rough: 0.3)
        lacquer.clearCoat.contents = 1.0
        lacquer.clearCoatRoughness.contents = 0.08
        let gold = Self.pbr(Self.neonGold, metal: 1, rough: 0.22)
        let chromeRail = Self.pbr(Self.chrome, metal: 1, rough: 0.1)
        let gunmetal = Self.pbr(UIColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1), metal: 0.6, rough: 0.45)
        let hw = W / 2, hh = W * 1.25 / 2
        let ft = frameTop, fb = frameBottom
        let L = Self.leftEdge, R = Self.rightEdge
        let frame = SCNNode()
        /// 左下角 (x0, y0) 到右上角 (x1, y1) 的盒子，正面在 z1
        func box(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, z0: Float = -0.4, z1: Float, _ m: SCNMaterial, chamfer: CGFloat = 0.1) {
            let n = SCNNode(geometry: SCNBox(width: CGFloat(x1 - x0), height: CGFloat(y1 - y0), length: CGFloat(z1 - z0), chamferRadius: chamfer))
            n.geometry!.firstMaterial = m
            n.position = SCNVector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
            frame.addChildNode(n)
        }
        let top = hh + ft, bottom = -hh - fb
        box(L, bottom, -hw, top, z1: 0.9, lacquer)                               // 左框
        box(Self.laneWall, bottom, R, top, z1: 0.9, lacquer)                     // 右框
        box(-hw, hh, Self.laneWall, top, z1: 0.9, lacquer)                       // 灯牌
        box(-hw, bottom, Self.slotLeft, -hh, z1: 1.0, lacquer)                   // 面板
        box(Self.slotLeft, bottom, Self.laneWall, bottom + 0.35, z1: 1.0, lacquer) // 拉杆槽的下沿
        // 发射轨道和拉杆槽的底板（比台面暗）
        box(Self.slotLeft, bottom, Self.laneWall, 3.9, z0: -0.4, z1: -0.02, gunmetal, chamfer: 0)
        // 金色内边
        box(-hw - 0.08, -hh, -hw + 0.04, hh, z0: 0.82, z1: 1.02, gold, chamfer: 0.05)
        box(-hw - 0.08, hh - 0.04, Self.laneWall, hh + 0.08, z0: 0.82, z1: 1.02, gold, chamfer: 0.05)
        box(-hw - 0.08, -hh - 0.08, Self.slotLeft, -hh + 0.04, z0: 0.92, z1: 1.1, gold, chamfer: 0.05)
        box(Self.slotLeft - 0.1, bottom + 0.3, Self.slotLeft + 0.02, -hh, z0: 0.92, z1: 1.1, gold, chamfer: 0.04)
        box(Self.laneWall - 0.02, bottom + 0.3, Self.laneWall + 0.1, hh, z0: 0.82, z1: 1.02, gold, chamfer: 0.04)
        root.addChildNode(frame.flattenedClone())

        // 灯泡：两组交替闪（只换两个共享材质的发光强度）
        bulbA = Self.pbr(.white, metal: 0, rough: 0.3, emission: Self.neonGold, emissionIntensity: 2.2)
        bulbB = Self.pbr(.white, metal: 0, rough: 0.3, emission: Self.neonPink, emissionIntensity: 0.6)
        let bulbGeoA = SCNSphere(radius: 0.13); bulbGeoA.segmentCount = 10; bulbGeoA.firstMaterial = bulbA
        let bulbGeoB = SCNSphere(radius: 0.13); bulbGeoB.segmentCount = 10; bulbGeoB.firstMaterial = bulbB
        var k = 0
        let bulbs = SCNNode()
        func bulb(_ x: Float, _ y: Float, z: Float = 0.95) {
            let n = SCNNode(geometry: k % 2 == 0 ? bulbGeoA : bulbGeoB)
            n.position = SCNVector3(x, y, z)
            bulbs.addChildNode(n)
            k += 1
        }
        let sideCount = lowTier ? 14 : 20
        for i in 0..<sideCount {
            let y = bottom + 0.35 + (top - bottom - 0.7) * Float(i) / Float(sideCount - 1)
            bulb((L - hw) / 2, y)
            bulb((Self.laneWall + R) / 2, y)
        }
        let topCount = lowTier ? 10 : 14
        for i in 1..<topCount {
            let x = -hw + (Self.laneWall + hw) * Float(i) / Float(topCount)
            bulb(x, top - 0.22)
        }
        root.addChildNode(bulbs)

        // 拱顶导轨（镀铬）：外半径 0.495、内半径 0.47。右侧在仰角 14°–26° 留一个缺口（单向挡片），发射的珠子从这里进来
        let rO = CGFloat(0.495 * Double(W)), rI = CGFloat(B.archRadius * Double(W))
        let cy = CGFloat((B.archCenterY - 0.625) * Double(W))
        let railBottom = CGFloat(-0.625 * Double(W))
        let a0 = CGFloat(B.flapStart), a1 = CGFloat(B.flapEnd)
        let railA = UIBezierPath()
        railA.move(to: CGPoint(x: -rO, y: railBottom))
        railA.addLine(to: CGPoint(x: -rO, y: cy))
        railA.addArc(withCenter: CGPoint(x: 0, y: cy), radius: rO, startAngle: .pi, endAngle: a1, clockwise: false)
        railA.addArc(withCenter: CGPoint(x: 0, y: cy), radius: rI, startAngle: a1, endAngle: .pi, clockwise: true)
        railA.addLine(to: CGPoint(x: -rI, y: railBottom))
        railA.close()
        let railB = UIBezierPath()
        railB.move(to: CGPoint(x: rO * cos(a0), y: cy + rO * sin(a0)))
        railB.addArc(withCenter: CGPoint(x: 0, y: cy), radius: rO, startAngle: a0, endAngle: 0, clockwise: false)
        railB.addLine(to: CGPoint(x: rO, y: railBottom))
        railB.addLine(to: CGPoint(x: rI, y: railBottom))
        railB.addLine(to: CGPoint(x: rI, y: cy))
        railB.addArc(withCenter: CGPoint(x: 0, y: cy), radius: rI, startAngle: 0, endAngle: a0, clockwise: true)
        railB.close()
        for path in [railA, railB] {
            path.flatness = 0.02
            let shape = SCNShape(path: path, extrusionDepth: 0.35)
            shape.chamferRadius = 0.05
            shape.firstMaterial = chromeRail
            let n = SCNNode(geometry: shape)
            n.position = SCNVector3(0, 0, 0.18)
            root.addChildNode(n)
        }
        // 单向挡片：铰在缺口上端，珠子经过时向里摆一下
        let p1 = SCNVector3(Float(rI + 0.12) * Float(cos(a1)), Float(cy) + Float(rI + 0.12) * Float(sin(a1)), 0.2)
        let p0 = SCNVector3(Float(rI + 0.12) * Float(cos(a0)), Float(cy) + Float(rI + 0.12) * Float(sin(a0)), 0.2)
        let flapLen = hypot(p0.x - p1.x, p0.y - p1.y)
        flapNode.position = p1
        flapNode.eulerAngles.z = atan2(p0.y - p1.y, p0.x - p1.x)
        let blade = SCNNode(geometry: SCNBox(width: CGFloat(flapLen), height: 0.09, length: 0.3, chamferRadius: 0.04))
        blade.geometry!.firstMaterial = Self.pbr(Self.neonGold, metal: 1, rough: 0.2, emission: Self.neonGold, emissionIntensity: 0.35)
        blade.position = SCNVector3(flapLen / 2, 0, 0)
        flapNode.addChildNode(blade)
        root.addChildNode(flapNode)
        flapRest = flapNode.eulerAngles.z

        // 发射轨道的外轨：下面直、上端收进拱顶。外轨外侧到右框之间用红漆填满
        let rLaneOut = CGFloat(Self.laneOuter)
        func outerR(_ phi: CGFloat) -> CGFloat {
            let m0: CGFloat = 12 * .pi / 180, m1: CGFloat = 31 * .pi / 180
            if phi <= m0 { return rLaneOut }
            let u = min(1, (phi - m0) / (m1 - m0))
            return rLaneOut + (rO - rLaneOut) * u * u * (3 - 2 * u)
        }
        var curve: [CGPoint] = []
        let steps = 28
        let phiMax: CGFloat = 31 * .pi / 180
        for i in 0...steps {
            let phi = phiMax * CGFloat(i) / CGFloat(steps)
            curve.append(CGPoint(x: outerR(phi) * cos(phi), y: cy + outerR(phi) * sin(phi)))
        }
        let slotBottom = CGFloat(bottom + 0.35)
        let fill = UIBezierPath()
        fill.move(to: CGPoint(x: rLaneOut, y: slotBottom))
        for pt in curve { fill.addLine(to: pt) }
        fill.addLine(to: CGPoint(x: curve.last!.x, y: CGFloat(hh)))
        fill.addLine(to: CGPoint(x: CGFloat(Self.laneWall), y: CGFloat(hh)))
        fill.addLine(to: CGPoint(x: CGFloat(Self.laneWall), y: slotBottom))
        fill.close()
        let fillShape = SCNShape(path: fill, extrusionDepth: 1.3)
        fillShape.chamferRadius = 0.06
        fillShape.firstMaterial = lacquer
        let fillNode = SCNNode(geometry: fillShape)
        fillNode.position = SCNVector3(0, 0, 0.25)
        root.addChildNode(fillNode)
        let strip = UIBezierPath()
        strip.move(to: CGPoint(x: rLaneOut, y: slotBottom))
        for pt in curve { strip.addLine(to: pt) }
        for i in stride(from: steps, through: 0, by: -1) {
            let phi = phiMax * CGFloat(i) / CGFloat(steps)
            strip.addLine(to: CGPoint(x: (outerR(phi) + 0.09) * cos(phi), y: cy + (outerR(phi) + 0.09) * sin(phi)))
        }
        strip.addLine(to: CGPoint(x: rLaneOut + 0.09, y: slotBottom))
        strip.close()
        let stripShape = SCNShape(path: strip, extrusionDepth: 0.4)
        stripShape.firstMaterial = chromeRail
        let stripNode = SCNNode(geometry: stripShape)
        stripNode.position = SCNVector3(0, 0, 0.2)
        root.addChildNode(stripNode)
        // 台面右墙在面板里往下接一段（拉杆槽的左壁）
        buildPlunger(bottom: bottom, chrome: chromeRail, gold: gold)

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
        // アウト口：深色的槽 + 来回滑的幸运杯（v12.6）
        let out = SCNNode(geometry: SCNBox(width: CGFloat(0.44 * W), height: 0.34, length: 0.06, chamferRadius: 0.03))
        out.geometry!.firstMaterial = Self.pbr(.black, metal: 0.5, rough: 0.4)
        out.position = Self.world(0.5, 0.035, z: 0.02)
        root.addChildNode(out)
        let track = SCNNode(geometry: SCNBox(width: CGFloat(0.42 * W), height: 0.05, length: 0.12, chamferRadius: 0.02))
        track.geometry!.firstMaterial = chromeMat
        track.position = Self.world(0.5, 0.016, z: 0.1)
        root.addChildNode(track)
        let cupMat = Self.pbr(Self.neonGold, metal: 1, rough: 0.18, emission: Self.neonGold, emissionIntensity: 0.55)
        let cupHalf = Float(PachinkoConstants.catcherHalfWidth + PachinkoConstants.ballRadius) * W
        func cupPart(_ w: Float, _ h: Float, _ x: Float, _ y: Float) {
            let n = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(h), length: 0.42, chamferRadius: 0.035))
            n.geometry!.firstMaterial = cupMat
            n.position = SCNVector3(x, y, 0)
            catcherNode.addChildNode(n)
        }
        cupPart(cupHalf * 2 + 0.14, 0.09, 0, -0.14)
        cupPart(0.08, 0.3, -cupHalf - 0.03, 0)
        cupPart(0.08, 0.3, cupHalf + 0.03, 0)
        catcherNode.position = Self.world(0.5, 0.038, z: 0.24)
        root.addChildNode(catcherNode)

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
        let contentW = Self.contentWidth
        let contentH = (Self.W * 1.25 + frameTop + frameBottom) * cos(Self.tilt) + 0.3
        let fovV = Float(26.0 * .pi / 180)
        let aspect = Float(viewSize.width / viewSize.height)
        let dV = (contentH / 2) / tan(fovV / 2)
        let dH = (contentW / 2) / (tan(fovV / 2) * aspect)
        let d = max(dV, dH) + 1.2
        let centerY = (frameTop - frameBottom) / 2 * cos(Self.tilt)
        cameraNode.position = SCNVector3(Self.contentCenterX, centerY - 0.2, d)
        cameraNode.look(at: SCNVector3(Self.contentCenterX, centerY, 0))
        reportLCD()
    }

    /// 台面坐标 → 视图坐标
    func project(_ x: Double, _ y: Double, z: Float = 0.3) -> CGPoint? {
        guard let view else { return nil }
        let p = root.convertPosition(Self.world(x, y, z: z), to: nil)
        let s = view.projectPoint(p)
        return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
    }

    /// 机器上的一块矩形（世界坐标）在视图里的外接框
    private func viewRect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, z: Float) -> CGRect? {
        guard let view else { return nil }
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for (x, y) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)] {
            let s = view.projectPoint(root.convertPosition(SCNVector3(x, y, z), to: nil))
            xs.append(CGFloat(s.x)); ys.append(CGFloat(s.y))
        }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// 现在的几块区域；投影还不可靠时返回 nil
    func currentRects() -> Rects? {
        typealias B = PachinkoBoard
        let W = Self.W, hh = W * 0.625
        func wx(_ x: Double) -> Float { Float(x - 0.5) * W }
        func wy(_ y: Double) -> Float { Float(y - 0.625) * W }
        guard let vb = view?.bounds, vb.width > 10,
              let lcd = viewRect(wx(B.lcdX0), wy(B.lcdY0), wx(B.lcdX1), wy(B.lcdY1), z: 0.02),
              let marquee = viewRect(-W / 2, hh + 0.12, Self.laneWall, hh + frameTop - 0.42, z: 0.9),
              let apron = viewRect(-W / 2, -hh - frameBottom + 0.1, Self.slotLeft - 0.12, -hh - 0.12, z: 1.0),
              let plunger = viewRect(Self.slotLeft - 0.5, -hh - frameBottom, Self.rightEdge, -hh + 1.2, z: 0.6) else { return nil }
        // 第一帧之前投影可能还不对：只接受落在视图里、宽度合理的结果
        guard vb.insetBy(dx: -2, dy: -2).contains(lcd), lcd.width > vb.width * 0.2, lcd.width < vb.width * 0.8 else { return nil }
        return Rects(lcd: lcd, marquee: marquee, apron: apron, plunger: plunger)
    }

    func reportLCD() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let r = self.currentRects() else { return }
            self.onRects?(r)
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
        syncBalls(game)
        syncParts(force: false)
        syncPlunger(game, dt: dt)
        bulbClock += dt
        let period = (game.machine.phase == .play && now > flashUntil) ? 0.5 : 0.16
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

    private lazy var goldBallGeometry: SCNSphere = {
        let s = SCNSphere(radius: CGFloat(PachinkoConstants.ballRadius) * CGFloat(Self.W))
        s.segmentCount = lowTier ? 16 : 24
        s.firstMaterial = Self.pbr(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), metal: 1, rough: 0.14, emission: Self.neonGold, emissionIntensity: 0.55)
        return s
    }()

    /// 台面上的珠子 + 发射轨道上的珠子
    private func syncBalls(_ game: PachinkoGame) {
        let rb = Float(PachinkoConstants.ballRadius) * Self.W
        let balls = game.balls, lane = game.laneBalls
        let total = balls.count + lane.count
        while ballNodes.count < total {
            let n = SCNNode(geometry: ballGeometry)
            ballRoot.addChildNode(n)
            ballNodes.append(n)
            let s = SCNNode(geometry: shadowGeometry)
            s.renderingOrder = -1
            ballRoot.addChildNode(s)
            shadowNodes.append(s)
        }
        var inFlap = false
        for i in 0..<ballNodes.count {
            if i < balls.count {
                let b = balls[i]
                let p = Self.world(b.x, b.y, z: rb + 0.02)
                let geo = b.bonus ? goldBallGeometry : ballGeometry
                if ballNodes[i].geometry !== geo { ballNodes[i].geometry = geo }
                ballNodes[i].isHidden = false
                ballNodes[i].position = p
                shadowNodes[i].isHidden = false
                shadowNodes[i].position = SCNVector3(p.x + 0.05, p.y - 0.12, 0.012)
            } else if i < total {
                let l = lane[i - balls.count]
                let d = l.distance
                let pt = PachinkoBoard.lanePoint(d)
                if ballNodes[i].geometry !== ballGeometry { ballNodes[i].geometry = ballGeometry }
                ballNodes[i].isHidden = false
                ballNodes[i].position = Self.world(pt.x, pt.y, z: rb + 0.02)
                shadowNodes[i].isHidden = true
                if l.result != nil {
                    let phi = (d - PachinkoBoard.laneStraight) / 0.485
                    if phi > PachinkoBoard.flapStart - 0.12 && phi < PachinkoBoard.flapEnd + 0.1 { inFlap = true }
                }
            } else {
                ballNodes[i].isHidden = true
                shadowNodes[i].isHidden = true
            }
        }
        if inFlap != flapOpen {
            flapOpen = inFlap
            flapNode.runAction(.rotateTo(x: 0, y: 0, z: CGFloat(flapRest + (inFlap ? 0.75 : 0)), duration: inFlap ? 0.05 : 0.18, usesShortestUnitArc: true))
        }
        catcherNode.position.x = Self.world(game.catcherX, 0).x
    }
    private var flapRest: Float = 0

    // MARK: v12.6 弹簧拉杆（在面板右边的槽里）
    /// 拉杆顶在静止时的位置：发射轨道最下面那颗珠子的正下方
    private var tipRestY: Float { Float(PachinkoBoard.laneBottomY - 0.625) * Self.W - Float(PachinkoConstants.ballRadius) * Self.W }
    private static let plungerTravel: Float = 1.15
    /// 杆长按面板高度定：手柄拉到底还在面板里
    private var rodLength: Float {
        let bottom = -Self.W * 0.625 - frameBottom
        return max(2.2, (tipRestY - 0.14) - (bottom + 0.35 + Self.plungerTravel + 0.5))
    }
    private var bracketY: Float { tipRestY - 0.14 - rodLength * 0.64 }

    private func buildPlunger(bottom: Float, chrome: SCNMaterial, gold: SCNMaterial) {
        let x = Float(PachinkoBoard.laneX - 0.5) * Self.W
        // 固定的托架（弹簧顶在它上面）
        let bracket = SCNNode(geometry: SCNBox(width: 0.62, height: 0.16, length: 0.5, chamferRadius: 0.04))
        bracket.geometry!.firstMaterial = gold
        bracket.position = SCNVector3(x, bracketY, 0.22)
        root.addChildNode(bracket)
        // 会动的部分：顶帽、杆、手柄
        plungerRoot.position = SCNVector3(x, tipRestY, 0.2)
        let cap = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.16))
        cap.geometry!.firstMaterial = Self.pbr(UIColor(red: 0.85, green: 0.1, blue: 0.2, alpha: 1), metal: 0.2, rough: 0.35)
        cap.position = SCNVector3(0, -0.07, 0)
        plungerRoot.addChildNode(cap)
        let rodLen = rodLength
        let rod = SCNNode(geometry: SCNCylinder(radius: 0.065, height: CGFloat(rodLen)))
        rod.geometry!.firstMaterial = chrome
        rod.position = SCNVector3(0, -0.14 - rodLen / 2, 0)
        plungerRoot.addChildNode(rod)
        let knob = SCNSphere(radius: 0.36)
        knob.segmentCount = 20
        knob.firstMaterial = Self.pbr(UIColor(red: 0.9, green: 0.08, blue: 0.2, alpha: 1), metal: 0.1, rough: 0.2, emission: UIColor(red: 0.6, green: 0, blue: 0.1, alpha: 1), emissionIntensity: 0.4)
        knob.firstMaterial!.clearCoat.contents = 1.0
        knobNode = SCNNode(geometry: knob)
        knobNode.position = SCNVector3(0, -0.14 - rodLen, 0.1)
        knobNode.scale = SCNVector3(1, 0.85, 1)
        plungerRoot.addChildNode(knobNode)
        let collar = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 0.1))
        collar.geometry!.firstMaterial = gold
        collar.position = SCNVector3(0, -0.14 - rodLen + 0.3, 0)
        plungerRoot.addChildNode(collar)
        root.addChildNode(plungerRoot)
        // 弹簧：一串镀铬的环，间距随压缩变化
        let ringGeo = SCNTorus(ringRadius: 0.18, pipeRadius: 0.042)
        ringGeo.ringSegmentCount = 16; ringGeo.pipeSegmentCount = 6
        ringGeo.firstMaterial = chrome
        for _ in 0..<(lowTier ? 8 : 11) {
            let n = SCNNode(geometry: ringGeo)
            n.position.x = x
            n.position.z = 0.2
            n.eulerAngles.z = 0.16
            root.addChildNode(n)
            springRings.append(n)
        }
        // 等在拉杆顶上的下一颗珠子
        waitingBall = SCNNode(geometry: ballGeometry)
        root.addChildNode(waitingBall)
        layoutPlunger(pull: 0, hasBall: false)
    }

    private func layoutPlunger(pull: Double, hasBall: Bool) {
        let tip = tipRestY - Float(pull) * Self.plungerTravel
        plungerRoot.position.y = tip
        // 弹簧夹在顶帽和托架之间
        let s0 = bracketY + 0.1, s1 = tip - 0.16
        let n = springRings.count
        for (i, r) in springRings.enumerated() {
            r.position.y = s0 + (s1 - s0) * Float(i) / Float(max(1, n - 1))
        }
        let rb = Float(PachinkoConstants.ballRadius) * Self.W
        waitingBall.isHidden = !hasBall
        waitingBall.position = SCNVector3(plungerRoot.position.x, tip + rb, rb + 0.02)
    }

    private func syncPlunger(_ game: PachinkoGame, dt: Double) {
        var target = game.pull
        if target <= 0, game.auto, game.tray > 0 {
            // AUTO：拉杆自己慢慢拉下去，到点弹回
            let p = game.fireProgress
            target = PachinkoConstants.pull(forPower: game.power) * p * p
        }
        // 往下拉跟手；松开时弹回（很快，带一点过冲）
        if target >= shownPull { shownPull = target } else { shownPull = max(target, shownPull - dt * 14) }
        let busy = game.laneBalls.contains { $0.distance < 0.06 }
        layoutPlunger(pull: shownPull, hasBall: game.tray > 0 && !busy)
    }

    /// 金珠雨：灯泡快闪一阵
    func flashBulbs(seconds: Double) { flashUntil = CACurrentMediaTime() + seconds }

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
        case .catcher:
            amount = PachinkoConstants.catcherPayout
            catcherNode.runAction(.sequence([.scale(to: 1.35, duration: 0.07), .scale(to: 1, duration: 0.16)]))
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
        if !firstFrameLogged && game != nil {
            firstFrameLogged = true
            NSLog("PACHINKO_FIRST_FRAME ms=%.0f prewarmed=%d", (CACurrentMediaTime() - createdAt) * 1000, Self.prewarmed ? 1 : 0)
            DispatchQueue.main.async { [weak self] in
                self?.reportLCD()
                self?.onFirstFrame?(); self?.onFirstFrame = nil
            }
        }
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

    // MARK: 大厅里预热（v12.5）
    /// 第一次进弹子机原来要等好几秒：环境图、台面画在主线程现画，着色器在第一帧同步编译。
    /// 大厅空闲时在后台把这些都做掉：搭一个不接游戏的场景，用离屏 SCNView.prepare 编译着色器、上传贴图。
    /// SceneKit 按材质配置缓存编译好的管线，之后真正进场时新建的场景直接复用。
    private(set) static var prewarmed = false
    /// 预热时拍的一张机器快照
    private(set) static var placeholder: UIImage?
    /// 快照里各块区域的位置（快照和进场后的视图一样大），3D 视图还没建好时先按它摆
    private(set) static var placeholderRects: Rects?
    /// 第一帧画出来了（主线程回调，PachinkoView 撤掉快照）
    var onFirstFrame: (() -> Void)?
    private static var prewarmStarted = false
    private static var prewarmView: SCNView?

    static func prewarmOnce() {
        guard !prewarmStarted, !ProcessInfo.processInfo.arguments.contains("-noPachinkoPrewarm") else { return }
        prewarmStarted = true
        // 和 PachinkoView 一样的机器尺寸（同一个 Layout，快照才对得上）。窗口尺寸在主线程取，场景在后台搭
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        let size = PachinkoView.machineSize(in: window.bounds.inset(by: window.safeAreaInsets).size)
        DispatchQueue.global(qos: .utility).async {
            _ = PusherScene3D.sharedCasinoEnvironment
            for m in [PachinkoMode.normal, .st, .jitan] { _ = boardArt(mode: m) }
            let s = Pachinko3DScene(game: nil, layout: .fitting(size))
            DispatchQueue.main.async {
                // 离屏 prepare 在模拟器上要十几秒、还和真正进场抢 GPU；改成在窗口里放一个几乎看不见的视图真画几帧，
                // 用和游戏一样的视图设置（透明、抗锯齿、HDR），编出来的管线和进场时一样
                let v = SCNView(frame: CGRect(x: 0, y: window.bounds.height - 2, width: size.width, height: size.height), options: nil)
                v.antialiasingMode = VisualFX.lowTier ? .none : .multisampling2X
                v.backgroundColor = .clear
                v.isOpaque = false
                v.alpha = 0.011
                v.isUserInteractionEnabled = false
                v.scene = s.scene
                v.pointOfView = s.cameraNode
                v.preferredFramesPerSecond = 30
                s.fit(viewSize: v.bounds.size)
                let probe = PrewarmProbe()
                v.delegate = probe
                prewarmProbe = probe
                window.addSubview(v)
                v.isPlaying = true
                prewarmView = v
                let t0 = CACurrentMediaTime()
                probe.onFrames = {
                    prewarmed = true
                    // 进场时第一帧出来之前先显示这张（同一台机器、同一个相机）
                    placeholder = prewarmView?.snapshot()
                    s.view = prewarmView
                    placeholderRects = s.currentRects()
                    NSLog("PACHINKO_PREWARM ok=1 ms=%.0f rects=%d snap=%@ view=%@", (CACurrentMediaTime() - t0) * 1000, placeholderRects == nil ? 0 : 1,
                          NSCoder.string(for: placeholder?.size ?? .zero), NSCoder.string(for: prewarmView?.bounds.size ?? .zero))
                    prewarmView?.isPlaying = false
                    prewarmView?.removeFromSuperview()
                    prewarmView = nil
                    prewarmProbe = nil
                }
            }
        }
    }
    private static var prewarmProbe: PrewarmProbe?

    /// 预热视图画满 5 帧就收工
    private final class PrewarmProbe: NSObject, SCNSceneRendererDelegate {
        var onFrames: (() -> Void)?
        private var n = 0
        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            n += 1
            if n == 5 { DispatchQueue.main.async { self.onFrames?(); self.onFrames = nil } }
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
    private static let artLock = NSLock()
    /// 台面画（v12.6 重画，1024 × 1280）：深色漆面 + 从液晶放射的光芒 + 装饰弧线 + 各个口的标记和赔付数字。
    /// ST 品红、时短青色
    static func boardArt(mode: PachinkoMode) -> UIImage {
        artLock.lock(); defer { artLock.unlock() }
        if let c = artCache[mode] { return c }
        typealias B = PachinkoBoard
        let size = CGSize(width: 1024, height: 1280)
        let (top, bottom, accent): (UIColor, UIColor, UIColor) = {
            switch mode {
            case .normal: return (UIColor(red: 0.20, green: 0.13, blue: 0.52, alpha: 1), UIColor(red: 0.03, green: 0.03, blue: 0.16, alpha: 1), UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1))
            case .st: return (UIColor(red: 0.62, green: 0.08, blue: 0.46, alpha: 1), UIColor(red: 0.16, green: 0.02, blue: 0.14, alpha: 1), UIColor(red: 1.0, green: 0.45, blue: 0.8, alpha: 1))
            case .jitan: return (UIColor(red: 0.05, green: 0.42, blue: 0.52, alpha: 1), UIColor(red: 0.02, green: 0.08, blue: 0.14, alpha: 1), UIColor(red: 0.4, green: 1.0, blue: 0.9, alpha: 1))
            }
        }()
        let goldC = UIColor(red: 1, green: 0.8, blue: 0.32, alpha: 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        /// 台面坐标 → 图上的点（图的上边是台面的上边）
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * 1024, y: (1.25 - y) / 1.25 * 1280) }
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let lcd = pt(0.5, 0.78)
            let g = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: lcd, startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 900, options: [.drawsAfterEndLocation])
            // 放射光芒：宽窄相间的扇形
            for i in 0..<48 {
                let a0 = Double(i) / 48 * 2 * .pi, a1 = a0 + (i % 2 == 0 ? 0.05 : 0.025)
                c.move(to: lcd)
                c.addLine(to: CGPoint(x: lcd.x + cos(a0) * 1500, y: lcd.y + sin(a0) * 1500))
                c.addLine(to: CGPoint(x: lcd.x + cos(a1) * 1500, y: lcd.y + sin(a1) * 1500))
                c.closePath()
                c.setFillColor((i % 4 == 0 ? goldC : accent).withAlphaComponent(i % 2 == 0 ? 0.09 : 0.06).cgColor)
                c.fillPath()
            }
            // 同心装饰弧（围着液晶）
            for (k, r) in [330.0, 420.0, 520.0, 640.0].enumerated() {
                c.setStrokeColor((k % 2 == 0 ? goldC : accent).withAlphaComponent(0.22).cgColor)
                c.setLineWidth(k % 2 == 0 ? 3 : 1.5)
                c.setLineDash(phase: 0, lengths: k % 2 == 0 ? [] : [10, 14])
                c.addArc(center: lcd, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
                c.strokePath()
            }
            c.setLineDash(phase: 0, lengths: [])
            // 星点
            var seed = PachinkoRandom(seed: 42)
            for _ in 0..<260 {
                let x = seed.uniform() * 1024, y = seed.uniform() * 1280, r = 0.8 + seed.uniform() * 2.4
                c.setFillColor(UIColor(white: 1, alpha: 0.12 + seed.uniform() * 0.4).cgColor)
                c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            // 四角星
            func sparkle(_ p: CGPoint, _ r: CGFloat, _ col: UIColor) {
                c.setFillColor(col.cgColor)
                c.move(to: CGPoint(x: p.x, y: p.y - r))
                for i in 1..<8 {
                    let a = Double(i) * .pi / 4 - .pi / 2
                    let rr = i % 2 == 0 ? r : r * 0.28
                    c.addLine(to: CGPoint(x: p.x + cos(a) * rr, y: p.y + sin(a) * rr))
                }
                c.closePath()
                c.fillPath()
            }
            for _ in 0..<16 {
                sparkle(CGPoint(x: seed.uniform() * 1024, y: seed.uniform() * 1280), 6 + seed.uniform() * 9, goldC.withAlphaComponent(0.4))
            }
            /// 发光的圆环（口的底座）
            func halo(_ p: CGPoint, _ r: CGFloat, _ col: UIColor) {
                let hg = CGGradient(colorsSpace: space, colors: [col.withAlphaComponent(0.55).cgColor, col.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                c.drawRadialGradient(hg, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
            }
            func label(_ text: String, _ p: CGPoint, size: CGFloat, color: UIColor, kern: CGFloat = 1) {
                let font = UIFont.systemFont(ofSize: size, weight: .black)
                let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
                let attrs: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: color, .kern: kern,
                                                            .strokeColor: UIColor.black.withAlphaComponent(0.6), .strokeWidth: -2.5]
                let s = NSAttributedString(string: text, attributes: attrs)
                let sz = s.size()
                s.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
            }
            func chevrons(_ p: CGPoint, _ col: UIColor) {
                c.setStrokeColor(col.cgColor)
                c.setLineWidth(5)
                c.setLineCap(.round)
                c.setLineJoin(.round)
                for i in 0..<3 {
                    let y = p.y + CGFloat(i) * 15
                    c.move(to: CGPoint(x: p.x - 16, y: y))
                    c.addLine(to: CGPoint(x: p.x, y: y + 11))
                    c.addLine(to: CGPoint(x: p.x + 16, y: y))
                }
                c.strokePath()
            }
            // 始动口
            let cyan = UIColor(red: 0.3, green: 0.95, blue: 1, alpha: 1)
            halo(pt(0.5, B.startY0 + 0.01), 110, cyan)
            label("START", pt(0.5, 0.555), size: 34, color: cyan, kern: 3)
            chevrons(pt(0.5, 0.530), cyan.withAlphaComponent(0.85))
            // 郁金香、袖口
            let pink = UIColor(red: 1, green: 0.5, blue: 0.75, alpha: 1)
            for sgn in [-1.0, 1.0] {
                let tx = 0.5 + sgn * (0.5 - B.tulipX), sx = 0.5 + sgn * (0.5 - B.sideX)
                halo(pt(tx, B.tulipY), 90, pink)
                label("+\(PachinkoConstants.tulipPayout)", pt(tx, B.tulipY - 0.062), size: 30, color: pink)
                halo(pt(sx, B.sideY), 70, goldC)
                label("+\(PachinkoConstants.sidePayout)", pt(sx + sgn * 0.004, B.sideY - 0.05), size: 26, color: goldC)
                // 风车底下一圈
                c.setStrokeColor(cyan.withAlphaComponent(0.35).cgColor)
                c.setLineWidth(3)
                c.addArc(center: pt(0.5 + sgn * 0.34, 0.676), radius: 44, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
                c.strokePath()
            }
            // 大入赏口
            let red = UIColor(red: 1, green: 0.35, blue: 0.4, alpha: 1)
            let aRect = CGRect(x: pt(B.attackerX0, 0).x - 14, y: pt(0, B.attackerY1).y - 12,
                               width: (1 - 2 * B.attackerX0) * 1024 + 28, height: (B.attackerY1 - B.attackerY0) / 1.25 * 1280 + 24)
            c.setStrokeColor(red.withAlphaComponent(0.7).cgColor)
            c.setLineWidth(4)
            c.addPath(UIBezierPath(roundedRect: aRect, cornerRadius: 14).cgPath)
            c.strokePath()
            label("JACKPOT GATE  +\(PachinkoConstants.attackerPayout)", pt(0.5, B.attackerY0 - 0.03), size: 24, color: red, kern: 2)
            // 幸运杯
            label("LUCKY CUP  +\(PachinkoConstants.catcherPayout)", pt(0.5, 0.098), size: 22, color: goldC, kern: 2)
            // 底部霓虹弧
            c.setStrokeColor(UIColor(red: 1, green: 0.3, blue: 0.65, alpha: 0.4).cgColor)
            c.setLineWidth(8)
            c.addArc(center: CGPoint(x: 512, y: 1500), radius: 560, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
            c.strokePath()
            c.setStrokeColor(goldC.withAlphaComponent(0.3).cgColor)
            c.setLineWidth(3)
            c.addArc(center: CGPoint(x: 512, y: 1500), radius: 590, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
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
