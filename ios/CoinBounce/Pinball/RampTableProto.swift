import SwiftUI
import SceneKit

// MARK: - v14 弹珠台立体样台（hj 11-28：第一稿「完全没有 3D 触感」，推倒重做）
// 这是给 hj 判断手感用的骨架，不是成品：球用 SceneKit 的真 3D 物理在倾斜的台面上滚，能冲上坡道、
// 沿铁丝轨道绕回左边；相机低角度跟着球走。不计分、不花币。入口：-startPinball -pinballProto（加 -pinballDemo 自动打）。
final class RampTableScene: NSObject, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let table = SCNNode()          // 整张台面（最后整体后仰 tilt 度）
    private var ball = SCNNode()
    private var bumperCaps: [SCNNode] = []
    private var pyramidTop = SCNNode()
    private let camPos = SCNVector3(0, 21.4, 15.6), camLook = SCNVector3(0, 0.5, 1.0)
    private let args = ProcessInfo.processInfo.arguments
    private lazy var demo = args.contains("-pinballDemo")
    private lazy var logging = args.contains("-protoLog")
    private var lastLaunch: TimeInterval = 0
    private var pendingLaunch = false
    private var slowSince: TimeInterval?
    private var lastTime: TimeInterval = 0
    private var lastLog: TimeInterval = 0
    private var onRail = false
    /// 得分（样台先有个数：蘑菇柱 100、弹射 10、金字塔靶 500、走完铁丝轨道 1000）
    var onScore: ((Int) -> Void)?
    private func score(_ n: Int) { DispatchQueue.main.async { self.onScore?(n) } }

    /// 一块挡板：角度自己一帧一帧推（不用动作），这样知道它这一帧扫过了哪里、转得多快，
    /// 球被扫到时按「板面速度」算出球该飞多快——只靠物理引擎的话，板一帧转十几度，球经常被穿过去或者只是被挤开
    private final class Flipper {
        let node = SCNNode()
        let left: Bool
        let pivot: SCNVector3
        var angle: Float
        var wantUp = false
        var kicked = false
        var botRelease: TimeInterval = 0, botCooldown: TimeInterval = 0
        var rest: Float { left ? -0.44 : 0.44 }
        var up: Float { left ? 0.52 : -0.52 }
        init(left: Bool, pivot: SCNVector3) { self.left = left; self.pivot = pivot; angle = left ? -0.44 : 0.44 }
        /// 板的方向（从轴指向板尖）和朝台面远端的法线，台面坐标的 (x, z)
        var dir: (Float, Float) { left ? (cos(angle), -sin(angle)) : (-cos(angle), sin(angle)) }
        var normal: (Float, Float) { (-sin(angle), -cos(angle)) }
        /// 球相对板：沿板的距离 a、离板面中线的高度 h
        func local(_ p: SCNVector3) -> (a: Float, h: Float) {
            let rx = p.x - pivot.x, rz = p.z - pivot.z
            return (rx * dir.0 + rz * dir.1, rx * normal.0 + rz * normal.1)
        }
    }
    private let flipperL = Flipper(left: true, pivot: SCNVector3(-2.7, 0.27, 7.3))
    private let flipperR = Flipper(left: false, pivot: SCNVector3(1.9, 0.27, 7.3))
    static let flipperLength: Float = 1.75
    static let flipUpRate: Float = 15, flipDownRate: Float = 9      // 弧度/秒

    static let tilt: Float = 9 * .pi / 180
    static let ballR: CGFloat = 0.28
    private static let catBall = 1, catTable = 2, catBumper = 4, catTarget = 8

    override init() {
        super.init()
        build()
    }

    // MARK: 材质
    private func pbr(_ c: UIColor, metal: CGFloat, rough: CGFloat, glow: UIColor? = nil, intensity: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let glow { m.emission.contents = glow; m.emission.intensity = intensity }
        return m
    }
    private lazy var chrome = pbr(UIColor(white: 0.92, alpha: 1), metal: 1, rough: 0.12)
    private lazy var gold = pbr(UIColor(red: 1, green: 0.76, blue: 0.25, alpha: 1), metal: 1, rough: 0.22)
    private lazy var wood = pbr(UIColor(red: 0.09, green: 0.03, blue: 0.015, alpha: 1), metal: 0, rough: 0.85)
    private lazy var sand = pbr(UIColor(red: 0.8, green: 0.6, blue: 0.34, alpha: 1), metal: 0.1, rough: 0.7)
    private lazy var rubber = pbr(UIColor(red: 0.85, green: 0.08, blue: 0.14, alpha: 1), metal: 0, rough: 0.4)
    private lazy var invisible: SCNMaterial = {
        let m = SCNMaterial(); m.colorBufferWriteMask = []; m.writesToDepthBuffer = false; return m
    }()

    // MARK: 搭建
    private func staticBody(_ g: SCNGeometry, restitution: CGFloat, friction: CGFloat, category: Int = catTable) -> SCNPhysicsBody {
        let b = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: g, options: nil))
        b.restitution = restitution
        b.friction = friction
        b.categoryBitMask = category
        b.contactTestBitMask = category == Self.catTable ? 0 : Self.catBall
        return b
    }

    @discardableResult
    private func solid(_ g: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3, restitution: CGFloat = 0.35, friction: CGFloat = 0.25, category: Int = catTable,
                       in parent: SCNNode? = nil) -> SCNNode {
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.position = p
        n.physicsBody = staticBody(g, restitution: restitution, friction: friction, category: category)
        (parent ?? table).addChildNode(n)
        return n
    }

    /// 从 a 到 b 的一堵墙（台面坐标，y 是墙底的高度）
    @discardableResult
    private func wall(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float, y: Float = 0, height: Float = 0.9, thick: Float = 0.22,
                      _ m: SCNMaterial? = nil, restitution: CGFloat = 0.4) -> SCNNode {
        let len = hypot(bx - ax, bz - az)
        let n = solid(SCNBox(width: CGFloat(len + thick), height: CGFloat(height), length: CGFloat(thick), chamferRadius: 0.04), m ?? chrome,
                      at: SCNVector3((ax + bx) / 2, y + height / 2, (az + bz) / 2), restitution: restitution)
        n.eulerAngles.y = -atan2(bz - az, bx - ax)
        return n
    }

    private func build() {
        // 物理：重力加大、台面斜 9 度（球沿台面的加速度约 11，接近真机的手感），步长细一点防止球穿墙
        scene.physicsWorld.gravity = SCNVector3(0, -70, 0)
        scene.physicsWorld.timeStep = 1.0 / 240
        scene.physicsWorld.contactDelegate = self
        scene.background.contents = UIColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)

        // 台面：10 宽、20 长，远端在 -z。碰撞用一块看不见的厚板，画贴在一张平面上
        solid(SCNBox(width: 10, height: 0.4, length: 20, chamferRadius: 0), invisible, at: SCNVector3(0, -0.2, 0), friction: 0.12)
        let floorM = pbr(.white, metal: 0, rough: 0.5)
        floorM.diffuse.contents = UIImage(named: "PinballPharaohField")
        floorM.clearCoat.contents = 0.06
        floorM.clearCoatRoughness.contents = 0.15
        let art = SCNNode(geometry: SCNPlane(width: 10, height: 20))
        art.geometry!.firstMaterial = floorM
        art.eulerAngles.x = -.pi / 2
        table.addChildNode(art)
        // 玻璃盖（看不见）：球飞不出去
        solid(SCNBox(width: 10, height: 0.2, length: 20, chamferRadius: 0), invisible, at: SCNVector3(0, 2.9, 0))
        // 机柜：两侧和远端高，靠玩家这边矮（不挡挡板）；再往外一块台沿，镜头下面不露黑
        for (x, z, w, l) in [(Float(-5.3), Float(0), Float(0.6), Float(21.2)), (5.3, 0, 0.6, 21.2), (0, -10.3, 11.2, 0.6)] {
            solid(SCNBox(width: CGFloat(w), height: 1.8, length: CGFloat(l), chamferRadius: 0.1), wood, at: SCNVector3(x, 0.5, z))
        }
        solid(SCNBox(width: 11.2, height: 1.2, length: 0.6, chamferRadius: 0.1), wood, at: SCNVector3(0, 0.2, 10.3))
        // 四边再各加一堵看不见的高墙，一直顶到玻璃：球被弹飞起来也翻不出机柜
        for (x, z, w, l) in [(Float(-5.3), Float(0), Float(0.6), Float(21.2)), (5.3, 0, 0.6, 21.2), (0, -10.3, 11.2, 0.6), (0, 10.3, 11.2, 0.6)] {
            solid(SCNBox(width: CGFloat(w), height: 3.2, length: CGFloat(l), chamferRadius: 0), invisible, at: SCNVector3(x, 1.4, z))
        }
        let apron = SCNNode(geometry: SCNBox(width: 11.2, height: 1.2, length: 4, chamferRadius: 0.1))
        apron.geometry!.firstMaterial = wood
        apron.position = SCNVector3(0, 0.19, 12.6)
        table.addChildNode(apron)
        let trim = SCNNode(geometry: SCNBox(width: 11.2, height: 0.08, length: 0.14, chamferRadius: 0.03))
        trim.geometry!.firstMaterial = gold
        trim.position = SCNVector3(0, 0.82, 10.05)
        table.addChildNode(trim)
        // 背板：立在远端的灯箱画（真机的 backglass）
        let glassM = SCNMaterial()
        glassM.lightingModel = .constant
        glassM.diffuse.contents = UIImage(named: "PinballPharaohBackdrop")
        let back = SCNNode(geometry: SCNPlane(width: 11.2, height: 4.38))
        back.geometry!.firstMaterial = glassM
        back.position = SCNVector3(0, 1.4 + 2.19, -10.5)
        back.eulerAngles.x = -0.12
        table.addChildNode(back)
        let backTrim = SCNNode(geometry: SCNBox(width: 11.4, height: 0.16, length: 0.2, chamferRadius: 0.05))
        backTrim.geometry!.firstMaterial = gold
        backTrim.position = SCNVector3(0, 1.42, -10.2)
        table.addChildNode(backTrim)

        // 拱顶：半圆
        let n = 14
        for i in 0..<n {
            let a0 = Float.pi * Float(i) / Float(n), a1 = Float.pi * Float(i + 1) / Float(n)
            wall(5 * cos(a0), -5 - 5 * sin(a0), 5 * cos(a1), -5 - 5 * sin(a1), height: 1.0)
            wall(5.1 * cos(a0), -5 - 5.1 * sin(a0), 5.1 * cos(a1), -5 - 5.1 * sin(a1), y: 1.0, height: 1.8, invisible)   // 上面接一段看不见的，球翻不过拱顶
        }
        // 发射轨道的内墙；两侧通往挡板的斜导轨
        wall(4.2, -4.6, 4.2, 10)
        let slingL = wall(-5, 3.2, -2.9, 7.05, restitution: 0.25), slingR = wall(4.2, 3.2, 2.1, 7.05, restitution: 0.25)
        // 两条导轨带弹射：球撞得够重就被弹回场内（轻轻滚下来的不弹），外面套一圈红橡皮
        for (n, name) in [(slingL, "slingL"), (slingR, "slingR")] {
            n.name = name
            n.physicsBody?.categoryBitMask = Self.catBumper
            n.physicsBody?.contactTestBitMask = Self.catBall
            let band = SCNNode(geometry: SCNBox(width: 4.5, height: 0.22, length: 0.3, chamferRadius: 0.1))
            band.geometry!.firstMaterial = rubber
            band.position = SCNVector3(0, 0.05, 0)
            n.addChildNode(band)
        }
        // 发射轨道底下的挡块
        solid(SCNBox(width: 0.8, height: 0.8, length: 0.4, chamferRadius: 0.05), rubber, at: SCNVector3(4.6, 0.4, 9.4), restitution: 0.1)

        buildFlippers()
        buildBumpers()
        buildRamp()
        buildPyramid()
        buildBall()
        buildLightsAndCamera()

        table.eulerAngles.x = Self.tilt
        scene.rootNode.addChildNode(table)
    }

    private func buildFlippers() {
        for f in [flipperL, flipperR] {
            let dir: Float = f.left ? 1 : -1
            let L = CGFloat(Self.flipperLength)
            f.node.position = f.pivot
            f.node.eulerAngles.y = f.angle
            let g = SCNBox(width: L, height: 0.5, length: 0.34, chamferRadius: 0.16)
            g.firstMaterial = pbr(UIColor(red: 0.92, green: 0.1, blue: 0.18, alpha: 1), metal: 0.1, rough: 0.25, glow: UIColor(red: 0.5, green: 0, blue: 0.08, alpha: 1), intensity: 0.5)
            let b = SCNNode(geometry: g)
            b.position = SCNVector3(dir * Float(L) / 2, 0, 0)
            f.node.addChildNode(b)
            // 碰撞体挂在轴上（形状往板的方向偏半个板长），跟着轴转
            let shape = SCNPhysicsShape(shapes: [SCNPhysicsShape(geometry: g, options: nil)],
                                        transforms: [NSValue(scnMatrix4: SCNMatrix4MakeTranslation(dir * Float(L) / 2, 0, 0))])
            let body = SCNPhysicsBody(type: .kinematic, shape: shape)
            body.restitution = 0.3
            body.friction = 0.4
            body.categoryBitMask = Self.catTable
            f.node.physicsBody = body
            let cap = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.56))
            cap.geometry!.firstMaterial = chrome
            f.node.addChildNode(cap)
            table.addChildNode(f.node)
        }
    }

    func setFlipper(left: Bool, up: Bool) {
        let f = left ? flipperL : flipperR
        guard f.wantUp != up else { return }
        f.wantUp = up
        if up { HapticManager.shared.slotColumnStop() }
    }

    /// 每帧推挡板的角度；板往上扫的时候碰到球，就按板面在那一点的速度把球打出去
    private func stepFlipper(_ f: Flipper, dt: Float, ballPos p: SCNVector3) {
        let target = f.wantUp ? f.up : f.rest
        if !f.wantUp { f.kicked = false }
        guard f.angle != target else { return }
        let rate = f.wantUp ? Self.flipUpRate : Self.flipDownRate
        let d = target - f.angle
        f.angle += abs(d) <= rate * dt ? d : (d > 0 ? 1 : -1) * rate * dt
        f.node.eulerAngles.y = f.angle
        guard f.wantUp, !f.kicked, p.y < 0.9, let body = ball.physicsBody else { return }
        let (a, h) = f.local(p)
        guard a > -0.05, a < Self.flipperLength + 0.25, h > -0.45, h < 0.5 else { return }
        let n = f.normal
        let v = table.convertVector(body.velocity, from: nil)
        let vn = v.x * n.0 + v.z * n.1
        let vs = Self.flipUpRate * max(a, 0.3)
        let out = vs + 0.35 * (vs - vn)
        guard out > vn else { return }
        let dv = table.convertVector(SCNVector3((out - vn) * n.0, 0, (out - vn) * n.1), to: nil)
        body.velocity = SCNVector3(body.velocity.x + dv.x, body.velocity.y + dv.y, body.velocity.z + dv.z)
        f.kicked = true
        if logging { print(String(format: "PB KICK %@ a=%.2f h=%.2f vn=%.1f out=%.1f", f.left ? "L" : "R", a, h, vn, out)) }
    }

    private func buildBumpers() {
        let colors = [UIColor(red: 1, green: 0.42, blue: 0.16, alpha: 1), UIColor(red: 0.1, green: 0.85, blue: 0.78, alpha: 1), UIColor(red: 1, green: 0.78, blue: 0.25, alpha: 1)]
        for (k, p) in [(Float(0.2), Float(-6.0)), (2.4, -5.2), (0.9, -3.6)].enumerated() {
            let body = solid(SCNCylinder(radius: 0.5, height: 0.9), pbr(UIColor(white: 0.1, alpha: 1), metal: 0.6, rough: 0.3), at: SCNVector3(p.0, 0.45, p.1),
                             restitution: 0.9, category: Self.catBumper)
            body.name = "bumper\(k)"
            let m = pbr(colors[k], metal: 0.2, rough: 0.25, glow: colors[k], intensity: 0.45)
            m.clearCoat.contents = 1.0
            let cap = SCNNode(geometry: SCNCylinder(radius: 0.68, height: 0.26))
            cap.geometry!.firstMaterial = m
            cap.position = SCNVector3(p.0, 1.02, p.1)
            table.addChildNode(cap)
            bumperCaps.append(cap)
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.55, pipeRadius: 0.06))
            ring.geometry!.firstMaterial = m
            ring.position = SCNVector3(p.0, 0.55, p.1)
            table.addChildNode(ring)
            let l = SCNNode()
            l.light = SCNLight()
            l.light!.type = .omni
            l.light!.color = colors[k]
            l.light!.intensity = 110
            l.light!.attenuationEndDistance = 5
            l.position = SCNVector3(p.0, 1.8, p.1)
            table.addChildNode(l)
        }
    }

    /// 坡道（从台面中左冲上二层）+ 铁丝轨道（在远端拐个 U 形弯，沿左墙把球送回左挡板上方）
    private func buildRamp() {
        // 坡道：z 1.5 → -4.5，升到 1.25 高。两边的护板一直落到台面，球钻不到坡道底下
        let rise: Float = 1.3, run: Float = 6
        let len = hypot(rise, run), ang = atan2(rise, run)
        let rampM = pbr(UIColor(red: 0.08, green: 0.3, blue: 0.36, alpha: 1), metal: 0.3, rough: 0.3, glow: UIColor(red: 0.1, green: 0.85, blue: 0.78, alpha: 1), intensity: 0.1)
        let sideM = pbr(UIColor(red: 0.16, green: 0.45, blue: 0.5, alpha: 1), metal: 0.7, rough: 0.3)
        let ramp = SCNNode()
        ramp.position = SCNVector3(-1.6, rise / 2 - 0.05, -1.5)
        ramp.eulerAngles.x = ang
        table.addChildNode(ramp)
        solid(SCNBox(width: 1.3, height: 0.1, length: CGFloat(len), chamferRadius: 0), rampM, at: SCNVector3Zero, restitution: 0.1, friction: 0.1, in: ramp)
        for dx: Float in [-0.7, 0.7] {
            solid(SCNBox(width: 0.1, height: 2.2, length: CGFloat(len), chamferRadius: 0.02), sideM, at: SCNVector3(dx, -0.55, 0), restitution: 0.3, in: ramp)
            let rail = SCNNode(geometry: SCNCylinder(radius: 0.06, height: CGFloat(len)))
            rail.geometry!.firstMaterial = chrome
            rail.eulerAngles.x = .pi / 2
            rail.position = SCNVector3(dx, 0.56, 0)
            ramp.addChildNode(rail)
        }
        // 坡道背面封成一个尖角（平的话球会停在上面）
        wall(-1.6, -5.25, -2.38, -4.4, height: 1.15, thick: 0.12, sideM, restitution: 0.3)
        wall(-1.6, -5.25, -0.82, -4.4, height: 1.15, thick: 0.12, sideM, restitution: 0.3)

        // 铁丝轨道经过的点：先在远端转 180 度（10 小段），再沿左墙一路往下，在 z=2 的地方把球放回台面
        var pts: [SCNVector3] = [SCNVector3(-1.6, 1.28, -4.5)]
        let cx: Float = -2.95, cz: Float = -4.5, r: Float = 1.35
        for i in 1...10 {
            let a = Float.pi * Float(i) / 10
            pts.append(SCNVector3(cx + r * cos(a), 1.28 - 0.014 * Float(i), cz - r * sin(a)))
        }
        pts += [SCNVector3(-4.3, 1.0, -2.5), SCNVector3(-4.3, 0.9, -0.5), SCNVector3(-4.3, 0.8, 1.0), SCNVector3(-4.3, 0.75, 2.0)]
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let d = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let l = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
            let seg = SCNNode()
            seg.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
            seg.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))   // 这时 table 还没后仰：台面坐标 = 世界坐标
            table.addChildNode(seg)
            solid(SCNBox(width: 1.0, height: 0.06, length: CGFloat(l + 0.12), chamferRadius: 0), invisible, at: SCNVector3(0, -0.03, 0), restitution: 0.05, friction: 0.05, in: seg)
            for dx: Float in [-0.46, 0.46] {
                solid(SCNBox(width: 0.08, height: 1.3, length: CGFloat(l + 0.1), chamferRadius: 0), invisible, at: SCNVector3(dx, 0.62, 0), restitution: 0.05, friction: 0.03, in: seg)
                // 看得见的是四根镀铬的管：下面两根托着球，上面两根拦着球
                for (ox, oy) in [(dx * 0.5, Float(-0.03)), (dx, Float(0.36))] {
                    let tube = SCNNode(geometry: SCNCylinder(radius: 0.065, height: CGFloat(l + 0.08)))
                    tube.geometry!.firstMaterial = chrome
                    tube.eulerAngles.x = .pi / 2
                    tube.position = SCNVector3(ox, oy, 0)
                    seg.addChildNode(tube)
                }
            }
        }
        // 轨道的支柱（只是样子，不挡球）
        for p in [pts[3], pts[8], pts[11], pts[12], pts[13]] {
            let post = SCNNode(geometry: SCNCylinder(radius: 0.05, height: CGFloat(p.y)))
            post.geometry!.firstMaterial = gold
            post.position = SCNVector3(p.x - 0.5, p.y / 2, p.z)
            table.addChildNode(post)
        }
    }

    /// 中央机关：一座金字塔。球打到塔前的靶子，塔尖升起来、亮一下
    private func buildPyramid() {
        // 看得见的是金字塔，碰撞用一个直上直下的方块（斜面会把球铲飞）
        let base = SCNNode(geometry: SCNPyramid(width: 2.2, height: 1.1, length: 2.2))
        base.geometry!.firstMaterial = pbr(UIColor(red: 0.95, green: 0.68, blue: 0.22, alpha: 1), metal: 0.9, rough: 0.38)
        base.position = SCNVector3(1.9, 0, -0.6)
        table.addChildNode(base)
        solid(SCNCylinder(radius: 1.0, height: 1.2), invisible, at: SCNVector3(1.9, 0.6, -0.6), restitution: 0.5)
        let tip = SCNPyramid(width: 0.9, height: 0.75, length: 0.9)
        tip.firstMaterial = pbr(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), metal: 1, rough: 0.15, glow: UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 1), intensity: 0.6)
        pyramidTop = SCNNode(geometry: tip)
        pyramidTop.position = SCNVector3(1.9, 0.72, -0.6)
        table.addChildNode(pyramidTop)
        let target = solid(SCNBox(width: 1.2, height: 0.7, length: 0.16, chamferRadius: 0.04),
                           pbr(UIColor(red: 0.75, green: 0.05, blue: 0.1, alpha: 1), metal: 0.2, rough: 0.3, glow: UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1), intensity: 0.7),
                           at: SCNVector3(1.9, 0.35, 0.75), restitution: 0.7, category: Self.catTarget)
        target.name = "target"
    }

    private func buildBall() {
        let g = SCNSphere(radius: Self.ballR)
        g.segmentCount = 32
        g.firstMaterial = pbr(UIColor(white: 0.95, alpha: 1), metal: 1, rough: 0.06)
        ball = SCNNode(geometry: g)
        let b = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: g, options: nil))
        b.mass = 1
        b.restitution = 0.45
        b.friction = 0.15
        b.rollingFriction = 0.02
        b.damping = 0.02
        b.angularDamping = 0.1
        b.categoryBitMask = Self.catBall
        b.contactTestBitMask = Self.catBumper | Self.catTarget
        b.continuousCollisionDetectionThreshold = Self.ballR
        ball.physicsBody = b
        table.addChildNode(ball)
        resetBall()
    }

    private var shotIndex = 0
    private func resetBall() {
        ball.physicsBody?.clearAllForces()
        ball.physicsBody?.velocity = SCNVector3Zero
        ball.physicsBody?.angularVelocity = SCNVector4Zero
        ball.position = SCNVector3(4.6, Float(Self.ballR) + 0.02, 8.6)
        ball.physicsBody?.resetTransform()
        // 调试：-protoRampShot 每次都从左挡板那里朝坡道口打一球，力度轮流换（检查坡道和铁丝轨道走不走得通）
        if args.contains("-protoRampShot") {
            let speeds: [Float] = [20, 23, 26, 29]
            let v = speeds[shotIndex % speeds.count]
            shotIndex += 1
            ball.position = SCNVector3(-1.6, Float(Self.ballR) + 0.02, 6.5)
            ball.physicsBody?.resetTransform()
            ball.physicsBody?.velocity = table.convertVector(SCNVector3(0, 0, -v), to: nil)
            if logging { print("PB SHOT v=\(v)") }
        }
    }

    func launch() { pendingLaunch = true }

    private func buildLightsAndCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 58
        cam.projectionDirection = .vertical
        cam.zNear = 0.5; cam.zFar = 120
        cam.wantsHDR = true
        cam.bloomIntensity = 0.5; cam.bloomThreshold = 0.9; cam.bloomBlurRadius = 5
        cam.exposureOffset = -0.5
        cam.wantsExposureAdaptation = false
        cam.vignettingIntensity = 0.6; cam.vignettingPower = 1.2
        cameraNode.camera = cam
        cameraNode.position = camPos
        cameraNode.look(at: camLook)
        scene.rootNode.addChildNode(cameraNode)
        // 暗场 + 一盏从玩家头顶打下来的聚光灯（带影子）
        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 140
        scene.rootNode.addChildNode(amb)
        let spot = SCNNode(); spot.light = SCNLight()
        spot.light!.type = .spot
        spot.light!.intensity = 800
        spot.light!.spotInnerAngle = 50; spot.light!.spotOuterAngle = 95
        spot.light!.castsShadow = true
        spot.light!.shadowRadius = 5
        spot.light!.shadowColor = UIColor.black.withAlphaComponent(0.6)
        spot.light!.shadowMapSize = CGSize(width: 2048, height: 2048)
        spot.position = SCNVector3(-6, 20, -4)
        spot.look(at: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(spot)
        scene.lightingEnvironment.contents = PusherScene3D.sharedCasinoEnvironment
        scene.lightingEnvironment.intensity = 0.9
    }

    // MARK: 每帧：挡板、相机跟球、掉球重来、发射、自动打
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(min(1.0 / 30, max(1.0 / 240, time - lastTime)))
        lastTime = time
        let p = ball.presentation.position            // 台面坐标
        let w = ball.presentation.worldPosition
        let v = table.convertVector(ball.physicsBody?.velocity ?? SCNVector3Zero, from: nil)
        // 掉进挡板中间，或者不知怎么飞出去了：回发射轨道
        if (p.z > 9.2 && p.x < 4.1) || p.y < -2 || abs(p.x) > 6 {
            if logging { print(String(format: "PB DRAIN x=%.2f z=%.2f", p.x, p.z)) }
            resetBall()
        }
        let inLane = p.x > 4.25 && p.z > 6.5
        if inLane && abs(v.z) < 0.6 && (pendingLaunch || (demo && time - lastLaunch > 1.5)) {
            let k: Float = 27 + Float.random(in: -0.8...0.8)
            ball.physicsBody?.applyForce(table.convertVector(SCNVector3(0, 0, -k), to: nil), asImpulse: true)
            lastLaunch = time
            if logging { print("PB LAUNCH") }
            DispatchQueue.main.async { AudioManager.shared.play(.pkLaunch) }
        }
        pendingLaunch = false
        // 球卡住了（不在发射轨道里，却 1.5 秒几乎不动）：往下推一把
        let speed = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        if !inLane && speed < 0.25 {
            if slowSince == nil { slowSince = time }
            if let t0 = slowSince, time - t0 > 1.5 {
                if logging { print(String(format: "PB STUCK x=%.2f y=%.2f z=%.2f", p.x, p.y, p.z)) }
                ball.physicsBody?.applyForce(SCNVector3(Float.random(in: -1.5...1.5), 1.5, 3), asImpulse: true)
                slowSince = nil
            }
        } else { slowSince = nil }
        if demo {
            // 自动打：球落到挡板外半截上方就拍一下（0.2 秒后放下），不按住
            for f in [flipperL, flipperR] {
                if f.wantUp {
                    if time > f.botRelease { f.wantUp = false }
                } else if time > f.botCooldown, p.y < 0.9 {
                    let (a, h) = f.local(p)
                    if a > 0.75, a < 1.7, h > 0, h < 0.85 {
                        f.wantUp = true
                        f.botRelease = time + 0.2
                        f.botCooldown = time + 0.5
                    }
                }
            }
        }
        stepFlipper(flipperL, dt: dt, ballPos: p)
        stepFlipper(flipperR, dt: dt, ballPos: p)
        let rail = p.y > 0.95 && p.x < -2.4
        if rail != onRail {
            onRail = rail
            if !rail && p.z > 1 { score(1000); DispatchQueue.main.async { AudioManager.shared.play(.fruitLit); HapticManager.shared.fruitLit() } }
            if logging { print(rail ? "PB RAIL on" : String(format: "PB RAIL off x=%.2f y=%.2f z=%.2f", p.x, p.y, p.z)) }
        }
        if logging {
            if time - lastLog > 0.1 {
                lastLog = time
                print(String(format: "PB %.1f  %.2f %.2f %.2f  v %.1f %.1f %.1f", time, p.x, p.y, p.z, v.x, v.y, v.z))
            }
        }
        // 相机（hj 11-28：更正对台面）：固定在高处往下看 55 度，整张台子和背板一直都在画面里，不再跟球
        _ = w
    }

    // MARK: 碰撞：蘑菇柱弹开、金字塔的靶子
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let other = contact.nodeA === ball ? contact.nodeB : contact.nodeA
        guard let name = other.name else { return }
        if name.hasPrefix("bumper"), let k = Int(name.dropFirst(6)) {
            let c = other.presentation.position, p = ball.presentation.position
            let dx = p.x - c.x, dz = p.z - c.z, l = max(0.01, hypot(dx, dz))
            ball.physicsBody?.applyForce(table.convertVector(SCNVector3(dx / l * 8, 0, dz / l * 8), to: nil), asImpulse: true)
            let cap = bumperCaps[k]
            cap.removeAllActions()
            cap.runAction(.sequence([.moveBy(x: 0, y: -0.16, z: 0, duration: 0.03), .moveBy(x: 0, y: 0.16, z: 0, duration: 0.1)]))
            DispatchQueue.main.async { AudioManager.shared.play(.baffleHit); HapticManager.shared.baffleHit() }
            score(100)
        } else if name.hasPrefix("sling"), contact.collisionImpulse > 4.5 {
            let nx: Float = name == "slingL" ? 0.878 : -0.878
            ball.physicsBody?.applyForce(table.convertVector(SCNVector3(nx * 7, 0, -0.479 * 7), to: nil), asImpulse: true)
            other.removeAllActions()
            other.runAction(.sequence([.scale(to: 1.06, duration: 0.03), .scale(to: 1, duration: 0.1)]))
            score(10)
            DispatchQueue.main.async { AudioManager.shared.play(.baffleHit); HapticManager.shared.baffleHit() }
        } else if name == "target" {
            score(500)
            pyramidTop.removeAllActions()
            pyramidTop.runAction(.sequence([.moveBy(x: 0, y: 0.9, z: 0, duration: 0.18), .wait(duration: 0.5), .moveBy(x: 0, y: -0.9, z: 0, duration: 0.35)]))
            DispatchQueue.main.async { AudioManager.shared.play(.fruitLit); HapticManager.shared.fruitLit() }
        }
    }
}

