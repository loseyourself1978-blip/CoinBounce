import CoreGraphics
import SwiftUI

// MARK: - 游戏布局
// 唯一的布局来源：只根据屏幕尺寸和安全区计算。
// 坐标系 = 整屏坐标（点，原点在屏幕左上角）。视图摆放各区域、GameState 计算物理都用这一套坐标，
// 不再有单独的「物理坐标」。
struct GameLayout: Equatable {
    let size: CGSize
    let safeArea: EdgeInsets
    /// 左右机柜立柱宽度
    let sideMargin: CGFloat

    // MARK: 区域（自上而下，互不重叠）
    let jackpot: CGRect
    let topRow: CGRect          // 金币余额（左）、帮助 / 设置（右）
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
    let coinPlateY: CGFloat            // COIN 牌中心 y（参考 585 像素）
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
    let bonusSliderWidth: CGFloat      // BONUS 牌外宽 = 开口 + 两根立柱
    let bonusOpeningWidth: CGFloat     // v11.6：两根立柱之间的开口（金币整枚穿过才触发老虎机）
    let bonusPostWidth: CGFloat        // v11.6：牌两侧的立柱（有碰撞体，随牌移动）
    let bonusSliderTravel: CGFloat
    let bedEntryY: CGFloat             // 下落金币越过这条线后交给 3D 推币台（推币台区域顶部附近）
    /// 当前布局与 v9.5 物理（下落 380 单位、推币床 215 单位）的纵向比例，
    /// 用来换算重力、初速度等纵向数值，使不同屏幕上的下落时长一致
    let fallScale: CGFloat

    static let margin: CGFloat = 10
    /// v11.1：机柜两侧木质立柱（带灯泡）各占屏宽 10%，下落区、老虎机、水果排都在立柱之间（参考 App 实测 10%～90%）
    static let sideMarginFraction: CGFloat = 0.10
    /// 金币直径占屏宽的比例（v11.0 的内容宽度 7.8% 换算到整屏宽，约 7.4%；下落和台面上同样大小）
    static let coinDiameterFraction: CGFloat = 0.074
    /// v9.5 物理的下落高度（-360 → 20）和推币床长度
    static let legacyFallHeight: CGFloat = 380

    /// v11.4：各区域按新参考录屏（60fps，1206×2622，隐藏状态栏）逐像素测量，用整屏比例（ReferenceBoxes.bands）：
    /// JACKPOT 0–250 像素、金币 / 按钮一行 330–460、投币口 460–787、老虎机 787–1280（转轴 820–1250）、战斗区 1280–1542、
    /// 水果 1542–1691、BONUS 1691–1809、推币台 1809–2370（台面前沿约 85.5%）、底部金色面板 2370 到底。
    /// 不再按安全区换算：参考画面从屏幕最顶端开始（JACKPOT 牌在灵动岛后面），可点的一行在安全区内
    /// 台面前沿在推币台区域（视图顶部 → 底部面板）中的位置比例：iPhone 17 上约 85.5% 屏高（参考接币盘前沿约 85–86%）
    static let pusherFrontFraction: CGFloat = 0.766

    /// iPhone 16/17 级别竖屏，GameState 在视图传入真实布局前使用
    static let reference = GameLayout(
        size: CGSize(width: 393, height: 852),
        safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    )

