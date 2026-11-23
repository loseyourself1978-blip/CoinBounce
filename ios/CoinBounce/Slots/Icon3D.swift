import SceneKit
import simd
import UIKit

// MARK: - v13.1 老虎机的图案和机器外框：真 3D 建模，离屏渲染成图
/// 每个图案是一个小 SceneKit 场景（PBR 材质 + 摄影棚环境光），渲染一次存成透明底的图，转轮上用图。
/// 做法和推币机的金币一样（代码建模、实时渲染器出图），不用任何图片素材。
enum Icon3D {
    /// 渲染出来的边长（像素）
    static let pixels: CGFloat = 360

    enum Kind: Hashable {
        /// 一个图案。四个高分图案和百搭的底牌随主题换模型；字母和金币三台机器共用
        case symbol(CaishenSymbol, SlotTheme = .caishen)
        /// 正面朝前、没有方孔的金币（锁定重转里上面要写数字）
        case blankCoin
        /// 一堆元宝和金币（机器旁边的摆设、天降财神时的大图）
        case pile
    }

    private static let lock = NSLock()
    private static var cache: [Kind: UIImage] = [:]
    private static var frameCache: [String: UIImage] = [:]
    private static let device = MTLCreateSystemDefaultDevice()

    static func image(_ kind: Kind) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[kind] { return c }
        guard let img = render(kind) else { return nil }
        cache[kind] = img
        return img
    }

    /// 提前在后台把所有图案渲染好（进老虎机之前调，免得第一次进去卡一下）
    static func preload() {
        DispatchQueue.global(qos: .userInitiated).async {
            for s in CaishenSymbol.allCases { _ = image(.symbol(s)) }
            for t in [SlotTheme.wukong, .athena] { for s in [CaishenSymbol.ingot, .fu, .redEnvelope, .lantern, .wild] { _ = image(.symbol(s, t)) } }
            _ = image(.blankCoin)
            _ = image(.pile)
        }
    }

    // MARK: 材质
    static func gold(rough: CGFloat = 0.2) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 1.0, green: 0.8, blue: 0.36, alpha: 1)
        m.metalness.contents = 1.0
        m.roughness.contents = rough
        m.emission.contents = UIColor(red: 0.5, green: 0.28, blue: 0.02, alpha: 1)
        m.emission.intensity = 0.08
        return m
    }

    /// 亮漆 / 珐琅：不是金属，上面一层清漆
    static func lacquer(_ color: UIColor, glow: CGFloat = 0.3, rough: CGFloat = 0.35) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 0.0
        m.roughness.contents = rough
        m.clearCoat.contents = 1.0
        m.clearCoatRoughness.contents = 0.1
        m.emission.contents = color
        m.emission.intensity = glow
        return m
    }

    static let red = UIColor(red: 0.86, green: 0.06, blue: 0.08, alpha: 1)

    /// 摄影棚环境：上面一大片暖白的柔光箱，中间一条金色的地平线，下面暗。金属有东西可反射才像金属
    static let studio: UIImage = {
        let size = CGSize(width: 512, height: 256)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1), UIColor(red: 0.62, green: 0.44, blue: 0.22, alpha: 1),
                          UIColor(red: 0.36, green: 0.18, blue: 0.06, alpha: 1), UIColor(red: 0.12, green: 0.05, blue: 0.02, alpha: 1),
                          UIColor(red: 0.04, green: 0.015, blue: 0.01, alpha: 1)].map(\.cgColor) as CFArray
            c.drawLinearGradient(CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.38, 0.5, 0.6, 1])!,
                                 start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // 一圈竖着的柔光箱，亮暗相间：朝向不同的面反射到的东西不一样，金属才有明暗层次；弧面上会拉出一道道高光
            for k in 0..<10 {
                let x = CGFloat(k) * 51.2 + 8
                let top: CGFloat = k % 2 == 0 ? 14 : 40, bottom: CGFloat = k % 2 == 0 ? 124 : 104
                for (inset, alpha) in [(0.0, 0.35), (4.0, 0.6), (8.0, 1.0)] as [(CGFloat, CGFloat)] {
                    c.setFillColor(UIColor(red: 1, green: 0.98, blue: 0.92, alpha: alpha).cgColor)
                    c.fill(CGRect(x: x + inset, y: top + inset, width: 30 - inset * 2, height: bottom - top - inset * 2))
                }
            }
            // 地面的暖色反光（朝下的面不至于全黑），和一道红墙的反光
            c.setFillColor(UIColor(red: 0.55, green: 0.3, blue: 0.08, alpha: 0.7).cgColor)
            c.fill(CGRect(x: 0, y: 150, width: size.width, height: 26))
            c.setFillColor(UIColor(red: 0.9, green: 0.1, blue: 0.08, alpha: 0.45).cgColor)
            c.fill(CGRect(x: 0, y: 130, width: size.width, height: 10))
        }
    }()

    // MARK: 场景
    private static func makeScene() -> (SCNScene, SCNNode, SCNNode) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 2.2
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.fieldOfView = 22
        cam.camera!.zNear = 0.5
        cam.camera!.zFar = 40
        // v13.1b：相机正对着图案（hj：要正视呈现，歪着摆不自然）
        cam.position = SCNVector3(0, 0, 6.1)
        cam.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cam)
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 500
        key.light!.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        key.eulerAngles = SCNVector3(-0.7, -0.55, 0)
        scene.rootNode.addChildNode(key)
        // 从后上方打一道轮廓光
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light!.type = .directional
        rim.light!.intensity = 500
        rim.light!.color = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        rim.eulerAngles = SCNVector3(-2.3, 0.6, 0)
        scene.rootNode.addChildNode(rim)
        // 离得很近的一盏点光源（左上前方）：正面朝前的平面上，各处到灯的角度不一样，
        // 所以会有一块从左上往右下淡下去的高光——平面才不是一整块死颜色
        let spot = SCNNode()
        spot.light = SCNLight()
        spot.light!.type = .omni
        spot.light!.intensity = 190
        spot.light!.color = UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)
        spot.position = SCNVector3(-1.1, 1.5, 2.2)
        scene.rootNode.addChildNode(spot)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 220
        scene.rootNode.addChildNode(amb)
        let root = SCNNode()
        scene.rootNode.addChildNode(root)
        return (scene, cam, root)
    }

    private static func snapshot(_ scene: SCNScene, _ cam: SCNNode, size: CGSize) -> UIImage? {
        guard let device else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = scene
        r.pointOfView = cam
        r.autoenablesDefaultLighting = false
        return r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    private static func render(_ kind: Kind) -> UIImage? {
        let (scene, cam, root) = makeScene()
        switch kind {
        case .blankCoin: root.addChildNode(blankCoin())
        case .pile:
            root.addChildNode(pile())
            return snapshot(scene, cam, size: CGSize(width: 600, height: 600))
        case .symbol(let s, let theme):
            switch s {
            case .ingot: root.addChildNode(theme == .wukong ? staff() : (theme == .athena ? helmet() : ingot()))
            case .fu: root.addChildNode(theme == .wukong ? headband() : (theme == .athena ? shield() : fuTile()))
            case .redEnvelope: root.addChildNode(theme == .wukong ? peach() : (theme == .athena ? wreath() : envelope()))
            case .lantern: root.addChildNode(theme == .wukong ? gourd() : (theme == .athena ? amphora() : lantern()))
            case .ace: root.addChildNode(letter("A", UIColor(red: 0.95, green: 0.16, blue: 0.1, alpha: 1)))
            case .kingCard: root.addChildNode(letter("K", UIColor(red: 0.62, green: 0.2, blue: 0.9, alpha: 1)))
            case .queenCard: root.addChildNode(letter("Q", UIColor(red: 0.1, green: 0.72, blue: 0.3, alpha: 1)))
            case .jack: root.addChildNode(letter("J", UIColor(red: 0.12, green: 0.5, blue: 1.0, alpha: 1)))
            case .wild: root.addChildNode(wild(enamel: theme.enamel))
            case .coin: root.addChildNode(holeCoin())
            }
        }
        return snapshot(scene, cam, size: CGSize(width: pixels, height: pixels))
    }

    // MARK: 模型
    /// 元宝的船身：自己算的网格。沿长度方向一圈一圈的截面，中间粗、两头细并且往上翘，顶面压平
    static func ingotHull() -> SCNGeometry {
        let n = 56, m = 40
        func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let u = Float(i) / Float(n) * 2 - 1
            let au = abs(u)
            let f = pow(max(0, 1 - pow(au, 3.2)), 0.5)
            let wz = 0.6 * f
            let ry = 0.3 * f + 0.012
            let yc = -0.2 + 0.6 * pow(au, 2.3)
            let th = Float(j) / Float(m) * 2 * .pi
            let cs = cos(th), sn = sin(th)
            // 超椭圆截面：下半边圆鼓鼓的，上半边压平成甲板
            let z = wz * (cs < 0 ? -1 : 1) * pow(abs(cs), 0.75)
            let y = yc + ry * (sn < 0 ? -pow(abs(sn), 0.8) : pow(abs(sn), 0.42) * 0.72)
            return SIMD3(u * 1.0, y, z)
        }
        var pos: [SCNVector3] = [], nrm: [SCNVector3] = [], idx: [Int32] = []
        for i in 0...n {
            for j in 0...m {
                let p = point(i, j)
                let du = point(min(n, i + 1), j) - point(max(0, i - 1), j)
                let dt = point(i, (j + 1) % m) - point(i, (j + m - 1) % m)
                var nn = simd_cross(du, dt)
                let len = simd_length(nn)
                nn = len > 1e-6 ? nn / len : SIMD3(i == 0 ? -1 : 1, 0, 0)
                pos.append(SCNVector3(p.x, p.y, p.z))
                nrm.append(SCNVector3(nn.x, nn.y, nn.z))
            }
        }
        for i in 0..<n {
            for j in 0..<m {
                let a = Int32(i * (m + 1) + j), b = Int32((i + 1) * (m + 1) + j)
                idx += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let mat = gold(rough: 0.16)
        mat.isDoubleSided = true
        g.materials = [mat]
        return g
    }

    /// 元宝：船形的身子 + 中间鼓起的一团
    static func ingot() -> SCNNode {
        let node = SCNNode()
        node.addChildNode(SCNNode(geometry: ingotHull()))
        let dome = SCNSphere(radius: 0.44)
        dome.segmentCount = 48
        dome.firstMaterial = gold(rough: 0.12)
        let domeNode = SCNNode(geometry: dome)
        domeNode.scale = SCNVector3(1, 0.85, 0.95)
        domeNode.position = SCNVector3(0, 0.06, 0)
        node.addChildNode(domeNode)
        // 甲板和那一团之间的一圈细边
        let ringG = SCNTorus(ringRadius: 0.44, pipeRadius: 0.03)
        ringG.ringSegmentCount = 48
        ringG.firstMaterial = gold(rough: 0.12)
        let ringNode = SCNNode(geometry: ringG)
        ringNode.scale = SCNVector3(1, 1, 0.95)
        ringNode.position = SCNVector3(0, 0.03, 0)
        node.addChildNode(ringNode)
        // 元宝正面朝前，只往前低一点头（看得见甲板和那一团），左右对称
        node.eulerAngles = SCNVector3(0.3, 0, 0)
        node.position = SCNVector3(0, 0.0, 0)
        node.scale = SCNVector3(1.02, 1.02, 1.02)
        return node
    }

    private static func disc(radius: CGFloat, depth: CGFloat, _ m: SCNMaterial, z: Float = 0) -> SCNNode {
        let g = SCNCylinder(radius: radius, height: depth)
        g.radialSegmentCount = 72
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.eulerAngles.x = .pi / 2
        n.position.z = z
        return n
    }

    private static func ring(radius: CGFloat, pipe: CGFloat, _ m: SCNMaterial, z: Float) -> SCNNode {
        let g = SCNTorus(ringRadius: radius, pipeRadius: pipe)
        g.ringSegmentCount = 72
        g.pipeSegmentCount = 18
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.eulerAngles.x = .pi / 2
        n.position.z = z
        return n
    }

    /// 方孔钱：圆片中间挖一个方孔，外圈和孔边各一道凸起的边
    static func holeCoin() -> SCNNode {
        let p = UIBezierPath(ovalIn: CGRect(x: -1, y: -1, width: 2, height: 2))
        p.append(UIBezierPath(rect: CGRect(x: -0.26, y: -0.26, width: 0.52, height: 0.52)).reversing())
        p.usesEvenOddFillRule = true
        p.flatness = 0.004
        let body = SCNShape(path: p, extrusionDepth: 0.16)
        body.chamferRadius = 0.03
        body.materials = [gold(rough: 0.3)]
        let node = SCNNode()
        node.addChildNode(SCNNode(geometry: body))
        for z in [Float(0.08), -0.08] {
            node.addChildNode(ring(radius: 0.92, pipe: 0.075, gold(rough: 0.14), z: z))
            // 孔边
            for (x, y, w, h) in [(0.0, 0.3, 0.72, 0.1), (0.0, -0.3, 0.72, 0.1), (0.3, 0.0, 0.1, 0.72), (-0.3, 0.0, 0.1, 0.72)] {
                let b = SCNNode(geometry: SCNBox(width: w, height: h, length: 0.09, chamferRadius: 0.04))
                b.geometry!.firstMaterial = gold(rough: 0.14)
                b.position = SCNVector3(Float(x), Float(y), z)
                node.addChildNode(b)
            }
        }
        // 四颗凸点（代替钱文）
        for k in 0..<4 {
            let a = Float(k) * .pi / 2 + .pi / 4
            let s = SCNSphere(radius: 0.1)
            s.firstMaterial = gold(rough: 0.14)
            let n = SCNNode(geometry: s)
            n.scale = SCNVector3(1, 1, 0.5)
            n.position = SCNVector3(cos(a) * 0.62, sin(a) * 0.62, 0.09)
            node.addChildNode(n)
        }
        node.scale = SCNVector3(0.98, 0.98, 0.98)
        return node
    }

    /// 正面的金币：一圈厚边，里面是略低的平面（上面写数字）
    static func blankCoin() -> SCNNode {
        let node = SCNNode()
        node.addChildNode(disc(radius: 1.0, depth: 0.16, gold(rough: 0.2)))
        node.addChildNode(disc(radius: 0.8, depth: 0.04, gold(rough: 0.42), z: 0.08))
        node.addChildNode(ring(radius: 0.9, pipe: 0.1, gold(rough: 0.12), z: 0.08))
        node.addChildNode(ring(radius: 0.76, pipe: 0.025, gold(rough: 0.12), z: 0.1))

        return node
    }

    /// 灯笼：压扁的红球 + 一圈金色的骨 + 上下两个金盖 + 穗子
    static func lantern() -> SCNNode {
        let node = SCNNode()
        let body = SCNNode()
        let s = SCNSphere(radius: 0.86)
        s.segmentCount = 64
        let m = lacquer(UIColor(red: 0.92, green: 0.08, blue: 0.06, alpha: 1), glow: 0.45, rough: 0.4)
        s.firstMaterial = m
        body.addChildNode(SCNNode(geometry: s))
        for k in 0..<8 {
            let holder = SCNNode()
            holder.eulerAngles.y = Float(k) * .pi / 8
            let t = SCNTorus(ringRadius: 0.865, pipeRadius: 0.022)
            t.ringSegmentCount = 64
            t.firstMaterial = gold(rough: 0.25)
            let rib = SCNNode(geometry: t)
            rib.eulerAngles.x = .pi / 2
            holder.addChildNode(rib)
            body.addChildNode(holder)
        }
        body.scale = SCNVector3(1, 0.82, 1)
        node.addChildNode(body)
        for side in [Float(1), -1] {
            let cap = SCNCylinder(radius: 0.4, height: 0.16)
            cap.radialSegmentCount = 48
            cap.firstMaterial = gold(rough: 0.18)
            let c = SCNNode(geometry: cap)
            c.position = SCNVector3(0, side * 0.7, 0)
            node.addChildNode(c)
            let lip = SCNTorus(ringRadius: 0.4, pipeRadius: 0.035)
            lip.firstMaterial = gold(rough: 0.12)
            let l = SCNNode(geometry: lip)
            l.position = SCNVector3(0, side * 0.62, 0)
            node.addChildNode(l)
        }
        let loop = SCNTorus(ringRadius: 0.12, pipeRadius: 0.03)
        loop.firstMaterial = gold(rough: 0.15)
        let loopNode = SCNNode(geometry: loop)
        loopNode.eulerAngles.x = .pi / 2
        loopNode.position = SCNVector3(0, 0.88, 0)
        node.addChildNode(loopNode)
        let bead = SCNSphere(radius: 0.09)
        bead.firstMaterial = gold(rough: 0.12)
        let beadNode = SCNNode(geometry: bead)
        beadNode.position = SCNVector3(0, -0.86, 0)
        node.addChildNode(beadNode)
        let tassel = SCNCone(topRadius: 0.05, bottomRadius: 0.13, height: 0.34)
        tassel.firstMaterial = lacquer(UIColor(red: 0.9, green: 0.1, blue: 0.08, alpha: 1), glow: 0.3, rough: 0.7)
        let tasselNode = SCNNode(geometry: tassel)
        tasselNode.position = SCNVector3(0, -1.08, 0)
        node.addChildNode(tasselNode)
        node.scale = SCNVector3(0.84, 0.84, 0.84)
        node.position = SCNVector3(0, 0.1, 0)
        return node
    }

    /// 红包：红色的厚信封 + 弧形的封口 + 金色的封印
    static func envelope() -> SCNNode {
        let node = SCNNode()
        let body = SCNBox(width: 1.2, height: 1.66, length: 0.3, chamferRadius: 0.14)
        body.firstMaterial = lacquer(red, glow: 0.3, rough: 0.5)
        node.addChildNode(SCNNode(geometry: body))
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -0.6, y: 0.83))
        p.addLine(to: CGPoint(x: 0.6, y: 0.83))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0.1), controlPoint: CGPoint(x: 0.58, y: 0.22))
        p.addQuadCurve(to: CGPoint(x: -0.6, y: 0.83), controlPoint: CGPoint(x: -0.58, y: 0.22))
        p.close()
        p.flatness = 0.005
        let flap = SCNShape(path: p, extrusionDepth: 0.05)
        flap.chamferRadius = 0.02
        flap.materials = [lacquer(UIColor(red: 0.98, green: 0.16, blue: 0.12, alpha: 1), glow: 0.35, rough: 0.4)]
        let flapNode = SCNNode(geometry: flap)
        flapNode.position = SCNVector3(0, 0, 0.16)
        node.addChildNode(flapNode)
        // 封口的金边：沿着弧线摆一串小金珠
        for i in 0...20 {
            let t = CGFloat(i) / 20
            let half = t < 0.5
            let u = half ? t * 2 : (t - 0.5) * 2
            let a = half ? CGPoint(x: -0.6, y: 0.83) : CGPoint(x: 0, y: 0.1)
            let c = half ? CGPoint(x: -0.58, y: 0.22) : CGPoint(x: 0.58, y: 0.22)
            let b = half ? CGPoint(x: 0, y: 0.1) : CGPoint(x: 0.6, y: 0.83)
            let x = (1 - u) * (1 - u) * a.x + 2 * u * (1 - u) * c.x + u * u * b.x
            let y = (1 - u) * (1 - u) * a.y + 2 * u * (1 - u) * c.y + u * u * b.y
            let s = SCNSphere(radius: 0.035)
            s.segmentCount = 12
            s.firstMaterial = gold(rough: 0.15)
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(Float(x), Float(y), 0.21)
            node.addChildNode(n)
        }
        let seal = SCNNode()
        seal.addChildNode(disc(radius: 0.25, depth: 0.08, gold(rough: 0.15)))
        seal.addChildNode(ring(radius: 0.22, pipe: 0.035, gold(rough: 0.1), z: 0.04))
        let hole = SCNNode(geometry: SCNBox(width: 0.13, height: 0.13, length: 0.1, chamferRadius: 0.01))
        hole.geometry!.firstMaterial = lacquer(red, glow: 0.2)
        seal.addChildNode(hole)
        seal.position = SCNVector3(0, 0.1, 0.22)
        node.addChildNode(seal)
        let band = SCNNode(geometry: SCNBox(width: 1.22, height: 0.12, length: 0.34, chamferRadius: 0.05))
        band.geometry!.firstMaterial = gold(rough: 0.2)
        band.position = SCNVector3(0, -0.58, 0)
        node.addChildNode(band)
        node.scale = SCNVector3(1.05, 1.05, 1.05)
        return node
    }

    /// 拉伸出来的立体字，原点挪到字的正中间
    private static func text(_ string: String, font: UIFont, depth: CGFloat, chamfer: CGFloat, front: SCNMaterial, side: SCNMaterial, height: Float? = nil, width: Float? = nil) -> SCNNode {
        let t = SCNText(string: string, extrusionDepth: depth)
        t.font = font
        t.flatness = 0.02
        t.chamferRadius = chamfer
        // 倒角的截面是四分之一圆（默认是一条斜线）
        let prof = UIBezierPath()
        prof.move(to: CGPoint(x: 0, y: 1))
        prof.addQuadCurve(to: CGPoint(x: 1, y: 0), controlPoint: CGPoint(x: 1, y: 1))
        t.chamferProfile = prof
        // 材质顺序：正面、背面、侧面、正面倒角、背面倒角
        t.materials = [front, side, side, side, side]
        let n = SCNNode(geometry: t)
        let (lo, hi) = n.boundingBox
        n.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        var k: Float = 1
        if let height { k = height / max(0.001, hi.y - lo.y) }
        if let width { k = min(height == nil ? .greatestFiniteMagnitude : k, width / max(0.001, hi.x - lo.x)) }
        n.scale = SCNVector3(k, k, k)
        return n
    }

    /// A、K、Q、J：厚厚的立体字，正面是带光泽的颜色，侧面和倒角是金的
    static func letter(_ s: String, _ color: UIColor) -> SCNNode {
        // 正面看：笔画粗细均匀的圆体字，配一圈圆的大倒角——厚度看不见了，立体感靠这圈鼓起来的金边
        let base = UIFont.systemFont(ofSize: 10, weight: .black)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 10) } ?? base
        let n = text(s, font: font, depth: 2.4, chamfer: 0.42, front: lacquer(color, glow: 0.45, rough: 0.25), side: gold(rough: 0.14), height: 1.62, width: 1.7)
        let holder = SCNNode()
        holder.addChildNode(n)
        return holder
    }

    /// 福字牌：斜放的红漆方牌、金边、凸起的金字
    static func fuTile() -> SCNNode {
        let node = SCNNode()
        let tile = SCNNode()
        let back = SCNNode(geometry: SCNBox(width: 1.36, height: 1.36, length: 0.12, chamferRadius: 0.05))
        back.geometry!.firstMaterial = gold(rough: 0.16)
        tile.addChildNode(back)
        let face = SCNNode(geometry: SCNBox(width: 1.18, height: 1.18, length: 0.14, chamferRadius: 0.04))
        face.geometry!.firstMaterial = lacquer(red, glow: 0.35, rough: 0.3)
        face.position.z = 0.03
        tile.addChildNode(face)
        for (x, y) in [(0.0, 0.8), (0.0, -0.8), (0.8, 0.0), (-0.8, 0.0)] {
            // 四个角上的小金珠（方牌转了 45°，这四个点正好在角上）
            let s = SCNSphere(radius: 0.07)
            s.firstMaterial = gold(rough: 0.12)
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(Float(x) * 1.2, Float(y) * 1.2, 0.04)
            node.addChildNode(n)
        }
        tile.eulerAngles.z = .pi / 4
        node.addChildNode(tile)
        let fu = text("福", font: UIFont(name: "PingFangSC-Semibold", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .heavy), depth: 1.0, chamfer: 0.12, front: gold(rough: 0.14), side: gold(rough: 0.3), height: 0.92)
        fu.position = SCNVector3(0, 0, 0.14)
        node.addChildNode(fu)
        node.scale = SCNVector3(1.02, 1.02, 1.02)
        return node
    }

    /// 百搭的底牌：金边红珐琅的圆牌
    static func wild(enamel: UIColor = red) -> SCNNode {
        let node = SCNNode()
        node.addChildNode(disc(radius: 1.0, depth: 0.14, gold(rough: 0.16)))
        node.addChildNode(disc(radius: 0.84, depth: 0.05, lacquer(enamel, glow: enamel == red ? 0.35 : 0.18, rough: 0.3), z: 0.07))
        node.addChildNode(ring(radius: 0.92, pipe: 0.085, gold(rough: 0.12), z: 0.07))
        // v13.1c：牌面上的财神头像和 WILD 字是另外叠上去的（CaishenSymbolView），这里只做金边红珐琅的底牌
        node.scale = SCNVector3(0.98, 0.98, 0.98)
        return node
    }

    /// 一堆财宝：三只元宝叠成品字，周围散着方孔钱
    static func pile() -> SCNNode {
        let node = SCNNode()
        for (x, y, z, yaw) in [(-0.46, -0.42, 0.0, 0.25), (0.46, -0.42, 0.0, -0.3), (0.0, 0.16, -0.1, 0.0)] as [(Float, Float, Float, Float)] {
            let n = ingot()
            n.scale = SCNVector3(0.5, 0.5, 0.5)
            n.position = SCNVector3(x, y, z)
            n.eulerAngles = SCNVector3(0.3, yaw, 0)
            node.addChildNode(n)
        }
        let coins: [(Float, Float, Float, Float, Float, Float)] = [
            (-0.86, -0.78, 0.5, -1.15, 0.3, 0.2), (-0.36, -0.86, 0.75, -1.25, -0.2, 0.0), (0.22, -0.84, 0.8, -1.2, 0.4, -0.1),
            (0.8, -0.76, 0.5, -1.1, -0.4, 0.3), (-0.62, -0.7, 0.9, -0.5, 0.5, 0.6), (0.58, -0.66, 0.95, -0.4, -0.6, -0.5),
            (0.0, -0.74, 1.1, -0.9, 0.1, 0.9), (-1.0, -0.5, 0.1, -0.2, 0.7, 0.3), (1.0, -0.48, 0.1, -0.25, -0.7, -0.2),
        ]
        for (x, y, z, pitch, yaw, roll) in coins {
            let c = holeCoin()
            c.scale = SCNVector3(0.27, 0.27, 0.27)
            c.position = SCNVector3(x, y, z)
            c.eulerAngles = SCNVector3(pitch, yaw, roll)
            node.addChildNode(c)
        }
        node.scale = SCNVector3(0.8, 0.8, 0.8)
        node.position = SCNVector3(0, 0.14, 0)
        return node
    }

    // MARK: 旋转体（葫芦、蟠桃、头盔、陶瓶都是一条轮廓线绕中轴转一圈）
    /// 把几个控制点连成一条光滑的轮廓线（Catmull-Rom），再绕 Y 轴转一圈。控制点从下往上写：(半径, 高度)。
    /// 贴图坐标：u 绕一圈，v 沿轮廓从下（0）到上（1）——所以一张从上到下的渐变图就是从底到顶的颜色
    static func lathe(_ control: [(Float, Float)], material: SCNMaterial, segments: Int = 56, steps: Int = 10) -> SCNGeometry {
        var prof: [SIMD2<Float>] = []
        let c = control.map { SIMD2($0.0, $0.1) }
        for i in 0..<(c.count - 1) {
            let p0 = c[max(0, i - 1)], p1 = c[i], p2 = c[i + 1], p3 = c[min(c.count - 1, i + 2)]
            for k in 0..<steps {
                let t = Float(k) / Float(steps), t2 = t * t, t3 = t2 * t
                var q = 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
                q.x = max(0, q.x)
                prof.append(q)
            }
        }
        prof.append(c[c.count - 1])
        let n = prof.count
        var pos: [SCNVector3] = [], nrm: [SCNVector3] = [], uv: [CGPoint] = [], idx: [Int32] = []
        for i in 0..<n {
            let d = prof[min(n - 1, i + 1)] - prof[max(0, i - 1)]
            // 轮廓线的法线（朝外）：切线 (dr, dy) 转 90°
            var nn = SIMD2(d.y, -d.x)
            let len = simd_length(nn)
            nn = len > 1e-6 ? nn / len : SIMD2(0, i == 0 ? -1 : 1)
            for j in 0...segments {
                let th = Float(j) / Float(segments) * 2 * .pi
                pos.append(SCNVector3(prof[i].x * cos(th), prof[i].y, prof[i].x * sin(th)))
                nrm.append(SCNVector3(nn.x * cos(th), nn.y, nn.x * sin(th)))
                uv.append(CGPoint(x: CGFloat(j) / CGFloat(segments), y: CGFloat(i) / CGFloat(n - 1)))
            }
        }
        for i in 0..<(n - 1) {
            for j in 0..<segments {
                let a = Int32(i * (segments + 1) + j), b = Int32((i + 1) * (segments + 1) + j)
                idx += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm), SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [material]
        return g
    }

    /// 从上到下的渐变图（配合 lathe 的贴图坐标：stops 里位置 0 是物体的底、1 是顶）
    static func gradientImage(_ stops: [(UIColor, CGFloat)]) -> UIImage {
        let size = CGSize(width: 8, height: 256)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: stops.map { $0.0.cgColor } as CFArray, locations: stops.map { $0.1 })!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    private static func ball(_ r: CGFloat, _ m: SCNMaterial, _ x: Float, _ y: Float, _ z: Float, scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
        let s = SCNSphere(radius: r)
        s.segmentCount = 36
        s.firstMaterial = m
        let n = SCNNode(geometry: s)
        n.position = SCNVector3(x, y, z)
        n.scale = scale
        return n
    }

    // MARK: 西游记的图案
    /// 金箍棒：竖着的红漆棒，两头是金箍，脚下一朵祥云
    static func staff() -> SCNNode {
        let node = SCNNode()
        let body = SCNCylinder(radius: 0.17, height: 1.36)
        body.radialSegmentCount = 40
        body.firstMaterial = lacquer(UIColor(red: 0.8, green: 0.05, blue: 0.06, alpha: 1), glow: 0.35, rough: 0.25)
        node.addChildNode(SCNNode(geometry: body))
        for side in [Float(1), -1] {
            let cap = SCNCylinder(radius: 0.22, height: 0.34)
            cap.radialSegmentCount = 40
            cap.firstMaterial = gold(rough: 0.16)
            let c = SCNNode(geometry: cap)
            c.position = SCNVector3(0, side * 0.82, 0)
            node.addChildNode(c)
            for dy in [Float(-0.17), 0, 0.17] {
                let t = SCNTorus(ringRadius: 0.225, pipeRadius: 0.04)
                t.ringSegmentCount = 40
                t.firstMaterial = gold(rough: 0.1)
                let r = SCNNode(geometry: t)
                r.position = SCNVector3(0, side * 0.82 + dy, 0)
                node.addChildNode(r)
            }
            node.addChildNode(ball(0.14, gold(rough: 0.1), 0, side * 1.03, 0))
        }
        // 祥云：一团珍珠色的球，垫在棒子后面
        let cloud = lacquer(UIColor(red: 1.0, green: 0.93, blue: 0.8, alpha: 1), glow: 0.25, rough: 0.35)
        for (x, y, r) in [(-0.55, -0.5, 0.26), (-0.28, -0.36, 0.3), (0.28, -0.36, 0.3), (0.55, -0.5, 0.26), (0, -0.56, 0.3), (-0.78, -0.62, 0.17), (0.78, -0.62, 0.17)] as [(Float, Float, CGFloat)] {
            node.addChildNode(ball(r, cloud, x, y, -0.3, scale: SCNVector3(1, 0.8, 0.6)))
        }
        node.scale = SCNVector3(0.94, 0.94, 0.94)
        return node
    }

    /// 紧箍：一道金圈，正面两个卷起来的云头，中间一颗红宝石。从前上方看（左右对称）
    static func headband() -> SCNNode {
        let node = SCNNode()
        let hoop = SCNNode()
        let t = SCNTorus(ringRadius: 0.84, pipeRadius: 0.1)
        t.ringSegmentCount = 72
        t.pipeSegmentCount = 24
        t.firstMaterial = gold(rough: 0.14)
        hoop.addChildNode(SCNNode(geometry: t))
        let thin = SCNTorus(ringRadius: 0.84, pipeRadius: 0.035)
        thin.ringSegmentCount = 72
        thin.firstMaterial = gold(rough: 0.08)
        let thinNode = SCNNode(geometry: thin)
        thinNode.position = SCNVector3(0, 0.12, 0)
        hoop.addChildNode(thinNode)
        // 正面的两个云头（立着的小圈）和宝石
        for side in [Float(-1), 1] {
            let curl = SCNTorus(ringRadius: 0.15, pipeRadius: 0.05)
            curl.firstMaterial = gold(rough: 0.1)
            let c = SCNNode(geometry: curl)
            c.eulerAngles.x = .pi / 2
            c.position = SCNVector3(side * 0.2, 0.2, 0.86)
            hoop.addChildNode(c)
        }
        hoop.addChildNode(ball(0.12, lacquer(UIColor(red: 0.9, green: 0.05, blue: 0.1, alpha: 1), glow: 0.5, rough: 0.1), 0, 0.12, 0.92))
        hoop.eulerAngles.x = 0.62
        node.addChildNode(hoop)
        node.position = SCNVector3(0, -0.08, 0)
        node.scale = SCNVector3(1.14, 1.14, 1.14)
        return node
    }

    /// 蟠桃：尖头朝上的桃子，从底下的奶黄过渡到顶上的桃红，两片绿叶
    static func peach() -> SCNNode {
        let node = SCNNode()
        let m = lacquer(.white, glow: 0.25, rough: 0.35)
        let skin = gradientImage([(UIColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1), 0.0), (UIColor(red: 1.0, green: 0.5, blue: 0.4, alpha: 1), 0.32),
                                  (UIColor(red: 0.92, green: 0.2, blue: 0.3, alpha: 1), 0.68), (UIColor(red: 0.75, green: 0.05, blue: 0.18, alpha: 1), 1.0)])
        m.diffuse.contents = skin
        m.emission.contents = skin
        m.emission.intensity = 0.1
        m.multiply.contents = UIColor(white: 0.7, alpha: 1)
        m.clearCoat.contents = 0.4
        let g = lathe([(0, -0.82), (0.42, -0.74), (0.76, -0.38), (0.86, 0.04), (0.72, 0.44), (0.42, 0.72), (0.14, 0.92), (0, 1.0)], material: m)
        node.addChildNode(SCNNode(geometry: g))
        let leaf = lacquer(UIColor(red: 0.12, green: 0.6, blue: 0.2, alpha: 1), glow: 0.3, rough: 0.3)
        for side in [Float(-1), 1] {
            let l = ball(0.5, leaf, side * 0.62, -0.7, 0.12, scale: SCNVector3(1, 0.3, 0.42))
            l.eulerAngles.z = side * 0.45
            node.addChildNode(l)
        }
        node.scale = SCNVector3(0.98, 0.98, 0.98)
        node.position = SCNVector3(0, -0.04, 0)
        return node
    }

    /// 葫芦：金葫芦，腰上系一条红绸
    static func gourd() -> SCNNode {
        let node = SCNNode()
        let g = lathe([(0, -0.95), (0.4, -0.9), (0.66, -0.58), (0.66, -0.26), (0.42, 0.06), (0.24, 0.2), (0.36, 0.42), (0.4, 0.6), (0.27, 0.8), (0.11, 0.9), (0.08, 1.0), (0, 1.02)],
                      material: gold(rough: 0.16))
        node.addChildNode(SCNNode(geometry: g))
        let silk = lacquer(UIColor(red: 0.9, green: 0.06, blue: 0.08, alpha: 1), glow: 0.35, rough: 0.4)
        let band = SCNTorus(ringRadius: 0.27, pipeRadius: 0.07)
        band.ringSegmentCount = 48
        band.firstMaterial = silk
        let bandNode = SCNNode(geometry: band)
        bandNode.position = SCNVector3(0, 0.2, 0)
        node.addChildNode(bandNode)
        // 蝴蝶结：两片 + 中间的结
        for side in [Float(-1), 1] {
            let b = ball(0.2, silk, side * 0.2, 0.2, 0.3, scale: SCNVector3(1, 0.6, 0.4))
            b.eulerAngles.z = side * 0.3
            node.addChildNode(b)
            let tail = ball(0.16, silk, side * 0.12, -0.02, 0.36, scale: SCNVector3(0.45, 1, 0.3))
            tail.eulerAngles.z = side * -0.3
            node.addChildNode(tail)
        }
        node.addChildNode(ball(0.08, silk, 0, 0.2, 0.36))
        node.scale = SCNVector3(0.95, 0.95, 0.95)
        return node
    }

    // MARK: 希腊神话的图案
    /// 头盔：科林斯式的金盔（T 形的面部开口），头顶一道横着的红色马鬃冠
    static func helmet() -> SCNNode {
        let node = SCNNode()
        let g = lathe([(0.6, -0.9), (0.66, -0.55), (0.76, -0.05), (0.74, 0.35), (0.56, 0.7), (0.28, 0.88), (0, 0.94)], material: gold(rough: 0.16))
        node.addChildNode(SCNNode(geometry: g))
        // 面部的开口：两只杏核形的眼孔 + 下面一道竖缝（中间留着护鼻）
        let dark = lacquer(UIColor(red: 0.03, green: 0.03, blue: 0.08, alpha: 1), glow: 0, rough: 0.6)
        dark.clearCoat.contents = 0
        for side in [Float(-1), 1] {
            let eye = ball(0.2, dark, side * 0.27, 0.02, 0.7, scale: SCNVector3(1, 0.5, 0.4))
            eye.eulerAngles.z = side * -0.2
            node.addChildNode(eye)
        }
        let slit = SCNNode(geometry: SCNBox(width: 0.17, height: 0.78, length: 0.3, chamferRadius: 0.06))
        slit.geometry!.firstMaterial = dark
        slit.position = SCNVector3(0, -0.56, 0.58)
        node.addChildNode(slit)
        // 眼孔上面的一道眉弓、盔沿
        let brow = SCNTorus(ringRadius: 0.75, pipeRadius: 0.04)
        brow.ringSegmentCount = 64
        brow.firstMaterial = gold(rough: 0.1)
        let browNode = SCNNode(geometry: brow)
        browNode.position = SCNVector3(0, 0.22, 0)
        node.addChildNode(browNode)
        // 横冠：一把扇形的红色马鬃，底下一道金托
        func fan(_ r0: CGFloat, _ r1: CGFloat, depth: CGFloat, _ m: SCNMaterial, z: Float) {
            let p = UIBezierPath()
            p.addArc(withCenter: .zero, radius: r1, startAngle: .pi * 0.08, endAngle: .pi * 0.92, clockwise: true)
            p.addArc(withCenter: .zero, radius: r0, startAngle: .pi * 0.92, endAngle: .pi * 0.08, clockwise: false)
            p.close()
            p.flatness = 0.004
            let shape = SCNShape(path: p, extrusionDepth: depth)
            shape.chamferRadius = min(0.04, depth / 3)
            shape.materials = [m]
            let n = SCNNode(geometry: shape)
            n.position = SCNVector3(0, 0.1, z)
            node.addChildNode(n)
        }
        fan(0.9, 1.34, depth: 0.16, lacquer(UIColor(red: 0.5, green: 0.0, blue: 0.02, alpha: 1), glow: 0.3, rough: 0.6), z: 0)
        fan(0.84, 0.94, depth: 0.22, gold(rough: 0.12), z: 0)
        node.scale = SCNVector3(0.74, 0.74, 0.74)
        node.position = SCNVector3(0, -0.2, 0)
        return node
    }

    /// 盾牌：圆盾，金边、蓝珐琅、中间一颗凸起的盾心和八道光芒
    static func shield() -> SCNNode {
        let node = SCNNode()
        node.addChildNode(disc(radius: 1.0, depth: 0.14, gold(rough: 0.16)))
        node.addChildNode(disc(radius: 0.8, depth: 0.05, lacquer(UIColor(red: 0.03, green: 0.18, blue: 0.62, alpha: 1), glow: 0.2, rough: 0.25), z: 0.07))
        node.addChildNode(ring(radius: 0.9, pipe: 0.1, gold(rough: 0.12), z: 0.07))
        node.addChildNode(ring(radius: 0.5, pipe: 0.035, gold(rough: 0.1), z: 0.1))
        for k in 0..<8 {
            let a = Float(k) * .pi / 4
            let d = simd_float3(cos(a), sin(a), 0)
            let ray = SCNCone(topRadius: 0, bottomRadius: 0.085, height: 0.34)
            ray.radialSegmentCount = 4
            ray.firstMaterial = gold(rough: 0.12)
            let n = SCNNode(geometry: ray)
            n.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: d)
            n.simdPosition = d * 0.42 + simd_float3(0, 0, 0.11)
            n.scale = SCNVector3(1, 1, 0.5)
            node.addChildNode(n)
        }
        node.addChildNode(ball(0.24, gold(rough: 0.1), 0, 0, 0.1, scale: SCNVector3(1, 1, 0.55)))
        // 边上一圈铆钉
        for k in 0..<12 {
            let a = Float(k) * .pi / 6
            node.addChildNode(ball(0.045, gold(rough: 0.08), cos(a) * 0.9, sin(a) * 0.9, 0.17))
        }
        node.scale = SCNVector3(0.98, 0.98, 0.98)
        return node
    }

    /// 橄榄花环：一圈金叶子，上面留个口，底下系红绸
    static func wreath() -> SCNNode {
        let node = SCNNode()
        let leafA = gold(rough: 0.14), leafB = gold(rough: 0.3)
        let count = 22
        for k in 0..<count {
            // 从底下往两边排上去，顶上留一个口
            let half = k % 2 == 0 ? Float(1) : -1
            let step = Float(k / 2)
            let a = -Float.pi / 2 + half * (0.22 + step * 0.26)
            let outer = (k / 2) % 2 == 0
            let r: Float = outer ? 0.84 : 0.66
            let leaf = ball(0.26, outer ? leafA : leafB, cos(a) * r, sin(a) * r, outer ? 0.04 : 0, scale: SCNVector3(1, 0.4, 0.22))
            // 叶尖朝着往上走的方向，外圈的往外撇、内圈的往里撇
            leaf.eulerAngles.z = a + half * (.pi / 2) + half * (outer ? -0.45 : 0.45)
            node.addChildNode(leaf)
        }
        let stem = SCNTorus(ringRadius: 0.75, pipeRadius: 0.03)
        stem.ringSegmentCount = 64
        stem.firstMaterial = gold(rough: 0.2)
        let stemNode = SCNNode(geometry: stem)
        stemNode.eulerAngles.x = .pi / 2
        stemNode.position.z = -0.04
        node.addChildNode(stemNode)
        let silk = lacquer(UIColor(red: 0.9, green: 0.06, blue: 0.08, alpha: 1), glow: 0.35, rough: 0.4)
        for side in [Float(-1), 1] {
            let b = ball(0.2, silk, side * 0.2, -0.78, 0.14, scale: SCNVector3(1, 0.6, 0.4))
            b.eulerAngles.z = side * 0.3
            node.addChildNode(b)
        }
        node.addChildNode(ball(0.09, silk, 0, -0.78, 0.2))
        node.position = SCNVector3(0, 0.04, 0)
        return node
    }

    /// 双耳瓶：陶土色的瓶身，黑色的纹带，两只耳
    static func amphora() -> SCNNode {
        let node = SCNNode()
        let clay = UIColor(red: 0.86, green: 0.4, blue: 0.16, alpha: 1), black = UIColor(red: 0.08, green: 0.05, blue: 0.05, alpha: 1)
        let goldC = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        let m = lacquer(.white, glow: 0.2, rough: 0.3)
        let skin = gradientImage([(black, 0), (black, 0.09), (clay, 0.1), (clay, 0.3), (goldC, 0.31), (black, 0.33), (black, 0.52), (goldC, 0.54), (clay, 0.56),
                                  (clay, 0.7), (black, 0.71), (black, 0.76), (clay, 0.77), (clay, 0.92), (black, 0.93), (black, 1)])
        m.diffuse.contents = skin
        m.emission.contents = skin
        m.emission.intensity = 0.1
        let g = lathe([(0, -1.0), (0.27, -1.0), (0.29, -0.9), (0.2, -0.8), (0.42, -0.5), (0.6, -0.1), (0.58, 0.2), (0.4, 0.48), (0.2, 0.62), (0.17, 0.8), (0.2, 0.9), (0.31, 0.97), (0.31, 1.0), (0.2, 1.0)],
                      material: m)
        node.addChildNode(SCNNode(geometry: g))
        for side in [Float(-1), 1] {
            let h = SCNTorus(ringRadius: 0.2, pipeRadius: 0.045)
            h.ringSegmentCount = 40
            h.firstMaterial = lacquer(black, glow: 0, rough: 0.3)
            let n = SCNNode(geometry: h)
            n.eulerAngles.x = .pi / 2
            n.scale = SCNVector3(0.9, 1, 1.25)
            n.position = SCNVector3(side * 0.36, 0.66, 0)
            node.addChildNode(n)
        }
        node.scale = SCNVector3(0.96, 0.96, 0.96)
        return node
    }

    // MARK: 立体的大字（大奖、财神到……）
    private static var titleCache: [String: UIImage] = [:]

    /// 一行厚厚的立体字：正面是亮漆的颜色，侧面和倒角是金的。图的宽高比 3:1
    static func title(_ string: String, front: UIColor = UIColor(red: 0.95, green: 0.1, blue: 0.08, alpha: 1)) -> UIImage? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        front.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = "\(string)|\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255))"
        lock.lock(); defer { lock.unlock() }
        if let c = titleCache[key] { return c }
        let (scene, cam, root) = makeScene()
        // 中文用苹方，其他用圆体
        let hasCJK = string.unicodeScalars.contains { $0.value >= 0x2E80 }
        let base = UIFont.systemFont(ofSize: 10, weight: .black)
        let font = hasCJK ? (UIFont(name: "PingFangSC-Semibold", size: 10) ?? base)
                          : (base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 10) } ?? base)
        // 汉字不做倒角：SCNText 给某些字（財神駕到、鎖定重轉、超級大獎）加倒角时会把网格算坏，画出一大片刺或一整块
        // 英文的长句（GOD OF WEALTH!）带倒角时同样会算坏，所以大字一律不做倒角
        let t = text(string, font: font, depth: hasCJK ? 2.6 : 3.2, chamfer: 0, front: lacquer(front, glow: 0.55, rough: 0.22), side: gold(rough: 0.14), height: 1.5, width: 6.2)
        // 保险：网格的外框离谱（字号 10 的一行字，高应该在 5–16 之间，宽不超过每个字 13）就不用这张图，画面退回普通的金字
        let (lo, hi) = t.geometry?.boundingBox ?? (SCNVector3Zero, SCNVector3Zero)
        let boxH = hi.y - lo.y, boxW = hi.x - lo.x
        guard boxH > 5, boxH < 16, boxW < Float(string.count) * 13 + 5 else { return nil }
        let holder = SCNNode()
        holder.addChildNode(t)
        root.addChildNode(holder)
        let img = snapshot(scene, cam, size: CGSize(width: 1080, height: 360))
        if let img { titleCache[key] = img }
        return img
    }

    // MARK: 机器外框
    /// 转轮外面的金框：size 是整张图的大小（点），window 是中间留给转轮的洞。框的截面是倒圆的金条，里面一圈红漆，四角各一颗金钉，上面正中一只元宝
    static func frame(size: CGSize, window: CGRect, scale: CGFloat, theme: SlotTheme = .caishen) -> UIImage? {
        let key = "\(theme.rawValue)-\(Int(size.width))x\(Int(size.height))-\(Int(window.width))x\(Int(window.height))"
        lock.lock(); defer { lock.unlock() }
        if let c = frameCache[key] { return c }
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 2.2
        // 1 个单位 = 100 点；正交相机正对着看
        let u: CGFloat = 0.01
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true
        cam.camera!.orthographicScale = Double(size.height * u / 2)
        cam.camera!.zNear = 0.1
        cam.camera!.zFar = 50
        cam.position = SCNVector3(0, 0, 10)
        scene.rootNode.addChildNode(cam)
        let key1 = SCNNode()
        key1.light = SCNLight()
        key1.light!.type = .directional
        key1.light!.intensity = 900
        key1.eulerAngles = SCNVector3(-0.8, -0.4, 0)
        scene.rootNode.addChildNode(key1)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 250
        scene.rootNode.addChildNode(amb)

        // 窗口在图里的位置 → 以图中心为原点、y 向上的坐标
        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: (r.minX - size.width / 2) * u, y: (size.height / 2 - r.maxY) * u, width: r.width * u, height: r.height * u)
        }
        func band(outer: CGRect, inner: CGRect, radius: CGFloat, depth: CGFloat, chamfer: CGFloat, _ m: SCNMaterial, z: Float) {
            let p = UIBezierPath(roundedRect: rect(outer), cornerRadius: radius * u)
            p.append(UIBezierPath(roundedRect: rect(inner), cornerRadius: max(2, radius - (inner.minX - outer.minX)) * u).reversing())
            p.usesEvenOddFillRule = true
            p.flatness = 0.002
            let g = SCNShape(path: p, extrusionDepth: depth)
            g.chamferRadius = chamfer
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position.z = z
            scene.rootNode.addChildNode(n)
        }
        let t: CGFloat = 13
        let outer = window.insetBy(dx: -t, dy: -t)
        band(outer: outer, inner: window.insetBy(dx: -4, dy: -4), radius: 16, depth: 0.16, chamfer: 0.045, gold(rough: 0.16), z: 0)
        band(outer: window.insetBy(dx: -5, dy: -5), inner: window, radius: 9, depth: 0.1, chamfer: 0.02, lacquer(theme.enamel, glow: 0.3), z: -0.02)
        for (x, y) in [(outer.minX + 5, outer.minY + 5), (outer.maxX - 5, outer.minY + 5), (outer.minX + 5, outer.maxY - 5), (outer.maxX - 5, outer.maxY - 5)] {
            let s = SCNSphere(radius: 7 * u)
            s.segmentCount = 32
            s.firstMaterial = gold(rough: 0.1)
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(Float((x - size.width / 2) * u), Float((size.height / 2 - y) * u), 0.1)
            scene.rootNode.addChildNode(n)
        }
        // 上面正中：红漆的小牌 + 元宝
        let plate = SCNNode(geometry: SCNBox(width: 86 * u, height: 26 * u, length: 0.18, chamferRadius: 0.05))
        plate.geometry!.firstMaterial = gold(rough: 0.16)
        plate.position = SCNVector3(0, Float((size.height / 2 - outer.minY - 2) * u), 0.05)
        scene.rootNode.addChildNode(plate)
        // 牌子上的摆件：这台机器最值钱的那个图案
        let top = theme == .wukong ? peach() : (theme == .athena ? shield() : ingot())
        let k = Float((theme == .caishen ? 22 : 15) * u)
        top.scale = SCNVector3(k, k, k)
        if theme == .caishen { top.eulerAngles = SCNVector3(0.5, 0, 0) }
        top.position = SCNVector3(0, Float((size.height / 2 - outer.minY + 6) * u), 0.4)
        scene.rootNode.addChildNode(top)

        let img = snapshot(scene, cam, size: CGSize(width: size.width * scale, height: size.height * scale))
        if let img { frameCache[key] = img }
        return img
    }

    #if DEBUG
    /// 调试：-dumpIcons <目录> 把所有图案渲染出来写成 PNG（模拟器上直接写到 Mac 的目录里），方便对着看
    static func debugDumpIfAsked() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-dumpIcons"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        var all: [(String, UIImage)] = []
        let theme = SlotTheme.launchTheme ?? .caishen
        for s in CaishenSymbol.allCases { if let img = image(.symbol(s, theme)) { all.append(("\(s)", img)) } }
        if let img = image(.blankCoin) { all.append(("blankCoin", img)) }
        if let img = image(.pile) { all.append(("pile", img)) }
        // 一张总览：深红底，5 个一行
        let cell: CGFloat = 240
        let rows = (all.count + 4) / 5
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: cell * 5, height: cell * CGFloat(rows)), format: fmt).image { ctx in
            UIColor(red: 0.2, green: 0.02, blue: 0.04, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: cell * 5, height: cell * CGFloat(rows)))
            for (k, item) in all.enumerated() {
                item.1.draw(in: CGRect(x: CGFloat(k % 5) * cell + 10, y: CGFloat(k / 5) * cell + 10, width: cell - 20, height: cell - 20))
            }
        }
        try? sheet.pngData()?.write(to: dir.appendingPathComponent("icons_sheet.png"))
        // 立体字：简繁都导出来看（有的字形 SCNText 会画坏）
        for (k, str) in ["财神驾到！", "財神駕到！", "GOD OF WEALTH!", "THE MONKEY KING!", "ATHENA DESCENDS!", "HOLD & RESPIN", "GRAND JACKPOT", "SUPER WIN!", "MEGA WIN!"].enumerated() {
            if let img = title(str) {
                let one = UIGraphicsImageRenderer(size: img.size, format: fmt).image { ctx in
                    UIColor(red: 0.2, green: 0.02, blue: 0.04, alpha: 1).setFill()
                    ctx.fill(CGRect(origin: .zero, size: img.size))
                    img.draw(at: .zero)
                }
                try? one.jpegData(compressionQuality: 0.8)?.write(to: dir.appendingPathComponent("title_\(k).jpg"))
            }
        }
        for (name, img) in all where name == "ingot" || name == "pile" {
            // 单张的垫上深色底再存（透明底的图在看图工具里是白底，看不清金色）
            let one = UIGraphicsImageRenderer(size: img.size, format: fmt).image { ctx in
                UIColor(red: 0.2, green: 0.02, blue: 0.04, alpha: 1).setFill()
                ctx.fill(CGRect(origin: .zero, size: img.size))
                img.draw(at: .zero)
            }
            try? one.pngData()?.write(to: dir.appendingPathComponent("\(name).png"))
        }
        if let f = frame(size: CGSize(width: 400, height: 330), window: CGRect(x: 20, y: 40, width: 360, height: 270), scale: 2, theme: theme) {
            try? f.pngData()?.write(to: dir.appendingPathComponent("frame.png"))
        }
    }
    #endif
}
