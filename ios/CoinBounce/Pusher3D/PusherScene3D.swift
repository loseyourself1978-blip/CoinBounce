import Metal
import SceneKit
import UIKit

// MARK: - 3D 推币机（SceneKit）
// v11.3：整台推币机和每一枚金币都在 3D 里，从投币口一直到掉进接币槽，同一个 3D 金币，没有 2D→3D 交接。
// 机器的每个部件按参考录屏（1206×2622，iPhone 17）逐帧测出的屏幕框摆放：固定相机（俯角 26°），
// 把参考里部件的屏幕位置沿视线投回 3D（与地面、推板顶面等平面求交）得到世界坐标，所以投影回屏幕正好落在测量框里。
// 坐标：x 向右，y 向上，z 朝向玩家；下层台面 y = 0，相机在 (0, cameraHeight, 0)。

/// 参考录屏里测出的屏幕位置（像素，1206×2622 帧）。其他机型按同样的屏幕比例换算
enum ReferenceBoxes {
    static let frame = CGSize(width: 1206, height: 2622)
    // 推板：后墙（推板顶面后沿）、前沿收回到底 / 推到最远（逐帧跟踪黑色前脸上沿：1982–2076，周期约 3.3 秒）
    static let wallY: CGFloat = 1970
    static let pusherFrontRetractedY: CGFloat = 1982
    static let pusherFrontExtendedY: CGFloat = 2076
    static let pusherFaceHeight: CGFloat = 45          // 黑色前脸 2065–2110
    static let pusherX: ClosedRange<CGFloat> = 408...800
    // 斜坡：外端（贴屏幕边）和内侧低端（推板顶面侧边正上方），绿色顶面 + 铜色前沿
    static let rampOuterX: CGFloat = 70, rampOuterTopY: CGFloat = 1815, rampOuterBottomY: CGFloat = 1885
    static let rampInnerX: CGFloat = 415, rampInnerTopY: CGFloat = 1965, rampInnerBottomY: CGFloat = 2010
    // 推板两侧铜柱、两侧绿色台阶（下层）、台阶下铜条
    static let postLeftX: ClosedRange<CGFloat> = 312...405, postRightX: ClosedRange<CGFloat> = 800...895
    static let postY: ClosedRange<CGFloat> = 2045...2160
    static let shelfLeftX: ClosedRange<CGFloat> = 40...312, shelfRightX: ClosedRange<CGFloat> = 895...1168
    static let shelfY: ClosedRange<CGFloat> = 2045...2140
    static let railY: ClosedRange<CGFloat> = 2140...2200
    // 金币堆（下层台面）、波浪铜前沿、下方左右彩色面板
    static let pileX: ClosedRange<CGFloat> = 272...935, pileY: ClosedRange<CGFloat> = 2130...2310
    static let lipX: ClosedRange<CGFloat> = 300...905, lipY: ClosedRange<CGFloat> = 2290...2380
    static let panelLeftX: ClosedRange<CGFloat> = 125...310, panelRightX: ClosedRange<CGFloat> = 895...1080
    static let panelY: ClosedRange<CGFloat> = 2215...2400
    // 底部面板、金色标牌、六边形投币按钮、BONUS 轨道、两侧炮管
    static let bottomFrame = CGRect(x: 40, y: 2370, width: 1128, height: 210)
    static let bottomLabel = CGRect(x: 150, y: 2410, width: 880, height: 130)
    static let dropButton = CGRect(x: 603 - 95, y: 2470 - 107.5, width: 190, height: 215)
    static let bonusBar = CGRect(x: 370, y: 1748, width: 490, height: 10)
    static let cannonLeft = CGRect(x: 40, y: 1690, width: 120, height: 140)
    static let cannonRight = CGRect(x: 1050, y: 1690, width: 120, height: 140)
    /// 参考：金币从投币口到第一次落在推板顶面 / 斜坡上约 1.75 秒
    static let fallSeconds: Double = 1.75

    static func x(_ px: CGFloat, _ size: CGSize) -> CGFloat { px / frame.width * size.width }
    static func y(_ px: CGFloat, _ size: CGSize) -> CGFloat { px / frame.height * size.height }
    static func rect(_ r: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: x(r.minX, size), y: y(r.minY, size), width: x(r.width, size), height: y(r.height, size))
    }
}

/// 按视图尺寸算出的整台机器的世界坐标（由参考屏幕框沿视线投回 3D 得到）
struct MachineGeometry {
    let viewSize: CGSize
    // 相机：整屏视图，焦距和俯角一起求解（scratchpad 里的最小二乘）——
    // 参考金币堆里金币椭圆长短轴比 0.41–0.45 → 看金币堆（屏幕 84% 高处）的视线约 26° 俯角；
    // 落在推板上的金币与金币堆前排金币的屏幕大小比约 1.15。两者同时满足：焦距 3.48 倍屏宽、相机俯角 14°
    let pitch: Float = 14 * .pi / 180
    let cameraHeight: Float = 16.8
    var focal: Float { Float(viewSize.width) * 3.48 }

    var cameraPosition: SCNVector3 { SCNVector3(0, cameraHeight, 0) }
    var forward: SCNVector3 { SCNVector3(0, -sin(pitch), -cos(pitch)) }

    /// 屏幕点（点）对应的视线方向（世界坐标，未归一化）
    func ray(_ sx: CGFloat, _ sy: CGFloat) -> SCNVector3 {
        let cx = Float(sx - viewSize.width / 2), cy = -Float(sy - viewSize.height / 2), cz = -focal
        let a = -pitch
        return SCNVector3(cx, cy * cos(a) - cz * sin(a), cy * sin(a) + cz * cos(a))
    }
    func hitY(_ sx: CGFloat, _ sy: CGFloat, y: Float) -> SCNVector3 {
        let d = ray(sx, sy), t = (y - cameraHeight) / d.y
        return SCNVector3(d.x * t, y, d.z * t)
    }
    func hitZ(_ sx: CGFloat, _ sy: CGFloat, z: Float) -> SCNVector3 {
        let d = ray(sx, sy), t = z / d.z
        return SCNVector3(d.x * t, cameraHeight + d.y * t, z)
    }
    /// 视线与过点 p0、法线为相机前向的平面（金币下落平面）的交点
    func hitPlane(_ sx: CGFloat, _ sy: CGFloat, through p0: SCNVector3) -> SCNVector3 {
        let d = ray(sx, sy), n = forward
        let c = cameraPosition
        let t = ((p0.x - c.x) * n.x + (p0.y - c.y) * n.y + (p0.z - c.z) * n.z) / (d.x * n.x + d.y * n.y + d.z * n.z)
        return SCNVector3(c.x + d.x * t, c.y + d.y * t, c.z + d.z * t)
    }
    func depth(_ p: SCNVector3) -> Float {
        let c = cameraPosition
        return (p.x - c.x) * forward.x + (p.y - c.y) * forward.y + (p.z - c.z) * forward.z
    }
    func sx(_ px: CGFloat) -> CGFloat { ReferenceBoxes.x(px, viewSize) }
    func sy(_ px: CGFloat) -> CGFloat { ReferenceBoxes.y(px, viewSize) }
    var cx: CGFloat { viewSize.width / 2 }

