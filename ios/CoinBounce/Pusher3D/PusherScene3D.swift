import SceneKit
import UIKit

// MARK: - 3D 推币台（SceneKit）
// 坐标：x 向右，y 向上，z 朝向玩家（台面前沿在 +z）。长度单位约等于 1 枚金币的半径。
// 结构：下层台面（固定）+ 推板（运动学刚体，前后往复，顶面就是上层台面）+ 推板上方的固定刮板
//      （推板后退时把上层金币刮落到下层）+ 左右挡板 + 前沿掉落口。
final class PusherScene3D: NSObject, SCNSceneRendererDelegate {

    struct Config {
        var coinRadius: Float = 0.5
        var coinThickness: Float = 0.09   // 薄币：约为半径的 18%（校准半径时按比例更新）
        var deckWidth: Float = 8
        var deckDepth: Float = 7          // 下层台面：z 从 -deckDepth/2 到 +deckDepth/2
        var pusherHeight: Float = 0.7
        var pusherDepth: Float = 5
        var pusherStroke: Float = GameConstants.pusherStroke
        var pusherPeriod: TimeInterval = GameConstants.pusherPeriod
        var maxCoins = 190
        var prefillCoins = 165
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
        // 与普通金币同样的浮雕正面和滚边，只是染成白金色并带柔和自发光（不再是一块纯白圆片）
        let platinum = UIColor(red: 0.85, green: 0.93, blue: 1.0, alpha: 1)
        let glow = UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 1)
        let side = SCNMaterial()
        side.lightingModel = .physicallyBased
        side.diffuse.contents = PusherScene3D.reededEdgeImage()
        side.diffuse.wrapS = .repeat
        side.diffuse.contentsTransform = SCNMatrix4MakeScale(24, 1, 1)
        side.multiply.contents = platinum
        side.emission.contents = glow
        side.emission.intensity = 0.35
        side.metalness.contents = 0.9
        side.roughness.contents = 0.3
        let face = SCNMaterial()
        face.lightingModel = .physicallyBased
        face.diffuse.contents = PusherScene3D.coinFaceImage()
        face.normal.contents = PusherScene3D.coinFaceNormalImage()
        face.multiply.contents = platinum
        face.emission.contents = glow
        face.emission.intensity = 0.3
        face.metalness.contents = 0.85
        face.roughness.contents = 0.3
        g.materials = [side, face, face]
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
        camera.fieldOfView = 24
        camera.zNear = 0.1
        camera.zFar = 100
        // 屏幕空间环境光遮蔽：金币堆叠处、推板下方自然变暗，增强立体感
        camera.screenSpaceAmbientOcclusionIntensity = 1.3
        camera.screenSpaceAmbientOcclusionRadius = 0.25
        let cameraNode = self.cameraNode
        cameraNode.camera = camera
        // 相机拉远、视角收窄：透视变形小，台面前后宽度接近，像参考那样从正前上方看整台；
        // 视角和俯角在视图尺寸确定后由 fitCamera 精确求解
        cameraNode.position = PusherScene3D.cameraPosition
        cameraNode.look(at: SCNVector3(0, -1.3, 0.7))
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
        // 侧面：齿纹边（竖条纹理 + 法线贴图），全金属
        coinMaterial.diffuse.contents = PusherScene3D.reededEdgeImage()
        coinMaterial.diffuse.wrapS = .repeat
        coinMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(24, 1, 1)
        coinMaterial.normal.contents = PusherScene3D.reededEdgeNormalImage()
        coinMaterial.normal.wrapS = .repeat
        coinMaterial.normal.contentsTransform = SCNMatrix4MakeScale(24, 1, 1)
        coinMaterial.metalness.contents = 1.0
        coinMaterial.roughness.contents = 0.32
        // 参考里的金币偏暖、偏深（古铜金），高光是缎面而不是镜面：整体染暖、粗糙度略高
        coinMaterial.multiply.contents = PusherScene3D.coinTint
        // 正反面：原创星形图案 + 浮雕法线贴图（星形和内圈凸起、外缘倒角），金属反射环境光
        let face = SCNMaterial()
        face.lightingModel = .physicallyBased
        face.diffuse.contents = PusherScene3D.coinFaceImage()
        face.normal.contents = PusherScene3D.coinFaceNormalImage()
        face.normal.intensity = 1.0
        face.metalness.contents = 0.95
        face.roughness.contents = 0.32
        face.multiply.contents = PusherScene3D.coinTint
        coinGeometry.materials = [coinMaterial, face, face]   // 侧面、顶面、底面