/// 样台的画面：全屏 3D + 左右半屏按住抬挡板 + 右下角发射 + 左上角返回
struct RampTableProtoView: View {
    var onExit: () -> Void
    @State private var table = RampTableScene()
    @State private var points = 0

    var body: some View {
        ZStack {
            RampTableSceneView(table: table).ignoresSafeArea()
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in table.setFlipper(left: true, up: true) }.onEnded { _ in table.setFlipper(left: true, up: false) })
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { _ in table.setFlipper(left: false, up: true) }.onEnded { _ in table.setFlipper(left: false, up: false) })
            }
            .ignoresSafeArea()
            VStack {
                HStack {
                    LobbyBackButton { onExit() }
                    Spacer()
                    Text(verbatim: "\(points)")
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundColor(ArtPalette.goldLight)
                        .shadow(color: .orange.opacity(0.8), radius: 6)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14).padding(.top, 6)
                Spacer()
                HStack {
                    Spacer()
                    Button { table.launch() } label: {
                        Text(verbatim: "LAUNCH")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.25, green: 0.1, blue: 0))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Capsule().fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom)))
                            .overlay(Capsule().stroke(ArtPalette.outline, lineWidth: 1.5))
                    }
                    .padding(.trailing, 16).padding(.bottom, 20)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { table.onScore = { n in withAnimation(.easeOut(duration: 0.2)) { points += n } } }
    }
}

struct RampTableSceneView: UIViewRepresentable {
    let table: RampTableScene
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = table.scene
        v.pointOfView = table.cameraNode
        v.delegate = table
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
