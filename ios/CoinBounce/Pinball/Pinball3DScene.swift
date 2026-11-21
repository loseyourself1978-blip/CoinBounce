import SceneKit
import SwiftUI
import UIKit

// MARK: - 弹球台 3D 画面（v12.7 做的；v13 换成「法老的宝藏」主题，并解决画面发糊）
// 原来的名字：v12.7 弹球台 3D 画面（SceneKit；物理和规则在 PinballEngine / PinballRules，这里只画）
/// 台面坐标 (x 0…1, y 0…1.9, y 向上) → 世界坐标：X = (x − 0.5)·W，Y = (y − 0.95)·W，台面在 Z = 0。
/// 整张台面往后仰（上边远、下边近），像站在弹球机前面往下看。
final class Pinball3DScene: NSObject, SCNSceneRendererDelegate {
    typealias T = PinballTable
    static let W: Float = 10
    static let tilt: Float = -0.40
    static let railWidth: Float = 0.45

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let root = SCNNode()
    private let ballRoot = SCNNode()
    private let fxRoot = SCNNode()
    private weak var game: PinballGame?
    weak var view: SCNView?

    private var ballNodes: [SCNNode] = []
    private var flipperNodes: [SCNNode] = []
    private var bumperCaps: [SCNNode] = []
    private var bumperMats: [SCNMaterial] = []
    private var dropNodes: [SCNNode] = []
    private var standupMats: [SCNMaterial] = []
    private var topLaneMats: [SCNMaterial] = []
    private var holeMat = SCNMaterial()
    private var saveMat = SCNMaterial()
    private var slingMats: [SCNMaterial] = []
    private var missionMats: [SCNMaterial] = []
    private var plungerRoot = SCNNode()
    private var springRings: [SCNNode] = []
    private var waitingBall = SCNNode()
    private var bulbA = SCNMaterial(), bulbB = SCNMaterial()
    private var shownHUD: PinballHUD?
    private var shownPull = 0.0
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var clock = 0.0
    private var flashUntil: CFTimeInterval = 0
    private var lowTier: Bool { VisualFX.lowTier }

    /// 帧率（每 2 秒一次，PINBALL_STATS）
    private var frames = 0
    private var fpsWindow: CFTimeInterval = 0

    init(game: PinballGame?) {
        self.game = game
        super.init()
        buildScene()
        buildTable()
        game?.onEvent = { [weak self] e in self?.physicsEvent(e) }
    }

    deinit { displayLink?.invalidate() }

    static func world(_ x: Double, _ y: Double, z: Float = 0) -> SCNVector3 {
        SCNVector3(Float(x - 0.5) * W, Float(y - 0.95) * W, z)
    }

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

