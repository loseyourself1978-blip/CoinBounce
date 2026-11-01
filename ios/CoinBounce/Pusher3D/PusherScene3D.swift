import Metal
import SceneKit
import UIKit

// MARK: - 3D 推币台（SceneKit）
// 坐标：x 向右，y 向上，z 朝向玩家（台面前沿在 +z）。长度单位约等于 1 枚金币的半径。
// 结构：下层台面（固定）+ 推板（运动学刚体，前后往复，顶面就是上层台面）+ 推板上方的固定刮板
//      （推板后退时把上层金币刮落到下层）+ 左右挡板 + 前沿掉落口。
final class PusherScene3D: NSObject, SCNSceneRendererDelegate {

    struct Config {
        var coinRadius: Float = 0.37       // iPhone 上校准后约 0.37（台面宽 8 对应下落区 80% 屏宽、金币 7.4% 屏宽）
        var coinThickness: Float = 0.37 * PusherScene3D.coinThicknessRatio
        var deckWidth: Float = 8
        var deckDepth: Float = 7          // 下层台面：z 从 -deckDepth/2 到 +deckDepth/2
        var pusherHeight: Float = 0.7
        var pusherDepth: Float = 5
        /// v11.1 按参考：推板只占中间约 34% 屏宽（台面宽 8 对应下落区 80% 屏宽 → 3.4，留一点余量取 3.6），
        /// 两侧是大斜坡；推板前方的接币盘（金币堆所在）约 54% 屏宽 → 5.4
        var pusherWidth: Float = 3.4   // v11.2：参考实测推板两边在 33% / 67% 屏宽 → 0.34 屏宽 / 0.8 → 3.4
        var trayWidth: Float = 4.2      // v11.2：接币盘前端内沿投影到 23% / 77% 屏宽（参考实测；近处透视放大，所以世界宽度比 5.4 窄）
        var pusherStroke: Float = GameConstants.pusherStroke
        var pusherPeriod: TimeInterval = GameConstants.pusherPeriod
        var maxCoins = 400
        var prefillCoins = 150
    }

