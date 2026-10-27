import CoreGraphics
import SwiftUI

// MARK: - 游戏布局
// 唯一的布局来源：只根据屏幕尺寸和安全区计算。
// 坐标系 = 整屏坐标（点，原点在屏幕左上角）。视图摆放各区域、GameState 计算物理都用这一套坐标，
// 不再有单独的「物理坐标」。
struct GameLayout: Equatable {
    let size: CGSize
    let safeArea: EdgeInsets

    // MARK: 区域（自上而下，互不重叠）
    let jackpot: CGRect
    let slotMachine: CGRect
    let sliderTrack: CGRect     // COIN 滑块（金币出口）
    let dropField: CGRect       // 战斗区，下落金币在这里碰格挡
    let fruitBar: CGRect
    let bonusLane: CGRect       // BONUS 滑块
    let pusher: CGRect          // 推币台
    let dropButton: CGRect
    /// 3D 推币台视图：从推币台区域顶部一直到屏幕底部，投币按钮叠在台面前沿之上（与参考布局一致）
    let pusherView: CGRect

    // MARK: 老虎机内部
    let slotReels: CGRect

    // MARK: 物理关键位置
    let coinRadius: CGFloat
    let coinSpawnY: CGFloat
    let coinSliderWidth: CGFloat
    let coinSliderTravel: CGFloat      // COIN 滑块偏离中心的最大距离
    let fieldMinX: CGFloat             // 下落金币的左右边界（金币中心）
    let fieldMaxX: CGFloat
    let slotObstacleRadius: CGFloat
    let slotObstacles: [CGPoint]       // 老虎机每个符号格的碰撞点（5×3），金币在符号之间弹跳
    let slotPins: [CGPoint]            // 转轴之间的格挡钉
    let slotPinRadius: CGFloat
    let fruitPinRadius: CGFloat
    let fruitPins: [CGPoint]           // 水果灯之间的小钉
    let fruitCenters: [CGPoint]        // 7 个水果
    let fruitLampWidth: CGFloat
    let fruitHitHalfWidth: CGFloat
    let fruitBaffleXs: [CGFloat]       // 水果之间的格挡
    let fruitBaffleHalfWidth: CGFloat
    let bonusSliderWidth: CGFloat
    let bonusSliderTravel: CGFloat
    let bedEntryY: CGFloat             // 下落金币越过这条线后交给 3D 推币台（推币台区域顶部附近）
    /// 当前布局与 v9.5 物理（下落 380 单位、推币床 215 单位）的纵向比例，
    /// 用来换算重力、初速度等纵向数值，使不同屏幕上的下落时长一致
    let fallScale: CGFloat

    static let margin: CGFloat = 10
    /// v9.5 物理的下落高度（-360 → 20）和推币床长度
    static let legacyFallHeight: CGFloat = 380

    /// 各区域占安全区内高度的比例，合计 1
    /// 顺序：顶栏、COIN 轨道（投币口在最顶端）、老虎机、战斗区、水果、BONUS、推币台、投币按钮
    /// 按参考 App 逐帧测量的屏幕高度比例（扣除我们更紧凑的顶栏后换算）：
    /// 老虎机约占 27%（参考转轴窗口约占全屏 17%、连同 COIN 拱形轨道约 29%），战斗区约 9.5%，水果约 5.5%，BONUS 约 5.5%
    static let heightRatios: [CGFloat] = [0.07, 0.055, 0.27, 0.095, 0.055, 0.055, 0.30, 0.10]

    /// iPhone 16/17 级别竖屏，GameState 在视图传入真实布局前使用
    static let reference = GameLayout(
        size: CGSize(width: 393, height: 852),
        safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    )