    init(size: CGSize, safeArea: EdgeInsets) {
        self.size = size
        self.safeArea = safeArea

        let m = max(GameLayout.margin, (size.width * GameLayout.sideMarginFraction).rounded())
        sideMargin = m
        let left = safeArea.leading + m
        let right = size.width - safeArea.trailing - m
        let contentW = max(0, right - left)
        let centerX = (left + right) / 2
        let usableH = max(0, size.height - safeArea.top - safeArea.bottom)

        _ = usableH
        func px(_ x: CGFloat) -> CGFloat { ReferenceBoxes.x(x, size) }
        let bands = ReferenceBoxes.bands.map { r in
            CGRect(x: 0, y: ReferenceBoxes.y(r.lowerBound, size), width: size.width, height: ReferenceBoxes.y(r.upperBound - r.lowerBound, size))
        }
        jackpot = CGRect(x: px(ReferenceBoxes.jackpotPanel.minX), y: bands[0].minY, width: px(ReferenceBoxes.jackpotPanel.width), height: bands[0].height)
        topRow = CGRect(x: px(ReferenceBoxes.balancePill.minX), y: bands[1].minY,
                        width: px(ReferenceBoxes.topButtonsMaxX - ReferenceBoxes.balancePill.minX), height: bands[1].height)
        sliderTrack = bands[2]
        slotMachine = CGRect(x: px(ReferenceBoxes.slotCabinetX.lowerBound), y: bands[3].minY,
                             width: px(ReferenceBoxes.slotCabinetX.upperBound - ReferenceBoxes.slotCabinetX.lowerBound), height: bands[3].height)
        dropField = CGRect(x: px(ReferenceBoxes.battle.minX), y: bands[4].minY, width: px(ReferenceBoxes.battle.width), height: bands[4].height)
        fruitBar = bands[5]
        bonusLane = bands[6]
        pusher = bands[7]
        dropButton = bands[8]
        pusherView = CGRect(x: 0, y: bands[7].minY, width: size.width, height: size.height - bands[7].minY)

        // 老虎机：没有 SPIN 按钮（只由 BONUS 触发），5 列转轴按参考转轴窗口（190–1030 × 820–1250 像素）
        slotReels = ReferenceBoxes.rect(ReferenceBoxes.slotReels, size)

        // 金币直径为内容宽度的 7.8%（v10.8 的 6% 加大 30%，下落和台面上的金币同样大小），随屏幕宽度缩放
        coinRadius = (size.width * GameLayout.coinDiameterFraction / 2).rounded()
        coinSpawnY = ReferenceBoxes.y(ReferenceBoxes.coinExitY, size)
        coinPlateY = ReferenceBoxes.y(ReferenceBoxes.coinPlateY, size)
        coinSliderWidth = px(ReferenceBoxes.coinPlate.width)
        // 参考 App 的 COIN 滑块只在中间约 ±17% 屏宽内往复
        coinSliderTravel = min(max(0, contentW / 2 - coinSliderWidth / 2), size.width * GameConstants.coinSliderTravelFraction)
        fieldMinX = left + coinRadius
        fieldMaxX = right - coinRadius

        // v11.6 格挡钉（参考逐帧测量，交错排列，最大限度改变金币轨迹）：A 排 3 根、B 排 4 根、C 排 3 根、D 排 4 根（贴墙的不放）
        let pegR = px(ReferenceBoxes.pegRadius)
        slotObstacleRadius = pegR
        let reels = slotReels, slotBottom = slotMachine.maxY, battle = dropField
        let colW = reels.width / 5
        var pegs: [CGPoint] = []
        for i in 1...3 { pegs.append(CGPoint(x: reels.minX + colW * (CGFloat(i) + 0.5), y: reels.minY - pegR * 1.6)) }     // A：上沿、中间三列上方
        // 两端紧贴下落区侧墙的钉子不放：钉子和墙之间的缝比金币窄，金币会架在上面停住
        for j in 1...4 { pegs.append(CGPoint(x: reels.minX + colW * CGFloat(j), y: reels.midY)) }                         // B：转轴中线、分隔线上
        // C：老虎机下沿、中间三列正下方（最外两列下面的钉子和侧墙之间物理上比金币窄，会卡住金币，不放）
        for i in 1...3 { pegs.append(CGPoint(x: reels.minX + colW * (CGFloat(i) + 0.5), y: (slotBottom + battle.minY) / 2 - pegR * 0.5)) }
        let battleW = battle.width / 5
        for j in 1...4 { pegs.append(CGPoint(x: battle.minX + battleW * CGFloat(j), y: battle.minY + battle.height * 0.55)) }  // D：战斗区
        slotObstacles = pegs
        slotPinRadius = pegR
        slotPins = []

        // 水果：7 等分内容宽度；判定宽度按 v9.5 比例（间距 40 对应 28 / 22）
        let lampW = contentW / 7
        let fruitY = fruitBar.midY
        fruitLampWidth = lampW
        fruitCenters = (0..<7).map { CGPoint(x: left + lampW * (CGFloat($0) + 0.5), y: fruitY) }
        fruitHitHalfWidth = lampW * (28.0 / 40.0)
        fruitBaffleXs = (1..<7).map { left + lampW * CGFloat($0) }
        fruitBaffleHalfWidth = lampW * (22.0 / 40.0)
        // v11.6：水果灯之间每个间隔（含两端）一根格挡钉，在水果灯高度居中
        fruitPinRadius = pegR
        let pinY = fruitBar.midY
        var posts: [CGPoint] = []
        for k in 1...6 { posts.append(CGPoint(x: left + lampW * CGFloat(k), y: pinY)) }
        fruitPins = posts

        bonusOpeningWidth = coinRadius * 2 * GameConstants.bonusOpeningToCoinDiameter
        bonusPostWidth = coinRadius * 2 * GameConstants.bonusPostToCoinDiameter
        bonusSliderWidth = bonusOpeningWidth + 2 * bonusPostWidth
        // 参考 App 的 BONUS 滑块约 ±16% 屏宽
        bonusSliderTravel = min(max(0, contentW / 2 - bonusSliderWidth / 2), size.width * GameConstants.bonusSliderTravelFraction)

        // 3D 推币台占满 pusher 区域；下落金币在区域顶部稍下方交接，3D 金币从上层台面落下
        bedEntryY = pusher.minY + pusher.height * 0.08
        fallScale = (bedEntryY - coinSpawnY) / GameLayout.legacyFallHeight
    }

