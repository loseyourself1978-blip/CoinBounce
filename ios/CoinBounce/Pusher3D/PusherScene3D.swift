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
    // v11.5（用户要求）：推板、金币堆加宽——铜柱各向外移 80 像素，两侧绿色台阶贴满到屏幕左右边，
    // 推板顶面 328–878（宽约 40%），金币堆 190–1016，铜前沿、彩色面板、斜坡跟着铜柱走
    static let pusherX: ClosedRange<CGFloat> = 328...878
    // 斜坡：外端（贴屏幕边）和内侧低端（推板顶面侧边正上方），绿色顶面 + 铜色前沿
    static let rampOuterX: CGFloat = 10, rampOuterTopY: CGFloat = 1815, rampOuterBottomY: CGFloat = 1885
    static let rampInnerX: CGFloat = 335, rampInnerTopY: CGFloat = 1965, rampInnerBottomY: CGFloat = 2010
    // 推板两侧铜柱、两侧绿色台阶（下层）、台阶下铜条
    static let postLeftX: ClosedRange<CGFloat> = 232...325, postRightX: ClosedRange<CGFloat> = 881...974
    static let postY: ClosedRange<CGFloat> = 2045...2160
    static let shelfLeftX: ClosedRange<CGFloat> = 0...232, shelfRightX: ClosedRange<CGFloat> = 974...1206
    static let shelfY: ClosedRange<CGFloat> = 2045...2140
    static let railY: ClosedRange<CGFloat> = 2140...2200
    // 金币堆（下层台面）、波浪铜前沿、下方左右彩色面板
    static let pileX: ClosedRange<CGFloat> = 190...1016, pileY: ClosedRange<CGFloat> = 2130...2310
    static let lipX: ClosedRange<CGFloat> = 220...986, lipY: ClosedRange<CGFloat> = 2290...2380
    static let panelLeftX: ClosedRange<CGFloat> = 45...230, panelRightX: ClosedRange<CGFloat> = 976...1161
    static let panelY: ClosedRange<CGFloat> = 2215...2400
    // 底部面板、金色标牌、六边形投币按钮、BONUS 轨道、两侧炮管
    static let bottomFrame = CGRect(x: 40, y: 2370, width: 1128, height: 210)
    static let bottomLabel = CGRect(x: 163, y: 2410, width: 880, height: 130)   // v11.8：以屏幕中线（603）居中，投币按钮正好在标牌正中（原来 x 150，偏左 13 像素）
    static let dropButton = CGRect(x: 603 - 95, y: 2475 - 107.5, width: 190, height: 215)   // v11.8：中心和金色标牌中心同一高度（2475）
    static let dropButtonCenterY: CGFloat = 2475
    static let bonusBar = CGRect(x: 370, y: 1748, width: 490, height: 10)
    static let cannonLeft = CGRect(x: 40, y: 1690, width: 120, height: 140)
    static let cannonRight = CGRect(x: 1050, y: 1690, width: 120, height: 140)
    // v11.4 上半部（参考隐藏状态栏、从屏幕最顶端画起）：JACKPOT 大牌、金币 / 按钮一行、投币口拱门、老虎机、战斗区、水果排
    // v11.6（用户要求）：老虎机向上加高（787 → 570 起），投币口拱门、COIN 牌跟着上移；
    // 金币余额、帮助 / 设置叠在投币口区域上方两侧（不挡 COIN 牌的往复范围）
    // JACKPOT 牌加高到 300（两行字放在灵动岛下面）
    static let jackpotPanel = CGRect(x: 50, y: 0, width: 1110, height: 320)
    static let topRowY: ClosedRange<CGFloat> = 326...400
    static let balancePill = CGRect(x: 50, y: 328, width: 360, height: 70)
    static let topButtonsMaxX: CGFloat = 1150
    static let archFrame = CGRect(x: 246, y: 330, width: 674, height: 230)   // 灯泡横条在 560
    static let coinPlate = CGSize(width: 170, height: 96)    // COIN 牌（随滑块左右往复），中心 y 470
    static let coinPlateY: CGFloat = 470
    static let coinExitY: CGFloat = 528                      // 金币从 COIN 牌下沿出来
    static let slotCabinetX: ClosedRange<CGFloat> = 130...1076
    static let slotReels = CGRect(x: 150, y: 650, width: 906, height: 600)
    static let battle = CGRect(x: 165, y: 1300, width: 875, height: 220)
    static let fruitRow = CGRect(x: 120, y: 1560, width: 970, height: 120)
    /// 自上而下各区域的上下边（像素）：JACKPOT、金币 / 按钮一行、投币口、老虎机、战斗区、水果、BONUS、推币台、底部面板
    static let bands: [ClosedRange<CGFloat>] = [0...320, 326...400, 320...570, 570...1280, 1280...1542, 1542...1691, 1691...1809, 1809...2370, 2370...2622]
    /// v11.6 格挡钉（按新参考录屏逐帧测量的排列，跟着老虎机转轴窗口、战斗区、水果排走）：
    /// A 排在转轴窗口上沿、中间三列正上方；B 排在转轴中线、5 列的 6 条分隔线上；C 排在老虎机和战斗区之间、5 列正中；
    /// D 排在战斗区 55% 高度、战斗区 5 等分的 6 条分隔线上；水果排每两个水果灯之间（含两端）一根。钉子半径 14 像素
    static let pegRadius: CGFloat = 14
    /// 参考：金币从投币口到第一次落在推板顶面 / 斜坡上约 1.75 秒
    /// v11.6：新参考录屏（格挡钉更多、更密）金币从投币口到落地约 2.0 秒（和我们自己的录屏同一套轨迹脚本对比换算，见 v11.6_spec.md）
    static let fallSeconds: Double = 2.0

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
    /// 推板收回时的前沿：v11.5 按参考收到墙根（1982 像素）——顶面几乎全部缩进后墙下面，
    /// 落在推板顶面上的金币一个来回就被后墙刮下去（收回时落下的金币落在推板前面的台面上，推板推出时推走）
    var pusherFrontRetractedZ: Float { hitY(cx, sy(ReferenceBoxes.pusherFrontRetractedY), y: pusherHeight).z }
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
    /// v11.7：斜坡向前延伸到铜柱前沿，盖住原来斜坡前面那块平台（推板两侧导轨的顶面、铜柱顶面），金币不会停在上面
    /// 延伸到金币堆台面开始处（铜柱前沿 − 0.3）：导轨也到这里为止，推板旁边从这里往前是看得见的台面
    var rampExtendedFrontZ: Float { max(rampFrontZ, postFrontZ - 0.3) }
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
    var postTop: Float { hitZ(sx((ReferenceBoxes.postLeftX.lowerBound + ReferenceBoxes.postLeftX.upperBound) / 2), sy(ReferenceBoxes.postY.lowerBound), z: postFrontZ).y }
    private var shelfMidX: CGFloat { (ReferenceBoxes.shelfLeftX.lowerBound + ReferenceBoxes.shelfLeftX.upperBound) / 2 }
    var shelfHeight: Float { postTop * 0.9 }
    var shelfZ: (back: Float, front: Float) {
        (hitY(sx(shelfMidX), sy(ReferenceBoxes.shelfY.lowerBound), y: shelfHeight).z, hitY(sx(shelfMidX), sy(ReferenceBoxes.shelfY.upperBound), y: shelfHeight).z)
    }
    func shelfX(_ r: ClosedRange<CGFloat>) -> (Float, Float) {
        let z = shelfZ.front
        return (hitZ(sx(r.lowerBound), sy(ReferenceBoxes.shelfY.upperBound), z: z).x, hitZ(sx(r.upperBound), sy(ReferenceBoxes.shelfY.upperBound), z: z).x)
    }
    var railBottom: Float { hitZ(sx(shelfMidX), sy(ReferenceBoxes.railY.upperBound), z: shelfZ.front).y }
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

final class PusherScene3D: NSObject, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {

    struct Config {
        var coinRadius: Float = 0.42
        var coinThickness: Float = 0.42 * PusherScene3D.coinThicknessRatio
        var pusherPeriod: TimeInterval = GameConstants.pusherPeriod
        var maxCoins = 480
        var prefillCoins = 280
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
    /// x：越线时金币圆心的屏幕横坐标；radius：金币屏幕半径；gateX：BONUS 牌当时的中心（和立柱碰撞体同一帧）
    var onCrossBonus: ((_ x: CGFloat, _ radius: CGFloat, _ gateX: CGFloat) -> Void)?
    /// v11.6 BONUS 闸门：滑块当前偏移（点），每帧读一次，移动牌两侧的立柱碰撞体
    var bonusOffsetProvider: (() -> CGFloat)?
    static var bonusGateEnabled = !ProcessInfo.processInfo.arguments.contains("-debugNoBonusGate")
    /// v11.8：两侧掉下的金币不算玩家的（返还率略低于 1）
    static var sideDropsPay = false
    private var gateLayout: GameLayout?
    private var bonusPosts: [(node: SCNNode, side: CGFloat)] = []
    private var bonusPostBaseX: Float = 0, bonusPostScale: Float = 0
    private var bonusPostTopY: CGFloat = 0, bonusPostBottomY: CGFloat = 0
    /// 立柱碰撞体当前所在的 BONUS 牌中心（屏幕点）
    private(set) var bonusGateX: CGFloat = 0
    /// 越过 BONUS 线的下落金币数、整枚穿过开口的数、越线时骑在立柱上的数、按旧规则（圆心在灯牌宽内）会命中的数
    private(set) var bonusCrossings = 0, bonusPasses = 0, bonusStraddles = 0, bonusOldRuleHits = 0
    /// 逐帧检查：下落金币压进立柱的最大深度（点）
    private(set) var bonusMaxPenetration: CGFloat = 0
    /// 接触松弛被横向推回的次数
    private(set) var bonusCorrections = 0
    /// v11.7 中奖金币：生成数、按原因的移除数（门槛：生成 = 场上 + 接币槽 + 两侧，其他原因 0）
    private(set) var rewardSpawned = 0
    /// v11.7 死角：停在推板顶面、斜坡、台面以外超过 3 秒的金币数（门槛 0）
    private(set) var deadZoneCount = 0
    private(set) var rewardRemoved: [String: Int] = [:]
    /// 场上的中奖金币、正在下落的金币（含还没生成的）：渲染线程每步更新，主线程只读（投币队列按下落数限流）
    private(set) var rewardInPlay = 0
    private(set) var fallingNow = 0
    /// v11.7 性能：主线程每帧都读它（投币队列限流）。不能用 coinLock：物理回调整个逐枚循环都拿着 coinLock，
    /// 金币一多（10 COIN 连点 170 枚）主线程每帧都在等它，真机主线程掉到 20 fps。改用只护这两个数的小锁
    var fallingCount: Int { spawnLock.lock(); defer { spawnLock.unlock() }; return fallingPublished + pendingSpawns.count }
    private var fallingPublished = 0
    /// v11.7：台面上（不算下落中）的金币数：物理回调每步顺手更新（不另外遍历），主线程用它决定放币快慢
    var tableCount: Int { spawnLock.lock(); defer { spawnLock.unlock() }; return tablePublished }
    private var tablePublished = 0
    private let spawnLock = NSLock()
    /// 陷进台面、被托回台面的次数
    private(set) var deckClamps = 0
    /// 屏幕上的事件线（点）：战斗区、水果排、BONUS 轨道（金币在 BONUS 线处解除平面约束，落向推板 / 斜坡）
    private(set) var battleLineY: CGFloat = 0, fruitLineY: CGFloat = 0, releaseLineY: CGFloat = 0
    /// 底部面板顶边（点）：金币在它下面就被面板挡住（声明的遮挡物）
    private(set) var panelTopY: CGFloat = 0

