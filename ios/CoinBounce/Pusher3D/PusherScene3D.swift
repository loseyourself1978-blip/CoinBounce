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
        var pusherStroke: Float = 1.8
        var pusherPeriod: TimeInterval = 2.4
        var maxCoins = 130
        var prefillCoins = 100
    }

    let scene = SCNScene()
    let config: Config
    private(set) var droppedCount = 0          // 掉出前沿的金币数（计分）
    var onCoinDropped: (() -> Void)?

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
        scene.physicsWorld.gravity = SCNVector3(0, -9.8 * 2.2, 0)   // 单位较小，加大重力让下落手感接近真实
        scene.physicsWorld.timeStep = 1.0 / 120.0

        // 相机：斜上方透视
        let camera = SCNCamera()
        // 按水平视角取景，保证整个台面宽度都在画面内；斜上方俯视，看得到台面纵深和金币厚度
        camera.projectionDirection = .horizontal
        camera.fieldOfView = 44
        camera.zNear = 0.1
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 13.0, 12.5)
        cameraNode.look(at: SCNVector3(0, -0.4, -0.3))
        scene.background.contents = PusherScene3D.backgroundImage()
        scene.rootNode.addChildNode(cameraNode)

        // 灯光
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 800
        key.light!.castsShadow = true
        key.light!.shadowMode = .deferred
        key.light!.shadowRadius = 2
        key.light!.shadowSampleCount = 4
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

        let felt = material(UIColor(red: 0.07, green: 0.40, blue: 0.27, alpha: 1))
        let wood = material(UIColor(red: 0.45, green: 0.27, blue: 0.10, alpha: 1))
        let red = material(UIColor(red: 0.62, green: 0.10, blue: 0.12, alpha: 1))
        let gold = material(UIColor(red: 0.85, green: 0.62, blue: 0.20, alpha: 1), metal: 0.8)

        // 下层台面
        let floor = box(c.deckWidth, 0.4, c.deckDepth, felt)
        floor.position = SCNVector3(0, -0.2, 0)
        staticBody(floor, friction: 0.45)
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
        pusherNode.runAction(.repeatForever(.sequence([forward, forward.reversed()])))

        // 刮板：固定在推板上方，离推板前沿（后退到底时）约 1 个单位；推板后退时上层金币被挡住，从前沿掉到下层
        let scraperZ = restZ + c.pusherDepth / 2 - 1.15
        let scraper = box(c.deckWidth, 2.0, 0.3, gold)
        scraper.position = SCNVector3(0, c.pusherHeight + 1.0 + 0.02, scraperZ)
        staticBody(scraper, friction: 0.2)
        scene.rootNode.addChildNode(scraper)

        // 后墙（装饰 + 防止金币掉到推板后面）
        let back = box(c.deckWidth, 3, 0.3, wood)
        back.position = SCNVector3(0, 1.5, restZ - c.pusherDepth / 2 - 0.2)
        staticBody(back, friction: 0.2)
        scene.rootNode.addChildNode(back)

        // 左右挡板（透明碰撞 + 可见边框）
        for side: Float in [-1, 1] {
            let wall = box(0.3, 2.4, c.deckDepth + c.pusherDepth + 2, wood)
            wall.position = SCNVector3(side * (c.deckWidth / 2 + 0.15), 1.0, -c.pusherDepth / 2)
            staticBody(wall, friction: 0.1)
            scene.rootNode.addChildNode(wall)
        }

        // 前沿金边、下方接币盘（只做视觉）
        let lip = box(c.deckWidth + 0.6, 0.18, 0.25, gold)
        lip.position = SCNVector3(0, -0.05, c.deckDepth / 2 + 0.12)
        scene.rootNode.addChildNode(lip)
        let tray = box(c.deckWidth + 1, 0.2, 2.5, gold)
        tray.position = SCNVector3(0, -3.2, c.deckDepth / 2 + 1.4)
        scene.rootNode.addChildNode(tray)

        // 两侧引导斜坡（后部角落）和装饰炮管
        for side: Float in [-1, 1] {
            let ramp = box(1.6, 0.25, 3.2, felt)
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

    // MARK: 金币
    @discardableResult
    func addCoin(at position: SCNVector3, tilt: Float = 0, velocity: SCNVector3 = SCNVector3Zero) -> SCNNode? {
        guard coins.count < config.maxCoins else { return nil }
        let node = SCNNode(geometry: coinGeometry)
        node.position = position
        node.eulerAngles = SCNVector3(tilt, Float.random(in: 0...(2 * .pi)), tilt * 0.5)
        node.castsShadow = true
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: coinGeometry, options: nil))
        body.mass = 0.05
        body.friction = 0.55
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

    /// 从上方投下一枚金币，落到推板顶面（上层台面）。xFraction ∈ [-1, 1]
    func dropCoin(xFraction: Float) {
        let c = config
        let x = max(-1, min(1, xFraction)) * (c.deckWidth / 2 - c.coinRadius - 0.1)
        let pusherTopZ = pusher.presentation.position.z + c.pusherDepth / 2 - 0.55
        addCoin(at: SCNVector3(x, 4.5, pusherTopZ),
                tilt: Float.random(in: -1.2...1.2),
                velocity: SCNVector3(Float.random(in: -0.3...0.3), -2, Float.random(in: 0.5...1.5)))
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
        var removed = 0
        coins.removeAll { node in
            if node.presentation.position.y < -2.5 {
                node.removeFromParentNode()
                removed += 1
                return true
            }
            return false
        }
        if removed > 0 {
            droppedCount += removed
            DispatchQueue.main.async { [weak self] in
                for _ in 0..<removed { self?.onCoinDropped?() }
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
