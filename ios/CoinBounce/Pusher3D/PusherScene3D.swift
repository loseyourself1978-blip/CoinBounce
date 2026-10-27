import SceneKit
import UIKit

// MARK: - 3D 推币台（SceneKit）
// 坐标：x 向右，y 向上，z 朝向玩家（台面前沿在 +z）。长度单位约等于 1 枚金币的半径。
// 结构：下层台面（固定）+ 推板（运动学刚体，前后往复，顶面就是上层台面）+ 推板上方的固定刮板
//      （推板后退时把上层金币刮落到下层）+ 左右挡板 + 前沿掉落口。
final class PusherScene3D: NSObject, SCNSceneRendererDelegate {

    struct Config {
        var coinRadius: Float = 0.5
        var coinThickness: Float = 0.14
        var deckWidth: Float = 8
        var deckDepth: Float = 7          // 下层台面：z 从 -deckDepth/2 到 +deckDepth/2
        var pusherHeight: Float = 0.7
        var pusherDepth: Float = 5
        var pusherStroke: Float = GameConstants.pusherStroke
        var pusherPeriod: TimeInterval = GameConstants.pusherPeriod
        var maxCoins = 150
        var prefillCoins = 130
    }

    let scene = SCNScene()
    private(set) var config: Config
    /// 相机节点（测试里用它做投影计算）
    let cameraNode = SCNNode()
    private(set) var droppedCount = 0          // 掉出前沿的金币数（计分）
    /// 有金币从前沿掉落；参数为是否特殊金币（主线程回调）
    var onCoinDropped: ((_ isSpecial: Bool) -> Void)?
    /// 特殊金币：白金色、自发光
    private lazy var specialGeometry: SCNCylinder = {
        let g = SCNCylinder(radius: CGFloat(config.coinRadius), height: CGFloat(config.coinThickness))
        g.radialSegmentCount = 24
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 1, green: 0.97, blue: 0.8, alpha: 1)
        m.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        m.metalness.contents = 0.6
        m.roughness.contents = 0.2
        g.materials = [m]
        return g
    }()
    private static let specialName = "special"

    private var coins: [SCNNode] = []
    private let coinGeometry: SCNCylinder
    private let coinMaterial = SCNMaterial()
    private var pusher: SCNNode!

    // 帧率统计
    private var frameCount = 0
    private var windowStart: TimeInterval = 0
    private(set) var lastFPS: Double = 0
    var onStats: ((_ fps: Double, _ coins: Int, _ awake: Int) -> Void)?

    init(config: Config = Config()) {
        self.config = config
        coinGeometry = SCNCylinder(radius: CGFloat(config.coinRadius), height: CGFloat(config.coinThickness))
        coinGeometry.radialSegmentCount = 24
        super.init()
        buildScene()
    }

    // MARK: 搭建场景
    private func buildScene() {
        let c = config
        scene.physicsWorld.gravity = baseGravity   // 单位较小，加大重力让下落手感接近真实
        scene.physicsWorld.timeStep = 1.0 / 120.0

        // 相机：斜上方透视
        let camera = SCNCamera()
        // 按水平视角取景，保证整个台面宽度都在画面内；斜上方俯视，看得到台面纵深和金币厚度
        camera.projectionDirection = .horizontal
        camera.fieldOfView = 33   // 收窄视角：台面撑满屏幕宽度，侧板压在屏幕边缘
        camera.zNear = 0.1
        camera.zFar = 100
        // 屏幕空间环境光遮蔽：金币堆叠处、推板下方自然变暗，增强立体感
        camera.screenSpaceAmbientOcclusionIntensity = 0.9
        camera.screenSpaceAmbientOcclusionRadius = 0.25
        let cameraNode = self.cameraNode
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 12.0, 12.0)
        cameraNode.look(at: SCNVector3(0, -1.3, 0.7))   // 视线略低，台面前沿和接币盘填满推币台区域下部
        scene.background.contents = PusherScene3D.backgroundImage()
        scene.rootNode.addChildNode(cameraNode)

        // 灯光
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 800
        key.light!.castsShadow = true
        key.light!.shadowMode = .deferred
        key.light!.shadowRadius = 4          // 柔和阴影
        key.light!.shadowSampleCount = 8
        key.light!.shadowColor = UIColor.black.withAlphaComponent(0.55)
        key.eulerAngles = SCNVector3(-Float.pi / 2.4, 0, 0)   // 接近正上方，侧壁不再有大块阴影
        scene.rootNode.addChildNode(key)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 600
        scene.rootNode.addChildNode(ambient)

        // 环境光照：竖向渐变，给金属材质提供反射
        scene.lightingEnvironment.contents = PusherScene3D.environmentImage()
        scene.lightingEnvironment.intensity = 1.4

        // 金币材质：侧面金属金色，正反面用原创星形金币图案
        coinMaterial.lightingModel = .physicallyBased
        coinMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.76, blue: 0.22, alpha: 1)
        coinMaterial.metalness.contents = 0.9
        coinMaterial.roughness.contents = 0.3
        let face = SCNMaterial()
        face.lightingModel = .physicallyBased
        face.diffuse.contents = PusherScene3D.coinFaceImage()
        face.metalness.contents = 0.75
        face.roughness.contents = 0.28
        coinGeometry.materials = [coinMaterial, face, face]   // 侧面、顶面、底面

        // 原创程序纹理：台面菱格绒布、侧板漆面、推板花纹，配色与上半部的紫红 / 金 / 青绿统一
        let felt = material(UIColor.white)
        felt.diffuse.contents = PusherScene3D.feltImage()
        felt.diffuse.wrapS = .repeat; felt.diffuse.wrapT = .repeat
        felt.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        felt.roughness.contents = 0.85
        let wood = material(UIColor(red: 0.55, green: 0.09, blue: 0.32, alpha: 1), metal: 0.35)   // 紫红漆面侧板
        wood.roughness.contents = 0.25
        let red = material(UIColor.white)
        red.diffuse.contents = PusherScene3D.pusherImage()
        red.roughness.contents = 0.35
        let gold = material(UIColor(red: 0.95, green: 0.72, blue: 0.25, alpha: 1), metal: 0.85)
        gold.roughness.contents = 0.25
        let neonTeal = material(UIColor(red: 0.1, green: 0.9, blue: 0.85, alpha: 1))
        neonTeal.emission.contents = UIColor(red: 0.1, green: 0.95, blue: 0.9, alpha: 1)
        let neonGold = material(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
        neonGold.emission.contents = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        let bulbA = material(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
        let bulbB = material(UIColor(red: 0.1, green: 0.9, blue: 0.85, alpha: 1))
        bulbA.emission.contents = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
        bulbB.emission.contents = UIColor(red: 0.1, green: 0.95, blue: 0.9, alpha: 1)
        bulbMaterials = [bulbA, bulbB]
        let blinker = SCNNode()
        blinker.runAction(.repeatForever(.sequence([.wait(duration: 0.45), .run { [weak self] _ in self?.toggleBulbs() }])))
        scene.rootNode.addChildNode(blinker)

        // 下层台面
        let floor = box(c.deckWidth, 0.4, c.deckDepth, felt)
        floor.position = SCNVector3(0, -0.2, 0)
        staticBody(floor, friction: GameConstants.deckFriction)
        scene.rootNode.addChildNode(floor)

        // 推板（运动学）：从台面后部伸出，前后往复
        let pusherNode = box(c.deckWidth - 0.05, c.pusherHeight, c.pusherDepth, red)
        let restZ = -c.deckDepth / 2 - c.pusherDepth / 2 + 1.2
        pusherNode.position = SCNVector3(0, c.pusherHeight / 2, restZ)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: pusherNode, options: nil))
        body.friction = 0.6
        pusherNode.physicsBody = body
        scene.rootNode.addChildNode(pusherNode)
        pusher = pusherNode
        let forward = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(c.pusherStroke), duration: c.pusherPeriod / 2)
        forward.timingMode = .easeInEaseOut
        pusherNode.runAction(.repeatForever(.sequence([forward, forward.reversed()])), forKey: "push")
        // 推板前沿发光边
        let edge = box(c.deckWidth - 0.1, 0.08, 0.08, neonGold)
        edge.position = SCNVector3(0, c.pusherHeight / 2 + 0.01, c.pusherDepth / 2 - 0.02)
        pusherNode.addChildNode(edge)

        // 刮板：固定在推板上方，离推板前沿（后退到底时）约 1 个单位；推板后退时上层金币被挡住，从前沿掉到下层
        let scraperZ = restZ + c.pusherDepth / 2 - 1.15
        let scraper = box(c.deckWidth, 2.0, 0.3, gold)
        scraper.position = SCNVector3(0, c.pusherHeight + 1.0 + 0.02, scraperZ)
        staticBody(scraper, friction: 0.2)
        scene.rootNode.addChildNode(scraper)

        // 后墙（装饰 + 防止金币掉到推板后面）
        let back = box(c.deckWidth, 3, 0.3, red)
        back.position = SCNVector3(0, 1.5, restZ - c.pusherDepth / 2 - 0.2)
        staticBody(back, friction: 0.2)
        scene.rootNode.addChildNode(back)

        // 左右挡板（透明碰撞 + 可见边框）
        for side: Float in [-1, 1] {
            let wall = box(0.3, 2.4, c.deckDepth + c.pusherDepth + 2, wood)
            wall.position = SCNVector3(side * (c.deckWidth / 2 + 0.15), 1.0, -c.pusherDepth / 2)
            staticBody(wall, friction: 0.1)
            scene.rootNode.addChildNode(wall)
            // 侧板顶部金色压条 + 一排灯泡（交替闪烁）
            let trim = box(0.42, 0.12, c.deckDepth + c.pusherDepth + 2, gold)
            trim.position = SCNVector3(side * (c.deckWidth / 2 + 0.15), 2.26, -c.pusherDepth / 2)
            scene.rootNode.addChildNode(trim)
            // 低面数灯泡；两组材质交替切换发光颜色来闪烁（不改透明度，避免透明渲染开销）
            for k in 0..<6 {
                let sphere = SCNSphere(radius: 0.11)
                sphere.segmentCount = 8
                sphere.materials = [k.isMultiple(of: 2) ? bulbA : bulbB]
                let bulb = SCNNode(geometry: sphere)
                bulb.position = SCNVector3(side * (c.deckWidth / 2 + 0.15), 2.38, c.deckDepth / 2 - 0.5 - Float(k) * 1.7)
                scene.rootNode.addChildNode(bulb)
            }
            // 台面两侧霓虹灯带
            let strip = box(0.06, 0.05, c.deckDepth, neonTeal)
            strip.position = SCNVector3(side * (c.deckWidth / 2 - 0.05), 0.03, 0)
            scene.rootNode.addChildNode(strip)
        }

        // 前沿金边、下方接币盘（只做视觉）
        let lip = box(c.deckWidth + 0.6, 0.35, 0.35, gold)
        lip.position = SCNVector3(0, -0.22, c.deckDepth / 2 + 0.17)
        scene.rootNode.addChildNode(lip)
        let lipNeon = box(c.deckWidth + 0.4, 0.06, 0.06, neonGold)
        lipNeon.position = SCNVector3(0, -0.4, c.deckDepth / 2 + 0.36)
        scene.rootNode.addChildNode(lipNeon)
        easyDropGlow = lipNeon
        // 接币盘：底板 + 前后挡边，更立体
        let tray = box(c.deckWidth + 1, 0.2, 2.5, gold)
        tray.position = SCNVector3(0, -3.2, c.deckDepth / 2 + 1.4)
        scene.rootNode.addChildNode(tray)
        for dz: Float in [-1.2, 1.2] {
            let rim = box(c.deckWidth + 1, 0.5, 0.15, gold)
            rim.position = SCNVector3(0, -2.95, c.deckDepth / 2 + 1.4 + dz)
            scene.rootNode.addChildNode(rim)
        }

        // 两侧引导斜坡（后部角落）和装饰炮管
        for side: Float in [-1, 1] {
            let ramp = box(1.6, 0.25, 3.2, wood)
            ramp.position = SCNVector3(side * (c.deckWidth / 2 - 0.7), 0.55, -c.deckDepth / 2 + 1.0)
            ramp.eulerAngles = SCNVector3(0, 0, -side * 0.5)
            staticBody(ramp, friction: 0.2)
            scene.rootNode.addChildNode(ramp)

            let barrel = SCNNode(geometry: SCNCylinder(radius: 0.35, height: 1.6))
            barrel.geometry?.materials = [material(UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1), metal: 0.7)]
            barrel.eulerAngles = SCNVector3(0, 0, Float.pi / 2 + side * 0.25)
            barrel.position = SCNVector3(side * (c.deckWidth / 2 + 0.3), 1.6, -c.deckDepth / 2 + 2.0)
            scene.rootNode.addChildNode(barrel)
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.36, pipeRadius: 0.07))
            ring.geometry?.materials = [gold]
            ring.eulerAngles = barrel.eulerAngles
            ring.position = SCNVector3(side * (c.deckWidth / 2 - 0.45), 1.6 - side * 0.0, -c.deckDepth / 2 + 2.0)
            scene.rootNode.addChildNode(ring)
        }

        prefill()
    }

    private func material(_ color: UIColor, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = 0.6
        return m
    }

    private func box(_ w: Float, _ h: Float, _ d: Float, _ m: SCNMaterial) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0.02)
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    private func staticBody(_ node: SCNNode, friction: CGFloat) {
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(node: node, options: nil))
        body.friction = friction
        body.restitution = 0.05
        node.physicsBody = body
    }

    // MARK: 灯泡闪烁
    private var bulbMaterials: [SCNMaterial] = []
    private var bulbPhase = false
    private func toggleBulbs() {
        bulbPhase.toggle()
        let gold = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), teal = UIColor(red: 0.1, green: 0.95, blue: 0.9, alpha: 1)
        guard bulbMaterials.count == 2 else { return }
        bulbMaterials[0].emission.contents = bulbPhase ? teal : gold
        bulbMaterials[1].emission.contents = bulbPhase ? gold : teal
    }

    // MARK: 卡牌效果

    private weak var easyDropGlow: SCNNode?
    private var baseGravity = SCNVector3(0, -9.8 * 2.2, 0)

    /// 推板速度倍率（卡牌「推板加速」）
    func setPusherSpeed(_ multiplier: Double) {
        let c = config
        pusher.removeAction(forKey: "push")
        let forward = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(c.pusherStroke), duration: c.pusherPeriod / 2 / max(0.1, multiplier))
        forward.timingMode = .easeInEaseOut
        // 先回到起点再开始新的往复，避免位置漂移
        let restZ = -c.deckDepth / 2 - c.pusherDepth / 2 + 1.2
        let home = SCNAction.move(to: SCNVector3(0, c.pusherHeight / 2, restZ), duration: 0.15)
        pusher.runAction(.sequence([home, .repeatForever(.sequence([forward, forward.reversed()]))]), forKey: "push")
    }

    /// 卡牌「轻松掉落」：台面向前微倾（重力加一点向前分量），前沿灯带闪烁
    func setEasyDrop(_ on: Bool) {
        scene.physicsWorld.gravity = on ? SCNVector3(baseGravity.x, baseGravity.y, 3.2) : baseGravity
        easyDropGlow?.removeAllActions()
        if on {
            easyDropGlow?.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.2, duration: 0.25), .fadeOpacity(to: 1, duration: 0.25)])))
        } else {
            easyDropGlow?.opacity = 1
        }
    }

    // MARK: 金币
    @discardableResult
    func addCoin(at position: SCNVector3, tilt: Float = 0, velocity: SCNVector3 = SCNVector3Zero, special: Bool = false) -> SCNNode? {
        guard coins.count < config.maxCoins else { return nil }
        let node = SCNNode(geometry: special ? specialGeometry : coinGeometry)
        if special { node.name = PusherScene3D.specialName }
        node.position = position
        node.eulerAngles = SCNVector3(tilt, Float.random(in: 0...(2 * .pi)), tilt * 0.5)
        node.castsShadow = true
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: coinGeometry, options: nil))
        body.mass = 0.05
        body.friction = GameConstants.pusherCoinFriction
        body.rollingFriction = 0.08
        body.restitution = 0.08
        body.damping = 0.15
        body.angularDamping = 0.35
        body.allowsResting = true
        body.velocity = velocity
        node.physicsBody = body
        scene.rootNode.addChildNode(node)
        coins.append(node)
        return node
    }

    /// 开局预铺：下层台面铺 2～3 层，推板顶面放一层
    private func prefill() {
        let c = config
        let d = c.coinRadius * 2.02
        var placed = 0
        var layer = 0
        while placed < c.prefillCoins && layer < 3 {
            var row = 0
            var z = c.deckDepth / 2 - c.coinRadius - 0.05 - Float(layer) * 0.6
            let frontLimit = -c.deckDepth / 2 + c.pusherStroke + 1.3
            while z > frontLimit && placed < c.prefillCoins {
                var x = -c.deckWidth / 2 + c.coinRadius + (row.isMultiple(of: 2) ? 0.05 : d / 2)
                while x < c.deckWidth / 2 - c.coinRadius && placed < c.prefillCoins {
                    let y = c.coinThickness / 2 + Float(layer) * (c.coinThickness + 0.01) + 0.02
                    addCoin(at: SCNVector3(x + Float.random(in: -0.05...0.05), y, z), tilt: Float.random(in: -0.04...0.04))
                    placed += 1
                    x += d * (layer == 0 ? 1.0 : 1.35)
                }
                z -= d * 0.87 * (layer == 0 ? 1.0 : 1.4)
                row += 1
            }
            layer += 1
        }
    }

    /// 承载场景的视图，用于把 2D 下落区的屏幕位置换算到 3D
    weak var view: SCNView?

    // MARK: 金币尺寸校准（2D → 3D 交接时屏幕上大小一致）

    /// 屏幕点 p 在推板顶面落币平面（z 固定）上对应的世界坐标
    func worldPointOnHandoffPlane(_ p: CGPoint, in view: SCNSceneRenderer) -> SCNVector3? {
        let planeZ = pusher.presentation.position.z + config.pusherDepth / 2 - 0.55
        let near = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let dz = far.z - near.z
        guard abs(dz) > 1e-4 else { return nil }
        let t = (planeZ - near.z) / dz
        return SCNVector3(near.x + (far.x - near.x) * t, near.y + (far.y - near.y) * t, planeZ)
    }

    /// 交接点处一枚 3D 金币在屏幕上的直径（点）
    func projectedCoinDiameter(at p: CGPoint, in view: SCNSceneRenderer) -> CGFloat {
        guard let w = worldPointOnHandoffPlane(p, in: view) else { return 0 }
        let r = config.coinRadius
        let a = view.projectPoint(SCNVector3(w.x - r, w.y, w.z))
        let b = view.projectPoint(SCNVector3(w.x + r, w.y, w.z))
        return CGFloat(abs(b.x - a.x))
    }

    /// 按视图尺寸和相机，把 3D 金币半径调到「交接点处屏幕直径 = 2D 金币直径」；尺寸变化时重新预铺
    func calibrateCoinSize(view: SCNSceneRenderer, viewSize: CGSize, handoffY: CGFloat, targetDiameter: CGFloat) {
        guard viewSize.width > 0, targetDiameter > 0 else { return }
        let p = CGPoint(x: viewSize.width / 2, y: handoffY)
        guard let w0 = worldPointOnHandoffPlane(p, in: view),
              let w1 = worldPointOnHandoffPlane(CGPoint(x: p.x + 10, y: p.y), in: view) else { return }
        let worldPerPoint = abs(w1.x - w0.x) / 10
        let radius = Float(targetDiameter / 2) * worldPerPoint
        guard radius > 0.05, abs(radius - config.coinRadius) / config.coinRadius > 0.01 else { return }
        config.coinRadius = radius
        coinGeometry.radius = CGFloat(radius)
        specialGeometry.radius = CGFloat(radius)
        coins.forEach { $0.removeFromParentNode() }
        coins.removeAll()
        prefill()
    }

    /// 从 2D 下落区交接：金币出现在与 2D 金币相同的屏幕位置（view 坐标），带向下的速度，保证衔接连续
    func dropCoin(atViewPoint p: CGPoint, special: Bool = false) {
        guard let view, view.bounds.width > 0, var world = worldPointOnHandoffPlane(p, in: view) else {
            dropCoin(xFraction: Float(p.x / max(1, view?.bounds.width ?? 1)) * 2 - 1, special: special)
            return
        }
        let c = config
        world.x = max(-(c.deckWidth / 2 - c.coinRadius - 0.1), min(c.deckWidth / 2 - c.coinRadius - 0.1, world.x))
        world.y = max(c.pusherHeight + c.coinRadius + 0.3, world.y)
        // 平着落下（不旋转），带向下速度；落到台面碰撞后才翻滚
        addCoin(at: world, tilt: Float.random(in: -0.08...0.08),
                velocity: SCNVector3(Float.random(in: -0.3...0.3), -6, Float.random(in: 0.3...1.0)),
                special: special)
    }

    /// 从上方投下一枚金币，落到推板顶面（上层台面）。xFraction ∈ [-1, 1]
    func dropCoin(xFraction: Float, special: Bool = false) {
        let c = config
        let x = max(-1, min(1, xFraction)) * (c.deckWidth / 2 - c.coinRadius - 0.1)
        let pusherTopZ = pusher.presentation.position.z + c.pusherDepth / 2 - 0.55
        addCoin(at: SCNVector3(x, 4.5, pusherTopZ),
                tilt: Float.random(in: -0.08...0.08),
                velocity: SCNVector3(Float.random(in: -0.3...0.3), -2, Float.random(in: 0.5...1.5)),
                special: special)
    }

    // MARK: 每帧：回收掉出前沿的金币 + 统计
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        frameCount += 1
        if windowStart == 0 { windowStart = time }
        if time - windowStart >= 2 {
            lastFPS = Double(frameCount) / (time - windowStart)
            let awake = coins.filter { $0.physicsBody?.isResting == false }.count
            onStats?(lastFPS, coins.count, awake)
            frameCount = 0
            windowStart = time
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        var removed: [Bool] = []
        coins.removeAll { node in
            if node.presentation.position.y < -2.5 {
                removed.append(node.name == PusherScene3D.specialName)
                node.removeFromParentNode()
                return true
            }
            return false
        }
        if !removed.isEmpty {
            droppedCount += removed.count
            DispatchQueue.main.async { [weak self] in
                for special in removed { self?.onCoinDropped?(special) }
            }
        }
    }

    var coinCount: Int { coins.count }

    // MARK: 贴图（代码生成）
    static func coinFaceImage(size: CGFloat = 256) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let colors = [UIColor(red: 1, green: 0.95, blue: 0.65, alpha: 1).cgColor,
                          UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1).cgColor,
                          UIColor(red: 0.8, green: 0.5, blue: 0.05, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
            cg.drawRadialGradient(g, startCenter: CGPoint(x: size * 0.4, y: size * 0.35), startRadius: 0,
                                  endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size * 0.7, options: .drawsAfterEndLocation)
            cg.setStrokeColor(UIColor(red: 0.75, green: 0.48, blue: 0.05, alpha: 1).cgColor)
            cg.setLineWidth(size * 0.05)
            cg.strokeEllipse(in: rect.insetBy(dx: size * 0.13, dy: size * 0.13))
            let star = UIBezierPath()
            for i in 0..<10 {
                let a = Double(i) * .pi / 5 - .pi / 2
                let r = i.isMultiple(of: 2) ? size * 0.26 : size * 0.12
                let pt = CGPoint(x: size / 2 + CGFloat(cos(a)) * r, y: size / 2 + CGFloat(sin(a)) * r)
                i == 0 ? star.move(to: pt) : star.addLine(to: pt)
            }
            star.close()
            UIColor(red: 1, green: 0.95, blue: 0.65, alpha: 1).setFill()
            star.fill()
            UIColor(red: 0.75, green: 0.48, blue: 0.05, alpha: 1).setStroke()
            star.lineWidth = size * 0.02
            star.stroke()
        }
    }

    /// 台面：青绿菱格绒布
    static func feltImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.04, green: 0.36, blue: 0.33, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            cg.setStrokeColor(UIColor(red: 0.12, green: 0.55, blue: 0.5, alpha: 0.7).cgColor)
            cg.setLineWidth(2)
            for k in stride(from: -128, through: 256, by: 32) {
                cg.move(to: CGPoint(x: k, y: 0)); cg.addLine(to: CGPoint(x: k + 128, y: 128))
                cg.move(to: CGPoint(x: k + 128, y: 0)); cg.addLine(to: CGPoint(x: k, y: 128))
            }
            cg.strokePath()
            UIColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 0.5).setFill()
            for x in stride(from: 0, through: 128, by: 32) {
                for y in stride(from: 0, through: 128, by: 32) { cg.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)) }
            }
        }
    }

    /// 推板：深紫红底 + 金色波纹花边
    static func pusherImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 256, height: 128)).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.62, green: 0.08, blue: 0.3, alpha: 1).cgColor,
                          UIColor(red: 0.35, green: 0.03, blue: 0.18, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 128), options: [])
            cg.setStrokeColor(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 0.9).cgColor)
            cg.setLineWidth(3)
            for row in [32.0, 96.0] {
                cg.move(to: CGPoint(x: 0, y: row))
                for x in stride(from: 0.0, through: 256.0, by: 16.0) {
                    cg.addQuadCurve(to: CGPoint(x: x + 16, y: row), control: CGPoint(x: x + 8, y: row + (Int(x / 16) % 2 == 0 ? -10 : 10)))
                }
            }
            cg.strokePath()
        }
    }

    static func backgroundImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 256)).image { ctx in
            let colors = [UIColor(red: 0.22, green: 0.10, blue: 0.06, alpha: 1).cgColor,
                          UIColor(red: 0.08, green: 0.04, blue: 0.03, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
    }

    static func environmentImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 256)).image { ctx in
            let colors = [UIColor(white: 1, alpha: 1).cgColor,
                          UIColor(red: 0.9, green: 0.6, blue: 0.4, alpha: 1).cgColor,
                          UIColor(red: 0.15, green: 0.08, blue: 0.05, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
    }
}