        // 原创程序纹理：台面菱格绒布、侧板漆面、推板花纹，配色与上半部的紫红 / 金 / 青绿统一
        let felt = material(UIColor.white)
        felt.diffuse.contents = PusherScene3D.feltImage()
        felt.diffuse.wrapS = .repeat; felt.diffuse.wrapT = .repeat
        felt.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        felt.roughness.contents = 0.85
        let wood = material(UIColor(red: 0.55, green: 0.09, blue: 0.32, alpha: 1), metal: 0.35)   // 紫红漆面侧板
        wood.roughness.contents = 0.25
        // 推板：暗紫色金属 + 金色花纹，金属度高、略粗糙，读起来像金属
        let red = material(UIColor.white, metal: 0.8)
        red.diffuse.contents = PusherScene3D.pusherImage()
        red.roughness.contents = 0.3
        let gold = material(UIColor(red: 0.95, green: 0.72, blue: 0.25, alpha: 1), metal: 0.85)
        gold.roughness.contents = 0.25
        let neonTeal = material(UIColor(red: 0.1, green: 0.9, blue: 0.85, alpha: 1))
        neonTeal.emission.contents = UIColor(red: 0.1, green: 0.95, blue: 0.9, alpha: 1)
        let neonGold = material(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
        neonGold.emission.contents = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)

        // 下层台面
        let floor = box(c.deckWidth, 0.4, c.deckDepth, felt)
        floor.position = SCNVector3(0, -0.2, 0)
        staticBody(floor, friction: GameConstants.deckFriction)
        scene.rootNode.addChildNode(floor)

        // 推板（运动学）：从台面后部伸出，前后往复
        let pusherNode = box(c.deckWidth - 0.05, c.pusherHeight, c.pusherDepth, red)
        let restZ = pusherRestZ
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

        // 后挡板（刮板）：前表面正好在推板收回到底时的前沿位置，底边贴着推板顶面。
        // 推板每次完全缩回到挡板后面，顶面上的金币全部被刮下、掉到下层台面
        let scraper = box(c.deckWidth, PusherScene3D.scraperHeight, 0.3, red)
        scraper.position = SCNVector3(0, scraperBottomY + PusherScene3D.scraperHeight / 2, scraperFrontZ - 0.15)
        let scraperEdge = box(c.deckWidth, 0.08, 0.08, gold)
        scraperEdge.position = SCNVector3(0, scraperBottomY + 0.04, scraperFrontZ + 0.02)
        scene.rootNode.addChildNode(scraperEdge)
        staticBody(scraper, friction: 0.2)
        scene.rootNode.addChildNode(scraper)

        // 后墙（装饰 + 防止金币掉到推板后面）
        let back = box(c.deckWidth, 3, 0.3, red)
        back.position = SCNVector3(0, 1.5, restZ - c.pusherDepth / 2 - 0.2)
        staticBody(back, friction: 0.2)
        scene.rootNode.addChildNode(back)

        // 左右边界：不再有可见侧板。透明碰撞墙 + 台面上一条细金边，相机校准后沿屏幕左右边缘摆放（fitCamera），
        // 使推币区域在屏幕上的宽度处处等于上方下落区宽度
        let invisible = SCNMaterial()
        invisible.colorBufferWriteMask = []
        invisible.writesToDepthBuffer = false
        for side: Float in [-1, 1] {
            let wall = box(0.3, 2.4, 1, invisible)
            wall.castsShadow = false
            wall.name = "sideWall"
            let rail = box(0.1, 0.1, 1, gold)
            rail.name = "sideRail"
            wall.addChildNode(rail)
            scene.rootNode.addChildNode(wall)
            sideWalls.append(wall)
            placeSideWall(wall, side: side, back: SCNVector3(side * (c.deckWidth / 2 + 0.15), 0, scraperFrontZ - c.pusherDepth),
                          front: SCNVector3(side * (c.deckWidth / 2 + 0.15), 0, c.deckDepth / 2 + 0.6))
        }