    // MARK: 推板
    var pusherFrontExtendedZ: Float { hitY(cx, sy(ReferenceBoxes.pusherFrontExtendedY + ReferenceBoxes.pusherFaceHeight), y: 0).z }
    var pusherHeight: Float { hitZ(cx, sy(ReferenceBoxes.pusherFrontExtendedY), z: pusherFrontExtendedZ).y }
    var wallZ: Float { hitY(cx, sy(ReferenceBoxes.wallY), y: pusherHeight).z }
    /// 推板收回时的前沿：参考里几乎收到墙根（1982 像素），我们留到下落平面前方一枚金币，
    /// 任何时候落下的金币下面都有推板顶面（不会落到推板前脸和金币堆之间）
    var pusherFrontRetractedZ: Float {
        max(hitY(cx, sy(ReferenceBoxes.pusherFrontRetractedY), y: pusherHeight).z, fallPlaneZ + PusherScene3D.nominalCoinRadius + 0.15)
    }
    var pusherStroke: Float { pusherFrontExtendedZ - pusherFrontRetractedZ }
    var pusherHalfWidth: Float {
        let r = abs(hitY(sx(ReferenceBoxes.pusherX.upperBound), sy(ReferenceBoxes.pusherFrontExtendedY), y: pusherHeight).x)
        let l = abs(hitY(sx(ReferenceBoxes.pusherX.lowerBound), sy(ReferenceBoxes.pusherFrontExtendedY), y: pusherHeight).x)
        return (r + l) / 2
    }
    // MARK: 下层台面（金币堆）
    var lipZ: Float { hitY(cx, sy(ReferenceBoxes.lipY.lowerBound), y: 0).z }
    func pileHalfWidth(atZ z: Float) -> Float {
        // 金币堆左右边在屏幕上是竖直的（参考 272 / 935 像素）：沿这条屏幕竖线投到台面上
        let back = abs(hitY(sx(ReferenceBoxes.pileX.upperBound), sy(ReferenceBoxes.pileY.lowerBound), y: 0).x)
        let backZ = hitY(sx(ReferenceBoxes.pileX.upperBound), sy(ReferenceBoxes.pileY.lowerBound), y: 0).z
        let front = abs(hitY(sx(ReferenceBoxes.pileX.upperBound), sy(ReferenceBoxes.pileY.upperBound), y: 0).x)
        let frontZ = hitY(sx(ReferenceBoxes.pileX.upperBound), sy(ReferenceBoxes.pileY.upperBound), y: 0).z
        let t = max(0, min(1, (z - backZ) / (frontZ - backZ)))
        return back + (front - back) * t
    }
    // MARK: 斜坡（推板深度处、悬在推板两侧上方）
    /// 斜坡前沿伸到下落平面前方，边上落下的金币一定落在斜坡上；内侧低端仍对准参考的屏幕位置 (415, 1965)
    var rampFrontZ: Float { fallPlaneZ + PusherScene3D.nominalCoinRadius + 0.25 }
    var rampInnerHeight: Float { hitZ(sx(ReferenceBoxes.rampInnerX), sy(ReferenceBoxes.rampInnerTopY), z: rampFrontZ).y }
    var rampInnerX: Float { abs(hitZ(sx(ReferenceBoxes.rampInnerX), sy(ReferenceBoxes.rampInnerTopY), z: rampFrontZ).x) }
    var rampOuter: SCNVector3 { hitZ(sx(ReferenceBoxes.rampOuterX), sy(ReferenceBoxes.rampOuterTopY), z: rampFrontZ) }
    var rampOuterBottomHeight: Float { hitZ(sx(ReferenceBoxes.rampOuterX), sy(ReferenceBoxes.rampOuterBottomY), z: rampFrontZ).y }
    var rampInnerBottomHeight: Float { hitZ(sx(ReferenceBoxes.rampInnerX), sy(ReferenceBoxes.rampInnerBottomY), z: rampFrontZ).y }
    // MARK: 铜柱、台阶、面板
    var postFrontZ: Float { hitY(sx((ReferenceBoxes.postLeftX.lowerBound + ReferenceBoxes.postLeftX.upperBound) / 2), sy(ReferenceBoxes.postY.upperBound), y: 0).z }
    func postX(_ r: ClosedRange<CGFloat>) -> (Float, Float) {
        (hitY(sx(r.lowerBound), sy(ReferenceBoxes.postY.upperBound), y: 0).x, hitY(sx(r.upperBound), sy(ReferenceBoxes.postY.upperBound), y: 0).x)
    }
    var postTop: Float { hitZ(sx(358), sy(ReferenceBoxes.postY.lowerBound), z: postFrontZ).y }
    var shelfHeight: Float { postTop * 0.9 }
    var shelfZ: (back: Float, front: Float) {
        (hitY(sx(176), sy(ReferenceBoxes.shelfY.lowerBound), y: shelfHeight).z, hitY(sx(176), sy(ReferenceBoxes.shelfY.upperBound), y: shelfHeight).z)
    }
    func shelfX(_ r: ClosedRange<CGFloat>) -> (Float, Float) {
        let z = shelfZ.front
        return (hitZ(sx(r.lowerBound), sy(ReferenceBoxes.shelfY.upperBound), z: z).x, hitZ(sx(r.upperBound), sy(ReferenceBoxes.shelfY.upperBound), z: z).x)
    }
    var railBottom: Float { hitZ(sx(176), sy(ReferenceBoxes.railY.upperBound), z: shelfZ.front).y }
    func frontRect(x r: ClosedRange<CGFloat>, y yr: ClosedRange<CGFloat>, z: Float) -> (minX: Float, maxX: Float, minY: Float, maxY: Float) {
        let a = hitZ(sx(r.lowerBound), sy(yr.lowerBound), z: z), b = hitZ(sx(r.upperBound), sy(yr.upperBound), z: z)
        return (min(a.x, b.x), max(a.x, b.x), min(a.y, b.y), max(a.y, b.y))
    }
    // MARK: 金币下落平面、金币大小
    /// 下落平面：后墙前方的竖直平面（z 固定），在后背板之前，下落的金币不会跑到墙后面
    var fallPlaneZ: Float { wallZ + PusherScene3D.nominalCoinRadius + 0.12 }
    /// 落点：推板顶面上、下落平面正下方
    var landingPoint: SCNVector3 { SCNVector3(0, pusherHeight, fallPlaneZ) }
    /// 金币半径：落点处屏幕直径 = 7.4% 屏宽（v11.0 定下的金币大小）
    var coinRadius: Float { Float(viewSize.width) * 0.037 * depth(landingPoint) / focal }
    /// 屏幕上的一个点数在落点处对应的世界长度
    var worldPerPoint: Float { depth(landingPoint) / focal }
    /// 后背板（红绒布竖板）：挡住后墙后面的推板和台面，顶边在 BONUS 区下沿
    var backPanelZ: Float { wallZ - 0.7 }
    /// 后背板顶边的屏幕位置（点）：BONUS 区下沿（参考约 1830 像素，炮管下沿）
    var backPanelTopScreenY: CGFloat { sy(1830) }
}

final class PusherScene3D: NSObject, SCNSceneRendererDelegate {

    struct Config {
        var coinRadius: Float = 0.42
        var coinThickness: Float = 0.42 * PusherScene3D.coinThicknessRatio
        var pusherPeriod: TimeInterval = GameConstants.pusherPeriod
        var maxCoins = 400
        var prefillCoins = 200
    }

    let scene = SCNScene()
    private(set) var config: Config
    private(set) var geo: MachineGeometry
    /// 相机节点（测试里用它做投影计算）
    let cameraNode = SCNNode()
    weak var view: SCNView?
    private(set) var droppedCount = 0          // 掉进接币槽的金币数（计分）
    private(set) var rejectedCount = 0         // 达到上限、没能生成的金币数（应始终为 0）
    var logsPhysicsStats = false
    var logsLifecycle = false
    private var logWindowStart: TimeInterval = 0
    private var logFrames = 0
    /// 有金币掉进接币槽；参数为是否特殊金币（主线程回调）
    var onCoinDropped: ((_ isSpecial: Bool) -> Void)?
    /// 下落中的金币越过战斗区 / 水果排 / BONUS 轨道（按屏幕投影位置判断，主线程回调）
    var onCrossBattle: (() -> Void)?
    var onCrossFruit: ((_ x: CGFloat) -> Void)?
    var onCrossBonus: ((_ x: CGFloat) -> Void)?
    /// 屏幕上的事件线（点）：战斗区、水果排、BONUS 轨道（金币在 BONUS 线处解除平面约束，落向推板 / 斜坡）
    private(set) var battleLineY: CGFloat = 0, fruitLineY: CGFloat = 0, releaseLineY: CGFloat = 0
    /// 底部面板顶边（点）：金币在它下面就被面板挡住（声明的遮挡物）
    private(set) var panelTopY: CGFloat = 0

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

    /// 金币列表：渲染线程（物理回调）和主线程（投币、检查）都会访问，统一加锁
    private let coinLock = NSRecursiveLock()
    private var _coins: [SCNNode] = []
    private var coins: [SCNNode] { coinLock.lock(); defer { coinLock.unlock() }; return _coins }
    private func withCoins<T>(_ body: (inout [SCNNode]) -> T) -> T { coinLock.lock(); defer { coinLock.unlock() }; return body(&_coins) }
    /// 等待在渲染线程生成的下落金币（主线程投币时放进来）
    private var pendingSpawns: [(CGPoint, CGVector, Bool)] = []
    private let coinGeometry: SCNCylinder
    private let coinMaterial = SCNMaterial()
    private var pusher: SCNNode!
    private let machineRoot = SCNNode()
    private let pegRoot = SCNNode()
    private var materials: [String: SCNMaterial] = [:]
    private(set) var lastFPS: Double = 0
    private var frameCount = 0
    private var windowStart: TimeInterval = 0
    var onStats: ((_ fps: Double, _ coins: Int, _ awake: Int) -> Void)?

    // 碰撞类别：机器、金币（落定后）、下落中的金币、格挡钉。
    // 不能用 2：那是 SceneKit 保留给静态体的类别，静态体默认不和类别 2 碰撞（碰撞要双方的掩码都允许），金币会穿过台面
    static let catMachine = 1, catCoin = 4, catFalling = 8, catPeg = 16

    init(config: Config = Config(), viewSize: CGSize = CGSize(width: 402, height: 874)) {
        self.config = config
        geo = MachineGeometry(viewSize: viewSize)
        coinGeometry = SCNCylinder(radius: CGFloat(config.coinRadius), height: CGFloat(config.coinThickness))
        coinGeometry.radialSegmentCount = 28
        super.init()
        buildScene()
        apply(geometry: MachineGeometry(viewSize: viewSize))
    }