    init(size: CGSize, safeArea: EdgeInsets) {
        self.size = size
        self.safeArea = safeArea

        let m = GameLayout.margin
        let left = safeArea.leading + m
        let right = size.width - safeArea.trailing - m
        let contentW = max(0, right - left)
        let centerX = (left + right) / 2
        let usableH = max(0, size.height - safeArea.top - safeArea.bottom)

        var y = safeArea.top
        var bands: [CGRect] = []
        for ratio in GameLayout.heightRatios {
            let h = usableH * ratio
            bands.append(CGRect(x: 0, y: y, width: size.width, height: h))
            y += h
        }
        jackpot = bands[0]
        sliderTrack = bands[1]
        slotMachine = bands[2].insetBy(dx: m, dy: 0)
        dropField = bands[3].insetBy(dx: m, dy: 0)
        fruitBar = bands[4]
        bonusLane = bands[5]
        pusher = bands[6]
        dropButton = bands[7]
        pusherView = CGRect(x: 0, y: bands[6].minY, width: size.width, height: size.height - bands[6].minY)

        // 老虎机：没有 SPIN 按钮（只由 BONUS 触发），5 列转轴均匀铺满外框宽度
        let slotInner = slotMachine.insetBy(dx: 10, dy: 8)
        slotReels = slotInner

        // 金币直径约为屏宽的 6%（参考 App 下落中金币约 6% 屏宽），随屏幕宽度缩放
        coinRadius = (contentW * 0.06 / 2).rounded()
        coinSpawnY = sliderTrack.midY
        coinSliderWidth = max(44, contentW * 0.14)
        // 参考 App 的 COIN 滑块只在中间约 ±17% 屏宽内往复
        coinSliderTravel = min(max(0, contentW / 2 - coinSliderWidth / 2), size.width * GameConstants.coinSliderTravelFraction)
        fieldMinX = left + coinRadius
        fieldMaxX = right - coinRadius

        // 老虎机符号格就是下落区的障碍物：每格中心一个碰撞圆（与 SlotMachineView 的 5 列、3 行、列间距 4 一致）
        let reelSpacing: CGFloat = 4
        let cellW = (slotReels.width - reelSpacing * 4) / 5
        let cellH = slotReels.height / 3
        slotObstacleRadius = max(6, min(cellW, cellH) * 0.25)   // 留出与格挡钉之间至少一枚金币的空隙
        var obstacles: [CGPoint] = []
        for row in 0..<3 {
            for col in 0..<5 {
                obstacles.append(CGPoint(x: slotReels.minX + (cellW + reelSpacing) * CGFloat(col) + cellW / 2,
                                         y: slotReels.minY + cellH * (CGFloat(row) + 0.5)))
            }
        }
        slotObstacles = obstacles
        // 转轴之间的金色格挡钉：每列之间、每行交界处各一个，金币在符号间多次弹跳、下落变慢
        slotPinRadius = max(3, cellW * 0.06)
        var pins: [CGPoint] = []
        for row in 0...3 {
            for col in 1..<5 {
                let x = slotReels.minX + (cellW + reelSpacing) * CGFloat(col) - reelSpacing / 2
                pins.append(CGPoint(x: x, y: slotReels.minY + cellH * CGFloat(row) + (row == 0 ? slotPinRadius : row == 3 ? -slotPinRadius : 0)))
            }
        }
        slotPins = pins

        // 水果：7 等分内容宽度；判定宽度按 v9.5 比例（间距 40 对应 28 / 22）
        let lampW = contentW / 7
        let fruitY = bands[4].midY
        fruitLampWidth = lampW
        fruitCenters = (0..<7).map { CGPoint(x: left + lampW * (CGFloat($0) + 0.5), y: fruitY) }
        fruitHitHalfWidth = lampW * (28.0 / 40.0)
        fruitBaffleXs = (1..<7).map { left + lampW * CGFloat($0) }
        fruitBaffleHalfWidth = lampW * (22.0 / 40.0)
        fruitPinRadius = 4
        fruitPins = fruitBaffleXs.map { CGPoint(x: $0, y: bands[4].minY + bands[4].height * 0.2) }

        bonusSliderWidth = fruitLampWidth
        // 参考 App 的 BONUS 滑块约 ±16% 屏宽
        bonusSliderTravel = min(max(0, contentW / 2 - bonusSliderWidth / 2), size.width * GameConstants.bonusSliderTravelFraction)

        // 3D 推币台占满 pusher 区域；下落金币在区域顶部稍下方交接，3D 金币从上层台面落下
        bedEntryY = pusher.minY + pusher.height * 0.08
        fallScale = (bedEntryY - coinSpawnY) / GameLayout.legacyFallHeight
    }

    var centerX: CGFloat { (fieldMinX + fieldMaxX) / 2 }

    /// 自上而下的全部区域，用于检查是否越界、重叠
    var regions: [(name: String, frame: CGRect)] {
        [("jackpot", jackpot), ("sliderTrack", sliderTrack), ("slotMachine", slotMachine),
         ("dropField", dropField), ("fruitBar", fruitBar), ("bonusLane", bonusLane),
         ("pusher", pusher), ("dropButton", dropButton)]
    }

    func coinSliderCenter(offset: CGFloat) -> CGPoint {
        CGPoint(x: centerX + offset, y: sliderTrack.midY)
    }

    func bonusSliderCenter(offset: CGFloat) -> CGPoint {
        CGPoint(x: centerX + offset, y: bonusLane.midY)
    }

    /// 金币横坐标落在哪一个水果灯的列（0…6）；在内容区外返回 nil
    func fruitColumn(forX x: CGFloat) -> Int? {
        let left = fruitCenters[0].x - fruitLampWidth / 2
        let col = Int(floor((x - left) / fruitLampWidth))
        return (0..<fruitCenters.count).contains(col) ? col : nil
    }

    /// 屏幕横坐标 → 3D 推币台横向位置（-1 左 … 1 右）
    func pusherFraction(forX x: CGFloat) -> CGFloat {
        let half = max(1, (fieldMaxX - fieldMinX) / 2)
        return min(1, max(-1, (x - centerX) / half))
    }

    /// 金币是否正从 BONUS 滑块中间穿过
    func bonusContains(x: CGFloat, offset: CGFloat) -> Bool {
        abs(x - bonusSliderCenter(offset: offset).x) < bonusSliderWidth / 2
    }
}