    /// 特殊金币：白金色、自发光
    private lazy var specialGeometry: SCNCylinder = {
        let g = SCNCylinder(radius: CGFloat(config.coinRadius), height: CGFloat(config.coinThickness))
        g.radialSegmentCount = 20
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
    private var pendingSpawns: [(CGPoint, CGVector, Bool, Bool)] = []
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
        coinGeometry.radialSegmentCount = 20   // v11.5：28 → 20（看不出差别，绘制、阴影和碰撞体都更省）
        super.init()
        buildScene()
        apply(geometry: MachineGeometry(viewSize: viewSize))
        // v11.5：手机发热（.serious 及以上）时降低画质（阴影、环境光遮蔽、抗锯齿），玩法和物理不变；降温到 .fair 及以下恢复
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRenderQuality()
        }
        updateRenderQuality()
    }
    deinit { if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) } }

    // MARK: 发热降级
    enum RenderQuality: Equatable { case full, reduced }
    private let keyLightNode = SCNNode()
    private var thermalObserver: NSObjectProtocol?
    private(set) var renderQuality: RenderQuality = .full
    /// 画面验收（逐帧连续性、大小检查覆盖所有金币）：测试里默认开；App 里只在 -autoplay 验收时开（玩家玩的时候关，省每帧对上百枚金币的投影）
    var verifiesMotion = true
    /// 调试：-forceThermalFallback 强制降级画质
    static var forcesFallback = ProcessInfo.processInfo.arguments.contains("-forceThermalFallback")
    static func renderQuality(for state: ProcessInfo.ThermalState) -> RenderQuality {
        if forcesFallback { return .reduced }
        switch state {
        case .serious, .critical: return .reduced
        default: return .full
        }
    }
    func updateRenderQuality(thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) {
        apply(renderQuality: PusherScene3D.renderQuality(for: thermalState))
    }
    func apply(renderQuality q: RenderQuality) {
        renderQuality = q
        let full = q == .full
        // 阴影：全画质 12 次采样柔和阴影；降级时 1 次采样、阴影贴图减半
        keyLightNode.light?.shadowSampleCount = full ? 12 : 1
        keyLightNode.light?.shadowRadius = full ? 5 : 1
        keyLightNode.light?.shadowMapSize = full ? .zero : CGSize(width: 1024, height: 1024)
        cameraNode.camera?.screenSpaceAmbientOcclusionIntensity = full ? 1.2 : 0
        if let view {
            view.antialiasingMode = full ? .multisampling2X : .none
            view.preferredFramesPerSecond = 60
        }
    }

    // MARK: 灯光、材质、相机
    private func buildScene() {
        scene.physicsWorld.gravity = baseGravity
        scene.physicsWorld.timeStep = PusherScene3D.physicsTimeStep
        scene.physicsWorld.contactDelegate = self
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
        let key = keyLightNode
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
        coinMaterial.roughness.contents = 0.2
        coinMaterial.multiply.contents = PusherScene3D.coinTint
        // v11.5：更亮的金色——微弱的金色自发光托住暗部，粗糙度更低、反光更集中
        coinMaterial.emission.contents = PusherScene3D.coinGlow
        coinMaterial.emission.intensity = 0.12
        let face = SCNMaterial()
        face.lightingModel = .physicallyBased
        face.diffuse.contents = PusherScene3D.coinFaceImage()
        face.normal.contents = PusherScene3D.coinFaceNormalImage()
        face.metalness.contents = 1.0
        face.roughness.contents = 0.18
        face.multiply.contents = PusherScene3D.coinTint
        face.emission.contents = PusherScene3D.coinGlow
        face.emission.intensity = 0.16
        coinGeometry.materials = [coinMaterial, face, face]
        // 只照金币的高光灯：从机器后上方照向相机方向，平放的金币正面把它反射进镜头（金色反光）；
        // 不照台面和铜件，机器整体亮度不变
        let glint = SCNNode()
        glint.light = SCNLight()
        glint.light!.type = .directional
        glint.light!.intensity = 800
        glint.light!.color = UIColor(red: 1, green: 0.92, blue: 0.7, alpha: 1)
        glint.light!.categoryBitMask = PusherScene3D.coinLightMask
        glint.position = SCNVector3(0, 30, -70)
        glint.look(at: SCNVector3(0, 0, -34))
        scene.rootNode.addChildNode(glint)
        // v11.6：下落中的金币币面朝着相机，后上方的高光灯照不到它的正面——加一盏沿视线方向、只照下落中金币的灯，
        // 上半区的金币和台面上的金币一样亮、一样有金色反光
        fallLightNode.light = SCNLight()
        fallLightNode.light!.type = .directional
        fallLightNode.light!.intensity = PerfDebug.noFallLight ? 0 : PusherScene3D.fallLightIntensity
        fallLightNode.light!.color = UIColor(red: 1, green: 0.9, blue: 0.68, alpha: 1)
        fallLightNode.light!.categoryBitMask = PusherScene3D.fallLightMask
        scene.rootNode.addChildNode(fallLightNode)

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
        fallLightNode.eulerAngles = cameraNode.eulerAngles   // 和视线同方向
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

    /// 带旋转的静态部件：先摆好位置、转好角度、装好物理体，最后才放进场景。
    /// （v11.5 查出：先放进场景再改角度、换物理体的写法，新物理体不生效——金币堆侧墙、屏幕边墙之前其实没有碰撞）
    @discardableResult
    private func orientedNode(_ name: String, box w: Float, _ h: Float, _ d: Float, at p: SCNVector3, euler: SCNVector3, _ m: String, friction: CGFloat = 0.3) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0)
        g.materials = [materials[m]!]
        let n = SCNNode(geometry: g)
        n.name = name
        n.position = p
        n.eulerAngles = euler
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: g, options: nil))
        body.friction = friction
        body.restitution = 0.05
        body.categoryBitMask = PusherScene3D.catMachine
        n.physicsBody = body
        n.castsShadow = false
        machineRoot.addChildNode(n)
        return n
    }

    /// 台面边带（v11.7）：顶面是 4 个点围成的斜面（梯形），往下 2 的直棱柱；凸包碰撞体，毛毡贴图按世界坐标铺
    private func prismNode(_ name: String, top: [SCNVector3], depth: Float = 2) {
        let bottom = top.map { SCNVector3($0.x, $0.y - depth, $0.z) }
        let faces: [[SCNVector3]] = [top, bottom.reversed(),
                                     [top[0], bottom[0], bottom[1], top[1]], [top[1], bottom[1], bottom[2], top[2]],
                                     [top[2], bottom[2], bottom[3], top[3]], [top[3], bottom[3], bottom[0], top[0]]]
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        let center = (top + bottom).reduce(SCNVector3Zero) { SCNVector3($0.x + $1.x / 8, $0.y + $1.y / 8, $0.z + $1.z / 8) }
        for f in faces {
            let a = SCNVector3(f[1].x - f[0].x, f[1].y - f[0].y, f[1].z - f[0].z), b = SCNVector3(f[2].x - f[0].x, f[2].y - f[0].y, f[2].z - f[0].z)
            var n = SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
            let l = max(1e-6, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()); n = SCNVector3(n.x / l, n.y / l, n.z / l)
            // 法线朝外（不管点的绕向）
            let fc = SCNVector3(f[0].x - center.x, f[0].y - center.y, f[0].z - center.z)
            let outward = n.x * fc.x + n.y * fc.y + n.z * fc.z >= 0
            if !outward { n = SCNVector3(-n.x, -n.y, -n.z) }
            let base = Int32(verts.count)
            for v in f { verts.append(v); normals.append(n); uvs.append(CGPoint(x: CGFloat(v.x + v.y) / 4, y: CGFloat(v.z) / 4)) }
            idx += outward ? [base, base + 1, base + 2, base, base + 2, base + 3] : [base, base + 2, base + 1, base, base + 3, base + 2]
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        geo.materials = [materials["felt"]!]
        let n = SCNNode(geometry: geo)
        n.name = name
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: geo, options: [.type: SCNPhysicsShape.ShapeType.convexHull]))
        body.friction = GameConstants.deckFriction
        body.restitution = 0.05
        body.categoryBitMask = PusherScene3D.catMachine
        n.physicsBody = body
        machineRoot.addChildNode(n)
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
        // v11.5：铜柱前沿以后（金币堆那一段）台面只铺到金币堆两侧墙外沿：翻到侧墙外面的金币从两侧的缝
        // 掉进接币槽（像真机两侧的落币槽），不会停在前沿两端、跑出画面
        let pileStartZ = g.postFrontZ - 0.3
        _ = node("table", box: wide * 2, 2, pileStartZ - floorBackZ, at: SCNVector3(0, -1, (pileStartZ + floorBackZ) / 2), "felt",
                 friction: GameConstants.deckFriction)
        let frontHalf = max(g.pileHalfWidth(atZ: pileStartZ), g.pileHalfWidth(atZ: lipZ))   // v11.6：台面只到金币堆边，边上的金币从两侧掉下
        // v11.5：金币堆台面中间略高、向两侧各倾斜 1.2°（边上低约一枚金币厚）：被推动的金币稍微往两侧散开，
        // 金币堆变薄（2–2.5 层）后两边也铺得满；两边的铜边相对更高，边上的金币留得住
        let crown = PusherScene3D.pileCrownAngle
        // v11.6（用户要求侧面明显掉币）：台面两边各有一条向外倾的边带（比金币和台面的摩擦角陡），
        // 被推挤到边带上的金币沿斜面滑下、从两侧掉进接币槽
        let stripW = PusherScene3D.edgeStripWidth, tilt = PusherScene3D.edgeStripTilt
        let flatHalf = frontHalf - stripW
        let len = lipZ - pileStartZ, zc = (lipZ + pileStartZ) / 2
        func tableBox(_ name: String, width: Float, top: SCNVector3, angle: Float) {
            let box = SCNBox(width: CGFloat(width), height: 2, length: CGFloat(len), chamferRadius: 0)
            box.materials = [materials["felt"]!]
            let n = SCNNode(geometry: box)
            n.name = name
            // top 是顶面中线上的点；盒子中心沿顶面法线往下 1
            n.position = SCNVector3(top.x + sin(angle), top.y - cos(angle), zc)
            n.eulerAngles = SCNVector3(0, 0, angle)
            let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: box, options: nil))
            body.friction = GameConstants.deckFriction
            body.restitution = 0.05
            body.categoryBitMask = PusherScene3D.catMachine
            n.physicsBody = body
            machineRoot.addChildNode(n)
        }
        for side: Float in [-1, 1] {
            let a = side * -crown   // 外侧向下
            tableBox(side < 0 ? "tableFrontLeft" : "tableFrontRight", width: flatHalf,
                     top: SCNVector3(side * flatHalf / 2 * cos(crown), -flatHalf / 2 * sin(crown), 0), angle: a)
            let edgeY = -flatHalf * sin(crown)
            // v11.7：边带外沿跟着侧边凸边走（金币堆前面窄、后面宽，梯形），在每个深度都正好停在凸边外沿：
            // 原来是长方形（按最宽处），前面凸边外留出一条小平台，翻过凸边的金币停在上面、靠着屏幕边的墙不掉
            let xi = flatHalf * cos(crown)
            func outer(_ z: Float) -> Float { g.pileHalfWidth(atZ: z) + 0.25 }
            func topAt(_ x: Float, _ z: Float) -> SCNVector3 { SCNVector3(side * x, edgeY - (x - xi) * tan(tilt), z) }
            prismNode(side < 0 ? "tableEdgeLeft" : "tableEdgeRight",
                      top: [topAt(xi, pileStartZ), topAt(xi, lipZ), topAt(outer(lipZ), lipZ), topAt(outer(pileStartZ), pileStartZ)])
        }
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
        // v11.7：后墙顶面是平的，弹上去的金币会一直停在上面（死角）。顶上加一道看不见的斜面（后高前低 35°），
        // 落上去的金币滑回推板顶面
        do {
            let z0 = wallZ - 0.6, z1 = wallZ, top = h + 0.36
            let dz = z1 - z0, dy = dz * tan(Float.pi * 35 / 180)
            let len = (dz * dz + dy * dy).squareRoot()
            orientedNode("backWallSlope", box: wide * 2, 0.06, len, at: SCNVector3(0, top + dy / 2 - 0.03, (z0 + z1) / 2),
                         euler: SCNVector3(atan2(dy, dz), 0, 0), "invisible", friction: 0.1)
        }
        // 后背板：竖直红绒布，从台面到 BONUS 区下沿，挡住后墙后面
        let panelTop = g.hitZ(g.cx, g.backPanelTopScreenY, z: g.backPanelZ).y
        _ = node("backPanel", box: wide * 2, panelTop, 0.2, at: SCNVector3(0, panelTop / 2, g.backPanelZ - 0.1), "backFelt", physics: true)
        // 斜坡：每侧一块薄板，内侧低端在推板顶面侧边正上方，外端贴屏幕边；绿色顶面 + 铜色前沿
        for side: Float in [-1, 1] {
            let inner = SCNVector3(side * g.rampInnerX, g.rampInnerHeight, g.rampFrontZ)
            let outer = SCNVector3(side * abs(g.rampOuter.x), g.rampOuter.y, g.rampFrontZ)
            let dx = outer.x - inner.x, dy = outer.y - inner.y
            let length = (dx * dx + dy * dy).squareRoot()
            let front = g.rampExtendedFrontZ
            let depth: Float = front - g.backPanelZ
            let plate = SCNBox(width: CGFloat(length), height: 0.08, length: CGFloat(depth), chamferRadius: 0.02)
            plate.materials = [materials["felt"]!]
            let ramp = SCNNode(geometry: plate)
            ramp.name = side < 0 ? "rampLeft" : "rampRight"
            ramp.position = SCNVector3((inner.x + outer.x) / 2, (inner.y + outer.y) / 2 - 0.04, front - depth / 2)
            ramp.eulerAngles = SCNVector3(0, 0, atan2(dy, dx) + (side < 0 ? .pi : 0))
            // 碰撞体比看得见的薄板厚（顶面相同、向下加厚到 0.5）：快速落下的金币不会陷进斜面、被前沿铜边挡住
            let solid = SCNBox(width: CGFloat(length), height: 0.5, length: CGFloat(depth), chamferRadius: 0)
            let rampShape = SCNPhysicsShape(shapes: [SCNPhysicsShape(geometry: solid, options: nil)],
                                            transforms: [NSValue(scnMatrix4: SCNMatrix4MakeTranslation(0, 0.04 - 0.25, 0))])
            let rb = SCNPhysicsBody(type: .static, shape: rampShape)
            rb.friction = PusherScene3D.rampFriction
            rb.categoryBitMask = PusherScene3D.catMachine
            ramp.physicsBody = rb
            machineRoot.addChildNode(ramp)
            rampNodes.append(ramp)
            // 斜坡前沿的挡边（看不见）：金币只能顺着斜坡滑到推板上，不会从斜坡前沿滚落到台阶上
            // 挡边高出斜面约 2.3：弹起的金币也翻不过去（翻过去会落进台阶后面看不见的角落）
            let guardBox = SCNBox(width: CGFloat(length), height: 2.4, length: 0.12, chamferRadius: 0)
            guardBox.materials = [materials["invisible"]!]
            let guardNode = SCNNode(geometry: guardBox)
            guardNode.name = "rampGuard"
            guardNode.position = SCNVector3((inner.x + outer.x) / 2, (inner.y + outer.y) / 2 + 1.1, front + 0.06)
            guardNode.eulerAngles = ramp.eulerAngles
            let gb = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: guardBox, options: nil))
            gb.categoryBitMask = PusherScene3D.catMachine
            guardNode.physicsBody = gb
            machineRoot.addChildNode(guardNode)
            // 斜坡外端的透明挡板：外端到屏幕边墙之间不留缝（立着的金币会从缝里掉进台阶后面看不见的角落）
            let capH = g.rampOuter.y + 0.9
            _ = node(side < 0 ? "rampCapLeft" : "rampCapRight", box: 1.2, capH, front + 0.12 - g.backPanelZ,
                     at: SCNVector3(side * (abs(g.rampOuter.x) - 0.05 + 0.6), capH / 2, (front + 0.12 + g.backPanelZ) / 2), "invisible", friction: 0.1)
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
            trim.position = SCNVector3(0, 0, front - 0.06)
            machineRoot.addChildNode(trim)
        }
        // v11.7（用户要求）：去掉推板两侧的铜柱——它和导轨顶面在斜坡前面形成一块平台，金币落上去就永远停在那里。
        // 斜坡向前延伸盖住这一块（rampExtendedFrontZ），导轨降到斜坡下面
        // 推板两侧的导轨：从推板侧面到金币堆侧墙、从后背板到铜柱，比推板顶面高一点，
        // 推板顶面边上的金币不会掉进铜柱后面看不见的空隙
        for side: Float in [-1, 1] {
            // 内侧面贴着推板侧面（不留缝，金币卡不进去、也不会被挤进导轨里；不伸进推板顶面，金币不会靠着它被推着走）
            let x0 = halfP, x1 = g.pileHalfWidth(atZ: g.postFrontZ) + 0.45
            // v11.7：导轨到斜坡前沿为止（不伸进金币堆台面：原来多出的 0.3 会把被挤过来的金币「吞」进导轨里，看不见）
            let z0 = g.backPanelZ, z1 = g.rampExtendedFrontZ
            // 比推板顶面高一点、但在斜坡内端下面（斜坡盖住它，金币碰不到它的顶面）
            let gh = min(h + 0.3, g.rampInnerHeight - 0.06)
            _ = node(side < 0 ? "pusherGuideLeft" : "pusherGuideRight", box: x1 - x0, gh, z1 - z0,
                     at: SCNVector3(side * (x0 + x1) / 2, gh / 2, (z0 + z1) / 2), "copper", friction: 0.1)
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
        // v11.6（用户要求）：金币堆两侧不再有墙，被推挤的金币从左右两侧和正前方都能掉下去（都算玩家的）
        // 两侧和正前方一样有一道很低的凸边（高 lipRise，看不见）：边上的金币要被推挤才翻过去掉下，金币堆两边铺得满
        for side: Float in [-1, 1] {
            let z0 = g.postFrontZ - 0.3, z1 = lipZ + 0.25
            let x0 = side * (g.pileHalfWidth(atZ: z0) + 0.125), x1 = side * (g.pileHalfWidth(atZ: z1) + 0.125)
            let dx = x1 - x0, dz = z1 - z0
            let sideRise = PusherScene3D.sideLipRise
            // 凸边高度从它所在位置的台面（边带斜面）算起
            let flatHalf = max(g.pileHalfWidth(atZ: z0), g.pileHalfWidth(atZ: lipZ)) - PusherScene3D.edgeStripWidth
            let lipX = abs(x0 + x1) / 2 - 0.125
            let base = -flatHalf * sin(PusherScene3D.pileCrownAngle) - max(0, lipX - flatHalf) * sin(PusherScene3D.edgeStripTilt)
            orientedNode(side < 0 ? "sideLipLeft" : "sideLipRight", box: 0.25, sideRise + 0.4, (dx * dx + dz * dz).squareRoot(),
                         at: SCNVector3((x0 + x1) / 2, base + (sideRise - 0.4) / 2, (z0 + z1) / 2), euler: SCNVector3(0, atan2(dx, dz), 0), "invisible", friction: 0.3)
        }
        // 屏幕左右边缘（透明碰撞墙，沿屏幕竖线投到台面上）：从后背板到前沿前方。台面比屏幕宽，
        // 翻到金币堆侧墙外（台阶上、角落里）的金币也只会沿台面滑到前沿掉进接币槽，不会从侧面跑出画面
        for side: Float in [-1, 1] {
            let sxEdge: CGFloat = side < 0 ? 0 : g.viewSize.width
            let a = g.hitY(sxEdge, g.sy(ReferenceBoxes.wallY), y: 0), b = g.hitY(sxEdge, g.viewSize.height, y: 0)
            // 沿 a→b 的直线延长到后背板和前沿前方 3
            let z0 = g.backPanelZ, z1 = lipZ + 3
            let slope = (b.x - a.x) / (b.z - a.z)
            // 墙厚 2（整个在画面外）：金币堆被推板挤压时也穿不过去
            let x0 = a.x + slope * (z0 - a.z) + side * 1.0, x1 = a.x + slope * (z1 - a.z) + side * 1.0
            let dx = x1 - x0, dz = z1 - z0
            orientedNode(side < 0 ? "screenWallLeft" : "screenWallRight", box: 2, 8, (dx * dx + dz * dz).squareRoot(),
                         at: SCNVector3((x0 + x1) / 2, PusherScene3D.screenWallBottom + 4, (z0 + z1) / 2), euler: SCNVector3(0, atan2(dx, dz), 0), "invisible", friction: 0.1)
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
        // v11.6（用户要求）：去掉下方左右的粉紫 / 金黄面板，整个金币堆露出来
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
        gateLayout = layout
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
            b.restitution = PusherScene3D.pegRestitution
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
            // 墙是世界竖直的，内侧面在投币口处贴着屏幕上下落区的边缘；透视下越往下越向内收（BONUS 线处约 6 点），
            // 金币不会落到斜坡外端以外（沿屏幕边缘倾斜的墙会让边上的金币落出斜坡、跑出画面）
            let len = abs(a.y - b.y)
            let box = SCNBox(width: 0.2, height: CGFloat(len), length: CGFloat(config.coinRadius * 4), chamferRadius: 0)
            let n = SCNNode(geometry: box)
            n.geometry?.materials = [materials["invisible"]!]
            // v11.6：下落中金币的外观按深度缩小（上半区约小 15–20%），碰撞半径不变——墙向外让出这个差值，
            // 屏幕上看得过去的钉子和墙之间的缝，物理上也过得去（否则金币会卡在边上的钉子和墙之间）
            let topScale = max(0.3, min(1, g.depth(a) / releaseDepth))
            let give = config.coinRadius * (1 - topScale)
            let out: Float = a.x > 0 ? 1 : -1
            n.position = SCNVector3(a.x + out * (0.1 + give), (a.y + b.y) / 2, (a.z + b.z) / 2)
            let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: box, options: nil))
            body.categoryBitMask = PusherScene3D.catPeg
            n.physicsBody = body
            n.name = "fieldWall"
            pegRoot.addChildNode(n)
        }
        buildBonusPosts(layout)
    }

    /// v11.6 BONUS 闸门：牌左右两根立柱（看不见的盒子碰撞体），高度和 BONUS 牌一样，
    /// 每帧随滑块移动（运动学刚体）。金币要么整枚从两柱之间的开口穿过，要么被立柱挡开从外面落下
    private func buildBonusPosts(_ layout: GameLayout) {
        bonusPosts = []
        guard PusherScene3D.bonusGateEnabled else { return }
        let g = geo, z = g.fallPlaneZ
        let plaqueH = ReferenceBoxes.y(GameConstants.bonusPlaqueHeightPx, layout.size)
        let midY = layout.bonusLane.midY
        bonusPostTopY = midY - plaqueH / 2
        bonusPostBottomY = midY + plaqueH / 2
        let m = g.hitZ(layout.centerX, midY, z: z)
        bonusPostScale = (g.hitZ(layout.centerX + 100, midY, z: z).x - m.x) / 100
        bonusPostBaseX = m.x
        let top = g.hitZ(layout.centerX, bonusPostTopY, z: z), bottom = g.hitZ(layout.centerX, bonusPostBottomY, z: z)
        // 碰撞体比画出来的立柱每边宽 1.5 点：高速金币（≈250 点/秒）接触时会压进去 2–3 点，这样画面上金币边不会压到立柱
        let width = Float(layout.bonusPostWidth + 2 * PusherScene3D.bonusPostContactPad) * bonusPostScale
        // 盒子碰撞体（胶囊和金币圆柱接触时会压进去约一个胶囊半径）；顶端是平的，停在上面的金币由「速度太小就横向轻推」挪走
        let capsule = SCNBox(width: CGFloat(width), height: CGFloat(abs(top.y - bottom.y)), length: CGFloat(config.coinRadius * 4), chamferRadius: 0)
        for side: CGFloat in [-1, 1] {
            let n = SCNNode(geometry: capsule)
            n.geometry?.materials = [materials["invisible"]!]
            n.position = SCNVector3(m.x, (top.y + bottom.y) / 2, (top.z + bottom.z) / 2)
            let b = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: capsule, options: nil))
            b.categoryBitMask = PusherScene3D.catPeg
            b.restitution = PusherScene3D.pegRestitution
            b.friction = 0.08
            n.physicsBody = b
            n.name = "bonusPost"
            pegRoot.addChildNode(n)
            bonusPosts.append((n, side))
        }
        updateBonusGate()
    }

    /// 立柱跟着 BONUS 牌走：中心 ±（开口/2 + 立柱/2）
    private func updateBonusGate() {
        guard let l = gateLayout else { return }
        let offset = bonusOffsetProvider?() ?? 0
        bonusGateX = l.centerX + offset
        for (n, side) in bonusPosts {
            n.position.x = bonusPostBaseX + Float(offset + side * (l.bonusOpeningWidth / 2 + l.bonusPostWidth / 2)) * bonusPostScale
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
        visual.categoryBitMask = 1 | PusherScene3D.coinLightMask
        visual.castsShadow = true
        node.addChildNode(visual)
        if special { node.name = PusherScene3D.specialName }
        node.position = position
        node.eulerAngles = SCNVector3(tilt, Float.random(in: 0...(2 * .pi)), tilt * 0.5)
        let shape = falling ? SCNPhysicsShape(geometry: coinGeometry, options: nil)
                            : PusherScene3D.pileShape(radius: config.coinRadius, thickness: config.coinThickness, geometry: coinGeometry)
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
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
    /// reward：v11.7 中奖金币（真的 3D 金币，不触发战斗、水果、BONUS）
    func spawnFallingCoin(atScreen s: CGPoint, screenVelocity v: CGVector = .zero, special: Bool = false, reward: Bool = false) {
        spawnLock.lock()
        pendingSpawns.append((s, v, special, reward))
        spawnLock.unlock()
    }

    @discardableResult
    func makeFallingCoin(atScreen s: CGPoint, screenVelocity v: CGVector, special: Bool, reward: Bool = false) -> SCNNode? {
        let g = geo
        let p = g.hitZ(s.x, s.y, z: g.fallPlaneZ)
        let wpp = g.depth(p) / g.focal
        let velocity = SCNVector3(Float(v.dx) * wpp, -Float(v.dy) * wpp / cos(g.pitch), 0)
        guard let node = addCoin(at: p, velocity: velocity, special: special, falling: true) else { return nil }
        node.eulerAngles = SCNVector3(Float.pi / 2 - g.pitch, 0, 0)   // 币面法线指向相机
        node.childNodes.first?.scale = fallScale(at: p)
        node.childNodes.first?.categoryBitMask |= PusherScene3D.fallLightMask
        let body = node.physicsBody!
        body.resetTransform()
        body.velocityFactor = SCNVector3(1, 1, 0)          // 只在竖直的下落平面里运动
        body.allowsResting = false                         // 下落中不休眠（刚生成时速度为 0，会直接休眠、不受重力）
        body.angularVelocityFactor = SCNVector3Zero
        body.categoryBitMask = PusherScene3D.catFalling
        body.collisionBitMask = PusherScene3D.catPeg | PusherScene3D.catFalling
        body.damping = GameConstants.fallLinearDamping
        body.restitution = PusherScene3D.pegRestitution
        body.friction = 0.08
        let track = tracks[ObjectIdentifier(node)]!
        track.phase = .falling
        track.falling = true
        track.lastScreen = s
        track.spawnScreenX = s.x
        track.isReward = reward
        if reward { rewardSpawned += 1 }
        body.contactTestBitMask = PusherScene3D.catPeg
        return node
    }

    /// 下落中金币的外观缩放：让它在屏幕上的直径一直等于 BONUS 线（解除约束处）的直径，到 BONUS 线时正好是 1
    private var releaseDepth: Float = 1
    private func fallScale(at p: SCNVector3) -> SCNVector3 {
        let s = max(0.3, min(1.5, geo.depth(p) / releaseDepth))
        return SCNVector3(s, s, s)
    }

    /// 金币越过 BONUS 线：解除平面约束，位置和速度不变，落向推板顶面 / 斜坡，碰到后自然翻滚
    /// v11.6：台面金币平时用方盒碰撞体（便宜）。叠在别的金币上、却只靠方盒看不见的角撑着（看上去悬空）的金币，
    /// 换成圆柱碰撞体，落到下面金币的圆面上；回到贴着台面时换回方盒。每 0.25 秒看一次，换形状时位置、速度不变
    /// 圆柱换回方盒时用的方盒边长比例（0.9·直径：原大的方盒角会压进挤紧的邻居）
    static let swapBackBoxScale: Float = 0.9
    static let hybridPile = !ProcessInfo.processInfo.arguments.contains("-debugBoxOnlyPile")
    private func updatePileCollider(_ node: SCNNode, track: CoinTrack, position p: SCNVector3, now: TimeInterval, among all: [SCNNode]) {
        guard PusherScene3D.pileUsesBoxCollider, now - track.lastShapeCheck > 0.1, let old = node.physicsBody else { return }
        track.lastShapeCheck = now
        let t = config.coinThickness
        // 推板顶面上的金币不换（它们在 pusherHeight 上，不算「叠起来」）；台面上高于一枚厚度的就用圆柱，回到贴着台面再换回方盒
        let onDeck = p.z > pusherFrontZ - config.coinRadius && p.y < geo.pusherHeight - 0.1
        // 只有「叠起来、却只靠方盒看不见的角撑着」的金币换成圆柱（落到圆面上）；回到贴着台面再换回方盒
        // 被别的金币盖住的看不见，也换回方盒（省物理开销）
        // （在 coinLock 里调用：用调用方的快照，不能再取 coins）
        // v11.6：换成圆柱后不再换回方盒——换回时方盒的角会压进挤紧的邻居，物理把金币压到台面以下
        // 被盖住（看不见）或回到台面时换回方盒。换回用小一号的方盒（边长 0.85·直径，角只比圆面多出约 0.2 半径）：
        // 原大的方盒角会压进挤紧的邻居，物理把金币压到台面以下
        let want = track.roundCollider ? onDeck && p.y > t * 0.9 && !isCovered(node, at: p, among: all)
                                       : onDeck && p.y > t * 1.15 && !isCovered(node, at: p, among: all) && !isVisuallySupported(node, at: p)
        guard want != track.roundCollider else { return }
        track.roundCollider = want
        let shape = want ? SCNPhysicsShape(geometry: coinGeometry, options: nil)
                         : PusherScene3D.pileShape(radius: config.coinRadius * PusherScene3D.swapBackBoxScale, thickness: config.coinThickness, geometry: coinGeometry)
        let v = old.velocity, w = old.angularVelocity, resting = old.isResting
        node.transform = node.presentation.transform
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = old.mass
        body.rollingFriction = old.rollingFriction
        body.angularDamping = old.angularDamping
        body.continuousCollisionDetectionThreshold = old.continuousCollisionDetectionThreshold
        body.allowsResting = old.allowsResting
        body.categoryBitMask = old.categoryBitMask
        body.collisionBitMask = old.collisionBitMask
        body.contactTestBitMask = old.contactTestBitMask
        body.damping = old.damping
        body.restitution = old.restitution
        body.friction = old.friction
        node.physicsBody = body
        if !resting { body.velocity = v; body.angularVelocity = w }
    }

    private func release(_ node: SCNNode, track: CoinTrack) {
        track.falling = false
        track.releasedAt = CACurrentMediaTime()
        guard let old = node.physicsBody else { return }
        // 换成台面用的碰撞体（盒子），位置、速度不变
        let v = old.velocity
        node.transform = node.presentation.transform
        let body = SCNPhysicsBody(type: .dynamic, shape: PusherScene3D.pileShape(radius: config.coinRadius, thickness: config.coinThickness, geometry: coinGeometry))
        track.roundCollider = !PusherScene3D.pileUsesBoxCollider
        body.mass = 0.05
        body.rollingFriction = 0.08
        body.angularDamping = 0.35
        body.continuousCollisionDetectionThreshold = CGFloat(config.coinThickness * 0.5)
        node.physicsBody = body
        body.velocity = v
        node.childNodes.first?.scale = SCNVector3(1, 1, 1)
        node.childNodes.first?.categoryBitMask &= ~PusherScene3D.fallLightMask
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
                    x += d * (layer == 0 ? 1.0 : 1.08)
                }
                z -= d * 0.87 * (layer == 0 ? 1.0 : 1.08)
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
    /// 测帧率用：渲染线程每帧从 willRender 到 didRender 的 CPU 时间（毫秒）
    private var renderStart: CFTimeInterval = 0, renderMsSum: Double = 0, renderMsMax: Double = 0, renderMsCount = 0
    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        if logsPhysicsStats { renderStart = CACurrentMediaTime() }
    }
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        guard logsPhysicsStats, renderStart > 0 else { return }
        let ms = (CACurrentMediaTime() - renderStart) * 1000
        renderMsSum += ms; renderMsCount += 1; renderMsMax = max(renderMsMax, ms)
    }
    private func takeRenderMs() -> (Double, Double) {
        defer { renderMsSum = 0; renderMsCount = 0; renderMsMax = 0 }
        return (renderMsCount == 0 ? 0 : renderMsSum / Double(renderMsCount), renderMsMax)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        spawnLock.lock()
        let spawns = pendingSpawns
        pendingSpawns.removeAll()
        // 生成出来的金币马上算进下落中（下面 makeFallingCoin 之后、下一次物理回调之前，限流不会少算）
        fallingPublished += spawns.count
        spawnLock.unlock()
        for (s, v, special, reward) in spawns { makeFallingCoin(atScreen: s, screenVelocity: v, special: special, reward: reward) }
        updateBonusGate()
        if logsPhysicsStats {
            logFrames += 1
            if logWindowStart == 0 { logWindowStart = time }
            if time - logWindowStart >= 1 {
                let rms = takeRenderMs()
                NSLog("RENDER_STATS renderMs=%.2f renderMaxMs=%.2f", rms.0, rms.1)
                NSLog("PUSHER_STATS fps=%.1f total=%d fallen=%d rejected=%d thermal=%d physMs=%.2f bonusX=%d bonusPass=%d bonusStraddle=%d bonusOld=%d bonusPen=%.2f bonusFix=%d front=%d side=%d tilt20=%.3f float=%.3f round=%d vfloat=%.3f sunk=%d clamps=%d rewardSpawned=%d rewardTray=%d rewardSide=%d rewardOther=%d rewardInPlay=%d dead=%d table=%d", Double(logFrames) / (time - logWindowStart), coins.count, droppedCount, rejectedCount, ProcessInfo.processInfo.thermalState.rawValue, takePhysicsMs(), bonusCrossings, bonusPasses, bonusStraddles, bonusOldRuleHits, bonusMaxPenetration, bonusCorrections, removalReasons["fellIntoTray"] ?? 0, removalReasons["fellSide"] ?? 0, PerfDebug.pileStats ? pileTiltShare() : 0, PerfDebug.pileStats ? pileFloatShare() : 0, tracks.values.filter { $0.roundCollider && !$0.falling }.count, lastVisibleFloatShare, lifecycleCounts["sunkBelowDeck"] ?? 0, deckClamps, rewardSpawned, rewardRemoved["fellIntoTray"] ?? 0, rewardRemoved["fellSide"] ?? 0, rewardRemoved.filter { $0.key != "fellIntoTray" && $0.key != "fellSide" }.values.reduce(0, +), rewardInPlay, deadZoneCount, tablePublished)
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
        sampleScreen(renderer, time: lastSimulationTime > 0 ? lastSimulationTime : time)
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
        physicsStepStart = CACurrentMediaTime()   // 到 didSimulatePhysics 之间是物理推进（含推板动作）
    }
    private var lastDebugTick = 0

    /// 最近一次物理推进的时间：每帧开头采样时 presentation 是上一帧物理的结果，帧间隔要用它（不是本帧的时间）
    private var lastSimulationTime: TimeInterval = 0
    private let fallLightNode = SCNNode()
    private var lastFallBoostTime: TimeInterval = 0
    func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        defer { lastFallBoostTime = time }
        lastSimulationTime = time
        let g = geo
        let now = CACurrentMediaTime()
        var removed: [Bool] = []
        if physicsStepStart > 0 { physicsMsSum += (now - physicsStepStart) * 1000; physicsMsCount += 1 }
        coinLock.lock(); defer { coinLock.unlock() }
        let snapshot = _coins   // 循环里不能再读 _coins（removeAll 正在改它）
        defer {
            var f = 0, r = 0
            for t in tracks.values { if t.falling { f += 1 }; if t.isReward { r += 1 } }
            fallingNow = f; rewardInPlay = r
            let table = _coins.count - f
            spawnLock.lock(); fallingPublished = f; tablePublished = table; spawnLock.unlock()
        }
        _coins.removeAll { node in
            let id = ObjectIdentifier(node)
            guard let track = tracks[id] else { return false }
            if track.falling {
                // 下落中：在竖直平面里（velocityFactor 锁住 z），按离相机的远近缩放外观，屏幕上大小不变
                node.childNodes.first?.scale = fallScale(at: node.presentation.position)
                // 下落中不能转动，停在钉子正上方会一直卡住：速度很小时给一点随机的横向推力（2D 版碰到格挡时也这样做）
                if let body = node.physicsBody {
                    var v = body.velocity
                    // 先看物理算出的速度：停在钉子顶上（几乎不动）就给一点随机横向速度让它滑下去
                    if v.x * v.x + v.y * v.y < 0.25 {
                        v = SCNVector3(Float.random(in: 0.8...1.6) * (Bool.random() ? 1 : -1), v.y - 0.5, 0)
                    }
                    // 再加下落平面里额外的向下加速度（钉子多、弹跳耗能，保持参考的下落时长）。
                    // 顺序不能反：先加速度再判断，停在钉顶的金币速度总大于阈值、永远不会被推下去
                    let dt = Float(min(0.05, max(0, time - lastFallBoostTime)))
                    v.y -= PusherScene3D.verticalGravity * GameConstants.fallGravityBoost * dt
                    body.velocity = v
                }
                return false
            }
            var p = node.presentation.position
            // v11.7：被金币堆和推板挤进台面的金币（物理引擎偶尔把薄金币压进静态台面）放回台面上；
            // 已经钻到推板前脸后面的，放到前脸前面（不然推板收回时从它上面滑过去，金币被推板盖住看不见）
            // 台面顶：金币堆那段中间高、两边略低；更后面（推板下面）是平的 0
            let deckTop = p.z < g.postFrontZ - 0.3 ? 0 : -abs(p.x) * sin(PusherScene3D.pileCrownAngle)
            // 平躺时圆心在台面上半个厚度；低了 0.03 以上就是压进台面了（刚开始陷就放回去，挪动很小）
            if p.y < deckTop + config.coinThickness / 2 - 0.03 && p.y > PusherScene3D.removeBelowY && p.z < g.lipZ - 0.4 && p.z > g.wallZ
                && abs(p.x) < g.pileHalfWidth(atZ: min(p.z, g.lipZ)) - PusherScene3D.edgeStripWidth - 0.2 {
                p.y = deckTop + config.coinThickness / 2 + 0.005
                if p.z < pusherFrontZ + config.coinRadius { p.z = pusherFrontZ + config.coinRadius + 0.02 }
                node.position = p
                node.orientation = SCNQuaternion(0, 0, 0, 1)
                if let body = node.physicsBody {
                    var v = body.velocity; v.y = max(0, v.y); body.velocity = v
                    body.angularVelocity = SCNVector4(0, 0, 0, 0)
                    body.resetTransform()
                }
                deckClamps += 1
            }
            updatePhase(node, track: track, position: p, now: now)
            if PusherScene3D.hybridPile { updatePileCollider(node, track: track, position: p, now: now, among: snapshot) }
            // v11.5：推板扫过的那段台面上的金币不休眠——睡着的金币被推板前脸撞醒时会一下子弹开（画面上跳一下）
            if let body = node.physicsBody {
                let inSweep = p.z < g.pusherFrontExtendedZ + config.coinRadius * 2 && p.z > g.wallZ && p.y < g.pusherHeight + 0.2
                if body.allowsResting == inSweep { body.allowsResting = !inSweep }
            }
            // 诊断：沉到台面以下的金币（不在前沿或两侧掉落的位置），每枚记一次
            if p.y < -0.04 && p.y > PusherScene3D.removeBelowY && p.z < g.lipZ - 0.4 && p.z > g.wallZ && !track.sunkLogged
                && abs(p.x) < g.pileHalfWidth(atZ: min(p.z, g.lipZ)) - PusherScene3D.edgeStripWidth - 0.2 {
                track.sunkLogged = true
                logEvent("sunkBelowDeck", detail: "\(p.x),\(p.y),\(p.z) round=\(track.roundCollider) pusherFront=\(pusherFrontZ)")
            }
            if p.y < PusherScene3D.removeBelowY {
                // 从前沿掉下，或从金币堆两侧墙外的落币槽掉下（v11.5），都进接币槽
                // 从前沿掉下、或从金币堆左右两侧掉下（v11.6 去掉侧墙后），都进接币槽、算玩家的
                // 侧面：掉下时已在金币堆左右边以外（从边角滑下的金币落到接币槽时 z 可能已过前沿，也算侧面）
                let sideDrop = p.z > g.postFrontZ - 0.4 && abs(p.x) > g.pileHalfWidth(atZ: min(p.z, g.lipZ)) + 0.05
                let reason = p.z > g.lipZ - 0.2 ? "fellIntoTray" : sideDrop ? "fellSide" : "lostBelow"
                removalReasons[reason, default: 0] += 1
                if track.isReward { rewardRemoved[reason, default: 0] += 1 }
                logEvent("removed", detail: "\(reason) at \(p.x),\(p.z) first=\(track.firstLanding?.rawValue ?? "-") prefilled=\(track.prefilled) phase=\(track.phase.rawValue) age=\(String(format: "%.1f", now - track.born))")
                tracks[id] = nil
                // v11.8：只有从前沿掉进接币槽的才算玩家的；从两侧掉下的进侧面回收槽（真实推币机的「抽水」），不计分
                if reason == "fellIntoTray" || (reason == "fellSide" && PusherScene3D.sideDropsPay) { removed.append(node.name == PusherScene3D.specialName) }
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

    // MARK: 格挡钉统计（v11.6）
    /// 每枚越过 BONUS 线的金币：碰到格挡钉的次数、从投币口到 BONUS 线的横向位移（点）、过 BONUS 线时的屏幕 x
    private(set) var pegHitCounts: [Int] = []
    private(set) var lateralShifts: [CGFloat] = []
    private(set) var releaseXs: [CGFloat] = []
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let a = contact.nodeA, b = contact.nodeB
        let coin: SCNNode
        if a.physicsBody?.categoryBitMask == PusherScene3D.catPeg { coin = b } else if b.physicsBody?.categoryBitMask == PusherScene3D.catPeg { coin = a } else { return }
        guard let track = tracks[ObjectIdentifier(coin)], track.falling else { return }
        // 同一次碰撞可能连着报几次接触：0.08 秒内只算一次
        let now = CACurrentMediaTime()
        if now - track.lastPegHitTime > 0.08 { track.pegHits += 1 }
        track.lastPegHitTime = now
    }

    /// v11.6 性能：台面上的金币用扁盒子做碰撞体（Bullet 盒对盒有专门的快速算法，金币堆的碰撞计算从约 14 毫秒降到约 5 毫秒）；
    /// 盒子边长 = 金币直径（同一层相邻的金币不会叠进去）。下落中的金币仍用圆柱，碰格挡钉的弹法和圆形金币一样
    static var pileUsesBoxCollider = !ProcessInfo.processInfo.arguments.contains("-debugCylinderPile")
    /// v11.6（用户要求侧面明显掉币）：台面两边向外倾的边带宽度和倾角
    /// 边带宽 1.2（约 1.4 枚金币宽）、倾 0.2 弧度（约 11°，比金币和台面的摩擦角 0.12 陡）；外沿凸边 0.02：
    /// 模拟器长跑 6 分钟约 7.7% 的出币从两侧掉下，金币堆两边仍铺满（覆盖 0.99）
    static let edgeStripWidth: Float = 1.2
    static let edgeStripTilt: Float = 0.2
    static func pileShape(radius: Float, thickness: Float, geometry: SCNGeometry) -> SCNPhysicsShape {
        guard pileUsesBoxCollider else { return SCNPhysicsShape(geometry: geometry, options: nil) }
        let side = CGFloat(radius * 2)
        return SCNPhysicsShape(geometry: SCNBox(width: side, height: CGFloat(thickness), length: side, chamferRadius: 0), options: nil)
    }

    // MARK: 性能统计
    /// v11.5：物理步长 180 → 120 Hz（真机上金币两两碰撞检测是主要开销，按步数线性增长；90 Hz 时下落变慢到 1.95 秒以上）
    static let physicsTimeStep: TimeInterval = 1.0 / 120.0
    private var physicsStepStart: TimeInterval = 0
    private var physicsMsSum: Double = 0, physicsMsCount = 0
    /// 每帧从渲染器 update 到物理推进完的平均毫秒数（读取后清零）
    func takePhysicsMs() -> Double {
        defer { physicsMsSum = 0; physicsMsCount = 0 }
        return physicsMsCount == 0 ? 0 : physicsMsSum / Double(physicsMsCount)
    }

    // MARK: 金币生命周期（调试日志 + 测试断言）
    static let removeBelowY: Float = -1.2
    enum CoinPhase: String { case falling, airborne, onPusher, onRamp, onPile, fallingFront, lostBehindWall, lostSide }
    final class CoinTrack {
        var phase: CoinPhase = .airborne
        var falling = false
        /// 台面金币当前用圆柱碰撞体（叠在别的金币上面时）还是方盒（贴着台面时）
        var roundCollider = false
        var sunkLogged = false
        /// v11.7 中奖金币
        var isReward = false
        /// v11.7 死角检查：从什么时候开始停在推板顶面、斜坡、台面以外的地方
        var deadSince: TimeInterval?
        var deadLogged = false
        /// 诊断：阶段变化记录（推板顶面停留过久时打印）
        var history = ""
        var lastSample: TimeInterval = 0
        var lastShapeCheck: TimeInterval = 0
        /// 在推板顶面期间到过的最高点、最靠前的位置（查停留过久的金币用）
        var pusherMaxY: Float = -.infinity, pusherMaxZ: Float = -.infinity
        var prefilled = false
        let born: TimeInterval
        var releasedAt: TimeInterval?
        var firstLanding: CoinPhase?
        var firstLandingTime: TimeInterval?
        var rampTime: TimeInterval?
        var pusherTime: TimeInterval?
        var rampReachedPusher = false
        var standingSince: TimeInterval?
        var lastScreen: CGPoint?
        var lastDiameter: CGFloat?
        var lastSampleTime: TimeInterval?
        var lastSpeed: CGFloat = 0
        var crossedBattle = false, crossedFruit = false, crossedBonus = false
        /// v11.6：下落中碰到格挡钉的次数（物理接触回调计数）、投币口处的屏幕 x
        var pegHits = 0
        var lastPegHitTime: TimeInterval = 0
        var spawnScreenX: CGFloat?
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
    var pendingRampCoins: Int { pendingRampCoins(asOf: CACurrentMediaTime()) }
    /// asOf：物理停下的时刻（测试先停物理再读统计，避免读数之间又有金币落上斜坡或滑到推板）
    func pendingRampCoins(asOf now: TimeInterval) -> Int {
        tracks.values.filter { if let r = $0.rampTime, r.isFinite, !$0.rampReachedPusher { return now - r < 3 } else { return false } }.count
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
        if abs(p.x) > g.rampInnerX - 0.05, p.z < g.rampExtendedFrontZ + 0.1, p.z > g.rampFrontZ - 3.2,
           p.y > g.rampInnerHeight - 0.05, p.y < abs(g.rampOuter.y) + config.coinRadius + 0.3 {
            let t = (abs(p.x) - g.rampInnerX) / max(0.01, abs(g.rampOuter.x) - g.rampInnerX)
            let surface = g.rampInnerHeight + t * (g.rampOuter.y - g.rampInnerHeight)
            if p.y < surface + config.coinRadius + 0.1 { return .onRamp }
        }
        if p.y < g.pusherHeight - 0.1 && p.z > pusherFrontZ - 0.1 { return .onPile }
        // v11.7：已经在推板前脸前面、叠在金币堆第二层上的金币（比推板顶面低一个半径以内）也算到了金币堆
        // （原来只认推板顶面以下的，掉到第二层上的金币一直算「空中」，推板顶面停留时间被算成十几秒）
        // 圆心已过推板前脸、斜靠在前脸上的金币也算离开了推板顶面
        if p.z > pusherFrontZ && p.y < g.pusherHeight + config.coinRadius { return .onPile }
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
                    // 绕「币面内的水平轴」（币面法线 × 竖直）转才会倒下；v11.6 前固定绕世界 x 轴，币面朝左右立着
                    // （侧面边带上滑下来的金币）时只会原地转，倒不下去
                    let ax = -m.m23, az = m.m21, len = (ax * ax + az * az).squareRoot()
                    let axis = len > 0.1 ? SCNVector3(ax / len, 0, az / len) : SCNVector3(1, 0, 0)
                    body.applyTorque(SCNVector4(axis.x, 0, axis.z, 0.015 * (Bool.random() ? 1 : -1)), asImpulse: true)
                }
                if let since = track.standingSince {
                    if now - since > 0.5 { standingViolations += 1; track.standingSince = .infinity; logEvent("standing", detail: "\(p.x),\(p.y),\(p.z)") }
                } else { track.standingSince = now }
            } else if track.standingSince != .infinity { track.standingSince = nil }
        }
        if let t0 = track.pusherTime {
            track.pusherMaxY = max(track.pusherMaxY, p.y); track.pusherMaxZ = max(track.pusherMaxZ, p.z)
            // 诊断：在推板顶面期间每秒记一次位置和推板前沿（停留过久时打印）
            if logsLifecycle, now - t0 > 2.5, now - track.lastSample >= 0.5 {
                track.lastSample = now
                let v = node.physicsBody?.velocity ?? SCNVector3Zero
                track.history += " [\(String(format: "%.1f", now - track.born)) x\(String(format: "%.2f", p.x)) y\(String(format: "%.2f", p.y)) z\(String(format: "%.2f", p.z)) f\(String(format: "%.2f", pusherFrontZ)) vz\(String(format: "%.2f", v.z)) \(ph.rawValue)]"
            }
        }
        // v11.7 死角检查：几乎不动、又不在推板顶面 / 斜坡 / 台面（金币堆、推板扫过的地方）上，超过 3 秒算一次
        if !track.falling {
            let v = node.physicsBody?.velocity ?? SCNVector3Zero
            let still = v.x * v.x + v.y * v.y + v.z * v.z < 0.04
            let onDeck = p.y < 0.9 && p.z > geo.wallZ && abs(p.x) < geo.pileHalfWidth(atZ: min(p.z, geo.lipZ)) + 0.3
            if still && ph != .onPusher && ph != .onRamp && !onDeck {
                if let since = track.deadSince {
                    if now - since > 3 && !track.deadLogged {
                        track.deadLogged = true
                        deadZoneCount += 1
                        logEvent("deadZone", detail: "\(p.x),\(p.y),\(p.z) phase=\(ph.rawValue)")
                    }
                } else { track.deadSince = now }
            } else { track.deadSince = nil }
        }
        guard ph != track.phase, ph != .airborne else { return }
        let previous = track.phase
        track.phase = ph
        if logsLifecycle { track.history += " \(ph.rawValue)@\(String(format: "%.1f", now - track.born)) y\(String(format: "%.2f", p.y)) z\(String(format: "%.1f", p.z))" }
        if !track.prefilled, track.firstLanding == nil, [.onPusher, .onRamp, .onPile].contains(ph) {
            track.firstLanding = ph
            track.firstLandingTime = now
            fallTimes.append(now - track.born)
            // 推板收回时落下的金币落在推板前脸前面、推板扫过的台面上（推出时被推走）：单独计为 landedSweep
            // v11.6：落在推板前脸前面那一排金币上面的（金币中心最远到前脸 + 2 个半径）也算落在推板扫过的台面上——
            // 下面那排金币在推板扫过的范围里，推出时连同上面的一起推走
            let sweep = ph == .onPile && p.z < geo.pusherFrontExtendedZ + config.coinRadius * 2
            logEvent(ph == .onPusher ? "landedPusher" : ph == .onRamp ? "landedRamp" : sweep ? "landedSweep" : "landedPile",
                     detail: "at \(p.x),\(p.y),\(p.z) pusherFront=\(pusherFrontZ)")
        }
        switch ph {
        // 斜坡 → 推板只跟踪第一次落在斜坡上的金币（与 landedRamp 一一对应）
        case .onRamp: if track.rampTime == nil, track.firstLanding == .onRamp { track.rampTime = now }
        case .onPusher:
            if let r = track.rampTime, r.isFinite, !track.rampReachedPusher {
                track.rampReachedPusher = true
                rampSlideTimes.append(now - r); logEvent("rampToPusher")
            }
            if track.pusherTime == nil { track.pusherTime = now }
        case .onPile where track.rampTime.map({ $0.isFinite }) == true && !track.rampReachedPusher && p.z < geo.pusherFrontExtendedZ + config.coinRadius:
            // v11.5：推板收回时斜坡上滑下的金币落在推板扫过的台面上（推出时推走），与滑到推板顶面同样算到位
            track.rampReachedPusher = true
            logEvent("rampToSweep")
        case .onPile:
            if let t = track.pusherTime, (previous == .onPusher || previous == .airborne) {
                pusherToPileTimes.append(now - t); logEvent("pusherToPile")
                if now - t > GameConstants.pusherPeriod { logEvent("pusherLong", detail: "dwell=\(String(format: "%.1f", now - t)) at \(p.x),\(p.y),\(p.z) maxY=\(track.pusherMaxY) maxZ=\(track.pusherMaxZ) pusherH=\(geo.pusherHeight) extFront=\(geo.pusherFrontExtendedZ) previous=\(previous.rawValue) round=\(track.roundCollider) reward=\(track.isReward) history:\(track.history)") }
                track.pusherMaxY = -.infinity; track.pusherMaxZ = -.infinity
                track.pusherTime = nil
            }
            // v11.6：斜坡末端滑下、落在推板前面金币上的金币（比推板扫过的台面稍远）：也离开了斜坡、到了台面，单独计数
            if let r = track.rampTime, r.isFinite, !track.rampReachedPusher {
                track.rampReachedPusher = true
                logEvent("rampToPile", detail: "at \(p.x),\(p.y),\(p.z) after=\(String(format: "%.2f", now - r))")
            }
        case .fallingFront:
            logEvent("fellFront")
            if let r = track.rampTime, r.isFinite, !track.rampReachedPusher { logEvent("rampLost", detail: "to=fallingFront at \(p.x),\(p.y),\(p.z)") }
        case .lostBehindWall: logEvent("lostBehindWall", detail: "\(p.x),\(p.y),\(p.z)")
        case .lostSide: logEvent("lostSide", detail: "\(p.x),\(p.y),\(p.z) first=\(track.firstLanding?.rawValue ?? "-") previous=\(previous.rawValue) prefilled=\(track.prefilled) age=\(now - track.born)")
        default: break
        }
        if let r = track.rampTime, !track.rampReachedPusher, now - r > 3, ph == .onRamp {
            rampTimeouts += 1; track.rampTime = .infinity
        }
    }

    /// 每帧：下落中的金币按屏幕投影位置触发事件、到 BONUS 线解除约束；所有金币做连续性检查（位置、大小）
    /// time：产生当前 presentation 的那次物理推进的场景时间。连续性检查的帧间隔用它而不是墙钟：
    /// 负载高时墙钟、本帧时间和物理实际推进的时间会错开一帧，造成误报
    private func sampleScreen(_ renderer: SCNSceneRenderer, time: TimeInterval) {
        let r = config.coinRadius
        var releaseList: [(SCNNode, CoinTrack)] = []
        var battle = 0
        var fruits: [CGFloat] = [], bonuses: [(CGFloat, CGFloat, CGFloat)] = []
        framesSampled += 1
        for node in coins {
            guard let track = tracks[ObjectIdentifier(node)] else { continue }
            // 不做画面验收时只看下落中的金币（触发战斗区 / 水果 / BONUS 事件、解除约束）；落地后的金币不必每帧投影
            if !verifiesMotion && !track.falling { continue }
            let p = node.presentation.position
            // 刚加进场景、物理还没同步的那一帧，presentation 在原点：跳过
            if p.x == 0 && p.y == 0 && p.z == 0 { continue }
            let s = renderer.projectPoint(p)
            var sp = CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
            // 屏幕直径：相机没有偏航和滚转，世界 x 方向的 2r 投到屏幕上正好是 2r·焦距/深度（省掉每枚每帧两次投影）
            let visualScale = CGFloat(node.childNodes.first?.scale.x ?? 1)
            let diameter = CGFloat(2 * r * geo.focal / max(0.1, geo.depth(p))) * visualScale
            let v = node.physicsBody?.velocity ?? SCNVector3Zero
            // 世界速度换算成屏幕速度：按这枚金币自己的深度（越靠近相机，同样的速度在屏幕上走得越快）
            let speed = CGFloat((v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() * geo.focal / max(0.1, geo.depth(p)))
            let nowT = time
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
            // 中奖金币不触发战斗、水果、BONUS（不会连锁中奖），越过 BONUS 线时照样解除约束落下
            if !track.crossedBattle && sp.y >= battleLineY { track.crossedBattle = true; if !track.isReward { battle += 1 } }
            if !track.crossedFruit && sp.y >= fruitLineY { track.crossedFruit = true; if !track.isReward { fruits.append(sp.x) } }
            // v11.6 闸门：在立柱高度范围内逐帧量金币压进立柱多深（圆到立柱矩形的距离 < 半径）。
            // 高速金币和运动学立柱接触时物理会让它压进去几点（接触松弛）：圆心在立柱高度范围内、从侧面压进去时，
            // 把金币沿横向推回它圆心所在的那一侧（开口里或外面）、横向速度反向——画面上金币不会一半在里一半在外
            if !bonusPosts.isEmpty, let l = gateLayout, sp.y + diameter / 2 > bonusPostTopY, sp.y - diameter / 2 < bonusPostBottomY {
                for side: CGFloat in [-1, 1] {
                    let a = bonusGateX + side * l.bonusOpeningWidth / 2, b = a + side * l.bonusPostWidth
                    let lo = min(a, b), hi = max(a, b)
                    if sp.y >= bonusPostTopY && sp.y <= bonusPostBottomY && sp.x + diameter / 2 > lo && sp.x - diameter / 2 < hi {
                        // 圆心在立柱中线靠开口一侧 → 推进开口；否则推到外面
                        let towardGate = (sp.x - (lo + hi) / 2) * side < 0
                        let target = towardGate ? (side < 0 ? hi + diameter / 2 : lo - diameter / 2) : (side < 0 ? lo - diameter / 2 : hi + diameter / 2)
                        let shift = target - sp.x
                        var pos = node.presentation.position
                        pos.x += Float(shift) * bonusPostScale
                        node.position = pos
                        if var vel = node.physicsBody?.velocity, (vel.x > 0) != (shift > 0) { vel.x = -vel.x * Float(PusherScene3D.pegRestitution); node.physicsBody?.velocity = vel }
                        sp.x = target
                        bonusCorrections += 1
                    }
                    // v11.7：从上面落在立柱顶上（或顶角）的金币：沿立柱矩形最近点的法线推回到正好贴着，法向速度反弹
                    if sp.y < bonusPostTopY {
                        let nx = min(max(sp.x, lo), hi), ny = bonusPostTopY
                        let ex = sp.x - nx, ey = sp.y - ny, d = hypot(ex, ey)
                        if d > 0.01, d < diameter / 2 {
                            let ux = ex / d, uy = ey / d, push = diameter / 2 - d
                            var pos = node.presentation.position
                            pos.x += Float(ux * push) * bonusPostScale
                            pos.y -= Float(uy * push) * bonusPostScale   // 屏幕 y 向下、世界 y 向上
                            node.position = pos
                            if var vel = node.physicsBody?.velocity {
                                let wn = SCNVector3(Float(ux), -Float(uy), 0)
                                let vn = vel.x * wn.x + vel.y * wn.y
                                if vn < 0 {
                                    let k = vn * (1 + Float(PusherScene3D.pegRestitution))
                                    vel.x -= k * wn.x; vel.y -= k * wn.y
                                    node.physicsBody?.velocity = vel
                                }
                            }
                            sp.x += ux * push; sp.y += uy * push
                            bonusCorrections += 1
                        }
                    }
                    let dx = max(lo - sp.x, 0, sp.x - hi), dy = max(bonusPostTopY - sp.y, 0, sp.y - bonusPostBottomY)
                    bonusMaxPenetration = max(bonusMaxPenetration, diameter / 2 - hypot(dx, dy))
                    if logsLifecycle, diameter / 2 - hypot(dx, dy) > 3 {
                        NSLog("BONUS_PEN pen=%.2f side=%.0f x=%.1f y=%.1f gate=%.1f top=%.1f bottom=%.1f r=%.1f v=%.2f,%.2f peg=%d", diameter / 2 - hypot(dx, dy), side, sp.x, sp.y, bonusGateX, bonusPostTopY, bonusPostBottomY, diameter / 2, v.x, v.y, track.pegHits)
                    }
                }
            }
            if !track.crossedBonus && sp.y >= releaseLineY {
                track.crossedBonus = true
                if !track.isReward { bonuses.append((sp.x, diameter / 2, bonusGateX)) }
                if let l = gateLayout, !track.isReward {
                    bonusCrossings += 1
                    let inside = l.bonusFullyInside(x: sp.x, radius: diameter / 2, gateX: bonusGateX)
                    let straddle = l.bonusStraddlesPost(x: sp.x, radius: diameter / 2, gateX: bonusGateX)
                    if inside { bonusPasses += 1 }
                    if straddle { bonusStraddles += 1 }
                    if abs(sp.x - bonusGateX) < l.fruitLampWidth / 2 { bonusOldRuleHits += 1 }
                    if logsLifecycle || logsPhysicsStats {
                        NSLog("BONUS_CROSS x=%.1f r=%.1f gate=%.1f inside=%d straddle=%d", sp.x, diameter / 2, bonusGateX, inside ? 1 : 0, straddle ? 1 : 0)
                    }
                }
                releaseList.append((node, track))
                pegHitCounts.append(track.pegHits)
                if let x0 = track.spawnScreenX { lateralShifts.append(sp.x - x0) }
                releaseXs.append(sp.x)
            }
        }
        for (node, track) in releaseList { release(node, track: track) }
        if battle > 0 || !fruits.isEmpty || !bonuses.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for _ in 0..<battle { self.onCrossBattle?() }
                fruits.forEach { self.onCrossFruit?($0) }
                bonuses.forEach { self.onCrossBonus?($0.0, $0.1, $0.2) }
            }
        }
    }

    // MARK: 遮挡检查：投影在视图内、不被底部面板（声明的遮挡物）和机器挡住
    /// 声明的遮挡物（参考里同样挡住金币堆两侧后角）
    static let declaredOccluders: Set<String> = ["postLeft", "postRight", "shelfLeft", "shelfRight", "shelfLeftRail", "shelfRightRail", "lip", "pusherGuideLeft", "pusherGuideRight"]
    private(set) var declaredHidden = 0
    /// maxCoins：最多检查几枚（App 里 -autoplay 在主线程上做，只抽查一部分，避免卡住界面；测试里查全部）
    func occlusionReport(in view: SCNView, maxCoins: Int = .max) -> (checked: Int, problems: [String]) {
        var problems: [String] = []
        var checked = 0
        let cam = cameraNode.position
        let all = coins
        let coinIDs = Set(all.map { ObjectIdentifier($0) })
        for node in (maxCoins < all.count ? Array(all.shuffled().prefix(maxCoins)) : all) {
            let p = node.presentation.position
            // 已经越过前沿往下掉：被铜前沿和底部面板挡住是允许的（低于台面 0.15，或已经过了凸起铜边的前面 lipZ + 0.25）
            guard p.y > -0.15 && p.z < geo.lipZ + 0.25 else { continue }
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
                if n === node || n.parent === node || coinIDs.contains(ObjectIdentifier(n)) || n.name == "coinVisual" || n.name == "peg" || n.name == "fieldWall" || n.name == "rampGuard" || n.name == "lipCollider" || (n.name ?? "").hasPrefix("pileWall") || (n.name ?? "").hasPrefix("screenWall") || (n.name ?? "").hasPrefix("rampCap") || (n.name ?? "").hasPrefix("sideLip") || n.name == "bonusPost" || n.name == "backWallSlope" { continue }   // 看不见的碰撞体不算遮挡
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
    /// 金币堆里斜着（币面法线偏离竖直 > 20°）的金币占比：方盒碰撞体的角会把金币斜撑起来
    func pileTiltShare() -> Double {
        let g = geo
        var n = 0, tilted = 0
        for c in coins {
            let p = c.presentation.position
            guard p.y > -0.1, p.y < g.pusherHeight - 0.1, p.z > pusherFrontZ, p.z < g.lipZ, tracks[ObjectIdentifier(c)]?.falling == false else { continue }
            n += 1
            if abs(c.presentation.worldTransform.m22) < 0.94 { tilted += 1 }
        }
        return n == 0 ? 0 : Double(tilted) / Double(n)
    }

    /// 金币堆里「看上去悬空」的金币占比：高出台面一枚厚度以上的金币，物理接触点没有一个同时落在两枚金币
    /// 看得见的圆面里（或落在机器上）——它只靠方盒碰撞体看不见的角撑着
    private var visibleFloating = 0
    /// 上一次 pileFloatShare 里「看得见（没被盖住）的悬空金币」占比
    private(set) var lastVisibleFloatShare: Double = 0
    func pileFloatShare() -> Double {
        // 测试里从主线程调用：锁住场景，渲染线程这时不在模拟物理、不改 tracks
        if Thread.isMainThread { SCNTransaction.lock() }
        defer { if Thread.isMainThread { SCNTransaction.unlock() } }
        let g = geo, t = config.coinThickness
        var n = 0, floating = 0
        visibleFloating = 0
        defer { lastVisibleFloatShare = n == 0 ? 0 : Double(visibleFloating) / Double(n) }
        let all = coins
        for c in all {
            guard let tr = tracks[ObjectIdentifier(c)], !tr.falling else { continue }
            let p = c.presentation.position
            guard p.y > -0.1, p.y < g.pusherHeight - 0.1, p.z > pusherFrontZ, p.z < g.lipZ else { continue }
            n += 1
            if p.y > t * 1.2 && !isVisuallySupported(c, at: p) {
                floating += 1
                if !isCovered(c, at: p, among: all) { visibleFloating += 1 }
            }
        }
        return n == 0 ? 0 : Double(floating) / Double(n)
    }

    /// 上面压着别的金币（圆面在水平方向重叠、比它高）：这枚金币看不见
    private func isCovered(_ c: SCNNode, at p: SCNVector3, among all: [SCNNode]) -> Bool {
        let r = config.coinRadius, t = config.coinThickness
        return all.contains { o in
            guard o !== c, tracks[ObjectIdentifier(o)]?.falling == false else { return false }
            let q = o.presentation.position
            return q.y > p.y + t * 0.3 && q.y < p.y + t * 3 && (p.x - q.x) * (p.x - q.x) + (p.z - q.z) * (p.z - q.z) < (2 * r * 0.9) * (2 * r * 0.9)
        }
    }

    /// 物理接触点里有没有一个看得见的支撑：靠在机器上时接触点在自己的圆面里；靠在另一枚金币上时接触点同时在
    /// 两枚的圆面里，或叠在下面那枚上、两枚圆面在水平方向重叠（平叠时盒子接触点在重叠方块的角上）
    private func isVisuallySupported(_ c: SCNNode, at p: SCNVector3) -> Bool {
        guard let body = c.physicsBody else { return true }
        let r = config.coinRadius, t = config.coinThickness
        func onDisc(_ node: SCNNode, _ w: SCNVector3) -> Bool {
            let l = node.presentation.convertPosition(w, from: nil)
            return (l.x * l.x + l.z * l.z).squareRoot() <= r * 1.03
        }
        return scene.physicsWorld.contactTest(with: body, options: nil).contains { k in
            let other = k.nodeA === c ? k.nodeB : k.nodeA
            guard tracks[ObjectIdentifier(other)] != nil else { return onDisc(c, k.contactPoint) }
            if onDisc(c, k.contactPoint) && onDisc(other, k.contactPoint) { return true }
            let q = other.presentation.position
            return q.y < p.y - t * 0.3 && (p.x - q.x) * (p.x - q.x) + (p.z - q.z) * (p.z - q.z) < (2 * r * 0.98) * (2 * r * 0.98)
        }
    }

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
        // 屏幕覆盖：每枚金币在屏幕上占 [x−r, x+r]，求并集覆盖金币堆平的那一段（两边向外倾的边带之间）的比例。
        // v11.6：边带是让金币从两侧掉下去的，本来就稀疏，不算在覆盖里
        guard let v = view else { return (p90, 0, pts.count) }
        let flatHalf = max(g.pileHalfWidth(atZ: g.postFrontZ - 0.3), g.pileHalfWidth(atZ: g.lipZ)) - PusherScene3D.edgeStripWidth
        let zMid = (pusherFrontZ + g.lipZ) / 2
        let lo = CGFloat(v.projectPoint(SCNVector3(-flatHalf, 0, zMid)).x), hi = CGFloat(v.projectPoint(SCNVector3(flatHalf, 0, zMid)).x)
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
    /// 前沿铜边高出台面的高度（约 1 枚金币厚）；v11.6 和两侧边带一起调到返还率约 0.97–1.04（场上约 95 枚）
    static let lipRise: Float = 0.06
    /// 金币堆两侧的凸边高出边带斜面多少：0.02（不到半枚金币厚），金币靠在上面铺满两边，被推挤就翻下去（约 8.5% 从两侧掉）
    static let sideLipRise: Float = 0.02
    /// v11.7：屏幕边的透明墙从台面中线高度往上（台面两边比中线低）：翻过台面边沿的金币直接掉下，不会卡在台面边和墙之间
    static let screenWallBottom: Float = 0.05
    /// 金币堆台面向两侧的倾角（弧度）：v11.6 约 1.1°，被推挤的金币往两侧散开，金币堆两边铺满
    static let pileCrownAngle: Float = 0.02
    /// BONUS 立柱碰撞体每边比画出来的宽多少（点）
    static let bonusPostContactPad: CGFloat = 1.5
    /// 斜坡摩擦：金币滑到推板顶面约 0.5 秒（参考 0.43–0.70 秒）
    static let rampFriction: CGFloat = 0.9
    /// 推板顶面摩擦：金币在推板顶面停留约 7.5 秒后被推到金币堆（参考 6.5–8.5 秒）
    static let pusherTopFriction: CGFloat = 0.31
    static let coinTint = UIColor(red: 1.0, green: 0.79, blue: 0.40, alpha: 1)
    static let coinGlow = UIColor(red: 1.0, green: 0.66, blue: 0.14, alpha: 1)
    /// 高光灯只照这个类别的节点（金币外观节点 = 默认类别 1 | 这个）
    static let coinLightMask = 1 << 4
    /// 只照下落中金币的灯（下落时外观节点加上这个类别，落地解除约束时去掉）
    static let fallLightMask = 1 << 5
    /// v11.6 格挡钉和下落金币的弹性（钉子变多后要更有弹性，金币碰到钉子会明显弹开、不在钉上停留）
    static let pegRestitution: CGFloat = 0.6
    static var fallLightIntensity: CGFloat = 1500

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




/// v11.6 真机测帧率用的调试开关和主线程卡顿监视（只有带对应启动参数时才生效）
enum PerfDebug {
    static let args = ProcessInfo.processInfo.arguments
    /// -debugFreezeUI：30 Hz 重画的 SwiftUI 动画层（JACKPOT 字、BONUS 牌、灯牌闪光）改为 1 小时才重画一次
    static let freezeUI = args.contains("-debugFreezeUI")
    /// -debugNoFallLight：关掉只照下落金币的灯
    static let noFallLight = args.contains("-debugNoFallLight")
    static func interval(_ normal: TimeInterval) -> TimeInterval { freezeUI ? 3600 : normal }
    /// -debugPileStats：每秒统计金币堆斜着 / 悬空（物理接触查询，测帧率时不开）
    static let pileStats = args.contains("-debugPileStats")

    /// 主线程帧监视：每秒打印主线程帧数和最大帧间隔（-autoplayLite / -debugPhysicsLog 时开）
    final class MainThreadMonitor: NSObject {
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0, windowStart: CFTimeInterval = 0, frames = 0, maxGap: CFTimeInterval = 0
        private var over33 = 0, over100 = 0
        /// v11.7：每秒 GameState.objectWillChange 次数（整个游戏画面重算的次数）
        var stateChanges = 0
        func start() {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        @objc private func tick(_ l: CADisplayLink) {
            let t = l.timestamp
            if last > 0 {
                let gap = t - last
                maxGap = max(maxGap, gap)
                if gap > 0.033 { over33 += 1 }
                if gap > 0.1 { over100 += 1 }
            }
            last = t; frames += 1
            if windowStart == 0 { windowStart = t }
            if t - windowStart >= 1 {
                NSLog("MAIN_STATS fps=%.1f maxGapMs=%.1f over33=%d over100=%d stateChanges=%d", Double(frames) / (t - windowStart), maxGap * 1000, over33, over100, stateChanges)
                frames = 0; maxGap = 0; windowStart = t; over33 = 0; over100 = 0; stateChanges = 0
            }
        }
    }
    static let monitor = MainThreadMonitor()
}