    static let gold = UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1)
    /// v13 埃及主题：这一色原来是粉红，现在是红玉髓的橙红（名字没改，用的地方多）
    static let pink = UIColor(red: 1.0, green: 0.42, blue: 0.16, alpha: 1)
    /// 绿松石
    static let cyan = UIColor(red: 0.1, green: 0.85, blue: 0.78, alpha: 1)
    static let chrome = UIColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1)

    // MARK: 灯光和相机（和推币机、弹子机同一套）
    private func buildScene() {
        scene.background.contents = nil
        let cam = SCNCamera()
        cam.fieldOfView = 22
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
            // v13：泛光收小（原来 ×1.4，整张台面蒙着一层雾）
            cam.bloomIntensity = VisualFX.bloomIntensity * 0.6
            cam.bloomBlurRadius = 4
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
        key.light!.intensity = 620
        key.light!.castsShadow = !lowTier
        key.light!.shadowMode = .deferred
        key.light!.shadowColor = UIColor.black.withAlphaComponent(0.45)
        key.light!.shadowRadius = 4
        key.light!.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light!.orthographicScale = 14
        key.eulerAngles = SCNVector3(-0.95, -0.3, 0)
        key.position = SCNVector3(4, 12, 16)
        scene.rootNode.addChildNode(key)
        let spec = SCNNode()
        spec.light = SCNLight()
        spec.light!.type = .omni
        spec.light!.intensity = 140
        spec.light!.color = UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)
        spec.position = SCNVector3(-6, 4, 14)
        scene.rootNode.addChildNode(spec)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 240
        scene.rootNode.addChildNode(amb)
        scene.lightingEnvironment.contents = on ? PusherScene3D.sharedCasinoEnvironment : PusherScene3D.environmentImage()
        scene.lightingEnvironment.intensity = on ? VisualFX.environmentIntensity * 0.5 : 1.0

        root.eulerAngles = SCNVector3(Self.tilt, 0, 0)
        scene.rootNode.addChildNode(root)
        root.addChildNode(ballRoot)
        root.addChildNode(fxRoot)
    }

    // MARK: 台面
    private func buildTable() {
        let W = Self.W
        let hw = W / 2, hh = W * Float(T.height) / 2
        let chromeM = Self.pbr(Self.chrome, metal: 1, rough: 0.12)
        // v13：机柜是青金石蓝的漆（原来的红漆在 HDR 下发白）
        let lacquer = Self.pbr(UIColor(red: 0.03, green: 0.1, blue: 0.4, alpha: 1), metal: 0, rough: 0.7)
        lacquer.emission.contents = UIColor(red: 0.01, green: 0.04, blue: 0.16, alpha: 1)
        lacquer.clearCoat.contents = 0.05
        lacquer.clearCoatRoughness.contents = 0.3
        let goldM = Self.pbr(Self.gold, metal: 1, rough: 0.22)
        let rubber = Self.pbr(UIColor(white: 0.08, alpha: 1), metal: 0, rough: 0.6)
        let redRubber = Self.pbr(UIColor(red: 0.85, green: 0.08, blue: 0.15, alpha: 1), metal: 0, rough: 0.45)

        // 台面板：亮漆（清漆层反射环境）
        let art = Self.tableArt()
        // v13：台面是哑光的（原来清漆层在这个斜角下反射一大片环境光，画面像蒙了一层灰）
        let plateM = Self.pbr(.white, metal: 0, rough: 0.7)
        plateM.diffuse.contents = art
        plateM.clearCoat.contents = 0.06
        plateM.clearCoatRoughness.contents = 0.3
        // v13：台面只留一点自发光（原来 0.62，再过一遍泛光，整张图发灰发糊）
        plateM.emission.contents = art
        plateM.emission.intensity = 0.3
        plateM.diffuse.mipFilter = .linear
        plateM.diffuse.maxAnisotropy = 8
        plateM.emission.mipFilter = .linear
        plateM.emission.maxAnisotropy = 8
        let plate = SCNNode(geometry: SCNBox(width: CGFloat(W), height: CGFloat(hh * 2), length: 0.4, chamferRadius: 0))
        plate.geometry!.materials = [plateM]
        plate.position = SCNVector3(0, 0, -0.2)
        root.addChildNode(plate)

        let fixed = SCNNode()
        func box(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, z0: Float = 0, z1: Float, _ m: SCNMaterial, chamfer: CGFloat = 0.06, into parent: SCNNode? = nil) {
            let n = SCNNode(geometry: SCNBox(width: CGFloat(x1 - x0), height: CGFloat(y1 - y0), length: CGFloat(z1 - z0), chamferRadius: chamfer))
            n.geometry!.firstMaterial = m
            n.position = SCNVector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
            (parent ?? fixed).addChildNode(n)
        }
        func wx(_ x: Double) -> Float { Float(x - 0.5) * W }
        func wy(_ y: Double) -> Float { Float(y - 0.95) * W }
        let rw = Self.railWidth
        // 机柜的四条边：红漆 + 金边
        box(-hw - rw, -hh - rw, wx(T.wallLeft), hh + rw, z0: -0.4, z1: 1.0, lacquer)
        box(wx(T.laneOuter), -hh - rw, hw + rw, hh + rw, z0: -0.4, z1: 1.0, lacquer)
        box(-hw - rw, hh - 0.02, hw + rw, hh + rw, z0: -0.4, z1: 1.0, lacquer)
        box(-hw - rw, -hh - rw, hw + rw, -hh + 0.02, z0: -0.4, z1: 1.0, lacquer)
        box(wx(T.wallLeft) - 0.03, -hh, wx(T.wallLeft) + 0.05, wy(T.archCY), z0: 0, z1: 0.62, chromeM, chamfer: 0.03)
        box(wx(T.laneOuter) - 0.05, -hh, wx(T.laneOuter) + 0.03, wy(T.archCY), z0: 0, z1: 0.62, chromeM, chamfer: 0.03)
        // 下面的挡板（球从挡板中间掉进它下面）
        let apronTop = wy(0.105)
        box(wx(T.wallLeft), -hh, wx(0.335), apronTop, z0: 0, z1: 0.75, lacquer)
        box(wx(T.mirror(0.335)), -hh, wx(T.laneInner) - 0.08, apronTop, z0: 0, z1: 0.75, lacquer)
        box(wx(0.335), -hh, wx(T.mirror(0.335)), wy(0.03), z0: 0, z1: 0.75, lacquer)
        box(wx(T.wallLeft), apronTop - 0.06, wx(0.335), apronTop + 0.03, z0: 0.6, z1: 0.82, goldM, chamfer: 0.03)
        box(wx(T.mirror(0.335)), apronTop - 0.06, wx(T.laneInner) - 0.08, apronTop + 0.03, z0: 0.6, z1: 0.82, goldM, chamfer: 0.03)

        // 拱顶：外面两个角用红漆填满，里面一圈镀铬
        let cy = CGFloat(wy(T.archCY)), r = CGFloat(T.archR) * CGFloat(W)
        let corner = UIBezierPath()
        corner.move(to: CGPoint(x: -r, y: cy))
        corner.addArc(withCenter: CGPoint(x: 0, y: cy), radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
        corner.addLine(to: CGPoint(x: r, y: CGFloat(hh)))
        corner.addLine(to: CGPoint(x: -r, y: CGFloat(hh)))
        corner.close()
        corner.flatness = 0.02
        let cornerShape = SCNShape(path: corner, extrusionDepth: 1.0)
        cornerShape.firstMaterial = lacquer
        let cornerNode = SCNNode(geometry: cornerShape)
        cornerNode.position = SCNVector3(0, 0, 0.5)
        fixed.addChildNode(cornerNode)
        let ring = UIBezierPath()
        // 往里多出一点点（和红漆的内壁错开，不然两个面叠在一起会闪）
        ring.move(to: CGPoint(x: -r - 0.02, y: cy))
        ring.addArc(withCenter: CGPoint(x: 0, y: cy), radius: r + 0.02, startAngle: .pi, endAngle: 0, clockwise: false)
        ring.addArc(withCenter: CGPoint(x: 0, y: cy), radius: r - 0.05, startAngle: 0, endAngle: .pi, clockwise: true)
        ring.close()
        ring.flatness = 0.02
        let ringShape = SCNShape(path: ring, extrusionDepth: 0.62)
        ringShape.firstMaterial = chromeM
        let ringNode = SCNNode(geometry: ringShape)
        ringNode.position = SCNVector3(0, 0, 0.31)
        fixed.addChildNode(ringNode)

        // 线段：墙、导轨、弹弓的边、靶组的小斜坡
        for s in T.segments {
            switch s.kind {
            case .drop, .standup, .laneFloor, .slingFace: continue
            default: break
            }
            let ax = wx(s.x1), ay = wy(s.y1), bx = wx(s.x2), by = wy(s.y2)
            let len = hypot(bx - ax, by - ay)
            let thick = max(Float(s.r) * W, 0.05)
            let isGate = s.kind == .gate
            let g = SCNBox(width: CGFloat(len + thick), height: CGFloat(thick * 2), length: isGate ? 0.3 : 0.5, chamferRadius: CGFloat(thick * 0.9))
            g.firstMaterial = isGate ? goldM : chromeM
            let n = SCNNode(geometry: g)
            n.position = SCNVector3((ax + bx) / 2, (ay + by) / 2, isGate ? 0.5 : 0.25)
            n.eulerAngles.z = atan2(by - ay, bx - ax)
            fixed.addChildNode(n)
        }
        // 弹弓：发光的三角垫 + 红色胶带（会弹的那条边）
        for side in 0..<2 {
            func mx(_ x: Double) -> Double { side == 0 ? x : T.mirror(x) }
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: CGFloat(wx(mx(T.slingA.x))), y: CGFloat(wy(T.slingA.y))))
            tri.addLine(to: CGPoint(x: CGFloat(wx(mx(T.slingB.x))), y: CGFloat(wy(T.slingB.y))))
            tri.addLine(to: CGPoint(x: CGFloat(wx(mx(T.slingC.x))), y: CGFloat(wy(T.slingC.y))))
            tri.close()
            let shape = SCNShape(path: tri, extrusionDepth: 0.3)
            let m = Self.pbr(UIColor(red: 0.02, green: 0.2, blue: 0.22, alpha: 1), metal: 0.2, rough: 0.3, emission: Self.cyan, intensity: 0.45)
            shape.firstMaterial = m
            slingMats.append(m)
            let n = SCNNode(geometry: shape)
            n.position = SCNVector3(0, 0, 0.15)
            root.addChildNode(n)
            let ax = wx(mx(T.slingA.x)), ay = wy(T.slingA.y), cx = wx(mx(T.slingC.x)), cyy = wy(T.slingC.y)
            let band = SCNNode(geometry: SCNBox(width: CGFloat(hypot(cx - ax, cyy - ay)), height: 0.1, length: 0.22, chamferRadius: 0.05))
            band.geometry!.firstMaterial = redRubber
            band.position = SCNVector3((ax + cx) / 2, (ay + cyy) / 2, 0.36)
            band.eulerAngles.z = atan2(cyy - ay, cx - ax)
            fixed.addChildNode(band)
        }
        // 胶柱
        for p in T.posts {
            let c = SCNCylinder(radius: CGFloat(p.r) * CGFloat(W) * 0.7, height: 0.6)
            c.firstMaterial = chromeM
            let n = SCNNode(geometry: c)
            n.eulerAngles.x = .pi / 2
            n.position = Self.world(p.x, p.y, z: 0.3)
            fixed.addChildNode(n)
            let t = SCNTorus(ringRadius: CGFloat(p.r) * CGFloat(W) * 0.85, pipeRadius: 0.06)
            t.firstMaterial = redRubber
            let tn = SCNNode(geometry: t)
            tn.eulerAngles.x = .pi / 2
            tn.position = Self.world(p.x, p.y, z: 0.26)
            fixed.addChildNode(tn)
        }
        root.addChildNode(fixed.flattenedClone())

        // 蘑菇柱：底座 + 发光的帽子（被撞时往下一压、一闪）
        for (k, bp) in T.bumpers.enumerated() {
            let rr = CGFloat(T.bumperRadius) * CGFloat(W)
            let base = SCNNode(geometry: SCNCylinder(radius: rr * 0.82, height: 0.5))
            base.geometry!.firstMaterial = Self.pbr(.white, metal: 0.1, rough: 0.3)
            base.eulerAngles.x = .pi / 2
            base.position = Self.world(bp.x, bp.y, z: 0.25)
            root.addChildNode(base)
            let skirt = SCNNode(geometry: SCNTorus(ringRadius: rr * 0.92, pipeRadius: 0.07))
            skirt.geometry!.firstMaterial = chromeM
            skirt.eulerAngles.x = .pi / 2
            skirt.position = Self.world(bp.x, bp.y, z: 0.2)
            root.addChildNode(skirt)
            let color = [Self.pink, Self.cyan, Self.gold][k % 3]
            let m = Self.pbr(color, metal: 0.2, rough: 0.25, emission: color, intensity: 0.7)
            m.clearCoat.contents = 1.0
            let capGeo = SCNCylinder(radius: rr * 1.02, height: 0.22)
            capGeo.radialSegmentCount = 28
            capGeo.firstMaterial = m
            let cap = SCNNode(geometry: capGeo)
            cap.eulerAngles.x = .pi / 2
            cap.position = Self.world(bp.x, bp.y, z: 0.62)
            let star = SCNNode(geometry: SCNPlane(width: rr * 1.5, height: rr * 1.5))
            let sm = SCNMaterial()
            sm.lightingModel = .constant
            sm.diffuse.contents = Self.labelImage("★", color: .white, size: 96)
            sm.blendMode = .alpha
            star.geometry!.firstMaterial = sm
            star.eulerAngles.x = -.pi / 2
            star.position = SCNVector3(0, 0.115, 0)
            cap.addChildNode(star)
            root.addChildNode(cap)
            bumperCaps.append(cap)
            bumperMats.append(m)
        }

        // 顶部滚道的灯（7 7 7）
        for lx in T.topLaneX {
            let m = Self.pbr(UIColor(white: 0.12, alpha: 1), metal: 0, rough: 0.4, emission: Self.gold, intensity: 0.05)
            let d = SCNNode(geometry: SCNCylinder(radius: 0.3, height: 0.03))
            d.geometry!.firstMaterial = m
            d.eulerAngles.x = .pi / 2
            d.position = Self.world(lx, (T.topLaneY0 + T.topLaneY1) / 2 - 0.08, z: 0.02)
            root.addChildNode(d)
            topLaneMats.append(m)
        }
        // 幸运洞
        let hole = SCNNode(geometry: SCNCylinder(radius: CGFloat(T.holeRadius) * CGFloat(W), height: 0.04))
        hole.geometry!.firstMaterial = Self.pbr(.black, metal: 0.4, rough: 0.5)
        hole.eulerAngles.x = .pi / 2
        hole.position = Self.world(T.holeX, T.holeY, z: 0.02)
        root.addChildNode(hole)
        holeMat = Self.pbr(Self.gold, metal: 1, rough: 0.2, emission: Self.gold, intensity: 0.2)
        let holeRing = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(T.holeRadius) * CGFloat(W) * 1.15, pipeRadius: 0.07))
        holeRing.geometry!.firstMaterial = holeMat
        holeRing.eulerAngles.x = .pi / 2
        holeRing.position = Self.world(T.holeX, T.holeY, z: 0.07)
        root.addChildNode(holeRing)

        // 落靶 K Q J（左）、立靶三颗星（右）
        for (i, label) in ["K", "Q", "J"].enumerated() {
            let n = SCNNode(geometry: SCNBox(width: 0.3, height: CGFloat(T.targetHalf * 2) * CGFloat(W) * 0.92, length: 0.62, chamferRadius: 0.03))
            let face = Self.pbr(.white, metal: 0, rough: 0.35, emission: UIColor(white: 1, alpha: 1), intensity: 0.25)
            face.diffuse.contents = Self.targetImage(label)
            face.emission.contents = Self.targetImage(label)
            let side = Self.pbr(UIColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1), metal: 0, rough: 0.4)
            // SCNBox 的面：前、右、后、左、上、下。朝右（+X）的面和朝玩家（+Z）的面都贴字
            n.geometry!.materials = [face, face, side, side, side, side]
            n.geometry!.materials[4] = face
            n.position = Self.world(T.dropX - 0.012, T.targetY[i], z: 0.31)
            root.addChildNode(n)
            dropNodes.append(n)
        }
        for i in 0..<3 {
            let m = Self.pbr(UIColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1), metal: 0.1, rough: 0.3, emission: Self.cyan, intensity: 0.35)
            let n = SCNNode(geometry: SCNBox(width: 0.3, height: CGFloat(T.targetHalf * 2) * CGFloat(W) * 0.92, length: 0.62, chamferRadius: 0.05))
            n.geometry!.firstMaterial = m
            n.position = Self.world(T.standupX + 0.012, T.targetY[i], z: 0.31)
            root.addChildNode(n)
            standupMats.append(m)
        }

        // 任务灯：中间标志周围四盏，亮到第几盏就是做到第几步
        for i in 0..<4 {
            let ang = Double.pi * (0.5 - (Double(i) - 1.5) * 0.36)
            let m = Self.pbr(UIColor(white: 0.12, alpha: 1), metal: 0, rough: 0.4, emission: Self.pink, intensity: 0.05)
            let d = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.03))
            d.geometry!.firstMaterial = m
            d.eulerAngles.x = .pi / 2
            d.position = Self.world(T.fieldCenter + 0.205 * cos(ang), 0.82 + 0.205 * sin(ang), z: 0.02)
            root.addChildNode(d)
            missionMats.append(m)
        }

        // 挡板：红色的锥形板，围一圈黑胶
        let L = CGFloat(T.flipperLength) * CGFloat(W)
        let r1: CGFloat = 0.21, r2: CGFloat = 0.12
        // 两个圆（根部大、尖上小）的外包络，逆时针一圈
        let fp = UIBezierPath()
        let a = asin((r1 - r2) / L)
        var pts: [CGPoint] = []
        let n = 14
        for i in 0...n {
            let t = (.pi / 2 - a) + (.pi + 2 * a) * CGFloat(i) / CGFloat(n)
            pts.append(CGPoint(x: r1 * cos(t), y: r1 * sin(t)))
        }
        for i in 0...n {
            let t = -(.pi / 2 - a) + (.pi - 2 * a) * CGFloat(i) / CGFloat(n)
            pts.append(CGPoint(x: L + r2 * cos(t), y: r2 * sin(t)))
        }
        fp.move(to: pts[0])
        for p in pts.dropFirst() { fp.addLine(to: p) }
        fp.close()
        let flipM = Self.pbr(UIColor(red: 0.92, green: 0.1, blue: 0.2, alpha: 1), metal: 0.1, rough: 0.25, emission: UIColor(red: 0.5, green: 0, blue: 0.1, alpha: 1), intensity: 0.4)
        flipM.clearCoat.contents = 1.0
        for side in 0..<2 {
            let pivot = SCNNode()
            let px = side == 0 ? T.flipperPivot.x : T.mirror(T.flipperPivot.x)
            pivot.position = Self.world(px, T.flipperPivot.y, z: 0.05)
            let body = SCNShape(path: fp, extrusionDepth: 0.36)
            body.chamferRadius = 0.05
            body.firstMaterial = flipM
            let bn = SCNNode(geometry: body)
            bn.position = SCNVector3(0, 0, 0.2)
            pivot.addChildNode(bn)
            let band = SCNShape(path: fp, extrusionDepth: 0.14)
            band.firstMaterial = rubber
            let bandNode = SCNNode(geometry: band)
            bandNode.scale = SCNVector3(1.06, 1.18, 1)
            bandNode.position = SCNVector3(-0.01, 0, 0.2)
            pivot.addChildNode(bandNode)
            let cap = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.08))
            cap.geometry!.firstMaterial = chromeM
            cap.eulerAngles.x = .pi / 2
            cap.position = SCNVector3(0, 0, 0.42)
            pivot.addChildNode(cap)
            root.addChildNode(pivot)
            flipperNodes.append(pivot)
        }
        // 保球灯（挡板中间）
        saveMat = Self.pbr(UIColor(white: 0.1, alpha: 1), metal: 0, rough: 0.4, emission: UIColor(red: 0.3, green: 1, blue: 0.4, alpha: 1), intensity: 0.05)
        let save = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 0.03))
        save.geometry!.firstMaterial = saveMat
        save.eulerAngles.x = .pi / 2
        save.position = Self.world(T.fieldCenter, 0.19, z: 0.02)
        root.addChildNode(save)

        // 拉杆（发射轨道最下面）
        let px = Float(T.laneX - 0.5) * W
        plungerRoot.position = SCNVector3(px, wy(T.laneFloor), 0.22)
        let tip = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.16))
        tip.geometry!.firstMaterial = redRubber
        tip.position = SCNVector3(0, -0.08, 0)
        plungerRoot.addChildNode(tip)
        let rod = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 1.0))
        rod.geometry!.firstMaterial = chromeM
        rod.position = SCNVector3(0, -0.66, 0)
        plungerRoot.addChildNode(rod)
        root.addChildNode(plungerRoot)
        let ringGeo = SCNTorus(ringRadius: 0.18, pipeRadius: 0.04)
        ringGeo.ringSegmentCount = 16; ringGeo.pipeSegmentCount = 6
        ringGeo.firstMaterial = chromeM
        for _ in 0..<7 {
            let n = SCNNode(geometry: ringGeo)
            n.position = SCNVector3(px, 0, 0.22)
            n.eulerAngles.z = 0.16
            root.addChildNode(n)
            springRings.append(n)
        }
        waitingBall = SCNNode(geometry: ballGeometry)
        root.addChildNode(waitingBall)

        // 机柜上的灯泡
        bulbA = Self.pbr(.white, metal: 0, rough: 0.3, emission: Self.gold, intensity: 2.2)
        bulbB = Self.pbr(.white, metal: 0, rough: 0.3, emission: Self.cyan, intensity: 0.6)
        let ga = SCNSphere(radius: 0.13); ga.segmentCount = 10; ga.firstMaterial = bulbA
        let gb = SCNSphere(radius: 0.13); gb.segmentCount = 10; gb.firstMaterial = bulbB
        let bulbs = SCNNode()
        let count = lowTier ? 14 : 22
        for i in 0..<count {
            let y = -hh + (2 * hh) * Float(i) / Float(count - 1)
            for x in [-hw - rw / 2 + 0.1, hw + rw / 2 - 0.1] {
                let n = SCNNode(geometry: i % 2 == 0 ? ga : gb)
                n.position = SCNVector3(x, y, 1.02)
                bulbs.addChildNode(n)
            }
        }
        root.addChildNode(bulbs)
        layoutPlunger(pull: 0, hasBall: true)
    }

    // MARK: 相机：整张台面放进视图
    func fit(viewSize: CGSize) {
        guard viewSize.width > 10, viewSize.height > 10 else { return }
        let W = Self.W
        let halfH = W * Float(T.height) / 2 + Self.railWidth
        let halfW = W / 2 + Self.railWidth
        let c = cos(Self.tilt), s = sin(-Self.tilt)
        let fovV = Float(22.0 * .pi / 180)
        let aspect = Float(viewSize.width / viewSize.height)
        let tanV = tan(fovV / 2), tanH = tanV * aspect
        // 近边（台面下沿）离相机近 halfH·s，在画面里最宽、最低；远边最高
        var d: Float = 14
        for _ in 0..<400 {
            let near = d - halfH * s, far = d + halfH * s
            let fitsW = halfW / near <= tanH
            let fitsH = (halfH * c) / near <= tanV * 1.0 && (halfH * c) / far <= tanV
            if fitsW && fitsH { break }
            d += 0.25
        }
        // 往下看一点，把近大远小带来的上下留白摆匀
        let near = d - halfH * s, far = d + halfH * s
        let top = (halfH * c) / far, bottom = (halfH * c) / near
        let shift = (bottom - top) / 2 * d
        cameraNode.position = SCNVector3(0, -shift * 0.9, d)
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
    }

    func project(_ x: Double, _ y: Double, z: Float = 0.3) -> CGPoint? {
        guard let view else { return nil }
        let s = view.projectPoint(root.convertPosition(Self.world(x, y, z: z), to: nil))
        return CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
    }

    // MARK: 每帧
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

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick.map { now - $0 } ?? 0
        lastTick = now
        guard let game else { return }
        game.update(dt)
        clock += dt
        syncBalls(game)
        syncFlippers(game)
        syncPlunger(game, dt: dt)
        if shownHUD != game.hud { syncLights(game.hud) }
        // 灯泡交替闪；多球 / 大奖时快闪
        let period = now < flashUntil ? 0.14 : 0.5
        let phase = Int(clock / period) % 2 == 0
        bulbA.emission.intensity = phase ? 2.2 : 0.5
        bulbB.emission.intensity = phase ? 0.5 : 2.2
        // 幸运洞亮着的时候呼吸
        if game.hud.holeLit { holeMat.emission.intensity = 1.2 + 0.9 * CGFloat(sin(clock * 6)) }
    }

    private lazy var ballGeometry: SCNSphere = {
        let s = SCNSphere(radius: CGFloat(T.ballRadius) * CGFloat(Self.W))
        s.segmentCount = lowTier ? 16 : 28
        s.firstMaterial = Self.pbr(.white, metal: 1, rough: 0.1, emission: UIColor(white: 0.5, alpha: 1), intensity: 0.3)
        return s
    }()
    private lazy var goldBallGeometry: SCNSphere = {
        let s = SCNSphere(radius: CGFloat(T.ballRadius) * CGFloat(Self.W))
        s.segmentCount = lowTier ? 16 : 28
        s.firstMaterial = Self.pbr(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), metal: 1, rough: 0.14, emission: Self.gold, intensity: 0.5)
        return s
    }()

    private func syncBalls(_ game: PinballGame) {
        let rb = Float(T.ballRadius) * Self.W
        let balls = game.engine.balls
        while ballNodes.count < balls.count {
            let n = SCNNode(geometry: ballGeometry)
            n.castsShadow = true
            ballRoot.addChildNode(n)
            ballNodes.append(n)
        }
        for i in 0..<ballNodes.count {
            if i < balls.count {
                let b = balls[i]
                let geo = b.bonus ? goldBallGeometry : ballGeometry
                if ballNodes[i].geometry !== geo { ballNodes[i].geometry = geo }
                ballNodes[i].isHidden = false
                // 进了洞：往下沉一点
                ballNodes[i].position = Self.world(b.x, b.y, z: b.holeTime > 0 ? rb * 0.35 : rb + 0.01)
            } else {
                ballNodes[i].isHidden = true
            }
        }
    }

    private func syncFlippers(_ game: PinballGame) {
        for (i, f) in game.engine.flippers.enumerated() where i < flipperNodes.count {
            flipperNodes[i].eulerAngles.z = i == 0 ? Float(f.angle) : .pi - Float(f.angle)
        }
    }

    private func layoutPlunger(pull: Double, hasBall: Bool) {
        let floorY = Float(T.laneFloor - 0.95) * Self.W
        let tip = floorY - Float(pull) * 0.6
        plungerRoot.position.y = tip
        let s0 = floorY - 1.3, s1 = tip - 0.2
        for (i, r) in springRings.enumerated() {
            r.position.y = s0 + (s1 - s0) * Float(i) / Float(max(1, springRings.count - 1))
        }
        let rb = Float(T.ballRadius) * Self.W
        waitingBall.isHidden = !hasBall
        waitingBall.position = SCNVector3(plungerRoot.position.x, tip + rb, rb + 0.01)
    }

    private func syncPlunger(_ game: PinballGame, dt: Double) {
        let target = game.pull
        if target >= shownPull { shownPull = target } else { shownPull = max(target, shownPull - dt * 14) }
        layoutPlunger(pull: shownPull, hasBall: game.ballOnPlunger)
    }

    private func syncLights(_ h: PinballHUD) {
        shownHUD = h
        for i in 0..<3 {
            topLaneMats[i].emission.intensity = h.topLit[i] ? 2.4 : 0.05
            standupMats[i].emission.intensity = h.standupLit[i] ? 2.4 : 0.35
            let z: Float = h.dropDown[i] ? -0.28 : 0.31
            if abs(dropNodes[i].position.z - z) > 0.01 {
                dropNodes[i].runAction(.move(to: SCNVector3(dropNodes[i].position.x, dropNodes[i].position.y, z), duration: 0.1))
            }
        }
        if !h.holeLit { holeMat.emission.intensity = 0.2 }
        for (i, m) in missionMats.enumerated() { m.emission.intensity = i <= h.mission.rawValue ? 2.2 : 0.05 }
        saveMat.emission.intensity = h.ballSave ? 2.2 : 0.05
        for (k, m) in bumperMats.enumerated() {
            m.emission.contents = h.superBumpers ? UIColor.white : [Self.pink, Self.cyan, Self.gold][k % 3]
        }
    }

    // MARK: 特效
    private func physicsEvent(_ e: PinballEvent) {
        switch e {
        case .bumper(let k) where k < bumperCaps.count:
            let cap = bumperCaps[k], m = bumperMats[k]
            cap.removeAllActions()
            let z = cap.position.z
            cap.runAction(.sequence([.moveBy(x: 0, y: 0, z: -0.14, duration: 0.03), .moveBy(x: 0, y: 0, z: CGFloat(0.62 - (z - 0.14)), duration: 0.09)]))
            m.emission.intensity = 3.2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { m.emission.intensity = 0.7 }
            ringFX(at: Self.world(T.bumpers[k].x, T.bumpers[k].y, z: 0.5), color: [Self.pink, Self.cyan, Self.gold][k % 3])
        case .sling(let s) where s < slingMats.count:
            let m = slingMats[s]
            m.emission.intensity = 2.6
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { m.emission.intensity = 0.5 }
        case .holeCaptured:
            ringFX(at: Self.world(T.holeX, T.holeY, z: 0.3), color: Self.gold)
        case .dropTarget(let k):
            ringFX(at: Self.world(T.dropX + 0.03, T.targetY[k], z: 0.4), color: .white)
        case .standup(let k):
            ringFX(at: Self.world(T.standupX - 0.03, T.targetY[k], z: 0.4), color: Self.cyan)
        default: break
        }
    }

    private func ringFX(at p: SCNVector3, color: UIColor) {
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.3, pipeRadius: 0.045))
        ring.geometry!.firstMaterial = Self.pbr(.black, metal: 0, rough: 1, emission: color, intensity: 3)
        ring.eulerAngles.x = .pi / 2
        ring.position = p
        fxRoot.addChildNode(ring)
        ring.runAction(.sequence([.group([.scale(to: 2.4, duration: 0.3), .fadeOut(duration: 0.3)]), .removeFromParentNode()]))
    }

    /// 大奖、多球：灯泡快闪一阵
    func flashBulbs(seconds: Double) { flashUntil = CACurrentMediaTime() + seconds }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        frames += 1
        if fpsWindow == 0 { fpsWindow = time }
        if time - fpsWindow >= 2 {
            NSLog("PINBALL_STATS fps=%.1f balls=%d", Double(frames) / (time - fpsWindow), game?.engine.ballsInPlay ?? 0)
            frames = 0
            fpsWindow = time
        }
    }

    // MARK: 贴图（代码生成）
    static func labelImage(_ text: String, color: UIColor, size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { _ in
            let font = UIFont.systemFont(ofSize: size, weight: .black)
            let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let sz = s.size()
            s.draw(at: CGPoint(x: 64 - sz.width / 2, y: 64 - sz.height / 2))
        }
    }

    static func targetImage(_ text: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 128), format: format).image { ctx in
            UIColor(red: 0.98, green: 0.95, blue: 0.86, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 128))
            UIColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1).setStroke()
            ctx.cgContext.setLineWidth(5)
            ctx.cgContext.stroke(CGRect(x: 4, y: 4, width: 56, height: 120))
            let font = UIFont.systemFont(ofSize: 52, weight: .black)
            let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor(red: 0.75, green: 0.05, blue: 0.15, alpha: 1)])
            let sz = s.size()
            s.draw(at: CGPoint(x: 32 - sz.width / 2, y: 64 - sz.height / 2))
        }
    }

    private static var artCache: UIImage?
    private static let artLock = NSLock()
    /// 台面画（1024 × 1946）：深色漆面、放射光芒、星点、各个机关的标记
    static func tableArt() -> UIImage {
        artLock.lock(); defer { artLock.unlock() }
        if let c = artCache { return c }
        let w: CGFloat = 1024, h: CGFloat = 1946
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * Double(w), y: (T.height - y) / T.height * Double(h)) }
        let format = UIGraphicsImageRendererFormat()
        // v13：按 2 倍画（2048 × 3892）。原来 1024 宽的图铺满整屏，是画面发糊的原因之一
        format.scale = VisualFX.lowTier ? 1 : 2
        format.opaque = true
        let goldC = UIColor(red: 1, green: 0.8, blue: 0.32, alpha: 1)
        let sand = UIColor(red: 0.93, green: 0.78, blue: 0.5, alpha: 1)
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            // 「法老的宝藏」：青金石色的夜空，太阳从蘑菇柱中间升起
            let top = UIColor(red: 0.07, green: 0.2, blue: 0.5, alpha: 1), bottom = UIColor(red: 0.02, green: 0.04, blue: 0.14, alpha: 1)
            let center = pt(T.fieldCenter, 1.22)
            let g = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: 1300, options: [.drawsAfterEndLocation])
            func halo(_ p: CGPoint, _ r: CGFloat, _ col: UIColor, _ alpha: CGFloat = 0.55) {
                let hg = CGGradient(colorsSpace: space, colors: [col.withAlphaComponent(alpha).cgColor, col.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                c.drawRadialGradient(hg, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
            }
            halo(center, 620, goldC, 0.3)
            // 太阳的光芒：细而规整的金线
            for i in 0..<48 {
                let a0 = Double(i) / 48 * 2 * .pi, a1 = a0 + (i % 2 == 0 ? 0.03 : 0.012)
                c.move(to: center)
                c.addLine(to: CGPoint(x: center.x + cos(a0) * 2400, y: center.y + sin(a0) * 2400))
                c.addLine(to: CGPoint(x: center.x + cos(a1) * 2400, y: center.y + sin(a1) * 2400))
                c.closePath()
                c.setFillColor(goldC.withAlphaComponent(i % 2 == 0 ? 0.09 : 0.05).cgColor)
                c.fillPath()
            }
            // 太阳的几圈光环（外圈是一格一格的，像项圈上的镶嵌）
            for (k, r) in [250.0, 370.0, 500.0].enumerated() {
                c.setStrokeColor((k == 1 ? cyan : goldC).withAlphaComponent(0.4).cgColor)
                c.setLineWidth(k == 1 ? 8 : 2.5)
                c.setLineDash(phase: 0, lengths: k == 1 ? [18, 10] : [])
                c.addArc(center: center, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
                c.strokePath()
            }
            c.setLineDash(phase: 0, lengths: [])
            var seed = PachinkoRandom(seed: 7)
            for _ in 0..<220 {
                let x = seed.uniform() * Double(w), y = seed.uniform() * Double(h), r = 0.6 + seed.uniform() * 1.8
                c.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.15 + seed.uniform() * 0.45).cgColor)
                c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            func label(_ text: String, _ p: CGPoint, size: CGFloat, color: UIColor, kern: CGFloat = 1, angle: CGFloat = 0, serif: Bool = false) {
                let font = UIFont.systemFont(ofSize: size, weight: .black)
                let styled = font.fontDescriptor.withDesign(serif ? .serif : .rounded).map { UIFont(descriptor: $0, size: size) } ?? font
                let s = NSAttributedString(string: text, attributes: [.font: styled, .foregroundColor: color, .kern: kern,
                                                                      .strokeColor: UIColor.black.withAlphaComponent(0.6), .strokeWidth: -2.5])
                let sz = s.size()
                c.saveGState()
                c.translateBy(x: p.x, y: p.y)
                c.rotate(by: angle)
                s.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2))
                c.restoreGState()
            }
            /// 安卡（生命之符）：上面一个圈，下面一个十字
            func ankh(_ p: CGPoint, _ k: CGFloat, _ col: UIColor) {
                c.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor)
                for pass in 0..<2 {
                    c.setLineWidth(pass == 0 ? k * 0.3 : k * 0.18)
                    if pass == 1 { c.setStrokeColor(col.cgColor) }
                    c.setLineCap(.round)
                    c.strokeEllipse(in: CGRect(x: p.x - k * 0.3, y: p.y - k * 0.95, width: k * 0.6, height: k * 0.8))
                    c.move(to: CGPoint(x: p.x, y: p.y - k * 0.15)); c.addLine(to: CGPoint(x: p.x, y: p.y + k * 0.95))
                    c.move(to: CGPoint(x: p.x - k * 0.5, y: p.y + k * 0.1)); c.addLine(to: CGPoint(x: p.x + k * 0.5, y: p.y + k * 0.1))
                    c.strokePath()
                }
            }
            /// 展开的翅膀（蘑菇柱底下：带翼的日轮）
            func wings(_ p: CGPoint, _ r: CGFloat, _ col: UIColor) {
                for side in [CGFloat(-1), 1] {
                    for i in 0..<5 {
                        let a = CGFloat(i) * 0.2 - 0.25
                        c.move(to: CGPoint(x: p.x + side * r * 0.9, y: p.y))
                        c.addQuadCurve(to: CGPoint(x: p.x + side * r * 2.1 * cos(a), y: p.y + r * 2.1 * sin(a)),
                                       control: CGPoint(x: p.x + side * r * 1.6, y: p.y - r * 0.5 + CGFloat(i) * r * 0.25))
                    }
                }
                c.setStrokeColor(col.withAlphaComponent(0.55).cgColor)
                c.setLineWidth(5)
                c.setLineCap(.round)
                c.strokePath()
            }
            // 蘑菇柱底下：光 + 翅膀
            for (k, bp) in T.bumpers.enumerated() {
                let col = [pink, cyan, goldC][k % 3]
                halo(pt(bp.x, bp.y), 130, col)
                wings(pt(bp.x, bp.y), 62, col)
            }
            // 顶部滚道：三个安卡
            for lx in T.topLaneX { ankh(pt(lx, T.topLaneY1 + 0.05), 30, goldC) }
            // 墓室入口（幸运洞）
            halo(pt(T.holeX, T.holeY), 110, goldC)
            label("TOMB", pt(T.holeX - 0.01, T.holeY - 0.065), size: 24, color: goldC, kern: 4, serif: true)
            // 靶
            halo(pt(T.dropX + 0.03, T.targetY[1]), 130, sand, 0.25)
            halo(pt(T.standupX - 0.03, T.targetY[1]), 130, cyan, 0.3)
            label("K · Q · J", pt(T.dropX + 0.085, T.targetY[1]), size: 24, color: sand, kern: 2, angle: -.pi / 2, serif: true)
            label("★ ★ ★", pt(T.standupX - 0.085, T.targetY[1]), size: 24, color: cyan, kern: 2, angle: .pi / 2)
            // 中间：金字塔和它上面的眼睛，下面是台名
            let mid = pt(T.fieldCenter, 0.84)
            halo(mid, 230, goldC, 0.28)
            let px: CGFloat = 190, pyTop = mid.y - 150, pyBase = mid.y + 60
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: mid.x, y: pyTop))
            tri.addLine(to: CGPoint(x: mid.x + px, y: pyBase))
            tri.addLine(to: CGPoint(x: mid.x - px, y: pyBase))
            tri.closeSubpath()
            c.saveGState()
            c.addPath(tri); c.clip()
            let pg = CGGradient(colorsSpace: space, colors: [UIColor(red: 1, green: 0.86, blue: 0.5, alpha: 1).cgColor, UIColor(red: 0.72, green: 0.45, blue: 0.14, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(pg, start: CGPoint(x: mid.x - px, y: pyTop), end: CGPoint(x: mid.x + px, y: pyBase), options: [])
            // 背光的一面
            c.move(to: CGPoint(x: mid.x, y: pyTop)); c.addLine(to: CGPoint(x: mid.x + px, y: pyBase)); c.addLine(to: CGPoint(x: mid.x + 40, y: pyBase)); c.closePath()
            c.setFillColor(UIColor(red: 0.3, green: 0.15, blue: 0.02, alpha: 0.45).cgColor)
            c.fillPath()
            // 砖缝
            c.setStrokeColor(UIColor(red: 0.35, green: 0.18, blue: 0.03, alpha: 0.55).cgColor)
            c.setLineWidth(1.5)
            var row = 0
            var y = pyBase
            while y > pyTop {
                c.move(to: CGPoint(x: mid.x - px, y: y)); c.addLine(to: CGPoint(x: mid.x + px, y: y))
                var x = mid.x - px + (row % 2 == 0 ? 0 : 19)
                while x < mid.x + px { c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x, y: y - 21)); x += 38 }
                y -= 21; row += 1
            }
            c.strokePath()
            c.restoreGState()
            c.addPath(tri)
            c.setStrokeColor(UIColor(red: 1, green: 0.93, blue: 0.65, alpha: 0.95).cgColor)
            c.setLineWidth(4)
            c.setLineJoin(.round)
            c.strokePath()
            // 塔尖上的眼睛
            let eye = CGPoint(x: mid.x, y: pyTop + 78)
            c.setFillColor(UIColor(red: 0.03, green: 0.06, blue: 0.2, alpha: 1).cgColor)
            c.move(to: CGPoint(x: eye.x - 46, y: eye.y))
            c.addQuadCurve(to: CGPoint(x: eye.x + 46, y: eye.y), control: CGPoint(x: eye.x, y: eye.y - 40))
            c.addQuadCurve(to: CGPoint(x: eye.x - 46, y: eye.y), control: CGPoint(x: eye.x, y: eye.y + 34))
            c.fillPath()
            c.setFillColor(cyan.cgColor)
            c.fillEllipse(in: CGRect(x: eye.x - 15, y: eye.y - 16, width: 30, height: 30))
            c.setFillColor(UIColor.black.cgColor)
            c.fillEllipse(in: CGRect(x: eye.x - 7, y: eye.y - 8, width: 14, height: 14))
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: eye.x - 9, y: eye.y - 11, width: 6, height: 6))
            label("PHARAOH'S", CGPoint(x: mid.x, y: pyBase + 42), size: 46, color: goldC, kern: 5, serif: true)
            label("TREASURE", CGPoint(x: mid.x, y: pyBase + 92), size: 46, color: sand, kern: 7, serif: true)
            // 台名两边各一个安卡
            ankh(CGPoint(x: mid.x - 215, y: pyBase + 62), 26, cyan)
            ankh(CGPoint(x: mid.x + 215, y: pyBase + 62), 26, cyan)
            // 内道的箭头、保球灯的字
            for side in 0..<2 {
                let x = side == 0 ? (T.guideX + T.slingA.x) / 2 : T.mirror((T.guideX + T.slingA.x) / 2)
                c.setStrokeColor(cyan.withAlphaComponent(0.8).cgColor)
                c.setLineWidth(5)
                c.setLineCap(.round)
                c.setLineJoin(.round)
                for i in 0..<3 {
                    let p = pt(x, 0.58 - Double(i) * 0.03)
                    c.move(to: CGPoint(x: p.x - 14, y: p.y))
                    c.addLine(to: CGPoint(x: p.x, y: p.y + 12))
                    c.addLine(to: CGPoint(x: p.x + 14, y: p.y))
                }
                c.strokePath()
            }
            label("BALL SAVE", pt(T.fieldCenter, 0.145), size: 18, color: UIColor(red: 0.4, green: 1, blue: 0.5, alpha: 0.9), kern: 2)
            // 发射轨道：暗一点，画几道箭头
            c.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            c.fill(CGRect(x: pt(T.laneInner, 0).x, y: pt(0, T.archCY).y, width: (T.laneOuter - T.laneInner) * Double(w), height: Double(h)))
            c.setStrokeColor(goldC.withAlphaComponent(0.7).cgColor)
            c.setLineWidth(5)
            for i in 0..<6 {
                let p = pt(T.laneX, 0.35 + Double(i) * 0.16)
                c.move(to: CGPoint(x: p.x - 16, y: p.y + 12))
                c.addLine(to: CGPoint(x: p.x, y: p.y))
                c.addLine(to: CGPoint(x: p.x + 16, y: p.y + 12))
            }
            c.strokePath()
        }
        artCache = img
        return img
    }
}

/// SwiftUI 包装
struct Pinball3DView: UIViewRepresentable {
    let scene3D: Pinball3DScene

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
        v.antialiasingMode = VisualFX.lowTier ? .none : .multisampling4X
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isUserInteractionEnabled = false
        s.start()
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: ()) {
        (uiView.delegate as? Pinball3DScene)?.stop()
    }
}