    // MARK: 灯光、材质、相机
    private func buildScene() {
        scene.physicsWorld.gravity = baseGravity
        scene.physicsWorld.timeStep = 1.0 / 180.0
        scene.background.contents = nil      // 透明：3D 视图铺满全屏，盖在 2D 界面上，只画机器和金币
        let camera = SCNCamera()
        camera.projectionDirection = .horizontal
        camera.zNear = 0.1
        camera.zFar = 200
        camera.screenSpaceAmbientOcclusionIntensity = 1.2
        camera.screenSpaceAmbientOcclusionRadius = 0.3
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // 主光：前上方，柔和阴影；补光：环境光偏暗（参考整体偏暗、金属高光明显）
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.light!.castsShadow = true
        key.light!.shadowMode = .deferred
        key.light!.shadowRadius = 5
        key.light!.shadowSampleCount = 12
        key.light!.shadowColor = UIColor.black.withAlphaComponent(0.6)
        key.eulerAngles = SCNVector3(-1.05, 0, 0)
        scene.rootNode.addChildNode(key)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 350
        scene.rootNode.addChildNode(ambient)
        // 基于图像的环境光照（IBL）：金属铜件、金币的反射
        scene.lightingEnvironment.contents = PusherScene3D.environmentImage()
        scene.lightingEnvironment.intensity = 1.6

        coinMaterial.lightingModel = .physicallyBased
        coinMaterial.diffuse.contents = PusherScene3D.reededEdgeImage()
        coinMaterial.diffuse.wrapS = .repeat
        coinMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(28, 1, 1)
        coinMaterial.normal.contents = PusherScene3D.reededEdgeNormalImage()
        coinMaterial.normal.wrapS = .repeat
        coinMaterial.normal.contentsTransform = SCNMatrix4MakeScale(28, 1, 1)
        coinMaterial.metalness.contents = 1.0
        coinMaterial.roughness.contents = 0.25
        coinMaterial.multiply.contents = PusherScene3D.coinTint
        let face = SCNMaterial()
        face.lightingModel = .physicallyBased
        face.diffuse.contents = PusherScene3D.coinFaceImage()
        face.normal.contents = PusherScene3D.coinFaceNormalImage()
        face.metalness.contents = 1.0
        face.roughness.contents = 0.3
        face.multiply.contents = PusherScene3D.coinTint
        coinGeometry.materials = [coinMaterial, face, face]

        func pbr(_ color: UIColor, metal: CGFloat, rough: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color
            m.metalness.contents = metal
            m.roughness.contents = rough
            return m
        }
        materials["copper"] = pbr(UIColor(red: 0.78, green: 0.45, blue: 0.25, alpha: 1), metal: 1, rough: 0.3)
        materials["brass"] = pbr(UIColor(red: 0.85, green: 0.66, blue: 0.3, alpha: 1), metal: 1, rough: 0.3)
        materials["gold"] = pbr(UIColor(red: 0.95, green: 0.74, blue: 0.3, alpha: 1), metal: 1, rough: 0.25)
        let felt = pbr(.white, metal: 0, rough: 0.9)
        felt.diffuse.contents = PusherScene3D.feltImage(base: PusherScene3D.greenFelt)
        felt.diffuse.wrapS = .repeat; felt.diffuse.wrapT = .repeat
        felt.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 4, 1)
        materials["felt"] = felt
        materials["pusherTop"] = pbr(UIColor(red: 0.26, green: 0.24, blue: 0.12, alpha: 1), metal: 0.6, rough: 0.45)   // 暗橄榄色
        materials["pusherFace"] = pbr(UIColor(red: 0.03, green: 0.03, blue: 0.03, alpha: 1), metal: 0.2, rough: 0.6)  // 黑色前脸
        materials["backFelt"] = pbr(PusherScene3D.redFelt, metal: 0, rough: 0.9)
        let pink = pbr(.white, metal: 0.2, rough: 0.4)
        pink.diffuse.contents = PusherScene3D.sidePanelImage(left: true)
        materials["panelLeft"] = pink
        let yellow = pbr(.white, metal: 0.2, rough: 0.4)
        yellow.diffuse.contents = PusherScene3D.sidePanelImage(left: false)
        materials["panelRight"] = yellow
        let invisible = SCNMaterial()
        invisible.colorBufferWriteMask = []
        invisible.writesToDepthBuffer = false
        materials["invisible"] = invisible

