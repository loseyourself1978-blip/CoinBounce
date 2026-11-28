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
    private var leftFlipper = SCNNode(), rightFlipper = SCNNode()
    private var bumperCaps: [SCNNode] = []
    private var pyramidTop = SCNNode()
    private var camPos = SCNVector3(0, 13, 19), camLook = SCNVector3(0, 0, 4)
    private let demo = ProcessInfo.processInfo.arguments.contains("-pinballDemo")
    private var lastLaunch: TimeInterval = 0
    private var pendingLaunch = false
    private var leftUp = false, rightUp = false
    private var slowSince: TimeInterval?

    static let tilt: Float = 7 * .pi / 180
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
    @discardableResult
    private func solid(_ g: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3, restitution: CGFloat = 0.35, friction: CGFloat = 0.25, category: Int = catTable) -> SCNNode {
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.position = p
        let b = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: g, options: nil))
        b.restitution = restitution
        b.friction = friction
        b.categoryBitMask = category
        b.contactTestBitMask = category == Self.catTable ? 0 : Self.catBall
        n.physicsBody = b
        table.addChildNode(n)
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
        // 物理：重力加大（台面只斜 7 度，球才有真机的速度），步长细一点防止球穿墙
        scene.physicsWorld.gravity = SCNVector3(0, -60, 0)
        scene.physicsWorld.timeStep = 1.0 / 240
        scene.physicsWorld.contactDelegate = self
        scene.background.contents = UIColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)

        // 台面：10 宽、20 长，远端在 -z。先用旧台面的画当底图（样台阶段）
        let floorM = pbr(.white, metal: 0, rough: 0.35)
        floorM.diffuse.contents = Pinball3DScene.tableArt()
        floorM.clearCoat.contents = 0.15
        solid(SCNBox(width: 10, height: 0.4, length: 20, chamferRadius: 0), floorM, at: SCNVector3(0, -0.2, 0), friction: 0.12)
        // 玻璃盖（看不见）：球飞不出去
        solid(SCNBox(width: 10, height: 0.2, length: 20, chamferRadius: 0), invisible, at: SCNVector3(0, 2.9, 0))
        // 机柜四边
        for (x, z, w, l) in [(Float(-5.3), Float(0), Float(0.6), Float(21.2)), (5.3, 0, 0.6, 21.2), (0, -10.3, 11.2, 0.6), (0, 10.3, 11.2, 0.6)] {
            solid(SCNBox(width: CGFloat(w), height: 1.8, length: CGFloat(l), chamferRadius: 0.1), wood, at: SCNVector3(x, 0.5, z))
        }
        // 拱顶：半圆，12 段
        let n = 14
        for i in 0..<n {
            let a0 = Float.pi * Float(i) / Float(n), a1 = Float.pi * Float(i + 1) / Float(n)
            wall(5 * cos(a0), -5 - 5 * sin(a0), 5 * cos(a1), -5 - 5 * sin(a1), height: 1.0)
        }
        // 发射轨道的内墙；两侧通往挡板的斜导轨
        wall(4.2, -4.6, 4.2, 10)
        wall(-5, 3.2, -2.75, 7.05, restitution: 0.25)
        wall(4.2, 3.2, 1.95, 7.05, restitution: 0.25)
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
        func flipper(pivot: SCNVector3, dir: Float, rest: Float) -> SCNNode {
            let p = SCNNode()
            p.position = pivot
            p.eulerAngles.y = rest
            let L: CGFloat = 1.75
            let g = SCNBox(width: L, height: 0.5, length: 0.34, chamferRadius: 0.16)
            g.firstMaterial = pbr(UIColor(red: 0.92, green: 0.1, blue: 0.18, alpha: 1), metal: 0.1, rough: 0.25, glow: UIColor(red: 0.5, green: 0, blue: 0.08, alpha: 1), intensity: 0.5)
            let b = SCNNode(geometry: g)
            b.position = SCNVector3(dir * Float(L) / 2, 0, 0)
            let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: g, options: nil))
            body.restitution = 0.5
            body.friction = 0.4
            body.categoryBitMask = Self.catTable
            b.physicsBody = body
            p.addChildNode(b)
            let cap = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.56))
            cap.geometry!.firstMaterial = chrome
            p.addChildNode(cap)
            table.addChildNode(p)
            return p
        }
        leftFlipper = flipper(pivot: SCNVector3(-2.55, 0.27, 7.3), dir: 1, rest: -0.44)
        rightFlipper = flipper(pivot: SCNVector3(1.75, 0.27, 7.3), dir: -1, rest: 0.44)
    }

    func setFlipper(left: Bool, up: Bool) {
        if left { guard leftUp != up else { return }; leftUp = up } else { guard rightUp != up else { return }; rightUp = up }
        let node = left ? leftFlipper : rightFlipper
        let angle: CGFloat = left ? (up ? 0.52 : -0.44) : (up ? -0.52 : 0.44)
        node.removeAllActions()
        node.runAction(.rotateTo(x: 0, y: angle, z: 0, duration: up ? 0.05 : 0.09, usesShortestUnitArc: true))
        if up { HapticManager.shared.slotColumnStop() }
    }

    private func buildBumpers() {
        let colors = [UIColor(red: 1, green: 0.42, blue: 0.16, alpha: 1), UIColor(red: 0.1, green: 0.85, blue: 0.78, alpha: 1), UIColor(red: 1, green: 0.78, blue: 0.25, alpha: 1)]
        for (k, p) in [(Float(-1.9), Float(-5.0)), (1.3, -5.0), (-0.3, -3.1)].enumerated() {
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

    /// 坡道（从台面中左冲上二层）+ 铁丝轨道（绕回左侧，把球送回左挡板）
    private func buildRamp() {
        // 坡道：z 2 → -5，升到 1.5 高
        let rise: Float = 1.5, run: Float = 7
        let len = hypot(rise, run), ang = atan2(rise, run)
        let rampM = pbr(UIColor(red: 0.08, green: 0.3, blue: 0.36, alpha: 1), metal: 0.3, rough: 0.3, glow: UIColor(red: 0.1, green: 0.85, blue: 0.78, alpha: 1), intensity: 0.08)
        let plate = solid(SCNBox(width: 1.3, height: 0.1, length: CGFloat(len), chamferRadius: 0.02), rampM, at: SCNVector3(-1.6, rise / 2, -1.5), restitution: 0.1, friction: 0.1)
        plate.eulerAngles.x = ang
        for dx: Float in [-0.7, 0.7] {
            let rail = solid(SCNBox(width: 0.1, height: 0.5, length: CGFloat(len), chamferRadius: 0.03), chrome, at: SCNVector3(-1.6 + dx, rise / 2 + 0.28, -1.5), restitution: 0.3)
            rail.eulerAngles.x = ang
        }
        // 铁丝轨道：一串槽（底 + 两边的管），沿这些点走
        let pts: [SCNVector3] = [SCNVector3(-1.6, 1.5, -5), SCNVector3(-2.1, 1.5, -6.5), SCNVector3(-3.3, 1.46, -7.0), SCNVector3(-4.2, 1.38, -6.0),
                                 SCNVector3(-4.35, 1.2, -3.5), SCNVector3(-4.35, 0.85, -0.6), SCNVector3(-4.35, 0.55, 1.5)]
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let d = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let l = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
            let mid = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
            let seg = SCNNode()
            seg.position = mid
            seg.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))   // 这时 table 还没后仰：台面坐标 = 世界坐标
            table.addChildNode(seg)
            func part(_ g: SCNGeometry, _ m: SCNMaterial, _ off: SCNVector3, rot: Bool = false) {
                g.firstMaterial = m
                let n = SCNNode(geometry: g)
                n.position = off
                if rot { n.eulerAngles.x = .pi / 2 }
                let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: g, options: nil))
                body.restitution = 0.1; body.friction = 0.05; body.categoryBitMask = Self.catTable
                n.physicsBody = body
                seg.addChildNode(n)
            }
            part(SCNBox(width: 0.9, height: 0.06, length: CGFloat(l + 0.2), chamferRadius: 0), invisible, SCNVector3(0, -0.03, 0))
            for dx: Float in [-0.42, 0.42] {
                part(SCNBox(width: 0.08, height: 0.5, length: CGFloat(l + 0.35), chamferRadius: 0), invisible, SCNVector3(dx, 0.22, 0))
                // 看得见的是四根镀铬的管：下面两根托着球，上面两根拦着球
                for (ox, oy) in [(dx * 0.55, Float(-0.02)), (dx, Float(0.34))] {
                    let tube = SCNNode(geometry: SCNCylinder(radius: 0.05, height: CGFloat(l + 0.2)))
                    tube.geometry!.firstMaterial = chrome
                    tube.eulerAngles.x = .pi / 2
                    tube.position = SCNVector3(ox, oy, 0)
                    seg.addChildNode(tube)
                }
            }
        }
        // 轨道的支柱
        for p in [pts[1], pts[3], pts[4], pts[5]] {
            let post = SCNNode(geometry: SCNCylinder(radius: 0.06, height: CGFloat(p.y)))
            post.geometry!.firstMaterial = gold
            post.position = SCNVector3(p.x, p.y / 2, p.z)
            table.addChildNode(post)
        }
    }

    /// 中央机关：一座金字塔。球打到塔前的靶子，塔尖升起来、亮一下
    private func buildPyramid() {
        let base = SCNPyramid(width: 2.2, height: 1.1, length: 2.2)
        solid(base, sand, at: SCNVector3(1.9, 0, -0.6), restitution: 0.5)
        let tip = SCNPyramid(width: 0.9, height: 0.75, length: 0.9)
        tip.firstMaterial = pbr(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), metal: 1, rough: 0.15, glow: UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 1), intensity: 0.6)
        pyramidTop = SCNNode(geometry: tip)
        pyramidTop.position = SCNVector3(1.9, 0.72, -0.6)
        table.addChildNode(pyramidTop)
        let target = solid(SCNBox(width: 1.2, height: 0.7, length: 0.16, chamferRadius: 0.04),
                           pbr(UIColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1), metal: 0.2, rough: 0.3, glow: UIColor(red: 1, green: 0.3, blue: 0.7, alpha: 1), intensity: 0.9),
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

    private func resetBall() {
        ball.physicsBody?.clearAllForces()
        ball.physicsBody?.velocity = SCNVector3Zero
        ball.physicsBody?.angularVelocity = SCNVector4Zero
        ball.position = SCNVector3(4.6, Float(Self.ballR) + 0.02, 8.6)
        ball.physicsBody?.resetTransform()
        // 调试：-protoRampShot 每次都从坡道正下方把球直直打上去（检查坡道和铁丝轨道走不走得通）
        if ProcessInfo.processInfo.arguments.contains("-protoRampShot") {
            ball.position = SCNVector3(-1.6, Float(Self.ballR) + 0.02, 5.5)
            ball.physicsBody?.resetTransform()
            ball.physicsBody?.velocity = SCNVector3(0, 0, -19)
        }
    }

    func launch() { pendingLaunch = true }

    private func buildLightsAndCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 62
        cam.projectionDirection = .vertical
        cam.zNear = 0.5; cam.zFar = 120
        cam.wantsHDR = true
        cam.bloomIntensity = 0.5; cam.bloomThreshold = 0.9; cam.bloomBlurRadius = 5
        cam.exposureOffset = -0.5
        cam.wantsExposureAdaptation = false
        cam.vignettingIntensity = 0.6; cam.vignettingPower = 1.2
        cameraNode.camera = cam
        cameraNode.position = camPos
        scene.rootNode.addChildNode(cameraNode)
        // 暗场 + 一盏从玩家头顶打下来的聚光灯（带影子）
        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 90
        scene.rootNode.addChildNode(amb)
        let spot = SCNNode(); spot.light = SCNLight()
        spot.light!.type = .spot
        spot.light!.intensity = 900
        spot.light!.spotInnerAngle = 50; spot.light!.spotOuterAngle = 95
        spot.light!.castsShadow = true
        spot.light!.shadowRadius = 5
        spot.light!.shadowColor = UIColor.black.withAlphaComponent(0.6)
        spot.light!.shadowMapSize = CGSize(width: 2048, height: 2048)
        spot.position = SCNVector3(-2, 18, 8)
        spot.look(at: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(spot)
        scene.lightingEnvironment.contents = PusherScene3D.sharedCasinoEnvironment
        scene.lightingEnvironment.intensity = 0.9
    }

    // MARK: 每帧：相机跟球、掉球重来、发射、自动打
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let p = ball.presentation.position            // 台面坐标
        let w = ball.presentation.worldPosition
        let v = ball.physicsBody?.velocity ?? SCNVector3Zero
        // 掉进挡板中间，或者不知怎么飞出去了：回发射轨道
        if (p.z > 9.3 && p.x < 4.1) || p.y < -2 || abs(p.x) > 6 { resetBall() }
        let inLane = p.x > 4.25 && p.z > 6.5
        if inLane && abs(v.z) < 0.6 && (pendingLaunch || (demo && time - lastLaunch > 1.5)) {
            // 冲量沿台面往远端（台面是后仰的，所以带一点向上的分量）
            let k: Float = 21.5 + Float.random(in: -0.6...0.6)
            ball.physicsBody?.applyForce(SCNVector3(0, k * sin(Self.tilt), -k * cos(Self.tilt)), asImpulse: true)
            lastLaunch = time
            DispatchQueue.main.async { AudioManager.shared.play(.pkLaunch) }
        }
        pendingLaunch = false
        // 球卡住了（不在发射轨道里，却 1.5 秒几乎不动）：往下推一把
        let speed = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        if !inLane && speed < 0.25 {
            if slowSince == nil { slowSince = time }
            if let t0 = slowSince, time - t0 > 1.5 {
                ball.physicsBody?.applyForce(SCNVector3(Float.random(in: -1.5...1.5), 1.5, 3), asImpulse: true)
                slowSince = nil
            }
        } else { slowSince = nil }
        if demo {
            // 自动打：球到挡板上方、正在往下落时抬板
            let nearL = p.z > 6.3 && p.z < 8.1 && p.x < -0.4 && p.x > -3.2 && v.z > -1
            let nearR = p.z > 6.3 && p.z < 8.1 && p.x >= -0.4 && p.x < 2.6 && v.z > -1
            DispatchQueue.main.async { self.setFlipper(left: true, up: nearL); self.setFlipper(left: false, up: nearR) }
        }
        // 相机：在球的后上方，球越往远端相机越跟上去；发射轨道里时看全场
        let tx = max(-2.2, min(2.2, w.x * 0.45)), tz = max(-4, min(8.5, w.z))
        let wantPos = SCNVector3(tx * 0.6, w.y + 9.5, tz + 12.5)
        let wantLook = SCNVector3(tx * 0.8, 0.5, tz - 1.5)
        let s: Float = 0.07
        camPos = SCNVector3(camPos.x + (wantPos.x - camPos.x) * s, camPos.y + (wantPos.y - camPos.y) * s, camPos.z + (wantPos.z - camPos.z) * s)
        camLook = SCNVector3(camLook.x + (wantLook.x - camLook.x) * s, camLook.y + (wantLook.y - camLook.y) * s, camLook.z + (wantLook.z - camLook.z) * s)
        cameraNode.position = camPos
        cameraNode.look(at: camLook)
    }

    // MARK: 碰撞：蘑菇柱弹开、金字塔的靶子
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let other = contact.nodeA === ball ? contact.nodeB : contact.nodeA
        guard let name = other.name else { return }
        if name.hasPrefix("bumper"), let k = Int(name.dropFirst(6)) {
            let c = other.presentation.position, p = ball.presentation.position
            let dx = p.x - c.x, dz = p.z - c.z, l = max(0.01, hypot(dx, dz))
            ball.physicsBody?.applyForce(SCNVector3(dx / l * 7, 0, dz / l * 7), asImpulse: true)
            let cap = bumperCaps[k]
            cap.removeAllActions()
            cap.runAction(.sequence([.moveBy(x: 0, y: -0.16, z: 0, duration: 0.03), .moveBy(x: 0, y: 0.16, z: 0, duration: 0.1)]))
            DispatchQueue.main.async { AudioManager.shared.play(.baffleHit); HapticManager.shared.baffleHit() }
        } else if name == "target" {
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
                    Text(verbatim: "PROTOTYPE")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
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