    let scene = SCNScene()
    private(set) var config: Config
    /// 相机节点（测试里用它做投影计算）
    let cameraNode = SCNNode()
    private(set) var droppedCount = 0          // 掉出前沿的金币数（计分）
    private(set) var rejectedCount = 0         // 达到上限、没能加入台面的金币数（应始终为 0）
    /// 调试：每秒在控制台打印推板上 / 台面上 / 已掉落的金币数和帧率（-autoplay 或 -debugPhysicsLog）
    var logsPhysicsStats = false
    private var logWindowStart: TimeInterval = 0
    private var logFrames = 0
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
        scene.physicsWorld.timeStep = 1.0 / 180.0   // 更细的步长：薄金币被推板挤压时不容易被压进台面

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
        felt.diffuse.contents = PusherScene3D.feltImage(base: PusherScene3D.greenFelt)
        felt.diffuse.wrapS = .repeat; felt.diffuse.wrapT = .repeat
        felt.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        felt.roughness.contents = 0.85
        let wood = material(UIColor(red: 0.68, green: 0.51, blue: 0.28, alpha: 1), metal: 0.2)   // 原木色边框（参考取色 #ae8247）
        wood.roughness.contents = 0.45
        // 斜坡：与台面同色的绿色绒布（参考取色 #388629）
        let slopeFelt = material(UIColor.white)
        slopeFelt.diffuse.contents = PusherScene3D.feltImage(base: PusherScene3D.greenFelt.withBrightness(0.85))
        slopeFelt.diffuse.wrapS = .repeat; slopeFelt.diffuse.wrapT = .repeat
        slopeFelt.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 2, 1)
        slopeFelt.roughness.contents = 0.85
        // 后挡板、后墙：深红绒布（参考取色 #881809）
        let backFelt = material(UIColor.white)
        backFelt.diffuse.contents = PusherScene3D.feltImage(base: PusherScene3D.redFelt)
        backFelt.diffuse.wrapS = .repeat; backFelt.diffuse.wrapT = .repeat
        backFelt.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 1, 1)
        backFelt.roughness.contents = 0.85
        // 推板：暗黄铜金属块（参考取色正面 #755c23、顶面 #382c0e）+ 金色花纹
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
        // 台面加厚到 2、加宽到斜坡外侧之外：薄台面会让高速落下的薄金币直接穿过去（v11.2 验证时发现）
        let floor = box(c.deckWidth + 1.6, 2.0, c.deckDepth, felt)
        floor.position = SCNVector3(0, -1.0, 0)
        staticBody(floor, friction: GameConstants.deckFriction)
        scene.rootNode.addChildNode(floor)

        // 推板（运动学）：从台面后部伸出，前后往复
        // 推板下沿伸进台面 0.2（台面是静态体，运动学推板与它重叠没关系）：推板和台面之间没有缝，薄金币不会被压到推板下面
        let pusherNode = box(c.pusherWidth, c.pusherHeight + PusherScene3D.pusherSink, c.pusherDepth, red)
        let restZ = pusherRestZ
        pusherNode.position = SCNVector3(0, (c.pusherHeight - PusherScene3D.pusherSink) / 2, restZ)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(node: pusherNode, options: nil))
        body.friction = 0.6
        pusherNode.physicsBody = body
        scene.rootNode.addChildNode(pusherNode)
        pusher = pusherNode
        let forward = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(c.pusherStroke), duration: c.pusherPeriod / 2)
        forward.timingMode = .easeInEaseOut
        pusherNode.runAction(.repeatForever(.sequence([forward, forward.reversed()])), forKey: "push")
        // 推板前沿发光边
        let edge = box(c.pusherWidth - 0.05, 0.08, 0.08, neonGold)
        edge.position = SCNVector3(0, (c.pusherHeight + PusherScene3D.pusherSink) / 2 + 0.01, c.pusherDepth / 2 - 0.02)
        pusherNode.addChildNode(edge)

        // 后挡板（刮板）：前表面正好在推板收回到底时的前沿位置，底边贴着推板顶面。
        // 推板每次完全缩回到挡板后面，顶面上的金币全部被刮下、掉到下层台面
        // 挡板加厚到 0.8：推板收回时把金币压向挡板，薄挡板会让金币被挤穿到挡板后面（v11.1 推板上的金币「消失」）
        let scraper = box(c.deckWidth, PusherScene3D.scraperHeight, 0.8, backFelt)
        scraper.position = SCNVector3(0, scraperBottomY + PusherScene3D.scraperHeight / 2, scraperFrontZ - 0.4)
        let scraperEdge = box(c.deckWidth, 0.08, 0.08, gold)
        scraperEdge.position = SCNVector3(0, scraperBottomY + 0.04, scraperFrontZ + 0.02)
        scene.rootNode.addChildNode(scraperEdge)
        staticBody(scraper, friction: 0.2)
        scene.rootNode.addChildNode(scraper)

        // 后墙（装饰 + 防止金币掉到推板后面）
        let back = box(c.deckWidth, 3, 0.3, backFelt)
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
            (wall.geometry as? SCNBox)?.height = 4
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
        // 前沿下方看得见的接币槽：金币从前沿翻落，一路落进槽里（屏幕上在底部金色面板之上），落到槽里才移除
        let trayFloor = box(c.trayWidth + 0.6, 0.2, 1.6, wood)
        trayFloor.position = SCNVector3(0, PusherScene3D.catchTrayY - 0.1, c.deckDepth / 2 + 0.9)
        scene.rootNode.addChildNode(trayFloor)
        let trayFront = box(c.trayWidth + 0.6, 0.45, 0.15, gold)
        trayFront.position = SCNVector3(0, PusherScene3D.catchTrayY + 0.2, c.deckDepth / 2 + 1.7)
        scene.rootNode.addChildNode(trayFront)

        // 两侧斜坡（每侧只有一块，参考布局）：实心块落在台面上，顶面外侧高、内侧低；内侧边从推板两侧（后部）
        // 向前斜着张开到接币盘边缘（前沿），所以斜坡本身就是接币盘的侧壁。前端面是彩色面板（参考左粉右黄）
        for side: Float in [-1, 1] {
            let panel = material(UIColor.white, metal: 0.3)
            panel.diffuse.contents = PusherScene3D.sidePanelImage(left: side < 0)
            panel.roughness.contents = 0.35
            let ramp = SCNNode(geometry: slopeGeometry(side: side, top: slopeFelt, front: panel, other: wood))
            let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: ramp.geometry!, options: [.type: SCNPhysicsShape.ShapeType.convexHull]))
            body.friction = 0.12
            body.restitution = 0.05
            ramp.physicsBody = body
            ramp.name = "ramp"
            ramp.castsShadow = true
            scene.rootNode.addChildNode(ramp)
            rampNodes.append(ramp)
            // 斜面内侧一条木色压边，读得出斜坡的走向
            let back = SCNVector3(side * rampInnerX(atZ: slopeBackZ), rampInnerHeight, slopeBackZ)
            let front = SCNVector3(side * rampInnerX(atZ: slopeFrontZ), rampInnerHeight, slopeFrontZ)
            let dx = front.x - back.x, dz = front.z - back.z
            let lip = box(0.08, 0.08, (dx * dx + dz * dz).squareRoot(), wood)
            lip.position = SCNVector3((back.x + front.x) / 2, rampInnerHeight, (back.z + front.z) / 2)
            lip.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)
            scene.rootNode.addChildNode(lip)
        }

        prefill()
    }

    /// 原创扑克牌牌面：白底圆角、红 / 黑「A」和花色（代码绘制）
    static func playingCardImage(red: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 140, height: 196)).image { ctx in
            let rect = CGRect(x: 0, y: 0, width: 140, height: 196)
            UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 14).fill()
            UIColor(red: 0.75, green: 0.55, blue: 0.3, alpha: 1).setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: 10)
            border.lineWidth = 3
            border.stroke()
            let ink = red ? UIColor(red: 0.8, green: 0.1, blue: 0.12, alpha: 1) : UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40, weight: .black), .foregroundColor: ink]
            ("A" as NSString).draw(at: CGPoint(x: 14, y: 10), withAttributes: attrs)
            // 中间的花色：红心或黑桃（简单几何拼成）
            ink.setFill()
            let cx: CGFloat = 70, cy: CGFloat = 110, r: CGFloat = 22
            let suit = UIBezierPath()
            if red {
                suit.addArc(withCenter: CGPoint(x: cx - r * 0.55, y: cy - r * 0.2), radius: r * 0.6, startAngle: .pi, endAngle: 0, clockwise: true)
                suit.addArc(withCenter: CGPoint(x: cx + r * 0.55, y: cy - r * 0.2), radius: r * 0.6, startAngle: .pi, endAngle: 0, clockwise: true)
                suit.addLine(to: CGPoint(x: cx, y: cy + r * 1.1))
                suit.close()
            } else {
                suit.move(to: CGPoint(x: cx, y: cy - r * 1.1))
                suit.addLine(to: CGPoint(x: cx + r * 1.1, y: cy + r * 0.2))
                suit.addArc(withCenter: CGPoint(x: cx + r * 0.55, y: cy + r * 0.25), radius: r * 0.55, startAngle: 0, endAngle: .pi, clockwise: true)
                suit.addArc(withCenter: CGPoint(x: cx - r * 0.55, y: cy + r * 0.25), radius: r * 0.55, startAngle: 0, endAngle: .pi, clockwise: true)
                suit.close()
                UIBezierPath(rect: CGRect(x: cx - 4, y: cy + r * 0.5, width: 8, height: r * 0.9)).fill()
            }
            suit.fill()
        }
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
    /// 台面极轻微向前倾（重力加 0.5 的向前分量，远小于静摩擦能抵抗的约 2.6）：金币自己不会滑，但被推时更容易整体前移
    static let tableForwardTilt: Float = 0.5
    static let pusherSink: Float = 0.2
    private var baseGravity = SCNVector3(0, -9.8 * 2.2, PusherScene3D.tableForwardTilt)

    /// 推板速度倍率（卡牌「推板加速」）
    func setPusherSpeed(_ multiplier: Double) {
        let c = config
        pusher.removeAction(forKey: "push")
        let forward = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(c.pusherStroke), duration: c.pusherPeriod / 2 / max(0.1, multiplier))
        forward.timingMode = .easeInEaseOut
        // 先回到起点再开始新的往复，避免位置漂移
        let restZ = pusherRestZ
        let home = SCNAction.move(to: SCNVector3(0, (c.pusherHeight - PusherScene3D.pusherSink) / 2, restZ), duration: 0.15)
        pusher.runAction(.sequence([home, .repeatForever(.sequence([forward, forward.reversed()]))]), forKey: "push")
    }

    /// 「轻松掉落」的向前重力分量：必须小于静摩擦能抵抗的大小（金币×台面摩擦 ≈ 0.42×0.32，乘以竖直重力 21.6 ≈ 2.9），
    /// 只让被推动的金币更容易掉，不会让整堆金币自己滑下去（v10.x 用 3.2，选到这张卡时整台金币全部滑落）
    static let easyDropForwardGravity: Float = 1.2
    static var verticalGravity: Float { 9.8 * 2.2 }

    /// 卡牌「轻松掉落」：台面向前微倾（重力加一点向前分量），前沿灯带闪烁
    func setEasyDrop(_ on: Bool) {
        scene.physicsWorld.gravity = on ? SCNVector3(baseGravity.x, baseGravity.y, PusherScene3D.tableForwardTilt + PusherScene3D.easyDropForwardGravity) : baseGravity
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
        guard coins.count < config.maxCoins else { rejectedCount += 1; return nil }
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
        body.continuousCollisionDetectionThreshold = CGFloat(config.coinThickness * 0.5)   // 薄币高速下落时不穿过推板 / 斜坡 / 台面
        body.velocity = velocity
        node.physicsBody = body
        scene.rootNode.addChildNode(node)
        coins.append(node)
        tracks[ObjectIdentifier(node)] = CoinTrack(born: 0)
        return node
    }

    /// 开局预铺：下层台面铺 2～3 层，推板顶面放一层
    private func prefill() {
        // 金币堆从台面前沿一直铺到推板推到最远时的前沿（不留空带），推板每次推出都会顶到金币堆
        let c = config
        let d = c.coinRadius * 2.02
        let backLimit = pusherFrontZExtended + c.coinRadius + 0.02
        var placed = 0
        var layer = 0
        while placed < c.prefillCoins && layer < 2 {   // 参考金币堆 1–2 层（GameConstants.referencePileLayers）
            var row = 0
            // 第一排像真机一样探出前沿约 45%（重心仍在台面上），轻轻一推就会掉
            var z = c.deckDepth / 2 - c.coinRadius * (layer == 0 ? 0.55 : 1.0) - Float(layer) * d * 0.5
            // 上层只铺前半部分，形成前高后低、自然叠放的金币堆
            let limit = backLimit
            while z > limit && placed < c.prefillCoins {
                let half = min(rampInnerX(atZ: z), playHalfWidth(z)) - 0.05
                var x = -half + c.coinRadius + (row.isMultiple(of: 2) ? 0.05 : d / 2)
                while x < half - c.coinRadius && placed < c.prefillCoins {
                    let y = c.coinThickness / 2 + Float(layer) * (c.coinThickness + 0.01) + 0.02
                    addCoin(at: SCNVector3(x + Float.random(in: -0.05...0.05), y, z), tilt: Float.random(in: -0.04...0.04))
                    placed += 1
                    x += d * (layer == 0 ? 1.0 : 1.15)
                }
                z -= d * 0.87 * (layer == 0 ? 1.0 : 1.15)
                row += 1
            }
            layer += 1
        }
    }

    /// 承载场景的视图，用于把 2D 下落区的屏幕位置换算到 3D
    weak var view: SCNView?

    // MARK: 关键几何（测试也用）
    static let scraperHeight: Float = 2.6
    /// 斜坡后部宽度：台面半宽 4 − 推板半宽 1.7 − 0.05
    static let rampWidth: Float = 2.25
    /// 接币槽底面高度（台面前沿下方，金币落进来才移除）
    static let catchTrayY: Float = -0.8   // 接币槽在底部面板上方，金币落进槽的全过程都看得见
    static let rampAngle: Float = 0.28          // 约 16°，外侧高、内侧低（外侧比内侧高约 0.65）；更陡的斜坡会把交接线顶得太高，台面前沿被底部面板挡住
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

    /// v11：直径比 v10.8 大 30%、厚度不变，厚度 / 半径 = 0.18 / 1.3
    static let coinThicknessRatio: Float = 0.18 / 1.3
    static let coinTint = UIColor(red: 1.0, green: 0.80, blue: 0.52, alpha: 1)
    static let cameraPosition = SCNVector3(0, 15, 21)
    private(set) var sideWalls: [SCNNode] = []
    /// 最近一次 fitCamera 后，台面前沿在视图里的 y
    private(set) var frontEdgeScreenY: CGFloat = 0
    /// 纵深 z 处左右墙之间可用的半宽（墙沿屏幕边缘摆放，越靠前越窄）
    private(set) var playHalfWidth: (Float) -> Float = { _ in 4 }
    /// 交接线左右两端在 3D 中的位置（推板顶面、交接平面上，台面可用宽度的两端）
    /// 交接高度：最高表面（斜坡外侧顶边）上方一枚金币半径
    var handoffHeight: Float { rampOuterHeight + config.coinRadius + 0.08 }
    var handoffEdgePoints: (left: SCNVector3, right: SCNVector3) {
        let y = handoffHeight, z = handoffPlaneZ, half = config.deckWidth / 2
        return (SCNVector3(-half, y, z), SCNVector3(half, y, z))
    }

    /// 求解相机视角和俯角：交接线上台面左右两端正好投影到屏幕上的 fieldLeft / fieldRight（下落区左右边缘），
    /// 交接点投影到 handoffY；然后把左右透明墙摆到「屏幕上始终在这两条竖线上」的位置
    /// frontY：台面前沿（金币掉落处）在视图里的目标高度；给出时同时求相机仰角，让前沿正好落在投币按钮上方
    func fitCamera(viewSize: CGSize, handoffY: CGFloat, fieldLeft: CGFloat, fieldRight: CGFloat, frontY: CGFloat? = nil) {
        guard viewSize.width > 0, viewSize.height > 0, fieldRight > fieldLeft else { return }
        let W = Float(viewSize.width), H = Float(viewSize.height)
        let usable = Float(fieldRight - fieldLeft)
        // 交接线对应的 3D 高度在最高表面（斜坡外侧）之上：金币一进入 3D 视图，交接深度上的点就在所有表面上方
        let target = SCNVector3(0, handoffHeight, handoffPlaneZ)

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
            var lo: Float = 0.02, hi: Float = 1.5
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                let p = position(mid)
                let s = solve(p)
                if screenY(front, P: p, pitch: s.pitch, f: s.f) > Float(frontY) { hi = mid } else { lo = mid }
            }
            P = position((lo + hi) / 2)
        }
        let (pitch, f) = solve(P)
        cameraPitch = pitch
        focalPoints = f
        // 交接深度 = 交接线中心点的深度（交接线在最高表面之上，见 handoffHeight）。
        // v11.2 验证：交接线放在推板顶面高度时，斜坡外侧的金币一进视图就已经在斜坡下面，交接直径误差最大 49%
        handoffDepth = -(target.z - P.z) * cos(pitch) - (target.y - P.y) * sin(pitch)
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
        // v11.2：两侧透明墙固定在斜坡外沿（直的，不再随透视收窄）——收窄的墙在后部比斜坡外沿还宽，金币会从缝里掉下去
        for (wall, side) in zip(sideWalls, [Float(-1), 1]) {
            placeSideWall(wall, side: side, back: SCNVector3(side * (config.deckWidth / 2 + 0.15), 0, zBack),
                          front: SCNVector3(side * (config.deckWidth / 2 + 0.15), 0, zFront))
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

    /// 斜坡后端（伸到挡板下面）和前端（台面前沿）
    var slopeBackZ: Float { scraperFrontZ - 0.3 }
    var slopeFrontZ: Float { config.deckDepth / 2 }
    /// 斜坡内侧边的 x：后部紧贴推板两侧，向前张开到接币盘边缘
    func rampInnerX(atZ z: Float) -> Float {
        let back = config.pusherWidth / 2 + 0.05, front = config.trayWidth / 2
        let t = max(0, min(1, (z - pusherFrontZExtended) / (slopeFrontZ - pusherFrontZExtended)))
        return back + (front - back) * t
    }
    /// 斜坡内侧顶边高度（只比推板顶面高一点）和外侧顶边高度
    var rampInnerHeight: Float { scraperBottomY + PusherScene3D.rampInnerRise }
    var rampOuterHeight: Float { rampInnerHeight + tan(PusherScene3D.rampAngle) * (config.deckWidth / 2 - config.pusherWidth / 2 - 0.05) }

    /// 斜坡实心块：底面在台面上，顶面外高内低，内侧边按 rampInnerX 张开。各面单独的材质：顶面绒布、前端面彩色面板、其他木色
    private func slopeGeometry(side: Float, top: SCNMaterial, front: SCNMaterial, other: SCNMaterial) -> SCNGeometry {
        let outer = side * config.deckWidth / 2
        // 后、中（推板推到最远处）、前三个截面，内侧边在中间截面开始张开
        let zs = [slopeBackZ, pusherFrontZExtended, slopeFrontZ]
        var sections: [[SCNVector3]] = []   // 每个截面：内底、外底、外顶、内顶
        for z in zs {
            let inner = side * rampInnerX(atZ: z)
            sections.append([SCNVector3(inner, 0, z), SCNVector3(outer, 0, z),
                             SCNVector3(outer, rampOuterHeight, z), SCNVector3(inner, rampInnerHeight, z)])
        }
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var groups: [[Int32]] = [[], [], []]   // 0 顶面，1 前端面，2 其他
        func face(_ quad: [SCNVector3], group: Int) {
            let u = SCNVector3(quad[1].x - quad[0].x, quad[1].y - quad[0].y, quad[1].z - quad[0].z)
            let v = SCNVector3(quad[2].x - quad[0].x, quad[2].y - quad[0].y, quad[2].z - quad[0].z)
            var n = SCNVector3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let len = max(1e-6, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot())
            n = SCNVector3(n.x / len, n.y / len, n.z / len)
            let base = Int32(vertices.count)
            vertices += quad
            normals += Array(repeating: n, count: 4)
            // 平面投影贴图坐标：按法线主方向选投影平面，0.5 个单位一格
            uvs += quad.map { v in
                abs(n.y) > 0.5 ? CGPoint(x: CGFloat(v.x) * 0.5, y: CGFloat(v.z) * 0.5)
                    : abs(n.z) > 0.5 ? CGPoint(x: CGFloat(v.x) * 0.25 + 0.5, y: CGFloat(-v.y) * 0.5 + 0.5)
                    : CGPoint(x: CGFloat(v.z) * 0.5, y: CGFloat(v.y) * 0.5)
            }
            groups[group] += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        // 顶点顺序按右手法则朝外；左侧（side<0）镜像后要反向
        func oriented(_ q: [SCNVector3]) -> [SCNVector3] { side > 0 ? q : q.reversed() }
        for i in 0..<2 {
            let a = sections[i], b = sections[i + 1]
            face(oriented([a[3], b[3], b[2], a[2]]), group: 0)           // 顶面
            face(oriented([a[0], a[1], b[1], b[0]]), group: 2)           // 底面
            face(oriented([a[0], b[0], b[3], a[3]]), group: 2)           // 内侧面（接币盘 / 推板侧壁）
            face(oriented([a[1], a[2], b[2], b[1]]), group: 2)           // 外侧面
        }
        let back = sections[0], frontSec = sections[2]
        face(oriented([back[0], back[3], back[2], back[1]]), group: 2)    // 后端面
        face(oriented([frontSec[0], frontSec[1], frontSec[2], frontSec[3]]), group: 1)   // 前端面（彩色面板）
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: groups.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        geometry.materials = [top, front, other]
        return geometry
    }

    static let rampInnerRise: Float = 0.06
    /// 斜面顶面内侧、外侧的高度
    func rampEdgeHeights(side: Float) -> (inner: Float, outer: Float) { (rampInnerHeight, rampOuterHeight) }

    /// 斜面顶面在 (x, z) 处的高度；不在斜坡上返回 nil
    func rampTopHeight(atX x: Float, z: Float) -> Float? {
        guard z >= scraperFrontZ, z <= slopeFrontZ else { return nil }
        let inner = rampInnerX(atZ: z), outer = config.deckWidth / 2
        guard abs(x) > inner else { return nil }
        let t = min(1, (abs(x) - inner) / max(0.01, outer - inner))
        return rampInnerHeight + t * (rampOuterHeight - rampInnerHeight)
    }

    /// 斜坡后部（推板旁边）的内侧边，测试用
    var rampInnerX: Float { rampInnerX(atZ: slopeBackZ) }

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
        twoDCoinDiameter = coinDiameter
        fitCamera(viewSize: viewSize, handoffY: handoffY, fieldLeft: fieldLeft, fieldRight: fieldRight, frontY: frontY)
        calibrateCoinSize(view: view, viewSize: viewSize, handoffY: handoffY, targetDiameter: coinDiameter)
        fitCamera(viewSize: viewSize, handoffY: handoffY, fieldLeft: fieldLeft, fieldRight: fieldRight, frontY: frontY)
        // 校准后的半径：交接深度处屏幕直径 = 2D 直径（交接都发生在这个深度上，见 handoffPoint）
        let radius = Float(coinDiameter / 2) * handoffDepth / max(1, focalPoints)
        if radius > 0.05, abs(radius - config.coinRadius) / config.coinRadius > 0.005 {
            setCoinRadius(radius)
        }
        CoinSpriteStore.shared.update(normal: renderCoinSprite(special: false), special: renderCoinSprite(special: true))
        isFitted = true
    }
    /// 相机和金币尺寸已按视图校准（之前不交接，下落金币继续 2D 下落）
    private(set) var isFitted = false

    private func setCoinRadius(_ radius: Float) {
        config.coinRadius = radius
        config.coinThickness = radius * PusherScene3D.coinThicknessRatio
        coinGeometry.height = CGFloat(config.coinThickness)
        specialGeometry.height = CGFloat(config.coinThickness)
        coinGeometry.radius = CGFloat(radius)
        specialGeometry.radius = CGFloat(radius)
        coins.forEach { $0.removeFromParentNode() }
        coins.removeAll()
        tracks.removeAll()
        prefill()
    }

    func calibrateCoinSize(view: SCNSceneRenderer, viewSize: CGSize, handoffY: CGFloat, targetDiameter: CGFloat) {
        guard viewSize.width > 0, targetDiameter > 0 else { return }
        let p = CGPoint(x: viewSize.width / 2, y: handoffY)
        guard let w0 = worldPointOnHandoffPlane(p, in: view),
              let w1 = worldPointOnHandoffPlane(CGPoint(x: p.x + 10, y: p.y), in: view) else { return }
        let worldPerPoint = abs(w1.x - w0.x) / 10
        let radius = Float(targetDiameter / 2) * worldPerPoint
        guard radius > 0.05, abs(radius - config.coinRadius) / config.coinRadius > 0.01 else { return }
        setCoinRadius(radius)
    }

    /// 从 2D 下落区交接：金币出现在与 2D 金币相同的屏幕位置（view 坐标），带向下的速度，保证衔接连续
    func dropCoin(atViewPoint p: CGPoint, special: Bool = false) {
        guard let view, view.bounds.width > 0, let world = spawnPoint(forViewPoint: p, in: view) else {
            dropCoin(xFraction: Float(p.x / max(1, view?.bounds.width ?? 1)) * 2 - 1, special: special)
            return
        }
        // 平着落下（不旋转），带向下速度；落到推板顶面或斜坡上，碰撞后才翻滚
        addCoin(at: world, tilt: Float.random(in: -0.08...0.08),
                velocity: SCNVector3(Float.random(in: -0.3...0.3), -4, Float.random(in: 0.1...0.5)),
                special: special)
    }

    /// 交接点：沿屏幕点 p 的视线，取推板顶面（或斜坡顶面）上方一点的位置。
    /// 在同一条视线上，所以 3D 金币出现的屏幕位置和 2D 金币完全相同，不会跳动
    func spawnPoint(forViewPoint p: CGPoint, in view: SCNSceneRenderer) -> SCNVector3? {
        let near = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let dy = far.y - near.y
        guard dy < -1e-4 else { return nil }
        func point(atHeight h: Float) -> SCNVector3 {
            let t = (h - near.y) / dy
            return SCNVector3(near.x + (far.x - near.x) * t, h, near.z + (far.z - near.z) * t)
        }
        // 从交接平面（推板顶面高度）沿视线往上走，找到第一个高出推板顶面 / 斜坡顶面一点的位置：
        // 金币总是出现在斜坡表面之上，而不是嵌在斜坡里或越过斜坡落到前面
        let c = config
        let clearance = c.coinRadius * 0.6 + 0.1
        var h = c.pusherHeight + clearance
        var q = point(atHeight: h)
        for _ in 0..<200 {
            let floor = rampTopHeight(atX: q.x, z: q.z) ?? (q.z < slopeFrontZ ? c.pusherHeight : 0)
            if q.y >= floor + clearance { break }
            h += 0.02
            q = point(atHeight: h)
        }
        let limit = c.deckWidth / 2 - c.coinRadius - 0.05
        q.x = max(-limit, min(limit, q.x))
        return q
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
    /// 金币分布：在推板顶面上 / 在下层台面上（含斜坡）
    var coinDistribution: (onPusher: Int, onTable: Int) {
        let pusherFront = (pusher?.presentation.position.z ?? pusherRestZ) + config.pusherDepth / 2
        var onPusher = 0, onTable = 0
        for node in coins {
            let p = node.presentation.position
            if p.y > config.pusherHeight - 0.05 && p.z < pusherFront { onPusher += 1 } else if p.y > -0.5 { onTable += 1 }
        }
        return (onPusher, onTable)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if logsPhysicsStats {
            logFrames += 1
            if logWindowStart == 0 { logWindowStart = time }
            if time - logWindowStart >= 1 {
                let d = coinDistribution
                NSLog("PUSHER_STATS fps=%.1f onPusher=%d onTable=%d fallen=%d total=%d rejected=%d",
                      Double(logFrames) / (time - logWindowStart), d.onPusher, d.onTable, droppedCount, coins.count, rejectedCount)
                logFrames = 0
                logWindowStart = time
            }
        }
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
        physicsTicks += 1
        let trackNow = physicsTicks % 4 == 0
        var removed: [Bool] = []
        coins.removeAll { node in
            let p = node.presentation.position
            let id = ObjectIdentifier(node)
            // 保险：金币被推板挤进台面里（看不见）时，立刻放回表面上（每次都记日志，正常应极少发生）
            if p.y < -0.02, p.z < config.deckDepth / 2 - 0.2, abs(p.x) < config.deckWidth / 2 {
                let surface = surfaceHeight(atX: p.x, z: p.z)
                node.position = SCNVector3(p.x, surface + config.coinThickness, p.z)
                node.physicsBody?.velocity = SCNVector3Zero
                node.physicsBody?.angularVelocity = SCNVector4Zero
                node.physicsBody?.resetTransform()
                logEvent("rescuedFromFloor", id: id, detail: "\(p.x),\(p.y),\(p.z)")
                return false
            }
            if trackNow || p.y < PusherScene3D.removeBelowY { updateTrack(id, position: p, time: time) }
            // 只有落进前沿下方接币槽的金币才移除（计分）；其他任何位置都不移除
            if p.y < PusherScene3D.removeBelowY {
                let reason = p.z > config.deckDepth / 2 - 0.05 ? "fellIntoTray" : "lostBelow"
                removalReasons[reason, default: 0] += 1
                logEvent("removed", id: id, detail: "\(reason) at \(p.x),\(p.z) phase=\(tracks[id]?.phase.rawValue ?? "?")")
                tracks[id] = nil
                if reason == "fellIntoTray" { removed.append(node.name == PusherScene3D.specialName) }
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

    // MARK: 金币生命周期（调试日志 + 测试断言）
    /// 落进接币槽的高度：低于这个高度就算落进槽里（接币槽底面在 catchTrayY）
    static let removeBelowY: Float = catchTrayY + 0.25
    enum CoinPhase: String { case falling, onPusher, onRamp, onTable, fallingFront, lostBehindWall, lostSide }
    final class CoinTrack {
        var phase: CoinPhase = .falling
        var wasOnPusher = false
        var scraped = false
        let born: TimeInterval
        init(born: TimeInterval) { self.born = born }
    }
    private var tracks: [ObjectIdentifier: CoinTrack] = [:]
    private var physicsTicks = 0
    /// 各类事件计数：onPusher、scraped、onRamp、onTable、fellFront、lostBehindWall、lostSide
    private(set) var lifecycleCounts: [String: Int] = [:]
    /// 移除原因计数：只允许 fellIntoTray
    private(set) var removalReasons: [String: Int] = [:]
    /// 每次交接的屏幕位置跳变（点）和直径误差（比例）
    private(set) var handoffSamples: [(jump: CGFloat, diameterError: CGFloat)] = []
    var logsLifecycle = false

    private func logEvent(_ event: String, id: ObjectIdentifier, detail: String = "") {
        lifecycleCounts[event, default: 0] += 1
        if logsLifecycle { NSLog("COIN_LIFE %@ %lu %@", event, UInt(bitPattern: id.hashValue) % 100000, detail) }
    }

    private func updateTrack(_ id: ObjectIdentifier, position p: SCNVector3, time: TimeInterval) {
        let track = tracks[id] ?? { let t = CoinTrack(born: time); tracks[id] = t; return t }()
        let c = config
        let pusherFront = (pusher?.presentation.position.z ?? pusherRestZ) + c.pusherDepth / 2
        let phase: CoinPhase
        if p.y < -0.15 && p.z > c.deckDepth / 2 - 0.3 {
            phase = .fallingFront
        } else if p.z < scraperFrontZ - 0.3 && p.y > -0.3 {
            phase = .lostBehindWall
        } else if abs(p.x) > c.deckWidth / 2 + 0.4 {
            phase = .lostSide
        } else if p.y > c.pusherHeight - 0.05, p.z < pusherFront, abs(p.x) < c.pusherWidth / 2 {
            phase = .onPusher
        } else if let top = rampTopHeight(atX: p.x, z: p.z), p.y > top - 0.3 {
            phase = .onRamp
        } else if p.y < c.pusherHeight - 0.05 {
            phase = .onTable
        } else {
            phase = track.phase == .falling ? .falling : track.phase
        }
        guard phase != track.phase else { return }
        track.phase = phase
        switch phase {
        case .onPusher:
            track.wasOnPusher = true
            logEvent("onPusher", id: id)
        case .onTable:
            if track.wasOnPusher && !track.scraped {
                track.scraped = true
                logEvent("scraped", id: id)
            }
            logEvent("onTable", id: id)
        case .onRamp: logEvent("onRamp", id: id)
        case .fallingFront: logEvent("fellFront", id: id)
        case .lostBehindWall: logEvent("lostBehindWall", id: id, detail: "\(p.x),\(p.y),\(p.z)")
        case .lostSide: logEvent("lostSide", id: id, detail: "\(p.x),\(p.y),\(p.z)")
        case .falling: break
        }
    }

    // MARK: 无缝交接（2D 下落金币 → 3D 金币）
    /// 相机俯角、焦距（点）和交接深度：交接深度处 3D 金币的屏幕直径 = 2D 直径（见 fit）
    private(set) var cameraPitch: Float = 0.6
    private(set) var focalPoints: Float = 400
    private(set) var handoffDepth: Float = 20
    private(set) var twoDCoinDiameter: CGFloat = 30

    /// 屏幕点 p 的视线上、相机深度等于交接深度的那个 3D 点
    func handoffPoint(forViewPoint p: CGPoint, in view: SCNSceneRenderer) -> SCNVector3? {
        let near = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        var dir = SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z)
        let len = (dir.x * dir.x + dir.y * dir.y + dir.z * dir.z).squareRoot()
        guard len > 1e-5 else { return nil }
        dir = SCNVector3(dir.x / len, dir.y / len, dir.z / len)
        let cam = cameraNode.position
        let fwd = SCNVector3(0, -sin(cameraPitch), -cos(cameraPitch))
        let along = dir.x * fwd.x + dir.y * fwd.y + dir.z * fwd.z
        guard along > 1e-4 else { return nil }
        let t = handoffDepth / along
        return SCNVector3(cam.x + dir.x * t, cam.y + dir.y * t, cam.z + dir.z * t)
    }

    /// 屏幕点 p 处的下落金币是否该交接了：交接深度上的 3D 点已经降到推板 / 斜坡 / 台面表面上方一枚金币半径以内
    /// 2D 金币每帧下落十几个点，所以向前多看 lookAheadPoints：下一帧就会碰到表面时现在就交接，3D 金币不会生成在斜坡里面
    static let handoffLookAheadPoints: CGFloat = 24
    func isReadyForHandoff(viewPoint p: CGPoint) -> Bool {
        guard isFitted, let view, let q = handoffPoint(forViewPoint: p, in: view) else { return false }
        guard q.z > scraperFrontZ + config.coinRadius * 0.5 else { return false }   // 还在挡板后面（屏幕上看是挡板），继续 2D 下落
        let clearance = config.coinRadius + 0.08
        // 推板在整个行程里随时可能移到金币下面，所以按推板推到最远时的顶面判断（不会出现推板「插进」刚交接的金币）
        if q.y <= surfaceHeight(atX: q.x, z: q.z, pusherFront: pusherFrontZExtended) + clearance { return true }
        guard let next = handoffPoint(forViewPoint: CGPoint(x: p.x, y: p.y + PusherScene3D.handoffLookAheadPoints), in: view) else { return false }
        return next.y <= surfaceHeight(atX: next.x, z: next.z, pusherFront: pusherFrontZExtended) + clearance
    }

    /// (x, z) 处最上面的表面高度：斜坡、推板顶面或台面
    func surfaceHeight(atX x: Float, z: Float, pusherFront fixedFront: Float? = nil) -> Float {
        if let top = rampTopHeight(atX: x, z: z) { return top }
        let pusherFront = fixedFront ?? (pusher?.presentation.position.z ?? pusherRestZ) + config.pusherDepth / 2
        if abs(x) < config.pusherWidth / 2, z < pusherFront { return config.pusherHeight }
        return 0
    }

    /// 交接：在同一屏幕位置、同样屏幕大小生成 3D 金币，正面朝向相机（与 2D 精灵一样是正圆），速度接着 2D 的下落速度
    @discardableResult
    func handOff(viewPoint p: CGPoint, screenVelocity v: CGVector, special: Bool = false) -> SCNNode? {
        guard let view, var q = handoffPoint(forViewPoint: p, in: view) else {
            dropCoin(xFraction: 0, special: special)
            return nil
        }
        // 交接深度上的点如果已经低于表面（屏幕上金币正好在高斜坡前面），沿同一条视线往相机方向移到表面上方：
        // 屏幕位置完全不变，只是离相机近一点（直径误差会记录下来）
        let clearance = config.coinRadius + 0.08
        let original = q
        if q.y < surfaceHeight(atX: q.x, z: q.z) + clearance {
            if logsLifecycle {
                NSLog("COIN_LIFE handoffBelowSurface q=%.2f,%.2f,%.2f surface=%.2f pusherFront=%.2f", q.x, q.y, q.z,
                      surfaceHeight(atX: q.x, z: q.z), (pusher?.presentation.position.z ?? 0) + config.pusherDepth / 2)
            }
            let cam = cameraNode.position
            var lo: Float = 0, hi: Float = 1   // 0 = 交接点，1 = 相机
            for _ in 0..<30 {
                let m = (lo + hi) / 2
                let pt = SCNVector3(q.x + (cam.x - q.x) * m, q.y + (cam.y - q.y) * m, q.z + (cam.z - q.z) * m)
                if pt.y >= surfaceHeight(atX: pt.x, z: pt.z) + clearance { hi = m } else { lo = m }
            }
            q = SCNVector3(q.x + (cam.x - q.x) * hi, q.y + (cam.y - q.y) * hi, q.z + (cam.z - q.z) * hi)
        }
        _ = original
        let wpp = handoffDepth / max(1, focalPoints)          // 交接深度处每点对应的世界长度
        let down = SCNVector3(0, -cos(cameraPitch), sin(cameraPitch))   // 屏幕向下在世界里的方向
        // 接着 2D 的下落速度（换算到交接深度），向下分量限制在 7 以内，避免薄金币高速撞穿台面
        let speedDown = min(Float(max(0, v.dy)) * wpp, 7)
        let velocity = SCNVector3(max(-2, min(2, Float(v.dx) * wpp)), down.y * speedDown, down.z * speedDown)
        guard let node = addCoin(at: q, tilt: 0, velocity: velocity, special: special) else { return nil }
        node.eulerAngles = SCNVector3(Float.pi / 2 - cameraPitch, 0, 0)   // 币面法线指向相机
        node.physicsBody?.resetTransform()
        // 记录交接误差：3D 金币中心和左右边缘投影到屏幕上，与 2D 的位置、直径比较
        let center = view.projectPoint(q)
        let r = config.coinRadius
        let left = view.projectPoint(SCNVector3(q.x - r, q.y, q.z)), right = view.projectPoint(SCNVector3(q.x + r, q.y, q.z))
        let jump = hypot(CGFloat(center.x) - p.x, CGFloat(center.y) - p.y)
        let diameter = CGFloat(abs(right.x - left.x))
        let error = abs(diameter - twoDCoinDiameter) / max(1, twoDCoinDiameter)
        handoffSamples.append((jump, error))
        if logsLifecycle {
            NSLog("COIN_LIFE handoff jump=%.2f diameter3D=%.2f diameter2D=%.2f at %.2f,%.2f,%.2f screen %.0f,%.0f", jump, diameter, twoDCoinDiameter,
                  q.x, q.y, q.z, p.x, p.y)
        }
        return node
    }

    // MARK: 遮挡检查（调试 / 测试）
    /// 逐枚检查还没落进接币槽的金币：中心投影是否在视图内、是否在 panelTopY 之上（没被底部面板挡住）、
    /// 视线上是否有金币以外的不透明物体挡在它前面
    func occlusionReport(in view: SCNView, panelTopY: CGFloat) -> (checked: Int, problems: [String]) {
        var problems: [String] = []
        var checked = 0
        let cam = cameraNode.position
        for node in coins {
            let p = node.presentation.position
            guard p.y > PusherScene3D.removeBelowY else { continue }
            checked += 1
            let s = view.projectPoint(p)
            let sp = CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
            if sp.x < 0 || sp.x > view.bounds.width || sp.y < 0 || sp.y > view.bounds.height {
                problems.append("offscreen \(p.x),\(p.y),\(p.z)"); continue
            }
            if sp.y > panelTopY { problems.append("panel \(p.x),\(p.y),\(p.z) y=\(sp.y)"); continue }
            let coinDistance = ((p.x - cam.x) * (p.x - cam.x) + (p.y - cam.y) * (p.y - cam.y) + (p.z - cam.z) * (p.z - cam.z)).squareRoot()
            let hits = view.hitTest(sp, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
            for hit in hits {
                let n = hit.node
                if n === node || coinsSet.contains(ObjectIdentifier(n)) || n.name == "sideWall" || n.name == "sideRail" { continue }
                let w = hit.worldCoordinates
                let d = ((w.x - cam.x) * (w.x - cam.x) + (w.y - cam.y) * (w.y - cam.y) + (w.z - cam.z) * (w.z - cam.z)).squareRoot()
                if d < coinDistance - config.coinRadius - 0.05 {
                    problems.append("wall(\(n.name ?? "?")) \(p.x),\(p.y),\(p.z)")
                }
                break
            }
        }
        return (checked, problems)
    }
    private var coinsSet: Set<ObjectIdentifier> { Set(coins.map { ObjectIdentifier($0) }) }

    /// 金币堆的层数：接币盘区域（推板推到最远处之前、斜坡之间）里，每枚金币下面压着几枚和它水平重叠的金币，
    /// 层数 = 1 + 这个数；返回 90 百分位和最大值
    func pileLayers() -> (p90: Float, max: Float, count: Int) {
        let c = config
        let pts = coins.map { $0.presentation.position }
            .filter { $0.z > pusherFrontZExtended && $0.z < c.deckDepth / 2 && $0.y > -0.1 && $0.y < 1.0 && abs($0.x) < rampInnerX(atZ: $0.z) }
        guard !pts.isEmpty else { return (0, 0, 0) }
        // 叠放深度：按高度从低到高，每枚金币的层数 = 1 + 它正下方（水平距离 < 半径、更低）金币里最大的层数
        let sorted = pts.sorted { $0.y < $1.y }
        var depth = [Float](repeating: 1, count: sorted.count)
        for i in sorted.indices {
            for j in 0..<i {
                let a = sorted[i], b = sorted[j]
                // 「压在上面」：大部分面积在下面那枚的正上方（中心水平距离 < 0.6 半径），且至少高出半个厚度
                if b.y < a.y - c.coinThickness * 0.5 && ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)) < 0.36 * c.coinRadius * c.coinRadius {
                    depth[i] = max(depth[i], depth[j] + 1)
                }
            }
        }
        var stacks = depth
        stacks.sort()
        return (stacks[min(stacks.count - 1, Int(Float(stacks.count) * 0.9))], stacks.last!, stacks.count)
    }

    // MARK: 2D 下落金币精灵：用同一个 3D 金币模型、同样的灯光和镜头角度渲染（交接前后看起来一模一样）
    func renderCoinSprite(special: Bool, pixels: CGFloat = 192) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let s = SCNScene()
        s.background.contents = UIColor.clear
        s.lightingEnvironment.contents = scene.lightingEnvironment.contents
        s.lightingEnvironment.intensity = scene.lightingEnvironment.intensity
        for light in scene.rootNode.childNodes where light.light != nil {
            let copy = SCNNode()
            copy.light = light.light?.copy() as? SCNLight
            copy.light?.castsShadow = false
            copy.eulerAngles = light.eulerAngles
            s.rootNode.addChildNode(copy)
        }
        let geometry = (special ? specialGeometry : coinGeometry).copy() as! SCNGeometry
        let coin = SCNNode(geometry: geometry)
        coin.eulerAngles = SCNVector3(Float.pi / 2 - cameraPitch, 0, 0)
        s.rootNode.addChildNode(coin)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.usesOrthographicProjection = true
        cam.camera?.orthographicScale = Double(config.coinRadius)
        cam.camera?.zNear = 0.01
        cam.camera?.zFar = 50
        let fwd = SCNVector3(0, -sin(cameraPitch), -cos(cameraPitch))
        cam.position = SCNVector3(-fwd.x * 10, -fwd.y * 10, -fwd.z * 10)
        cam.eulerAngles = SCNVector3(-cameraPitch, 0, 0)
        s.rootNode.addChildNode(cam)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = s
        renderer.pointOfView = cam
        return renderer.snapshot(atTime: 0, with: CGSize(width: pixels, height: pixels), antialiasingMode: .multisampling4X)
    }

    var coinCount: Int { coins.count }

    /// 每枚金币的当前位置（测试用，键为节点对象标识）
    var coinPositions: [ObjectIdentifier: SCNVector3] {
        Dictionary(uniqueKeysWithValues: coins.map { (ObjectIdentifier($0), $0.presentation.position) })
    }

    /// 测试用：在屏幕点上投一枚，返回 3D 金币节点
    @discardableResult
    func dropTestCoin(atViewPoint p: CGPoint) -> SCNNode? {
        guard let view, let world = spawnPoint(forViewPoint: p, in: view) else { return nil }
        return addCoin(at: world, velocity: SCNVector3(0, -4, 0.2))
    }

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
    static let greenFelt = UIColor(red: 0.22, green: 0.53, blue: 0.16, alpha: 1)   // 参考取色 #388629
    static let redFelt = UIColor(red: 0.53, green: 0.09, blue: 0.04, alpha: 1)     // 参考取色 #881809

    /// 接币盘两侧的彩色侧柜面板（原创渐变 + 斜纹）：左粉紫、右金黄
    static func sidePanelImage(left: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            let cg = ctx.cgContext
            let colors = (left
                ? [UIColor(red: 0.95, green: 0.35, blue: 0.65, alpha: 1).cgColor, UIColor(red: 0.45, green: 0.2, blue: 0.75, alpha: 1).cgColor]
                : [UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1).cgColor, UIColor(red: 0.9, green: 0.55, blue: 0.1, alpha: 1).cgColor]) as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 128, y: 128), options: [])
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor)
            cg.setLineWidth(6)
            for k in stride(from: -128, through: 256, by: 28) {
                cg.move(to: CGPoint(x: k, y: 0)); cg.addLine(to: CGPoint(x: k + 128, y: 128))
            }
            cg.strokePath()
        }
    }

    static func feltImage(base: UIColor = greenFelt) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            let cg = ctx.cgContext
            base.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            cg.setStrokeColor(base.withBrightness(1.25).withAlphaComponent(0.6).cgColor)
            cg.setLineWidth(2)
            for k in stride(from: -128, through: 256, by: 32) {
                cg.move(to: CGPoint(x: k, y: 0)); cg.addLine(to: CGPoint(x: k + 128, y: 128))
                cg.move(to: CGPoint(x: k + 128, y: 0)); cg.addLine(to: CGPoint(x: k, y: 128))
            }
            cg.strokePath()
            UIColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 0.35).setFill()
            for x in stride(from: 0, through: 128, by: 32) {
                for y in stride(from: 0, through: 128, by: 32) { cg.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)) }
            }
        }
    }

    /// 推板：深紫红底 + 金色波纹花边
    static func pusherImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 256, height: 128)).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.46, green: 0.36, blue: 0.14, alpha: 1).cgColor,
                          UIColor(red: 0.22, green: 0.17, blue: 0.06, alpha: 1).cgColor] as CFArray
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

extension UIColor {
    /// 按倍数调整亮度（HSB）
    func withBrightness(_ factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: sat, brightness: min(1, b * factor), alpha: a)
    }
}

/// 交给 2D 下落场景使用的金币精灵（由 3D 场景用同一个金币模型渲染）
final class CoinSpriteStore {
    static let shared = CoinSpriteStore()
    private(set) var normal: UIImage?
    private(set) var special: UIImage?
    private(set) var version = 0
    func update(normal: UIImage?, special: UIImage?) {
        guard let normal else { return }
        self.normal = normal
        self.special = special
        version += 1
    }
}