        scene.rootNode.addChildNode(machineRoot)
        scene.rootNode.addChildNode(pegRoot)
    }

    // MARK: 按视图尺寸搭建整台机器（参考屏幕框 → 世界坐标）
    func apply(geometry g: MachineGeometry) {
        geo = g
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        cameraNode.position = g.cameraPosition
        cameraNode.eulerAngles = SCNVector3(-g.pitch, 0, 0)
        cameraNode.camera?.fieldOfView = CGFloat(2 * atan(Float(g.viewSize.width) / 2 / g.focal) * 180 / .pi)
        SCNTransaction.commit()
        SCNTransaction.flush()
        machineRoot.childNodes.forEach { $0.removeFromParentNode() }
        withCoins { list in
            list.forEach { $0.removeFromParentNode() }
            list.removeAll()
            tracks.removeAll()
        }
        setCoinRadius(g.coinRadius)
        buildMachine(g)
        prefill()
    }

    private func setCoinRadius(_ radius: Float) {
        config.coinRadius = radius
        config.coinThickness = radius * PusherScene3D.coinThicknessRatio
        coinGeometry.radius = CGFloat(radius)
        coinGeometry.height = CGFloat(config.coinThickness)
        specialGeometry.radius = CGFloat(radius)
        specialGeometry.height = CGFloat(config.coinThickness)
    }

    private func node(_ name: String, box w: Float, _ h: Float, _ d: Float, at p: SCNVector3, _ m: String, physics: Bool = true, friction: CGFloat = 0.3) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: CGFloat(min(w, h, d) * 0.08))
        g.materials = [materials[m]!]
        let n = SCNNode(geometry: g)
        n.name = name
        n.position = p
        if physics {
            let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: g, options: nil))
            body.friction = friction
            body.restitution = 0.05
            body.categoryBitMask = PusherScene3D.catMachine
            n.physicsBody = body
        }
        machineRoot.addChildNode(n)
        return n
    }

    private func buildMachine(_ g: MachineGeometry) {
        #if DEBUG
        NSLog("MACHINE view=%.0fx%.0f h=%.3f wallZ=%.3f frontRet=%.3f frontExt=%.3f stroke=%.3f halfP=%.3f lipZ=%.3f pileHalfBack=%.3f pileHalfFront=%.3f rampFrontZ=%.3f rampInnerX=%.3f rampOuter=%.3f,%.3f fallZ=%.3f coinR=%.3f backPanelZ=%.3f postFrontZ=%.3f postTop=%.3f",
              g.viewSize.width, g.viewSize.height, g.pusherHeight, g.wallZ, g.pusherFrontRetractedZ, g.pusherFrontExtendedZ, g.pusherStroke,
              g.pusherHalfWidth, g.lipZ, g.pileHalfWidth(atZ: g.pusherFrontExtendedZ), g.pileHalfWidth(atZ: g.lipZ),
              g.rampFrontZ, g.rampInnerX, g.rampOuter.x, g.rampOuter.y, g.fallPlaneZ, g.coinRadius, g.backPanelZ, g.postFrontZ, g.postTop)
        #endif
        let h = g.pusherHeight
        let wallZ = g.wallZ, frontExt = g.pusherFrontExtendedZ, lipZ = g.lipZ
        let halfP = g.pusherHalfWidth
        let wide = abs(g.rampOuter.x) + 1.5
        rampNodes.removeAll()
        // 下层台面：从后背板一直到波浪前沿（后背板后面不放东西）
        let floorBackZ = g.backPanelZ - 0.2
        _ = node("table", box: wide * 2, 2, lipZ - floorBackZ, at: SCNVector3(0, -1, (lipZ + floorBackZ) / 2), "felt",
                 friction: GameConstants.deckFriction)
        // 推板（运动学）：暗橄榄色顶面 + 黑色前脸；下沿伸进台面，金币不会被压到推板下面。
        // 长度 = 推到最远时的前沿到后背板，收回时后端伸到后背板后面（看不见）
        let pusherDepth = frontExt - (g.backPanelZ + 0.05)
        let sink: Float = 0.2
        let pg = SCNBox(width: CGFloat(halfP * 2), height: CGFloat(h + sink), length: CGFloat(pusherDepth), chamferRadius: 0.02)
        let top = materials["pusherTop"]!, face = materials["pusherFace"]!
        pg.materials = [face, top, top, top, top, top]   // 前、右、后、左、上、下
        let p = SCNNode(geometry: pg)
        p.name = "pusher"
        let restZ = g.pusherFrontRetractedZ - pusherDepth / 2
        p.position = SCNVector3(0, (h - sink) / 2, restZ)
        let body = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: pg, options: nil))
        body.friction = PusherScene3D.pusherTopFriction
        body.categoryBitMask = PusherScene3D.catMachine
        p.physicsBody = body
        machineRoot.addChildNode(p)
        pusher = p
        pusherRestPosition = p.position
        pusherDepthValue = pusherDepth
        startPusher(multiplier: 1)
        // 后墙：推板顶面上方一道低矮的墙（推板收回时挡住顶面上的金币），红绒布
        _ = node("backWall", box: wide * 2, 0.35, 0.6, at: SCNVector3(0, h + 0.01 + 0.175, wallZ - 0.3), "backFelt")
        // 后背板：竖直红绒布，从台面到 BONUS 区下沿，挡住后墙后面
        let panelTop = g.hitZ(g.cx, g.backPanelTopScreenY, z: g.backPanelZ).y
        _ = node("backPanel", box: wide * 2, panelTop, 0.2, at: SCNVector3(0, panelTop / 2, g.backPanelZ - 0.1), "backFelt", physics: true)
        // 斜坡：每侧一块薄板，内侧低端在推板顶面侧边正上方，外端贴屏幕边；绿色顶面 + 铜色前沿
        for side: Float in [-1, 1] {
            let inner = SCNVector3(side * g.rampInnerX, g.rampInnerHeight, g.rampFrontZ)
            let outer = SCNVector3(side * abs(g.rampOuter.x), g.rampOuter.y, g.rampFrontZ)
            let dx = outer.x - inner.x, dy = outer.y - inner.y
            let length = (dx * dx + dy * dy).squareRoot()
            let depth: Float = g.rampFrontZ - g.backPanelZ
            let plate = SCNBox(width: CGFloat(length), height: 0.08, length: CGFloat(depth), chamferRadius: 0.02)
            plate.materials = [materials["felt"]!]
            let ramp = SCNNode(geometry: plate)
            ramp.name = side < 0 ? "rampLeft" : "rampRight"
            ramp.position = SCNVector3((inner.x + outer.x) / 2, (inner.y + outer.y) / 2 - 0.04, g.rampFrontZ - depth / 2)
            ramp.eulerAngles = SCNVector3(0, 0, atan2(dy, dx) + (side < 0 ? .pi : 0))
            let rb = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: plate, options: nil))
            rb.friction = PusherScene3D.rampFriction
            rb.categoryBitMask = PusherScene3D.catMachine
            ramp.physicsBody = rb
            machineRoot.addChildNode(ramp)
            rampNodes.append(ramp)
            // 斜坡前沿的挡边（看不见，高出斜面 0.3）：金币只能顺着斜坡滑到推板上，不会从斜坡前沿滚落到台阶上
            let guardBox = SCNBox(width: CGFloat(length), height: 0.6, length: 0.12, chamferRadius: 0)
            guardBox.materials = [materials["invisible"]!]
            let guardNode = SCNNode(geometry: guardBox)
            guardNode.name = "rampGuard"
            guardNode.position = SCNVector3((inner.x + outer.x) / 2, (inner.y + outer.y) / 2 + 0.2, g.rampFrontZ + 0.06)
            guardNode.eulerAngles = ramp.eulerAngles
            let gb = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: guardBox, options: nil))
            gb.categoryBitMask = PusherScene3D.catMachine
            guardNode.physicsBody = gb
            machineRoot.addChildNode(guardNode)
            // 铜色前沿：斜坡前端下方的立面（外端高、内端低）
            let path = UIBezierPath()
            path.move(to: CGPoint(x: CGFloat(inner.x), y: CGFloat(inner.y)))
            path.addLine(to: CGPoint(x: CGFloat(outer.x), y: CGFloat(outer.y)))
            path.addLine(to: CGPoint(x: CGFloat(outer.x), y: CGFloat(g.rampOuterBottomHeight)))
            path.addLine(to: CGPoint(x: CGFloat(inner.x), y: CGFloat(g.rampInnerBottomHeight)))
            path.close()
            let trimShape = SCNShape(path: path, extrusionDepth: 0.12)
            trimShape.materials = [materials["copper"]!]
            let trim = SCNNode(geometry: trimShape)
            trim.name = side < 0 ? "rampTrimLeft" : "rampTrimRight"
            trim.position = SCNVector3(0, 0, g.rampFrontZ - 0.06)
            machineRoot.addChildNode(trim)
        }
        // 推板两侧铜柱（立在下层台面上）
        for (name, r) in [("postLeft", ReferenceBoxes.postLeftX), ("postRight", ReferenceBoxes.postRightX)] {
            let (x0, x1) = g.postX(r)
            // 铜柱只到它顶面在屏幕上的上沿（参考 2045 像素）那么深，后面不再延伸
            let back = g.hitY(g.sx((r.lowerBound + r.upperBound) / 2), g.sy(ReferenceBoxes.postY.lowerBound), y: g.postTop).z
            let d: Float = max(0.2, g.postFrontZ - back)
            _ = node(name, box: abs(x1 - x0), g.postTop, d, at: SCNVector3((x0 + x1) / 2, g.postTop / 2, g.postFrontZ - d / 2), "copper")
        }
        // 推板两侧的导轨：从推板侧面到金币堆侧墙、从后背板到铜柱，比推板顶面高一点，
        // 推板顶面边上的金币不会掉进铜柱后面看不见的空隙
        for side: Float in [-1, 1] {
            let x0 = halfP + 0.03, x1 = g.pileHalfWidth(atZ: g.postFrontZ) + 0.45
            let z0 = g.backPanelZ, z1 = g.postFrontZ
            _ = node(side < 0 ? "pusherGuideLeft" : "pusherGuideRight", box: x1 - x0, h + 0.3, z1 - z0,
                     at: SCNVector3(side * (x0 + x1) / 2, (h + 0.3) / 2, (z0 + z1) / 2), "copper", friction: 0.1)
        }
        // 两侧绿色台阶（下层）和台阶下铜条
        let sz = g.shelfZ
        for (name, r) in [("shelfLeft", ReferenceBoxes.shelfLeftX), ("shelfRight", ReferenceBoxes.shelfRightX)] {
            let (x0, x1) = g.shelfX(r)
            let d = sz.front - sz.back
            _ = node(name, box: abs(x1 - x0), g.shelfHeight, d, at: SCNVector3((x0 + x1) / 2, g.shelfHeight / 2, sz.front - d / 2), "felt")
            let railH = g.shelfHeight - g.railBottom
            _ = node(name + "Rail", box: abs(x1 - x0), railH, 0.2, at: SCNVector3((x0 + x1) / 2, g.railBottom + railH / 2, sz.front + 0.1), "copper", physics: false)
        }
        // 金币堆两侧（透明碰撞墙，沿屏幕竖线）：从推板前沿到波浪前沿
        for side: Float in [-1, 1] {
            let z0 = g.postFrontZ - 0.3, z1 = lipZ + 0.3
            let x0 = side * (g.pileHalfWidth(atZ: z0) + 0.15), x1 = side * (g.pileHalfWidth(atZ: z1) + 0.15)
            let dx = x1 - x0, dz = z1 - z0
            let w = node(side < 0 ? "pileWallLeft" : "pileWallRight", box: 0.3, 3, (dx * dx + dz * dz).squareRoot(),
                         at: SCNVector3((x0 + x1) / 2, 1.5, (z0 + z1) / 2), "invisible", friction: 0.1)
            w.eulerAngles = SCNVector3(0, atan2(dx, dz), 0)
            w.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: w.geometry!, options: nil))
            w.physicsBody?.categoryBitMask = PusherScene3D.catMachine
            w.castsShadow = false
        }
        // 波浪铜前沿：台面前沿下方的立面，下沿呈波浪、中间低
        let lip = g.frontRect(x: ReferenceBoxes.lipX, y: ReferenceBoxes.lipY, z: lipZ)
        // 参考：前沿是凸起的铜边，金币堆被它挡住、整齐地排着，推板的压力够大时才从上面挤下去
        let lipH = PusherScene3D.lipRise
        let wave = UIBezierPath()
        wave.move(to: CGPoint(x: CGFloat(lip.minX), y: CGFloat(lipH)))
        wave.addLine(to: CGPoint(x: CGFloat(lip.maxX), y: CGFloat(lipH)))
        let steps = 24
        for i in (0...steps).reversed() {
            let t = CGFloat(i) / CGFloat(steps)
            let x = CGFloat(lip.minX) + (CGFloat(lip.maxX) - CGFloat(lip.minX)) * t
            let dip = sin(t * .pi)                       // 中间更低
            let ripple = 0.5 + 0.5 * cos(t * .pi * 8)    // 波浪
            let y = CGFloat(lip.minY) * (0.55 + 0.3 * dip + 0.15 * ripple)
            wave.addLine(to: CGPoint(x: x, y: y))
        }
        wave.close()
        let lipShape = SCNShape(path: wave, extrusionDepth: 0.25)
        lipShape.materials = [materials["copper"]!]
        let lipNode = SCNNode(geometry: lipShape)
        lipNode.name = "lip"
        lipNode.position = SCNVector3(0, 0, lipZ + 0.125)
        machineRoot.addChildNode(lipNode)
        // 凸起铜边的碰撞体：比台面高 lipRise
        _ = node("lipCollider", box: lip.maxX - lip.minX, lipH + 0.4, 0.25, at: SCNVector3((lip.minX + lip.maxX) / 2, (lipH - 0.4) / 2, lipZ + 0.125), "invisible", friction: 0.3)
        easyDropGlow = lipNode
        // 下方左右彩色面板（金框）
        for (name, r, m) in [("panelLeft", ReferenceBoxes.panelLeftX, "panelLeft"), ("panelRight", ReferenceBoxes.panelRightX, "panelRight")] {
            let f = g.frontRect(x: r, y: ReferenceBoxes.panelY, z: lipZ + 0.3)
            let n = node(name, box: f.maxX - f.minX, f.maxY - f.minY, 0.1, at: SCNVector3((f.minX + f.maxX) / 2, (f.minY + f.maxY) / 2, lipZ + 0.3), m, physics: false)
            let frame = SCNBox(width: CGFloat(f.maxX - f.minX) + 0.12, height: CGFloat(f.maxY - f.minY) + 0.12, length: 0.06, chamferRadius: 0.03)
            frame.materials = [materials["gold"]!]
            let fn = SCNNode(geometry: frame)
            fn.name = name + "Frame"
            fn.position = SCNVector3(0, 0, -0.06)
            n.addChildNode(fn)
        }
    }

    private var pusherRestPosition = SCNVector3Zero
    private var pusherDepthValue: Float = 10
    private(set) var rampNodes: [SCNNode] = []
    private weak var easyDropGlow: SCNNode?

    private func startPusher(multiplier: Double) {
        pusher.removeAction(forKey: "push")
        let forward = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(geo.pusherStroke), duration: config.pusherPeriod / 2 / max(0.1, multiplier))
        forward.timingMode = .easeInEaseOut
        let home = SCNAction.move(to: pusherRestPosition, duration: 0.1)
        pusher.runAction(.sequence([home, .repeatForever(.sequence([forward, forward.reversed()]))]), forKey: "push")
    }

    /// 推板速度倍率（卡牌「推板加速」）
    func setPusherSpeed(_ multiplier: Double) { startPusher(multiplier: multiplier) }

    /// 台面极轻微向前倾（远小于静摩擦）：金币自己不滑，被推时更容易整体前移
    static let tableForwardTilt: Float = 0.25
    static let easyDropForwardGravity: Float = 1.2
    static var verticalGravity: Float { 9.8 * 2.2 }
    private var baseGravity = SCNVector3(0, -9.8 * 2.2, PusherScene3D.tableForwardTilt)
    /// 卡牌「轻松掉落」：台面向前微倾，前沿闪烁
    func setEasyDrop(_ on: Bool) {
        scene.physicsWorld.gravity = on ? SCNVector3(baseGravity.x, baseGravity.y, PusherScene3D.tableForwardTilt + PusherScene3D.easyDropForwardGravity) : baseGravity
        easyDropGlow?.removeAllActions()
        if on {
            easyDropGlow?.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.5, duration: 0.25), .fadeOpacity(to: 1, duration: 0.25)])))
        } else {
            easyDropGlow?.opacity = 1
        }
    }

    // MARK: 视图尺寸确定后：按视图搭建机器、按 2D 界面放置下落区的格挡钉和事件线
    private(set) var isFitted = false
    func fit(viewSize: CGSize, layout: GameLayout) {
        if MachineGeometry(viewSize: viewSize).viewSize != geo.viewSize || !isFitted {
            apply(geometry: MachineGeometry(viewSize: viewSize))
        }
        battleLineY = layout.dropField.midY
        fruitLineY = layout.fruitBar.midY
        releaseLineY = layout.bonusLane.midY
        panelTopY = ReferenceBoxes.y(ReferenceBoxes.bottomFrame.minY, viewSize)
        releaseDepth = geo.depth(geo.hitZ(geo.cx, releaseLineY, z: geo.fallPlaneZ))
        buildPegs(layout)
        isFitted = true
    }

    /// 下落平面上的格挡：2D 老虎机符号格、水果钉的屏幕位置投到下落平面上（看不见，只有碰撞），
    /// 再加下落区左右两道墙。金币在平面内弹跳，和 2D 画面里的钉子完全对应
    private func buildPegs(_ layout: GameLayout) {
        pegRoot.childNodes.forEach { $0.removeFromParentNode() }
        let g = geo, z = g.fallPlaneZ
        let axis = SCNVector3(Float.pi / 2, 0, 0)   // 圆柱轴沿 z（垂直于下落平面）
        func peg(_ s: CGPoint, radius: CGFloat) {
            let c = g.hitZ(s.x, s.y, z: z)
            // 金币外观按深度缩放（屏幕上大小不变），但碰撞半径是原大小：钉子碰撞半径相应减小，
            // 使屏幕上「金币边碰到钉子边」时正好发生碰撞
            let d = g.depth(c)
            // 最小 0.08：太细的钉子在金币高速经过时会被「穿进去」再弹出来，看起来像跳了一下
            let pegR = max(0.05, Float(radius) * d / g.focal + config.coinRadius * (d / releaseDepth - 1))
            let cyl = SCNCylinder(radius: CGFloat(pegR), height: CGFloat(config.coinRadius * 4))
            let n = SCNNode(geometry: cyl)
            n.geometry?.materials = [materials["invisible"]!]
            n.position = c
            n.eulerAngles = axis
            let b = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: cyl, options: nil))
            b.categoryBitMask = PusherScene3D.catPeg
            b.restitution = 0.38
            b.friction = 0.08
            n.physicsBody = b
            n.name = "peg"
            pegRoot.addChildNode(n)
        }
        for o in layout.slotObstacles { peg(o, radius: layout.slotObstacleRadius) }
        for o in layout.fruitPins { peg(o, radius: layout.fruitPinRadius) }
        // 左右墙：投币口到 BONUS 线，沿屏幕上下落区的左右边缘
        for sxv in [layout.fieldMinX - layout.coinRadius, layout.fieldMaxX + layout.coinRadius] {
            let a = g.hitZ(sxv, layout.sliderTrack.minY, z: z), b = g.hitZ(sxv, layout.bonusLane.maxY, z: z)
            // 屏幕上的竖直边缘投到下落平面上不是世界竖直线（透视），墙沿 a→b 倾斜，内侧面始终贴着屏幕边缘
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            let box = SCNBox(width: 0.2, height: CGFloat(len), length: CGFloat(config.coinRadius * 4), chamferRadius: 0)
            let n = SCNNode(geometry: box)
            n.geometry?.materials = [materials["invisible"]!]
            let tilt = atan2(dx, -dy)
            let out: Float = a.x > 0 ? 0.1 : -0.1
            n.position = SCNVector3((a.x + b.x) / 2 + out * cos(tilt), (a.y + b.y) / 2 + out * sin(tilt), (a.z + b.z) / 2)
            n.eulerAngles = SCNVector3(0, 0, tilt)
            let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: box, options: nil))
            body.categoryBitMask = PusherScene3D.catPeg
            n.physicsBody = body
            n.name = "fieldWall"
            pegRoot.addChildNode(n)
        }
    }

    // MARK: 金币
    @discardableResult
    func addCoin(at position: SCNVector3, tilt: Float = 0, velocity: SCNVector3 = SCNVector3Zero, special: Bool = false, falling: Bool = false) -> SCNNode? {
        coinLock.lock(); defer { coinLock.unlock() }
        guard _coins.count < config.maxCoins else { rejectedCount += 1; return nil }
        // 物理节点不带几何体，外观放在子节点里：下落中按深度缩放外观时不会动到物理体
        let node = SCNNode()
        let visual = SCNNode(geometry: special ? specialGeometry : coinGeometry)
        visual.name = "coinVisual"
        visual.castsShadow = true
        node.addChildNode(visual)
        if special { node.name = PusherScene3D.specialName }
        node.position = position
        node.eulerAngles = SCNVector3(tilt, Float.random(in: 0...(2 * .pi)), tilt * 0.5)
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: coinGeometry, options: nil))
        body.mass = 0.05
        body.friction = GameConstants.pusherCoinFriction
        body.rollingFriction = 0.08
        body.restitution = 0.08
        body.damping = 0.15
        body.angularDamping = 0.35
        body.allowsResting = true
        body.continuousCollisionDetectionThreshold = CGFloat(config.coinThickness * 0.5)
        body.velocity = velocity
        body.categoryBitMask = PusherScene3D.catCoin
        body.collisionBitMask = PusherScene3D.catMachine | PusherScene3D.catCoin
        node.physicsBody = body
        let track = CoinTrack(born: CACurrentMediaTime())
        track.falling = falling
        tracks[ObjectIdentifier(node)] = track
        _coins.append(node)
        scene.rootNode.addChildNode(node)
        return node
    }

    /// 投币：在屏幕点（COIN 滑块出口）生成一枚 3D 金币，正面朝相机，约束在下落平面里，在格挡之间弹跳下落。
    /// 主线程调用时先排队，下一帧在渲染线程生成（物理回调也在渲染线程，避免两边同时改金币列表）
    func spawnFallingCoin(atScreen s: CGPoint, screenVelocity v: CGVector = .zero, special: Bool = false) {
        coinLock.lock()
        pendingSpawns.append((s, v, special))
        coinLock.unlock()
    }

    @discardableResult
    func makeFallingCoin(atScreen s: CGPoint, screenVelocity v: CGVector, special: Bool) -> SCNNode? {
        let g = geo
        let p = g.hitZ(s.x, s.y, z: g.fallPlaneZ)
        let wpp = g.depth(p) / g.focal
        let velocity = SCNVector3(Float(v.dx) * wpp, -Float(v.dy) * wpp / cos(g.pitch), 0)
        guard let node = addCoin(at: p, velocity: velocity, special: special, falling: true) else { return nil }
        node.eulerAngles = SCNVector3(Float.pi / 2 - g.pitch, 0, 0)   // 币面法线指向相机
        node.childNodes.first?.scale = fallScale(at: p)
        let body = node.physicsBody!
        body.resetTransform()
        body.velocityFactor = SCNVector3(1, 1, 0)          // 只在竖直的下落平面里运动
        body.allowsResting = false                         // 下落中不休眠（刚生成时速度为 0，会直接休眠、不受重力）
        body.angularVelocityFactor = SCNVector3Zero
        body.categoryBitMask = PusherScene3D.catFalling
        body.collisionBitMask = PusherScene3D.catPeg | PusherScene3D.catFalling
        body.damping = GameConstants.fallLinearDamping
        body.restitution = 0.38
        body.friction = 0.08
        let track = tracks[ObjectIdentifier(node)]!
        track.phase = .falling
        track.falling = true
        track.lastScreen = s
        return node
    }

    /// 下落中金币的外观缩放：让它在屏幕上的直径一直等于 BONUS 线（解除约束处）的直径，到 BONUS 线时正好是 1
    private var releaseDepth: Float = 1
    private func fallScale(at p: SCNVector3) -> SCNVector3 {
        let s = max(0.3, min(1.5, geo.depth(p) / releaseDepth))
        return SCNVector3(s, s, s)
    }

    /// 金币越过 BONUS 线：解除平面约束，位置和速度不变，落向推板顶面 / 斜坡，碰到后自然翻滚
    private func release(_ node: SCNNode, track: CoinTrack) {
        track.falling = false
        track.releasedAt = CACurrentMediaTime()
        guard let body = node.physicsBody else { return }
        node.childNodes.first?.scale = SCNVector3(1, 1, 1)
        body.velocityFactor = SCNVector3(1, 1, 1)
        body.angularVelocityFactor = SCNVector3(1, 1, 1)
        body.allowsResting = true
        // 解除约束时给一点绕水平轴的转动：竖着落下的金币碰到推板顶面后倒下平躺，不会靠着墙立住
        body.angularVelocity = SCNVector4(1, 0, 0, Float.random(in: 2.5...4) * (Bool.random() ? 1 : -1))
        body.categoryBitMask = PusherScene3D.catCoin
        body.collisionBitMask = PusherScene3D.catMachine | PusherScene3D.catCoin
        body.damping = 0.15
        body.restitution = 0.08
        body.friction = GameConstants.pusherCoinFriction
    }

    /// 开局预铺：下层台面金币堆两层（参考 2–3 层），紧贴推板前脸、铺满到波浪前沿
    private func prefill() {
        let c = config, g = geo
        let d = c.coinRadius * 2.02
        var placed = 0
        for layer in 0..<2 {
            var row = 0
            var z = g.lipZ - c.coinRadius - 0.03 - Float(layer) * d * 0.5   // 第一排紧贴凸起的铜边
            while z > g.pusherFrontExtendedZ + c.coinRadius && placed < c.prefillCoins {
                // 铜柱前沿之后（推板两侧是实心导轨）只铺推板宽度，之前才铺满金币堆宽度
                let half = (z < g.postFrontZ + c.coinRadius ? g.pusherHalfWidth : g.pileHalfWidth(atZ: z)) - 0.05
                var x = -half + c.coinRadius + (row.isMultiple(of: 2) ? 0.02 : d / 2)
                while x < half - c.coinRadius && placed < c.prefillCoins {
                    let y = c.coinThickness / 2 + Float(layer) * (c.coinThickness + 0.01) + 0.02
                    addCoin(at: SCNVector3(x + Float.random(in: -0.04...0.04), y, z), tilt: Float.random(in: -0.04...0.04))
                    placed += 1
                    x += d * (layer == 0 ? 1.0 : 1.15)
                }
                z -= d * 0.87 * (layer == 0 ? 1.0 : 1.15)
                row += 1
            }
        }
        // 预铺的金币不是从投币口来的
        for t in tracks.values { t.prefilled = true; t.phase = .onPile }
    }

    var coinCount: Int { coins.count }
    var coinPositions: [ObjectIdentifier: SCNVector3] {
        Dictionary(uniqueKeysWithValues: coins.map { (ObjectIdentifier($0), $0.presentation.position) })
    }
    var pusherFrontZ: Float { (pusher?.presentation.position.z ?? pusherRestPosition.z) + pusherDepthValue / 2 }

    // MARK: 每帧：下落平面约束、事件线、统计
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        coinLock.lock()
        let spawns = pendingSpawns
        pendingSpawns.removeAll()
        coinLock.unlock()
        for (s, v, special) in spawns { makeFallingCoin(atScreen: s, screenVelocity: v, special: special) }
        if logsPhysicsStats {
            logFrames += 1
            if logWindowStart == 0 { logWindowStart = time }
            if time - logWindowStart >= 1 {
                NSLog("PUSHER_STATS fps=%.1f total=%d fallen=%d rejected=%d", Double(logFrames) / (time - logWindowStart), coins.count, droppedCount, rejectedCount)
                logFrames = 0
                logWindowStart = time
            }
        }
        frameCount += 1
        if windowStart == 0 { windowStart = time }
        if time - windowStart >= 2 {
            lastFPS = Double(frameCount) / (time - windowStart)
            onStats?(lastFPS, coins.count, coins.filter { $0.physicsBody?.isResting == false }.count)
            frameCount = 0
            windowStart = time
        }
        sampleScreen(renderer)
        #if DEBUG
        if logsLifecycle, Int(time * 2) != lastDebugTick {
            lastDebugTick = Int(time * 2)
            if let t = machineRoot.childNode(withName: "table", recursively: false) {
                let (lo, hi) = t.boundingBox
                NSLog("COIN_DEBUG table body=%d cat=%d coll=%d type=%d pos=%.2f,%.2f,%.2f bbox=%.2f..%.2f y %.2f..%.2f z %.2f..%.2f machineNodes=%d",
                      t.physicsBody == nil ? 0 : 1, t.physicsBody?.categoryBitMask ?? -1, t.physicsBody?.collisionBitMask ?? -1,
                      t.physicsBody?.type.rawValue ?? -1, t.position.x, t.position.y, t.position.z, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, machineRoot.childNodes.count)
            }
            for (i, node) in coins.prefix(3).enumerated() {
                let p = node.presentation.position, v = node.physicsBody?.velocity ?? SCNVector3Zero
                NSLog("COIN_DEBUG #%d falling=%d p=%.2f,%.2f,%.2f v=%.2f,%.2f,%.2f resting=%d", i, tracks[ObjectIdentifier(node)]?.falling == true ? 1 : 0,
                      p.x, p.y, p.z, v.x, v.y, v.z, node.physicsBody?.isResting == true ? 1 : 0)
            }
            if let last = coins.last {
                let p = last.presentation.position, v = last.physicsBody?.velocity ?? SCNVector3Zero
                NSLog("COIN_DEBUG last falling=%d p=%.2f,%.2f,%.2f v=%.2f,%.2f,%.2f", tracks[ObjectIdentifier(last)]?.falling == true ? 1 : 0, p.x, p.y, p.z, v.x, v.y, v.z)
            }
        }
        #endif
    }
    private var lastDebugTick = 0

    func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        let g = geo
        let now = CACurrentMediaTime()
        var removed: [Bool] = []
        coinLock.lock(); defer { coinLock.unlock() }
        _coins.removeAll { node in
            let id = ObjectIdentifier(node)
            guard let track = tracks[id] else { return false }
            if track.falling {
                // 下落中：在竖直平面里（velocityFactor 锁住 z），按离相机的远近缩放外观，屏幕上大小不变
                node.childNodes.first?.scale = fallScale(at: node.presentation.position)
                // 下落中不能转动，停在钉子正上方会一直卡住：速度很小时给一点随机的横向推力（2D 版碰到格挡时也这样做）
                if let body = node.physicsBody {
                    let v = body.velocity
                    if v.x * v.x + v.y * v.y < 0.25 {
                        body.velocity = SCNVector3(Float.random(in: 0.8...1.6) * (Bool.random() ? 1 : -1), v.y - 0.5, 0)
                    }
                }
                return false
            }
            let p = node.presentation.position
            updatePhase(node, track: track, position: p, now: now)
            if p.y < PusherScene3D.removeBelowY {
                let reason = p.z > g.lipZ - 0.2 ? "fellIntoTray" : "lostBelow"
                removalReasons[reason, default: 0] += 1
                logEvent("removed", detail: "\(reason) at \(p.x),\(p.z)")
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
    static let removeBelowY: Float = -1.2
    enum CoinPhase: String { case falling, airborne, onPusher, onRamp, onPile, fallingFront, lostBehindWall, lostSide }
    final class CoinTrack {
        var phase: CoinPhase = .airborne
        var falling = false
        var prefilled = false
        let born: TimeInterval
        var releasedAt: TimeInterval?
        var firstLanding: CoinPhase?
        var firstLandingTime: TimeInterval?
        var rampTime: TimeInterval?
        var pusherTime: TimeInterval?
        var standingSince: TimeInterval?
        var lastScreen: CGPoint?
        var lastDiameter: CGFloat?
        var lastSampleTime: TimeInterval?
        var lastSpeed: CGFloat = 0
        var crossedBattle = false, crossedFruit = false, crossedBonus = false
        init(born: TimeInterval) { self.born = born }
    }
    private var tracks: [ObjectIdentifier: CoinTrack] = [:]
    /// 事件计数：landedPusher、landedRamp、landedPile、rampToPusher、pusherToPile、fellFront、lostBehindWall、lostSide、standing
    private(set) var lifecycleCounts: [String: Int] = [:]
    private(set) var removalReasons: [String: Int] = [:]
    /// 下落时长（投币到第一次落在表面）、斜坡滑到推板顶面的时长、推板顶面落到金币堆的时长
    private(set) var fallTimes: [Double] = []
    private(set) var rampSlideTimes: [Double] = []
    private(set) var pusherToPileTimes: [Double] = []
    /// 还在斜坡上、落上去不到 3 秒的金币（测试结束时还没滑到推板，不算失败）
    var pendingRampCoins: Int {
        let now = CACurrentMediaTime()
        return tracks.values.filter { if let r = $0.rampTime, r.isFinite, $0.pusherTime == nil { return now - r < 3 } else { return false } }.count
    }
    /// 斜坡上的金币 3 秒内没到推板顶面的次数（应为 0）
    private(set) var rampTimeouts = 0
    /// 连续性：逐帧屏幕位置跳变超过物理运动、或大小一帧变化超过 5% 的次数及最大值
    private(set) var continuityViolations: [String] = []
    private(set) var maxSizeChange: CGFloat = 0
    private(set) var framesSampled = 0
    /// 立着（币面法线接近水平）静止超过 0.5 秒的金币
    private(set) var standingViolations = 0

    private func logEvent(_ event: String, detail: String = "") {
        lifecycleCounts[event, default: 0] += 1
        if logsLifecycle { NSLog("COIN_LIFE %@ %@", event, detail) }
    }

    private func phase(at p: SCNVector3) -> CoinPhase {
        let g = geo
        if p.y < -0.15 && p.z > g.lipZ - 0.3 { return .fallingFront }
        if p.z < g.wallZ - 0.4 && p.y > -0.3 && p.y < g.pusherHeight + 0.6 { return .lostBehindWall }
        if abs(p.x) > abs(g.rampOuter.x) + 1 { return .lostSide }
        if p.y > g.pusherHeight - 0.05, p.y < g.pusherHeight + config.coinRadius + 0.1,
           abs(p.x) < g.pusherHalfWidth, p.z < pusherFrontZ, p.z > g.wallZ - 0.1 { return .onPusher }
        if abs(p.x) > g.rampInnerX - 0.05, p.z < g.rampFrontZ + 0.1, p.z > g.rampFrontZ - 3.2,
           p.y > g.rampInnerHeight - 0.05, p.y < abs(g.rampOuter.y) + config.coinRadius + 0.3 {
            let t = (abs(p.x) - g.rampInnerX) / max(0.01, abs(g.rampOuter.x) - g.rampInnerX)
            let surface = g.rampInnerHeight + t * (g.rampOuter.y - g.rampInnerHeight)
            if p.y < surface + config.coinRadius + 0.1 { return .onRamp }
        }
        if p.y < g.pusherHeight - 0.1 && p.z > pusherFrontZ - 0.1 { return .onPile }
        return .airborne
    }

    private func updatePhase(_ node: SCNNode, track: CoinTrack, position p: SCNVector3, now: TimeInterval) {
        let ph = phase(at: p)
        // 立着不动：币面法线（节点 y 轴）接近水平，且几乎不动
        if ph == .onPusher || ph == .onPile || ph == .onRamp {
            let m = node.presentation.worldTransform
            let normalY = abs(m.m22)
            let v = node.physicsBody?.velocity ?? SCNVector3Zero
            let speed = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
            if normalY < 0.5 && speed < 0.3 {
                // 立着停住的金币轻推一下让它倒下（真机里金币也几乎不会立着停住）
                if let since = track.standingSince, now - since > 0.2, now - since < 0.5, let body = node.physicsBody {
                    body.applyTorque(SCNVector4(1, 0, 0, 0.02 * (Bool.random() ? 1 : -1)), asImpulse: true)
                }
                if let since = track.standingSince {
                    if now - since > 0.5 { standingViolations += 1; track.standingSince = .infinity; logEvent("standing", detail: "\(p.x),\(p.y),\(p.z)") }
                } else { track.standingSince = now }
            } else if track.standingSince != .infinity { track.standingSince = nil }
        }
        guard ph != track.phase, ph != .airborne else { return }
        let previous = track.phase
        track.phase = ph
        if !track.prefilled, track.firstLanding == nil, [.onPusher, .onRamp, .onPile].contains(ph) {
            track.firstLanding = ph
            track.firstLandingTime = now
            fallTimes.append(now - track.born)
            logEvent(ph == .onPusher ? "landedPusher" : ph == .onRamp ? "landedRamp" : "landedPile",
                     detail: "at \(p.x),\(p.y),\(p.z) pusherFront=\(pusherFrontZ)")
        }
        switch ph {
        case .onRamp: if track.rampTime == nil { track.rampTime = now }
        case .onPusher:
            if let r = track.rampTime, previous == .onRamp || previous == .airborne, track.pusherTime == nil {
                rampSlideTimes.append(now - r); logEvent("rampToPusher")
            }
            if track.pusherTime == nil { track.pusherTime = now }
        case .onPile:
            if let t = track.pusherTime, (previous == .onPusher || previous == .airborne) {
                pusherToPileTimes.append(now - t); logEvent("pusherToPile")
                track.pusherTime = nil
            }
        case .fallingFront: logEvent("fellFront")
        case .lostBehindWall: logEvent("lostBehindWall", detail: "\(p.x),\(p.y),\(p.z)")
        case .lostSide: logEvent("lostSide", detail: "\(p.x),\(p.y),\(p.z)")
        default: break
        }
        if let r = track.rampTime, track.pusherTime == nil, now - r > 3, ph == .onRamp {
            rampTimeouts += 1; track.rampTime = .infinity
        }
    }

    /// 每帧：下落中的金币按屏幕投影位置触发事件、到 BONUS 线解除约束；所有金币做连续性检查（位置、大小）
    private func sampleScreen(_ renderer: SCNSceneRenderer) {
        let r = config.coinRadius
        let right = SCNVector3(1, 0, 0)
        var releaseList: [(SCNNode, CoinTrack)] = []
        var battle = 0
        var fruits: [CGFloat] = [], bonuses: [CGFloat] = []
        framesSampled += 1
        for node in coins {
            guard let track = tracks[ObjectIdentifier(node)], !track.prefilled || track.phase != .onPile || true else { continue }
            let p = node.presentation.position
            // 刚加进场景、物理还没同步的那一帧，presentation 在原点：跳过
            if p.x == 0 && p.y == 0 && p.z == 0 { continue }
            let s = renderer.projectPoint(p)
            let sp = CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
            let a = renderer.projectPoint(SCNVector3(p.x - right.x * r, p.y, p.z)), b = renderer.projectPoint(SCNVector3(p.x + right.x * r, p.y, p.z))
            let visualScale = CGFloat(node.childNodes.first?.scale.x ?? 1)
            let diameter = CGFloat(abs(b.x - a.x)) * visualScale
            let v = node.physicsBody?.velocity ?? SCNVector3Zero
            // 世界速度换算成屏幕速度：按这枚金币自己的深度（越靠近相机，同样的速度在屏幕上走得越快）
            let speed = CGFloat((v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() * geo.focal / max(0.1, geo.depth(p)))
            let nowT = CACurrentMediaTime()
            defer { track.lastSampleTime = nowT; track.lastSpeed = speed }
            if let last = track.lastScreen, let lastD = track.lastDiameter, let lastT = track.lastSampleTime {
                // 两帧之间物理允许的屏幕位移：采样到的最大速度 × 帧间隔 × 2（帧内碰撞会让速度变化）+ 帧内重力加速 + 10 点。
                // 真正的「瞬移 / 闪烁」是几十到几百点的跳变（v11.2 以前的交接问题），远大于这个范围
                let dt = CGFloat(min(0.25, nowT - lastT))
                let gravityPts = CGFloat(PusherScene3D.verticalGravity * geo.focal / max(0.1, geo.depth(p))) * dt * dt
                let allowed = max(speed, track.lastSpeed) * dt * 2 + gravityPts + 10
                let jump = hypot(sp.x - last.x, sp.y - last.y)
                if jump > allowed { continuityViolations.append("jump \(Int(jump))>\(Int(allowed)) phase=\(track.phase.rawValue) falling=\(track.falling) at \(p.x),\(p.y),\(p.z)") }
                let change = abs(diameter - lastD) / max(1, lastD)
                maxSizeChange = max(maxSizeChange, change)
                if change > 0.05 { if logsLifecycle { NSLog("COIN_SIZE change=%.3f d=%.1f last=%.1f scale=%.2f falling=%d p=%.2f,%.2f,%.2f", change, diameter, lastD, visualScale, track.falling ? 1 : 0, p.x, p.y, p.z) }
                    continuityViolations.append("size \(String(format: "%.3f", change)) phase=\(track.phase.rawValue) falling=\(track.falling) at \(p.x),\(p.y),\(p.z)") }
            }
            track.lastScreen = sp
            track.lastDiameter = diameter
            guard track.falling else { continue }
            if !track.crossedBattle && sp.y >= battleLineY { track.crossedBattle = true; battle += 1 }
            if !track.crossedFruit && sp.y >= fruitLineY { track.crossedFruit = true; fruits.append(sp.x) }
            if !track.crossedBonus && sp.y >= releaseLineY {
                track.crossedBonus = true
                bonuses.append(sp.x)
                releaseList.append((node, track))
            }
        }
        for (node, track) in releaseList { release(node, track: track) }
        if battle > 0 || !fruits.isEmpty || !bonuses.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for _ in 0..<battle { self.onCrossBattle?() }
                fruits.forEach { self.onCrossFruit?($0) }
                bonuses.forEach { self.onCrossBonus?($0) }
            }
        }
    }

    // MARK: 遮挡检查：投影在视图内、不被底部面板（声明的遮挡物）和机器挡住
    /// 声明的遮挡物（参考里同样挡住金币堆两侧后角）
    static let declaredOccluders: Set<String> = ["postLeft", "postRight", "shelfLeft", "shelfRight", "shelfLeftRail", "shelfRightRail", "lip", "panelLeft", "panelRight", "panelLeftFrame", "panelRightFrame", "pusherGuideLeft", "pusherGuideRight"]
    private(set) var declaredHidden = 0
    func occlusionReport(in view: SCNView) -> (checked: Int, problems: [String]) {
        var problems: [String] = []
        var checked = 0
        let cam = cameraNode.position
        let coinIDs = Set(coins.map { ObjectIdentifier($0) })
        for node in coins {
            let p = node.presentation.position
            guard p.y > -0.15 else { continue }        // 已经越过前沿往下掉：被铜前沿和底部面板挡住是允许的
            checked += 1
            let s = view.projectPoint(p)
            let sp = CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
            if sp.x < 0 || sp.x > view.bounds.width || sp.y < 0 || sp.y > view.bounds.height {
                problems.append("offscreen \(p.x),\(p.y),\(p.z)"); continue
            }
            if sp.y > panelTopY { problems.append("panel \(p.x),\(p.y),\(p.z)"); continue }
            let dist = ((p.x - cam.x) * (p.x - cam.x) + (p.y - cam.y) * (p.y - cam.y) + (p.z - cam.z) * (p.z - cam.z)).squareRoot()
            let hits = view.hitTest(sp, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
            for hit in hits {
                let n = hit.node
                if n === node || n.parent === node || coinIDs.contains(ObjectIdentifier(n)) || n.name == "coinVisual" || n.name == "peg" || n.name == "fieldWall" || n.name == "rampGuard" || n.name == "lipCollider" || (n.name ?? "").hasPrefix("pileWall") { continue }   // 看不见的碰撞体不算遮挡
                let w = hit.worldCoordinates
                let d = ((w.x - cam.x) * (w.x - cam.x) + (w.y - cam.y) * (w.y - cam.y) + (w.z - cam.z) * (w.z - cam.z)).squareRoot()
                if d < dist - config.coinRadius - 0.05 {
                    // 声明的遮挡物：参考里金币堆两侧后角也被铜柱、台阶铜条挡住一部分
                    let name = n.name ?? "?"
                    if PusherScene3D.declaredOccluders.contains(name) && p.z > pusherFrontZ - 0.2 { declaredHidden += 1 }
                    else { problems.append("hidden by \(name) \(p.x),\(p.y),\(p.z)") }
                }
                break
            }
        }
        return (checked, problems)
    }

    /// 金币堆：层数（每枚压在几枚之上，90 百分位）和屏幕横向覆盖率（参考金币堆 272–935 像素）
    func pileStats() -> (layersP90: Float, coverage: CGFloat, count: Int) {
        let c = config, g = geo
        let pts = coins.map { $0.presentation.position }.filter { $0.y > -0.1 && $0.y < g.pusherHeight - 0.1 && $0.z > pusherFrontZ - 0.1 && $0.z < g.lipZ }
        guard !pts.isEmpty else { return (0, 0, 0) }
        let sorted = pts.sorted { $0.y < $1.y }
        var depth = [Float](repeating: 1, count: sorted.count)
        for i in sorted.indices {
            for j in 0..<i {
                let a = sorted[i], b = sorted[j]
                if b.y < a.y - c.coinThickness * 0.5 && ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)) < 0.36 * c.coinRadius * c.coinRadius {
                    depth[i] = max(depth[i], depth[j] + 1)
                }
            }
        }
        let stacks = depth.sorted()
        let p90 = stacks[min(stacks.count - 1, Int(Float(stacks.count) * 0.9))]
        // 屏幕覆盖：每枚金币在屏幕上占 [x−r, x+r]，求并集覆盖参考金币堆左右范围的比例
        guard let v = view else { return (p90, 0, pts.count) }
        let lo = ReferenceBoxes.x(ReferenceBoxes.pileX.lowerBound, g.viewSize), hi = ReferenceBoxes.x(ReferenceBoxes.pileX.upperBound, g.viewSize)
        // 每枚金币按自己在屏幕上的实际大小（金币堆离相机更近，比推板上的金币大）
        let spans = pts.map { p -> (CGFloat, CGFloat) in
            (CGFloat(v.projectPoint(SCNVector3(p.x - c.coinRadius, p.y, p.z)).x), CGFloat(v.projectPoint(SCNVector3(p.x + c.coinRadius, p.y, p.z)).x))
        }.sorted { $0.0 < $1.0 }
        var covered: CGFloat = 0, cursor = lo
        for (a, b) in spans where b > cursor {
            let start = max(a, cursor), end = min(b, hi)
            if end > start { covered += end - start; cursor = end }
        }
        return (p90, covered / (hi - lo), pts.count)
    }

    /// 测试用：命名部件投影到屏幕上的外框（点）
    func screenBox(ofNodeNamed name: String, in renderer: SCNSceneRenderer) -> CGRect? {
        guard let n = machineRoot.childNode(withName: name, recursively: true) else { return nil }
        let (lo, hi) = n.boundingBox
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for x in [lo.x, hi.x] { for y in [lo.y, hi.y] { for z in [lo.z, hi.z] {
            let w = n.convertPosition(SCNVector3(x, y, z), to: nil)
            let s = renderer.projectPoint(w)
            minX = min(minX, CGFloat(s.x)); maxX = max(maxX, CGFloat(s.x)); minY = min(minY, CGFloat(s.y)); maxY = max(maxY, CGFloat(s.y))
        } } }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 2D 金币精灵（旧接口，2D 金币雨用）：用同一个 3D 金币模型渲染
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
        let coin = SCNNode(geometry: (special ? specialGeometry : coinGeometry).copy() as? SCNGeometry)
        coin.eulerAngles = SCNVector3(Float.pi / 2 - geo.pitch, 0, 0)
        s.rootNode.addChildNode(coin)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.usesOrthographicProjection = true
        cam.camera?.orthographicScale = Double(config.coinRadius)
        let fwd = geo.forward
        cam.position = SCNVector3(-fwd.x * 10, -fwd.y * 10, -fwd.z * 10)
        cam.eulerAngles = SCNVector3(-geo.pitch, 0, 0)
        s.rootNode.addChildNode(cam)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = s
        renderer.pointOfView = cam
        return renderer.snapshot(atTime: 0, with: CGSize(width: pixels, height: pixels), antialiasingMode: .multisampling4X)
    }

    static let coinThicknessRatio: Float = 0.18 / 1.3
    /// 几何布置用的金币半径（实际半径由屏幕大小算出，约 0.43）
    static let nominalCoinRadius: Float = 0.45
    /// 前沿铜边高出台面的高度（约 1.5 枚金币厚）
    static let lipRise: Float = 0.09
    /// 斜坡摩擦：金币滑到推板顶面约 0.5 秒（参考 0.43–0.70 秒）
    static let rampFriction: CGFloat = 0.9
    /// 推板顶面摩擦：金币在推板顶面停留约 7.5 秒后被推到金币堆（参考 6.5–8.5 秒）
    static let pusherTopFriction: CGFloat = 0.31
    static let coinTint = UIColor(red: 1.0, green: 0.80, blue: 0.52, alpha: 1)

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