    var centerX: CGFloat { (fieldMinX + fieldMaxX) / 2 }
    /// 台面前沿（金币掉落处）的屏幕 y：前沿到底部面板之间留出看得见的掉落空间
    var pusherFrontY: CGFloat { pusherView.minY + (dropButton.minY - pusherView.minY) * GameLayout.pusherFrontFraction }

    /// 自上而下的全部区域，用于检查是否越界、重叠
    var regions: [(name: String, frame: CGRect)] {
        [("jackpot", jackpot), ("topRow", topRow), ("sliderTrack", sliderTrack), ("slotMachine", slotMachine),
         ("dropField", dropField), ("fruitBar", fruitBar), ("bonusLane", bonusLane),
         ("pusher", pusher), ("dropButton", dropButton)]
    }

    func coinSliderCenter(offset: CGFloat) -> CGPoint {
        CGPoint(x: centerX + offset, y: coinPlateY)
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

    /// 金币是否正从 BONUS 滑块中间穿过（按标准金币半径）
    func bonusContains(x: CGFloat, offset: CGFloat) -> Bool {
        bonusFullyInside(x: x, radius: coinRadius, gateX: bonusSliderCenter(offset: offset).x)
    }

    /// v11.6 触发规则：整枚金币（整个直径，不只是圆心）都在两根立柱之间的开口里
    func bonusFullyInside(x: CGFloat, radius: CGFloat, gateX: CGFloat) -> Bool {
        abs(x - gateX) + radius <= bonusOpeningWidth / 2 + 0.001
    }

    /// 金币是否骑在立柱上（金币横跨的范围和某一根立柱重叠超过 tolerance 点）：一半在里一半在外
    func bonusStraddlesPost(x: CGFloat, radius: CGFloat, gateX: CGFloat, tolerance: CGFloat = 1) -> Bool {
        let d = abs(x - gateX), inner = bonusOpeningWidth / 2, outer = inner + bonusPostWidth
        return d + radius > inner + tolerance && d - radius < outer - tolerance
    }
}