        // 前沿竖直截面：台面前沿下方的立面（深色渐变 + 金色边条 + 顶部发光缝），让玩家看清金币从这里掉落
        let faceMat = material(UIColor.white, metal: 0.4)
        faceMat.diffuse.contents = PusherScene3D.dropFaceImage()
        faceMat.roughness.contents = 0.45
        let dropFace = box(c.deckWidth + 0.6, 2.7, 0.12, faceMat)
        dropFace.position = SCNVector3(0, -1.75, c.deckDepth / 2 - 0.02)
        scene.rootNode.addChildNode(dropFace)

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

        // 两侧引导斜坡（后部角落）
        for side: Float in [-1, 1] {
            // 引导斜坡：在推板上方（不与推板相交），外侧高、内侧低，边缘落下的金币滑到推板顶面
            let ramp = box(PusherScene3D.rampWidth, PusherScene3D.rampThickness, PusherScene3D.rampLength, wood)
            ramp.position = rampCenter(side: side)
            ramp.eulerAngles = SCNVector3(0, 0, side * PusherScene3D.rampAngle)
            staticBody(ramp, friction: 0.12)
            ramp.name = "ramp"
            scene.rootNode.addChildNode(ramp)
            rampNodes.append(ramp)

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
        let restZ = pusherRestZ
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
                let half = min(c.deckWidth / 2, playHalfWidth(z)) - 0.05
                var x = -half + c.coinRadius + (row.isMultiple(of: 2) ? 0.05 : d / 2)
                while x < half - c.coinRadius && placed < c.prefillCoins {
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

    // MARK: 关键几何（测试也用）
    static let scraperHeight: Float = 2.6
    static let rampWidth: Float = 1.3
    static let rampThickness: Float = 0.12
    static let rampLength: Float = 2.2
    static let rampAngle: Float = 0.38          // 约 22°，外侧高、内侧低
    private(set) var rampNodes: [SCNNode] = []

    /// 后挡板前表面 = 下层台面后缘
    var scraperFrontZ: Float { -config.deckDepth / 2 }
    /// 后挡板底边：比推板顶面高一点点，缝隙小于一枚金币厚度，金币钻不过去
    var scraperBottomY: Float { config.pusherHeight + 0.01 }
    /// 推板收回到底时的中心位置：前沿正好与挡板前表面齐平
    var pusherRestZ: Float { scraperFrontZ - config.pusherDepth / 2 }
    /// 推板前沿（收回到底 / 推到最远）
    var pusherFrontZRetracted: Float { pusherRestZ + config.pusherDepth / 2 }
    var pusherFrontZExtended: Float { pusherFrontZRetracted + config.pusherStroke }
    /// 交接平面：挡板前方，落在推板顶面上
    var handoffPlaneZ: Float { scraperFrontZ + config.coinRadius + 0.25 }

    static let coinTint = UIColor(red: 1.0, green: 0.80, blue: 0.52, alpha: 1)
    static let cameraPosition = SCNVector3(0, 15, 21)
    private(set) var sideWalls: [SCNNode] = []
    /// 最近一次 fitCamera 后，台面前沿在视图里的 y
    private(set) var frontEdgeScreenY: CGFloat = 0
    /// 纵深 z 处左右墙之间可用的半宽（墙沿屏幕边缘摆放，越靠前越窄）
    private(set) var playHalfWidth: (Float) -> Float = { _ in 4 }
    /// 交接线左右两端在 3D 中的位置（推板顶面、交接平面上，台面可用宽度的两端）
    var handoffEdgePoints: (left: SCNVector3, right: SCNVector3) {
        let y = config.pusherHeight, z = handoffPlaneZ, half = config.deckWidth / 2
        return (SCNVector3(-half, y, z), SCNVector3(half, y, z))
    }

    /// 求解相机视角和俯角：交接线上台面左右两端正好投影到屏幕上的 fieldLeft / fieldRight（下落区左右边缘），
    /// 交接点投影到 handoffY；然后把左右透明墙摆到「屏幕上始终在这两条竖线上」的位置
    /// frontY：台面前沿（金币掉落处）在视图里的目标高度；给出时同时求相机仰角，让前沿正好落在投币按钮上方
    func fitCamera(viewSize: CGSize, handoffY: CGFloat, fieldLeft: CGFloat, fieldRight: CGFloat, frontY: CGFloat? = nil) {
        guard viewSize.width > 0, viewSize.height > 0, fieldRight > fieldLeft else { return }
        let W = Float(viewSize.width), H = Float(viewSize.height)
        let usable = Float(fieldRight - fieldLeft)
        let target = SCNVector3(0, config.pusherHeight, handoffPlaneZ)

        /// 给定相机位置，求俯角和焦距，使交接线两端对齐下落区边缘、交接点在 handoffY
        func solve(_ P: SCNVector3) -> (pitch: Float, f: Float) {
            let vy = target.y - P.y, vz = target.z - P.z
            let dist = (vy * vy + vz * vz).squareRoot()
            let alpha = atan2(-vy, -vz)           // 交接点在水平线以下的角度
            var beta: Float = 0                   // 交接点在视线上方的角度
            var f: Float = 1                      // 焦距（点）
            for _ in 0..<30 {
                f = usable * dist * cos(beta) / config.deckWidth
                beta = atan((H / 2 - Float(handoffY)) / f)
            }
            return (alpha + beta, f)
        }
        /// 世界点在视图里的 y
        func screenY(_ q: SCNVector3, P: SCNVector3, pitch: Float, f: Float) -> Float {
            let dy = q.y - P.y, dz = q.z - P.z
            let depth = -dz * cos(pitch) - dy * sin(pitch)
            let up = dy * cos(pitch) - dz * sin(pitch)
            return H / 2 - f * up / depth
        }

        var P = cameraNode.position
        if let frontY {
            // 相机绕交接点、在固定距离上调整仰角（二分）：仰角越低台面纵深越「压扁」，前沿越往上
            let front = SCNVector3(0, 0, config.deckDepth / 2)
            let base = PusherScene3D.cameraPosition
            let dist = ((base.y - target.y) * (base.y - target.y) + (base.z - target.z) * (base.z - target.z)).squareRoot()
            func position(_ e: Float) -> SCNVector3 { SCNVector3(0, target.y + dist * sin(e), target.z + dist * cos(e)) }
            var lo: Float = 0.25, hi: Float = 1.35
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                let p = position(mid)
                let s = solve(p)
                if screenY(front, P: p, pitch: s.pitch, f: s.f) > Float(frontY) { hi = mid } else { lo = mid }
            }
            P = position((lo + hi) / 2)
        }
        let (pitch, f) = solve(P)
        frontEdgeScreenY = CGFloat(screenY(SCNVector3(0, 0, config.deckDepth / 2), P: P, pitch: pitch, f: f))
        SCNTransaction.begin()
        cameraNode.position = P
        SCNTransaction.disableActions = true
        cameraNode.eulerAngles = SCNVector3(-pitch, 0, 0)
        cameraNode.camera?.projectionDirection = .horizontal
        cameraNode.camera?.fieldOfView = CGFloat(2 * atan((W / 2) / f) * 180 / .pi)
        SCNTransaction.commit()
        SCNTransaction.flush()   // 立即生效，后面的投影 / 反投影（金币校准、测试）用的是新相机
        // 屏幕横坐标 sx 在高度 h、纵深 z 处对应的世界 x（相机无偏航：x = (sx - W/2)·depth / f）
        func worldX(_ sx: Float, h: Float, z: Float) -> Float {
            let depth = -(z - P.z) * cos(pitch) - (h - P.y) * sin(pitch)
            return (sx - W / 2) * depth / f
        }
        let h = config.pusherHeight * 0.5
        let zBack = scraperFrontZ - config.pusherDepth, zFront = config.deckDepth / 2 + 0.6
        let halfBack = worldX(Float(fieldRight), h: h, z: zBack), halfFront = worldX(Float(fieldRight), h: h, z: zFront)
        playHalfWidth = { z in halfBack + (halfFront - halfBack) * (z - zBack) / (zFront - zBack) }
        for (wall, side) in zip(sideWalls, [Float(-1), 1]) {
            let sx = Float(side < 0 ? fieldLeft : fieldRight)
            let back = SCNVector3(worldX(sx, h: h, z: zBack) + side * 0.15, 0, zBack)
            let front = SCNVector3(worldX(sx, h: h, z: zFront) + side * 0.15, 0, zFront)
            placeSideWall(wall, side: side, back: back, front: front)
        }
    }

    /// 把透明墙（厚 0.3，内侧面在 back→front 连线向内 0.15 处）沿 back→front 摆放
    private func placeSideWall(_ wall: SCNNode, side: Float, back: SCNVector3, front: SCNVector3) {
        let dx = front.x - back.x, dz = front.z - back.z
        let length = (dx * dx + dz * dz).squareRoot()
        (wall.geometry as? SCNBox)?.length = CGFloat(length)
        wall.position = SCNVector3((back.x + front.x) / 2, 1.0, (back.z + front.z) / 2)
        wall.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)
        if let rail = wall.childNodes.first(where: { $0.name == "sideRail" }) {
            (rail.geometry as? SCNBox)?.length = CGFloat(length)
            rail.position = SCNVector3(-side * 0.1, -1.0 + 0.05, 0)   // 紧贴边界外侧，落在屏幕边缘的金色立柱下方
        }
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: wall.geometry!, options: nil))
        body.friction = 0.1
        body.restitution = 0.05
        wall.physicsBody = body
    }

    func rampCenter(side: Float) -> SCNVector3 {
        // 内侧下沿比推板顶面高 0.12，外侧更高
        let halfW = PusherScene3D.rampWidth / 2
        let innerTop = config.pusherHeight + 0.12 + PusherScene3D.rampThickness / 2
        let y = innerTop + sin(PusherScene3D.rampAngle) * halfW
        return SCNVector3(side * (config.deckWidth / 2 - halfW), y, scraperFrontZ + PusherScene3D.rampLength / 2)
    }

    /// 斜坡底面内侧、外侧边缘的高度
    func rampEdgeHeights(side: Float) -> (inner: Float, outer: Float) {
        let c = rampCenter(side: side)
        let dy = sin(PusherScene3D.rampAngle) * PusherScene3D.rampWidth / 2
        let bottom = c.y - PusherScene3D.rampThickness / 2 / cos(PusherScene3D.rampAngle)
        return (bottom - dy, bottom + dy)
    }

    // MARK: 金币尺寸校准（2D → 3D 交接时屏幕上大小一致）

    /// 屏幕点 p 在推板顶面落币平面（z 固定）上对应的世界坐标
    func worldPointOnHandoffPlane(_ p: CGPoint, in view: SCNSceneRenderer) -> SCNVector3? {
        let planeZ = handoffPlaneZ
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
    /// 视图尺寸确定后：先对齐相机，再按 2D 直径校准金币大小（交接平面随金币半径微移，所以再对齐一次）
    func fit(view: SCNSceneRenderer, viewSize: CGSize, handoffY: CGFloat, fieldLeft: CGFloat, fieldRight: CGFloat,
             frontY: CGFloat? = nil, coinDiameter: CGFloat) {
        fitCamera(viewSize: viewSize, handoffY: handoffY, fieldLeft: fieldLeft, fieldRight: fieldRight, frontY: frontY)
        calibrateCoinSize(view: view, viewSize: viewSize, handoffY: handoffY, targetDiameter: coinDiameter)
        fitCamera(viewSize: viewSize, handoffY: handoffY, fieldLeft: fieldLeft, fieldRight: fieldRight, frontY: frontY)
    }

    func calibrateCoinSize(view: SCNSceneRenderer, viewSize: CGSize, handoffY: CGFloat, targetDiameter: CGFloat) {
        guard viewSize.width > 0, targetDiameter > 0 else { return }
        let p = CGPoint(x: viewSize.width / 2, y: handoffY)
        guard let w0 = worldPointOnHandoffPlane(p, in: view),
              let w1 = worldPointOnHandoffPlane(CGPoint(x: p.x + 10, y: p.y), in: view) else { return }
        let worldPerPoint = abs(w1.x - w0.x) / 10
        let radius = Float(targetDiameter / 2) * worldPerPoint
        guard radius > 0.05, abs(radius - config.coinRadius) / config.coinRadius > 0.01 else { return }
        config.coinRadius = radius
        config.coinThickness = radius * 0.18
        coinGeometry.height = CGFloat(config.coinThickness)
        specialGeometry.height = CGFloat(config.coinThickness)
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
        addCoin(at: SCNVector3(x, 4.5, handoffPlaneZ),
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
            let colors = [UIColor(red: 0.30, green: 0.10, blue: 0.40, alpha: 1).cgColor,
                          UIColor(red: 0.14, green: 0.04, blue: 0.20, alpha: 1).cgColor] as CFArray
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

    /// 前沿立面：顶部发光缝、深紫到黑的竖向渐变和金色横纹
    static func dropFaceImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 256)).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 1).cgColor,
                          UIColor(red: 0.25, green: 0.06, blue: 0.22, alpha: 1).cgColor,
                          UIColor(red: 0.04, green: 0.01, blue: 0.04, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.12, 1])!
            cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
            cg.setFillColor(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 0.35).cgColor)
            for y in stride(from: 60, to: 256, by: 48) { cg.fill(CGRect(x: 0, y: y, width: 64, height: 2)) }
        }
    }

    // MARK: 金币贴图：齿纹边、浮雕法线

    static func reededEdgeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor(red: 0.95, green: 0.72, blue: 0.22, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            UIColor(red: 0.62, green: 0.40, blue: 0.06, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 10, y: 0, width: 6, height: 16))
        }
    }

    /// 齿纹边法线：横向正弦起伏
    static func reededEdgeNormalImage() -> UIImage {
        normalMap(width: 32, height: 4) { x, _ in 0.5 + 0.5 * sin(Double(x) / 32 * 2 * .pi) }
    }

    /// 币面浮雕：外缘倒角下沉、内圈凸环、五角星凸起
    static func coinFaceNormalImage() -> UIImage {
        let n = 128
        let star = UIBezierPath()
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let r = i.isMultiple(of: 2) ? Double(n) * 0.26 : Double(n) * 0.12
            let pt = CGPoint(x: Double(n) / 2 + cos(a) * r, y: Double(n) / 2 + sin(a) * r)
            i == 0 ? star.move(to: pt) : star.addLine(to: pt)
        }
        star.close()
        return normalMap(width: n, height: n) { x, y in
            let dx = Double(x) - Double(n) / 2, dy = Double(y) - Double(n) / 2
            let r = (dx * dx + dy * dy).squareRoot() / (Double(n) / 2)
            var h = 0.5
            if r > 0.9 { h -= (r - 0.9) * 4 }                 // 外缘倒角
            if abs(r - 0.72) < 0.04 { h += 0.25 }             // 内圈凸环
            if star.contains(CGPoint(x: x, y: y)) { h += 0.35 } // 星形凸起
            return h
        }
    }

    /// 由高度函数生成切线空间法线贴图
    static func normalMap(width: Int, height: Int, height h: (Int, Int) -> Double) -> UIImage {
        var heights = [Double](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { heights[y * width + x] = h(x, y) } }
        func at(_ x: Int, _ y: Int) -> Double { heights[((y + height) % height) * width + ((x + width) % width)] }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let strength = 2.5
        for y in 0..<height {
            for x in 0..<width {
                let dx = (at(x + 1, y) - at(x - 1, y)) * strength
                let dy = (at(x, y + 1) - at(x, y - 1)) * strength
                let len = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * width + x) * 4
                pixels[i] = UInt8(max(0, min(255, (-dx / len * 0.5 + 0.5) * 255)))
                pixels[i + 1] = UInt8(max(0, min(255, (-dy / len * 0.5 + 0.5) * 255)))
                pixels[i + 2] = UInt8(max(0, min(255, (1 / len * 0.5 + 0.5) * 255)))
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
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
