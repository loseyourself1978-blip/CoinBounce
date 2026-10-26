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

    // MARK: 老虎机内部
    let slotReels: CGRect
    let spinButton: CGRect

    // MARK: 物理关键位置
    let coinRadius: CGFloat
    let coinSpawnY: CGFloat
    let coinSliderWidth: CGFloat
    let coinSliderTravel: CGFloat      // COIN 滑块偏离中心的最大距离
    let fieldMinX: CGFloat             // 下落金币的左右边界（金币中心）
    let fieldMaxX: CGFloat
    let pegRadius: CGFloat
    let pegRows: [[CGPoint]]           // 战斗区格挡，3 行（3/4/3 个）
    let fruitCenters: [CGPoint]        // 7 个水果
    let fruitLampWidth: CGFloat
    let fruitHitHalfWidth: CGFloat
    let fruitBaffleXs: [CGFloat]       // 水果之间的格挡
    let fruitBaffleHalfWidth: CGFloat
    let bonusSliderWidth: CGFloat
    let bonusSliderTravel: CGFloat
    let bedEntryY: CGFloat             // 下落金币越过这条线后进入推币台
    let bedTopY: CGFloat
    let bedDropY: CGFloat              // 推币台金币越过这条线即掉落得分
    let bedMinX: CGFloat
    let bedMaxX: CGFloat
    let pusherFrontRestY: CGFloat      // 推板前沿（静止）
    let pusherStroke: CGFloat          // 推板行程
    /// 当前布局与 v9.5 物理（下落 380 单位、推币床 215 单位）的纵向比例，
    /// 用来换算重力、初速度等纵向数值，使不同屏幕上的下落时长一致
    let fallScale: CGFloat
    let bedScale: CGFloat

    static let margin: CGFloat = 10
    /// v9.5 物理的下落高度（-360 → 20）和推币床长度
    static let legacyFallHeight: CGFloat = 380
    static let legacyBedLength: CGFloat = 215

    /// 各区域占安全区内高度的比例，合计 1
    static let heightRatios: [CGFloat] = [0.075, 0.155, 0.045, 0.165, 0.080, 0.045, 0.325, 0.110]

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
        slotMachine = bands[1].insetBy(dx: m, dy: 0)
        sliderTrack = bands[2]
        dropField = bands[3].insetBy(dx: m, dy: 0)
        fruitBar = bands[4]
        bonusLane = bands[5]
        pusher = bands[6]
        dropButton = bands[7]

        // 老虎机：SPIN 按钮放在转轴右侧，不遮挡转轴
        let slotInner = slotMachine.insetBy(dx: 8, dy: 8)
        let spinD = min(slotInner.height * 0.75, 64)
        spinButton = CGRect(x: slotInner.maxX - spinD, y: slotInner.midY - spinD / 2, width: spinD, height: spinD)
        slotReels = CGRect(x: slotInner.minX, y: slotInner.minY,
                           width: max(0, spinButton.minX - 6 - slotInner.minX), height: slotInner.height)

        coinRadius = 14
        coinSpawnY = sliderTrack.midY
        coinSliderWidth = max(44, contentW * 0.14)
        coinSliderTravel = max(0, contentW / 2 - coinSliderWidth / 2)
        fieldMinX = left + coinRadius
        fieldMaxX = right - coinRadius

        // 战斗区格挡：放在两侧人物之间（人物中心约在 13% / 87% 宽度），
        // 纵向放在 30%、55%、80% 高度，避开顶部的 VS / 连击文字
        pegRadius = 6
        let pegStep = contentW * 0.15
        let field = bands[3]
        let rowYs = [0.30, 0.55, 0.80].map { field.minY + field.height * $0 }
        pegRows = [
            [-1, 0, 1].map { CGPoint(x: centerX + pegStep * $0, y: rowYs[0]) },
            [-1.5, -0.5, 0.5, 1.5].map { CGPoint(x: centerX + pegStep * $0, y: rowYs[1]) },
            [-1, 0, 1].map { CGPoint(x: centerX + pegStep * $0, y: rowYs[2]) }
        ]

        // 水果：7 等分内容宽度；判定宽度按 v9.5 比例（间距 40 对应 28 / 22）
        let lampW = contentW / 7
        let fruitY = bands[4].midY
        fruitLampWidth = lampW
        fruitCenters = (0..<7).map { CGPoint(x: left + lampW * (CGFloat($0) + 0.5), y: fruitY) }
        fruitHitHalfWidth = lampW * (28.0 / 40.0)
        fruitBaffleXs = (1..<7).map { left + lampW * CGFloat($0) }
        fruitBaffleHalfWidth = lampW * (22.0 / 40.0)

        bonusSliderWidth = fruitLampWidth
        bonusSliderTravel = max(0, contentW / 2 - bonusSliderWidth / 2)

        // 推币台：沿用 v9.5 推币床的比例（推板前沿 40、行程 27、落币点 75，全长 215）
        bedTopY = pusher.minY
        bedScale = pusher.height / GameLayout.legacyBedLength
        pusherFrontRestY = bedTopY + 40 * bedScale
        pusherStroke = 27 * bedScale
        bedEntryY = bedTopY + 75 * bedScale
        // 前沿留出比一枚金币更高的掉落口，最前排金币探出台面时口子仍然可见
        bedDropY = pusher.maxY - (coinRadius * 2 + 8)
        let bedHalfW = size.width * 0.91 / 2
        bedMinX = size.width / 2 - bedHalfW + coinRadius
        bedMaxX = size.width / 2 + bedHalfW - coinRadius

        fallScale = (bedEntryY - coinSpawnY) / GameLayout.legacyFallHeight
    }

    var centerX: CGFloat { (fieldMinX + fieldMaxX) / 2 }

    /// 自上而下的全部区域，用于检查是否越界、重叠
    var regions: [(name: String, frame: CGRect)] {
        [("jackpot", jackpot), ("slotMachine", slotMachine), ("sliderTrack", sliderTrack),
         ("dropField", dropField), ("fruitBar", fruitBar), ("bonusLane", bonusLane),
         ("pusher", pusher), ("dropButton", dropButton)]
    }

    func coinSliderCenter(offset: CGFloat) -> CGPoint {
        CGPoint(x: centerX + offset, y: sliderTrack.midY)
    }

    func bonusSliderCenter(offset: CGFloat) -> CGPoint {
        CGPoint(x: centerX + offset, y: bonusLane.midY)
    }
}
