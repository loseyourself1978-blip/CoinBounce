import Foundation
import Combine
import CoreGraphics
import QuartzCore
import SwiftUI
import UIKit
import CoreHaptics

// MARK: - 老虎机符号类型 (V9.0)
enum SymbolType: String, CaseIterable {
    case wild, seven, bar, heart, diamond, star, nine, jack, king
    // v11.6 新增金色 / 贵重符号；bunny（兔女郎）是终极大奖符号
    case crown, coinPile, jokerBig, jokerSmall, bunny
}

// MARK: - 老虎机符号模型 (V9.0)
struct SlotSymbol: Identifiable {
    let id = UUID()
    let type: SymbolType
}

// MARK: - 2D金币物理体（V8.0 重构）
struct Active2DCoin: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var radius: CGFloat = 14
    /// 发光的特殊金币
    var isSpecial = false
    var hasBounced: [Int] = []
    var fruitTriggered = false
    var bonusTriggered = false
    var trailPositions: [(x: CGFloat, y: CGFloat)] = []
    var age: CGFloat = 0
}

// MARK: - 老虎机旋转状态
enum SlotSpinState: Equatable {
    case spinIdle
    case spinning
    case stopping(column: Int)
    case revealing
}

// MARK: - 中奖类型
enum WinType: Equatable {
    case none
    case smallWin(coins: Int)
    case bigWin(coins: Int)
    case jackpot
    case scatter
    case wild
}

// MARK: - 连击数据
struct ComboData {
    var count: Int = 0
    var lastHitTime: Date = Date()
    var isActive: Bool = false
    var message: String = ""

    mutating func hit(type: String) {
        let now = Date()
        if now.timeIntervalSince(lastHitTime) < 2.0 {
            count += 1
        } else {
            count = 1
        }
        lastHitTime = now
        isActive = count >= 2
        message = comboMessage()
    }

    mutating func reset() {
        count = 0
        isActive = false
        message = ""
    }

    private func comboMessage() -> String {
        switch count {
        case 2: return String(localized: "NICE! x2")
        case 3: return String(localized: "COMBO! x3")
        case 4: return String(localized: "HOT! x4")
        case 5: return String(localized: "FEVER! x5")
        case 6...9: return String(localized: "BLAZING! x\(count)")
        default: return String(localized: "MAX COMBO! x\(count)")
        }
    }
}

// MARK: - 飞金币特效
struct FloatingScore: Identifiable {
    let id = UUID()
    var text: String
    var x: CGFloat
    var y: CGFloat
    var opacity: Double = 1.0
    var scale: CGFloat = 1.0
    var color: Color = .arcadeGold
    /// 中奖用的大号飞字
    var big = false
}

// MARK: - GameState V8.0 - 超高性能物理驱动版
final class FloatingScoreBoard: ObservableObject {
    @Published var scores: [FloatingScore] = []
}

final class SliderMotion: ObservableObject {
    @Published var coin: CGFloat = 0
    @Published var bonus: CGFloat = 0
}

class GameState: ObservableObject {
    static let shared = GameState()

    // MARK: - 核心数值
    @Published var availableCoins: Int = GameConstants.initialCoins { didSet { scheduleSave() } }
    @Published var totalCoinsWon: Int = 0 { didSet { scheduleSave() } }
    /* v11.7：没有视图读它，不发布变化 */ var currentLevel: Int = 3

    // MARK: - 激励广告领币
    @Published var adRewardDay: String? = nil { didSet { scheduleSave() } }
    @Published var adRewardsClaimed: Int = 0 { didSet { scheduleSave() } }
    /// v11.8：顶部看广告按钮点过一次后不再闪烁
    @Published var adHintSeen = false { didSet { scheduleSave() } }
    /// 激励广告来源，测试里可替换
    var adPresenter: RewardedAdPresenting = AdsManager.shared

    // MARK: - 新手引导
    @Published var showTutorialArrow: Bool = true
    @Published var hasDroppedFirstCoin: Bool = false { didSet { scheduleSave() } }

    // MARK: - 滑块系统
    /// v11.5：两个滑块每帧都在动，放在单独的 SliderMotion 里发布——只有滑块那几个小视图跟着刷新，
    /// 整个游戏画面不再每帧重算一次（真机帧率）
    let sliders = SliderMotion()
    var coinSliderOffset: CGFloat = 0.0 { didSet { sliders.coin = coinSliderOffset } }
    /// 金币整枚穿过 BONUS 开口、启动老虎机的次数（验收：每次都对应一次完整穿过）
    private(set) var bonusTriggerCount = 0
    var bonusSliderOffset: CGFloat = 0.0 { didSet { sliders.bonus = bonusSliderOffset } }
    
    private var sliderTime: CGFloat = 0
    /// 滑块角速度（游戏时间，已除以 simulationSpeed），周期见 GameConstants
    private var coinSliderSpeed: Double { 2 * .pi / GameConstants.coinSliderPeriod / Double(GameConstants.simulationSpeed) }
    private var bonusSliderSpeed: Double { 2 * .pi / GameConstants.bonusSliderPeriod / Double(GameConstants.simulationSpeed) }

    // MARK: - 布局（物理坐标 = 屏幕坐标）
    /// 由 CoinPusherView 根据真实屏幕传入；之前使用参考尺寸
    private(set) var layout: GameLayout = .reference

    // MARK: - 水果系统
    @Published var fruitsLit: [Bool] = Array(repeating: false, count: 7) { didSet { scheduleSave() } }
    /* v11.7：没有视图读它，不发布变化 */ var litFruitIndex: Int? = nil
    /* v11.7：没有视图读它，不发布变化 */ var fruitBounceIndex: Int? = nil
    @Published var fruitPulseIndex: Int? = nil // V9.4: 命中的缩放效果
    
    // MARK: - 特效粒子 (Canvas 驱动)
    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var color: Color
        var life: CGFloat = 1.0
    }
    var particles: [Particle] = [] {
        didSet { let has = !particles.isEmpty; if has != hasParticles { hasParticles = has } }
    }
    /// v11.5：有粒子时才把全屏粒子画布放进画面（没有粒子时那层每帧在 CPU 上重画整屏，真机帧率的大头）
    @Published var hasParticles = false
    
    // MARK: - 2D 金币
    /// 等待下落区（SpriteKit）生成的金币；DropFieldScene 每帧取走
    var pendingDrops: [Active2DCoin] = []
    
    // MARK: - 老虎机
    @Published var slotSpinState: SlotSpinState = .spinIdle
    @Published var slotReels: [[SlotSymbol]] = [] // V9.0: 用于 SlotMachineView 的精美符号
    /* v11.7：没有视图读它，不发布变化 */ var slotValues: [Int] = (0..<15).map { _ in Int.random(in: 0...8) }
    /// 不是 @Published：没有视图读它，原来每帧（转动时一直在转）都让整个游戏画面重算（v11.7 真机连点掉帧）
    var slotScrollOffsets: [CGFloat] = Array(repeating: 0, count: 5)
    @Published var stoppedColumns: Set<Int> = []
    @Published var currentWin: WinType = .none
    /* v11.7：没有视图读它，不发布变化 */ var slotFlashColumns: Set<Int> = []

    var isSpinning: Bool { slotSpinState != .spinIdle }

    // MARK: - 特效
    @Published var combo: ComboData = ComboData()
    /* v11.7：没有视图读它，不发布变化 */ var showComboText: Bool = false
    /// v11.7：飞字放在自己的观察对象里，只有飞字层跟着刷新（每枚金币穿过水果 / 战斗都会加、淡出、删除各一次，
    /// 原来每次都让整个游戏画面重算）
    let floatingBoard = FloatingScoreBoard()
    var floatingScores: [FloatingScore] {
        get { floatingBoard.scores }
        set { floatingBoard.scores = newValue }
    }
    /* v11.7：没有视图读它，不发布变化 */ var baffleHitPositions: [(x: CGFloat, y: CGFloat, time: Date)] = []
    
    /// 累计从推币台掉落得分的金币数
    private(set) var bedDropCount = 0
    /// 下落区的金币到达推币台时调用：参数为横向位置（-1 左 … 1 右），由 3D 推币台生成金币
    /// 参数：金币在推币台视图内的位置（推币台区域左上角为原点）、是否特殊金币
    /// 下落金币交给 3D 推币台：推币台视图内的屏幕位置、屏幕速度（点/秒，向下为正）、是否特殊金币
    var onCoinToPusher: ((_ pointInPusher: CGPoint, _ screenVelocity: CGVector, _ isSpecial: Bool) -> Void)?
    /// 推币台判断这个屏幕位置的下落金币是否该交接了（3D 金币已经贴近表面）；没有推币台时按交接线判断
    var handoffReady: ((_ pointInPusher: CGPoint) -> Bool)?
    /// 每枚下落金币从投币口到交接的时长（秒），用于和参考 App 对比（验收日志和测试）
    var fallTimes: [TimeInterval] = []
    /// 投币时由 3D 推币机接手（v11.3：金币从投币口开始就是 3D 金币）
    var onDrop: ((Active2DCoin) -> Void)?
    /// 等待下落区生成的中奖金币雨（纯视觉）
    var pendingCoinRain = 0 {
        didSet { if pendingCoinRain > 0 && !coinRainShowing { coinRainShowing = true } }
    }
    /// v11.5：中奖金币雨（2D 精灵层）正在显示。没有金币雨时整个全屏 SpriteKit 层不放进画面，省一层全屏透明合成（真机帧率）
    @Published var coinRainShowing = false
    /// 生成特殊金币用的随机数（测试里可替换）
    var randomUnit: () -> Double = { Double.random(in: 0..<1) }

    // MARK: - 战斗区
    @Published var bossHealth: Double = 1
    /// 每次攻击 / 受击 / KO 加 1，视图据此播放动画
    @Published var warriorAttackCount = 0
    @Published var bossDefeatedCount = 0
    private var lastAttackTime: Date = .distantPast
    private var isNextDropRight: Bool = false

    // MARK: - 状态位
    @Published var showCardSelection: Bool = false
    @Published var offeredCards: [RewardCard] = []
    @Published var pickedCard: CardKind?
    // 卡牌效果
    /// 排队等待的老虎机转动次数（BONUS 连续命中、免费转动卡）
    @Published var queuedSpins = 0
    var specialCoinsLeft = 0
    var fastPusherUntil: Date?
    var wideMouthUntil: Date?
    @Published var pusherSpeedMultiplier: Double = 1
    @Published var wideMouthActive = false
    @Published var showJackpotExplosion: Bool = false

    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var comboResetTimer: Timer?

    // MARK: - 存档
    var saveStore = SaveStore()
    private var savePending = false



    private init() {
        saveStore.removeLegacySaves()
        applySave(saveStore.load() ?? .fresh)
        // 上次退出时水果已全亮但未选奖励：重新弹出选择
        if fruitsLit.allSatisfy({ $0 }) { presentCardPick() }
        initializeSlotReels()
        startDisplayLink()
    }
    
    // V9.0: 为自动化测试提供的重置接口
    func resetForTesting() {
        onDrop = nil          // 测试里投币进队列（App 宿主会把投币接到它自己的 3D 推币机上）
        layout = .reference
        offeredCards = []
        pickedCard = nil
        jackpotPool = GameConstants.jackpotSeed
        celebration = nil
        spinGeneration += 1
        slotSpinState = .spinIdle
        queuedSpins = 0
        dropQueue = 0
        dropCrowded = false
        pendingRewardDrops = 0
        rewardDropsReleased = 0
        lastReleaseWasPlayer = false
        specialCoinsLeft = 0
        fastPusherUntil = nil
        wideMouthUntil = nil
        pusherSpeedMultiplier = 1
        wideMouthActive = false
        lastAttackTime = .distantPast
        lastAdRewardAt = nil
        bossHealth = 1
        sliderTime = 0
        coinSliderOffset = 0
        bonusSliderOffset = 0
    }
    
    var currentSaveData: SaveData {
        SaveData(
            availableCoins: availableCoins,
            totalCoinsWon: totalCoinsWon,
            fruitsLit: fruitsLit,
            hasDroppedFirstCoin: hasDroppedFirstCoin,
            adRewardDay: adRewardDay,
            adRewardsClaimed: adRewardsClaimed,
            jackpotPool: jackpotPool,
            adHintSeen: adHintSeen,
            pendingRewardDrops: pendingRewardDrops
        )
    }

    func applySave(_ data: SaveData) {
        availableCoins = max(0, data.availableCoins)
        totalCoinsWon = max(0, data.totalCoinsWon)
        fruitsLit = data.fruitsLit.count == SaveData.fresh.fruitsLit.count ? data.fruitsLit : SaveData.fresh.fruitsLit
        hasDroppedFirstCoin = data.hasDroppedFirstCoin
        adRewardDay = data.adRewardDay
        adRewardsClaimed = max(0, data.adRewardsClaimed ?? 0)
        jackpotPool = max(GameConstants.jackpotSeed, data.jackpotPool ?? GameConstants.jackpotSeed)
        adHintSeen = data.adHintSeen ?? false
        pendingRewardDrops = max(0, data.pendingRewardDrops ?? 0)
        showTutorialArrow = !data.hasDroppedFirstCoin
    }

    func saveNow() {
        savePending = false
        saveStore.save(currentSaveData)
    }

    /// 同一帧内的多次数值变化合并成一次写入
    private func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.savePending else { return }
            self.saveNow()
        }
    }

    private func initializeSlotReels() {
        slotReels = (0..<5).map { _ in
            (0..<10).map { _ in SlotSymbol(type: SymbolType.allCases.randomElement()!) }
        }
    }

    /// 屏幕尺寸或安全区变化时由视图调用
    func updateLayout(_ newLayout: GameLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
    }

    func startDisplayLink() {
        // 只保留一个 display link，重复调用（如 onAppear）不会叠加物理步进
        guard displayLink == nil else { return }
        lastFrameTimestamp = nil
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let raw: CFTimeInterval
        if let last = lastFrameTimestamp {
            raw = link.timestamp - last
        } else {
            raw = link.targetTimestamp - link.timestamp
        }
        lastFrameTimestamp = link.timestamp
        advance(by: GameState.clampedFrameDelta(raw))
    }

    /// 按 simulationSpeed 推进真实时间 frameDelta，拆成不超过 1/60s 的子步，避免快速金币穿过格挡
    func advance(by frameDelta: CGFloat) {
        var remaining = frameDelta * GameConstants.simulationSpeed
        while remaining > 1e-6 {
            let dt = min(remaining, GameConstants.defaultFrameDelta)
            step(dt: dt)
            remaining -= dt
        }
    }

    /// 实际帧间隔 → 物理步长，上限 GameConstants.maxFrameDelta
    static func clampedFrameDelta(_ raw: CFTimeInterval) -> CGFloat {
        guard raw > 0 else { return GameConstants.defaultFrameDelta }
        return min(CGFloat(raw), GameConstants.maxFrameDelta)
    }

    /// 以 60Hz 固定步长推进一帧（供测试使用）
    func updateFrame() {
        step(dt: GameConstants.defaultFrameDelta)
    }

    // MARK: - 物理更新（V8.0: 空间网格优化防卡顿）
    func step(dt: CGFloat) {
        // === 滑块控制 ===
        sliderTime += dt
        updateCardEffects(now: Date())
        coinSliderOffset = layout.coinSliderTravel * CGFloat(sin(Double(sliderTime) * coinSliderSpeed))
        bonusSliderOffset = layout.bonusSliderTravel * CGFloat(sin(Double(sliderTime) * bonusSliderSpeed + .pi / 3))
        updateDropCrowded()
        releaseQueuedDrops(dt: dt)
        
        
        // === 2. 粒子物理组件 (V9.4) ===
        for i in (0..<particles.count).reversed() {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vy += 300 * dt // 粒子重力
            particles[i].life -= dt * 1.5
            if particles[i].life <= 0 {
                particles.remove(at: i)
            }
        }
        
        
        // === 3. 动画辅助 ===
        updateSlotAnimation(dt: dt)
    }

    private func updateSlotAnimation(dt: CGFloat) {
        let scrollSpeed: CGFloat = 280
        for i in 0..<5 {
            if !stoppedColumns.contains(i) {
                slotScrollOffsets[i] += scrollSpeed * dt
            }
        }
    }

    // MARK: - 行为接口
    var canDropCoin: Bool { availableCoins > 0 }

    // MARK: v11.6 COIN 倍数：点 COIN 牌在 1 → 2 → 5 → 10 之间切换，投币按钮一次投这么多枚（跟着滑块依次落下）
    static let coinMultipliers = [1, 2, 5, 10]
    @Published var coinMultiplier = 1
    func cycleCoinMultiplier() {
        let all = GameState.coinMultipliers
        let i = all.firstIndex(of: coinMultiplier) ?? 0
        coinMultiplier = all[(i + 1) % all.count]
        AudioManager.shared.play(.buttonTap)
    }
    /// 余额够不够这一次投币（按当前倍数）
    var canDropBatch: Bool { availableCoins - dropQueue >= coinMultiplier && dropQueue + coinMultiplier <= GameConstants.maxQueuedDrops }
    enum DropBatchResult { case queued, queueFull, insufficient }

    /// v11.7 投币队列：按当前倍数把金币放进队列（余额按队列预留），每隔 batchDropInterval 秒放出一枚、
    /// 同时在下落的金币不超过 maxCoinsInFlight 枚。队列满（maxQueuedDrops）时这次点击不投，不提示金币不足
    @discardableResult
    func dropBatch() -> DropBatchResult {
        let n = coinMultiplier
        guard availableCoins - dropQueue >= n else { return .insufficient }
        guard dropQueue + n <= GameConstants.maxQueuedDrops else { return .queueFull }
        if dropQueue == 0 { dropQueueClock = CGFloat(GameConstants.batchDropInterval); lastReleaseWasPlayer = false }   // 第一枚马上落下（奖励金币正在排队时也是玩家的先落）
        dropQueue += n
        releaseQueuedDrops(dt: 0)
        return .queued
    }
    /// 队列里还没放出的金币（已预留余额）
    @Published private(set) var dropQueue = 0
    private var dropQueueClock: CGFloat = 0
    /// 正在下落的金币数（3D 推币机接上后提供；测试里可以替换）
    var fallingCountProvider: (() -> Int)?
    /// v11.7：台面上（不算下落中）的金币数，由 3D 场景按计数器提供（不逐帧遍历）
    var tableCountProvider: (() -> Int)?
    /// 台面拥挤：放币间隔从 batchDropInterval 变成 crowdedDropInterval（带回差）
    private(set) var dropCrowded = false
    var currentDropInterval: Double { dropCrowded ? GameConstants.crowdedDropInterval : GameConstants.batchDropInterval }
    private func updateDropCrowded() {
        // 正在下落的金币（最多 maxCoinsInFlight 枚）马上也会落到台面上，一起算
        guard let table = tableCountProvider?() else { dropCrowded = false; return }
        let n = table + (fallingCountProvider?() ?? 0)
        if !dropCrowded, n >= GameConstants.crowdedThreshold { dropCrowded = true }
        else if dropCrowded, n < GameConstants.crowdedResume { dropCrowded = false }
    }

    /// v12.0：玩家投的金币和奖励金币共用一个放币时钟（间隔 currentDropInterval、同时下落不超过 maxCoinsInFlight），
    /// 两边都有时一枚一枚轮流。台面的进币速度和 v11.7 实测过帧率的「玩家连点」完全一样，奖励再大也不会一下子灌满
    private var lastReleaseWasPlayer = false
    private func releaseQueuedDrops(dt: CGFloat) {
        guard dropQueue > 0 || pendingRewardDrops > 0 else { dropQueueClock = 0; return }
        dropQueueClock += dt
        let interval = CGFloat(currentDropInterval)
        while (dropQueue > 0 || pendingRewardDrops > 0) && dropQueueClock >= interval {
            if let f = fallingCountProvider?(), f >= GameConstants.maxCoinsInFlight {
                dropQueueClock = interval   // 等位置时不攒时间，空出来后一枚一枚接着放
                return
            }
            dropQueueClock -= interval
            let playerTurn = dropQueue > 0 && (pendingRewardDrops == 0 || !lastReleaseWasPlayer)
            lastReleaseWasPlayer = playerTurn
            if playerTurn {
                dropQueue -= 1
                dropCoin()
            } else {
                releaseRewardCoin()
            }
        }
    }

    /// 重新显示首次投币引导（存档里记为未投过币）
    func resetTutorial() {
        hasDroppedFirstCoin = false
        showTutorialArrow = true
    }

    // MARK: v11.7 累积奖池
    /// 奖池（带小数：每枚 0.02）。只有 JACKPOT 牌的数字观察它（jackpotMeter），整个游戏画面不跟着重算
    private(set) var jackpotPool: Double = GameConstants.jackpotSeed {
        didSet { jackpotMeter.value = jackpotPool; scheduleSave() }
    }
    let jackpotMeter = JackpotMeter()

    func dropCoin(atX explicitX: CGFloat? = nil) {
        guard canDropCoin else { return }
        availableCoins -= 1
        econSpent += 1
        jackpotPool += GameConstants.jackpotContribution
        hasDroppedFirstCoin = true
        showTutorialArrow = false
        HapticManager.shared.coinDrop()
        AudioManager.shared.play(.coinDrop)

        let sideOffset: CGFloat = isNextDropRight ? 26 : -26
        isNextDropRight.toggle()
        let slider = layout.coinSliderCenter(offset: coinSliderOffset)
        let dropX = min(max(slider.x + sideOffset, layout.fieldMinX), layout.fieldMaxX)
        
        // 交给下落区（SpriteKit）生成金币：从 COIN 滑块中心落下
        var coin = Active2DCoin(
            x: dropX,
            y: layout.coinSpawnY,
            vx: CGFloat.random(in: -15...15),
            vy: CGFloat.random(in: 60...90) * layout.fallScale
        )
        if specialCoinsLeft > 0 {
            specialCoinsLeft -= 1
            coin.isSpecial = true
        } else {
            coin.isSpecial = randomUnit() < GameConstants.specialCoinChance
        }
        // v11.3：App 里由 3D 推币机直接生成下落金币；没有接上时（测试）放进队列
        if let onDrop { onDrop(coin) } else { pendingDrops.append(coin) }
    }

    // MARK: - 下落区事件（DropFieldScene 调用）

    /// 金币穿过水果灯排：按所在列点亮水果
    func coinCrossedFruitRow(x: CGFloat) {
        // 规则：金币从某个水果灯的中间穿过就点亮它；已亮的保持；7 个全亮后弹出卡牌，选完全部熄灭开始新一轮
        guard let column = layout.fruitColumn(forX: x),
              abs(x - layout.fruitCenters[column].x) <= layout.fruitLampWidth * GameConstants.fruitHitZoneFraction else { return }
        triggerFruitHit(index: column)
        combo.hit(type: "fruit")
        showComboText = combo.isActive
        resetComboTimer()
    }

    /// 金币穿过 BONUS 轨道：从滑块中间穿过时启动老虎机，返回是否命中
    @discardableResult
    /// v11.6：radius / gateX 来自 3D 场景越线那一帧（金币屏幕半径、BONUS 牌当时的位置）；不给就用标准金币和当前滑块位置
    func coinCrossedBonusLane(x: CGFloat, radius: CGFloat? = nil, gateX: CGFloat? = nil) -> Bool {
        let gx = gateX ?? layout.bonusSliderCenter(offset: bonusSliderOffset).x
        guard layout.bonusFullyInside(x: x, radius: radius ?? layout.coinRadius, gateX: gx) else { return false }
        bonusTriggerCount += 1
        NSLog("BONUS_TRIGGER x=%.1f r=%.1f gate=%.1f", x, radius ?? layout.coinRadius, gx)
        triggerBonusHit()
        return true
    }

    /// 金币碰到老虎机符号、SPIN 按钮或水果钉：只有声音和震动（真实物理下碰撞很频繁，不计入连击）
    func coinHitObstacle() {
        HapticManager.shared.baffleHit()
        AudioManager.shared.play(.baffleHit)
    }

    /// 下落金币是否该交给 3D 推币台
    func isReadyForHandoff(x: CGFloat, y: CGFloat) -> Bool {
        guard y >= layout.pusherView.minY else { return false }
        if y >= layout.dropButton.minY { return true }   // 保险：到底部面板之前一定交接
        guard let ready = handoffReady else { return y >= layout.bedEntryY }
        return ready(CGPoint(x: x - layout.pusherView.minX, y: y - layout.pusherView.minY))
    }

    /// 下落金币交给 3D 推币台：传入它当前的屏幕位置和速度，3D 金币在同一位置、同样大小出现并接着下落
    func coinReachedPusher(x: CGFloat, y: CGFloat? = nil, velocity: CGVector = .zero, isSpecial: Bool = false) {
        let clampedX = min(max(x, layout.fieldMinX), layout.fieldMaxX)
        let point = CGPoint(x: clampedX - layout.pusherView.minX, y: (y ?? layout.bedEntryY) - layout.pusherView.minY)
        onCoinToPusher?(point, velocity, isSpecial)
    }

    /// 3D 推币台上有金币从前沿掉落：计分（特殊金币奖励更多）
    func coinFellOffPusher(isSpecial: Bool = false) {
        bedDropCount += 1
        let reward = isSpecial ? GameConstants.specialCoinReward : GameConstants.bedDropReward
        // v12.0：掉下来的这一枚入账，特殊金币多出来的部分变成奖励金币从顶部落下
        addCoins(GameConstants.bedDropReward, source: .tray)
        payReward(reward - GameConstants.bedDropReward, source: .special)
        AudioManager.shared.play(.bedDrop)
        HapticManager.shared.coinFall()
        if isSpecial {
            addFloatingScore(text: "+\(reward)", x: layout.centerX, y: layout.pusher.maxY - 30, color: .yellow, big: true)
        }
    }

    /// 金币穿过战斗区：勇士攻击、BOSS 掉血；血量归零时 KO，1.2 秒后满血复活
    func coinCrossedBattle(now: Date = Date()) {
        guard now.timeIntervalSince(lastAttackTime) >= GameConstants.battleAttackCooldown, bossHealth > 0 else { return }
        lastAttackTime = now
        warriorAttackCount += 1
        bossHealth = max(0, bossHealth - GameConstants.bossDamagePerHit)
        if bossHealth <= 0.0001 { bossHealth = 0; bossKnockedOut() }   // 和勇士重击一样留一点余量：一次掉血很小时浮点误差不会留下一丝血
    }

    /// BOSS 被打倒：发奖，1.2 秒后满血复活
    private func bossKnockedOut() {
        bossDefeatedCount += 1
        payReward(GameConstants.bossKOReward, source: .boss)
        addFloatingScore(text: "K.O.! +\(GameConstants.bossKOReward)", x: layout.dropField.midX, y: layout.dropField.midY, color: .red, big: true)   // v11.7：居中（原来偏右，大屏上「+20」被屏幕边切掉）
        HapticManager.shared.bigWin()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            withAnimation(.easeOut(duration: 0.4)) { self?.bossHealth = 1 }
        }
    }

    /// v11.8 勇士重击卡：BOSS 立刻掉最大血量的 percent%（重击动画看 warriorStrikeCount），血量归零照常 K.O.
    @Published private(set) var warriorStrikeCount = 0
    private(set) var lastStrikePercent = 0
    func warriorStrike(percent: Int) {
        guard bossHealth > 0 else { return }
        lastStrikePercent = percent
        warriorStrikeCount += 1
        bossHealth = max(0, bossHealth - Double(percent) / 100)
        HapticManager.shared.bigWin()
        addFloatingScore(text: "-\(percent)%", x: layout.dropField.minX + layout.dropField.width * 0.8, y: layout.dropField.midY, color: .red, big: true)
        if bossHealth <= 0.0001 { bossHealth = 0; bossKnockedOut() }
    }

    /// 本地日期，用于每日次数重置
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 今天已领取的次数（跨日自动归零）
    func adRewardsUsed(on date: Date = Date()) -> Int {
        adRewardDay == GameState.dayKey(for: date) ? adRewardsClaimed : 0
    }

    /// v11.8：上次看完广告领币的时间（冷却用，不存档：重启 App 后冷却清零）
    var lastAdRewardAt: Date?

    /// 冷却还剩几秒（0 = 可以领）
    func adRewardCooldownRemaining(now: Date = Date()) -> TimeInterval {
        guard let last = lastAdRewardAt else { return 0 }
        return max(0, GameConstants.adRewardCooldown - now.timeIntervalSince(last))
    }

    /// 现在能不能看广告领币：有广告单元、今天还有次数、不在冷却中（不看余额）
    func canClaimAdReward(now: Date = Date()) -> Bool {
        adPresenter.adsEnabled
            && adRewardsUsed(on: now) < GameConstants.adRewardDailyLimit
            && adRewardCooldownRemaining(now: now) == 0
    }

    /// 金币快用完时，投币按钮旁边额外显示的大号领币按钮
    func canOfferAdReward(now: Date = Date()) -> Bool {
        canClaimAdReward(now: now) && availableCoins < GameConstants.adRewardCoinThreshold
    }

    /// 看广告领金币：播放激励广告，只有看完（SDK 发放奖励回调）才加金币
    func requestFreeCoins() {
        guard canClaimAdReward(), adPresenter.isAdReady else { return }
        adPresenter.showRewardedAd { [weak self] in
            self?.grantAdReward()
        }
    }

    /// 激励广告看完后的发奖；超过每日次数时不发
    @discardableResult
    func grantAdReward(now: Date = Date()) -> Bool {
        let used = adRewardsUsed(on: now)
        guard used < GameConstants.adRewardDailyLimit else { return false }
        adRewardDay = GameState.dayKey(for: now)
        adRewardsClaimed = used + 1
        lastAdRewardAt = now
        payReward(GameConstants.adRewardCoins, source: .ad)
        addFloatingScore(text: "+\(GameConstants.adRewardCoins)", x: layout.topRow.minX + layout.topRow.width * 0.2, y: layout.topRow.maxY + 12, color: .yellow, big: true)
        #if DEBUG
        NSLog("[Ads] granted %d coins, balance %d, today %d", GameConstants.adRewardCoins, availableCoins, adRewardsClaimed)
        #endif
        return true
    }

    // MARK: v12.0 奖励金币：所有金币奖励（老虎机、JACKPOT、卡片、BOSS K.O.、特殊金币、看广告）都变成真的 3D 金币从顶部落下，
    // 和玩家投的金币完全一样（格挡钉、水果灯、BONUS、BOSS），只有从推币台前沿掉进接币槽才入账。不花玩家的金币、不进奖池
    /// 等着落下的奖励金币（存档：退到后台、重启 App 后接着落，一枚不少）
    private(set) var pendingRewardDrops = 0 {
        didSet {
            guard pendingRewardDrops != oldValue else { return }
            rewardMeter.pending = pendingRewardDrops
            scheduleSave()
        }
    }
    /// 「+N」提示只观察它，整个游戏画面不跟着重算
    let rewardMeter = RewardMeter()
    /// 已放出的奖励金币（测试和统计用）
    private(set) var rewardDropsReleased = 0
    /// 3D 推币机接上后由它生成奖励金币
    var onRewardDrop: ((Active2DCoin) -> Void)?

    /// 派奖：total 枚全部排队，从顶部一枚一枚落下（见 releaseQueuedDrops）
    func payReward(_ total: Int, source: CoinSource = .slot) {
        guard total > 0 else { return }
        econAwarded[source, default: 0] += total
        pendingRewardDrops += total
    }

    /// 放出一枚奖励金币：从顶部随机位置落下
    private func releaseRewardCoin() {
        pendingRewardDrops -= 1
        rewardDropsReleased += 1
        let coin = Active2DCoin(x: CGFloat.random(in: layout.fieldMinX...layout.fieldMaxX), y: layout.coinSpawnY,
                                vx: CGFloat.random(in: -40...40), vy: CGFloat.random(in: 60...90) * layout.fallScale)
        onRewardDrop?(coin)
    }

    /// 收支来源（返还率统计用）
    enum CoinSource: String, CaseIterable { case tray, special, fruit, slot, jackpot, card, boss, ad, other }
    /// 累计投入（玩家投出的金币）和按来源的累计入账
    private(set) var econSpent = 0
    private(set) var econCredited: [CoinSource: Int] = [:]
    /// payReward 的名义派奖（全部变成真金币落到台面，最终经接币槽入账，记在 tray 里）
    private(set) var econAwarded: [CoinSource: Int] = [:]
    var econReturnRatio: Double { econSpent == 0 ? 0 : Double(econCredited.values.reduce(0, +)) / Double(econSpent) }
    func econSummary() -> String {
        "spent=\(econSpent) credited=\(econCredited.values.reduce(0, +)) ratio=\(String(format: "%.3f", econReturnRatio)) bonus=\(bonusTriggerCount) spins=\(spinsStarted) " +
        CoinSource.allCases.map { "\($0.rawValue)=\(econCredited[$0] ?? 0)" }.joined(separator: " ") +
        " awardedSlot=\(econAwarded[.slot] ?? 0) awardedJackpot=\(econAwarded[.jackpot] ?? 0) rewardReleased=\(rewardDropsReleased) pendingReward=\(pendingRewardDrops)"
    }

    func addCoins(_ amount: Int, source: CoinSource = .other) {
        availableCoins += amount
        totalCoinsWon += amount
        econCredited[source, default: 0] += amount
    }

    private func triggerFruitHit(index: Int) {
        guard index < fruitsLit.count else { return }
        // 规则（hj 2026-10-28 定）：金币从灯的中间（±35% 灯宽）穿过就点亮，没有随机
        if !fruitsLit[index] {
            fruitsLit[index] = true
            litFruitIndex = index
            fruitBounceIndex = index
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.litFruitIndex = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.fruitBounceIndex = nil }
            HapticManager.shared.fruitLit()
            AudioManager.shared.play(.fruitLit)
            if GameConstants.fruitHitReward > 0 {
                addFloatingScore(text: "+\(GameConstants.fruitHitReward)", x: layout.fruitCenters[index].x, y: layout.fruitBar.minY, color: .yellow)
                addCoins(GameConstants.fruitHitReward, source: .fruit)
            }
            if fruitsLit.allSatisfy({ $0 }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.presentCardPick() }
            }
        }
    }

    /// 金币穿过 BONUS：老虎机空闲时立即转，正在转时排队（停下后接着转）
    func triggerBonusHit() {
        HapticManager.shared.bonusTriggered()
        addFloatingScore(text: "BONUS!", x: layout.centerX, y: layout.bonusLane.minY, color: .orange)
        queueSpins(1)
    }

    /// 排入 n 次转动；空闲时马上开始第一次
    func queueSpins(_ n: Int) {
        queuedSpins += n
        startQueuedSpinIfIdle()
    }

    private func startQueuedSpinIfIdle() {
        guard queuedSpins > 0, slotSpinState == .spinIdle else { return }
        queuedSpins -= 1
        spinSlot()
    }

    private func resetComboTimer() {
        comboResetTimer?.invalidate()
        comboResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.combo.reset()
            self?.showComboText = false
        }
    }

    func addFloatingScore(text: String, x: CGFloat, y: CGFloat, color: Color, big: Bool = false) {
        let score = FloatingScore(text: text, x: x, y: y, color: color, big: big)
        floatingScores.append(score)
        let life: Double = big ? 1.4 : 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + (big ? 0.5 : 0.05)) {
            withAnimation(.easeOut(duration: life - 0.5 * (big ? 1 : 0))) {
                if let idx = self.floatingScores.firstIndex(where: { $0.id == score.id }) {
                    self.floatingScores[idx].opacity = 0
                    self.floatingScores[idx].y -= 50
                    self.floatingScores[idx].scale = 1.3
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + life + 0.05) {
            self.floatingScores.removeAll { $0.id == score.id }
        }
    }

    func spinSlotMachine() { spinSlot() }
    func triggerBonusSlot() { spinSlot() }
    
    /// v11.7：开始转动的次数、免费转动卡给的次数（测试：转动次数 = 整枚穿过 BONUS 的次数 + 免费转动）
    private(set) var spinsStarted = 0
    private(set) var freeSpinsGranted = 0
    /// 这一次是否快转（后面还有排队的转动时：先停 0.5 秒、每轴 0.12 秒，整次约 1.5 秒，排队不会越积越多）
    private(set) var spinIsTurbo = false
    /// 调试 / 测试：下一次转动必出中间一行 5 个兔女郎
    var forceUltimateJackpotNextSpin = false

    /// 每次转动的编号：resetForTesting 时加一，之前排好的停轴回调作废
    private var spinGeneration = 0
    /// 转轴停下、结算、接着转的定时（测试可以换成虚拟时钟，不受主线程卡顿影响）
    var spinScheduler: (Double, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func spinSlot() {
        guard slotSpinState == .spinIdle else { return }
        spinsStarted += 1
        let generation = spinGeneration
        spinIsTurbo = queuedSpins > 0
        slotSpinState = .spinning
        stoppedColumns.removeAll()
        slotFlashColumns.removeAll()
        currentWin = .none
        HapticManager.shared.slotStart()
        AudioManager.shared.play(.slotSpin)
        
        let symbolMap: [SymbolType] = SymbolType.allCases
        
        // 1. 生成 15 个物理格子结果 (5x3)：v11.6 按 slotWeights 抽；另有 1/1500 的机会直接出中间一行 5 个兔女郎（终极大奖）
        var results = (0..<15).map { _ in GameState.randomSymbolIndex(randomUnit()) }
        if forceUltimateJackpotNextSpin || randomUnit() < GameConstants.ultimateJackpotChance {
            forceUltimateJackpotNextSpin = false
            let bunny = SymbolType.allCases.firstIndex(of: .bunny)!
            for i in 5..<10 { results[i] = bunny }
        }
        for i in 0..<15 { slotValues[i] = results[i] }
        
        // 2. 将结果同步到 slotReels 中 (V9.0 核心：确保视觉与逻辑一致)
        for col in 0..<5 {
            var newReel: [SlotSymbol] = []
            // 前 3 个是我们想要停下的结果
            for row in 0..<3 {
                let symbolIdx = slotValues[col + row * 5]
                newReel.append(SlotSymbol(type: symbolMap[symbolIdx]))
            }
            // 补充 7 个随机符号平衡视觉
            for _ in 0..<7 {
                newReel.append(SlotSymbol(type: symbolMap.randomElement()!))
            }
            slotReels[col] = newReel
        }
        
        // 3. 驱动各轴停止（快转时更快）
        let firstStop = spinIsTurbo ? 0.5 : 1.2, step = spinIsTurbo ? 0.12 : 0.4
        let settle = spinIsTurbo ? 0.25 : 0.5, gap = spinIsTurbo ? 0.25 : 0.9
        for col in 0..<5 {
            spinScheduler(firstStop + Double(col) * step) { [weak self] in
                guard let self = self, self.spinGeneration == generation else { return }
                self.slotSpinState = .stopping(column: col) // 使用带 column 的枚举触发视图特定轴停止
                self.stoppedColumns.insert(col)
                self.slotScrollOffsets[col] = 0
                HapticManager.shared.slotStop()
                AudioManager.shared.play(.slotStop)
                if col == 4 { 
                    self.spinScheduler(settle) {
                        guard self.spinGeneration == generation else { return }
                        self.evaluateWin()
                        self.slotSpinState = .spinIdle
                        // 排队的转动（BONUS 连续命中、免费转动卡）稍等后接着转
                        if self.queuedSpins > 0 {
                            self.spinScheduler(gap) { self.startQueuedSpinIfIdle() }
                        }

                        // 中奖线显示 2.5 秒后熄灭
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            if self.slotSpinState == .spinIdle { self.currentWin = .none }
                        } 
                    } 
                }
            }
        }
    }

    /// v11.6 每个符号的出现概率（合计 1）；兔女郎（终极大奖符号）最少见
    static let slotWeights: [(SymbolType, Double)] = [
        (.wild, 0.03), (.seven, 0.10), (.bar, 0.12), (.heart, 0.12), (.diamond, 0.11), (.star, 0.10), (.nine, 0.10),
        (.jack, 0.08), (.king, 0.07), (.crown, 0.05), (.coinPile, 0.05), (.jokerBig, 0.025), (.jokerSmall, 0.025), (.bunny, 0.02)
    ]
    /// u ∈ [0, 1) → 符号在 SymbolType.allCases 里的下标
    static func randomSymbolIndex(_ u: Double) -> Int {
        var acc = 0.0
        for (type, w) in slotWeights {
            acc += w
            if u < acc { return SymbolType.allCases.firstIndex(of: type)! }
        }
        return SymbolType.allCases.firstIndex(of: slotWeights.last!.0)!
    }

    func evaluateWin() {
        let middleRow = [slotValues[5], slotValues[6], slotValues[7], slotValues[8], slotValues[9]]
        let bunny = SymbolType.allCases.firstIndex(of: .bunny)!
        // 终极大奖：中间一行 5 个都是兔女郎（百搭不算）
        if middleRow.allSatisfy({ $0 == bunny }) { ultimateJackpot() }
        else if middleRow.allSatisfy({ $0 == middleRow[0] || $0 == 0 }) { slotJackpot() }
        else if checkFourMatch(row: middleRow) { slotBigWin() }
        else if checkThreeMatch(row: middleRow) { slotSmallWin() }
    }

    private func spawnParticles(count: Int, x: CGFloat, y: CGFloat, colors: [Color]) {
        for _ in 0..<count {
            let p = Particle(
                x: x, y: y,
                vx: CGFloat.random(in: -300...300),
                vy: CGFloat.random(in: -500...0),
                color: colors.randomElement()!
            )
            particles.append(p)
        }
    }

    /// v11.8：和真老虎机一样从最左边一轴开始连：前 4 个相同（百搭可代替）= BIG WIN
    private func checkFourMatch(row: [Int]) -> Bool {
        let c = Array(row[0..<4])
        let b = c.first(where: { $0 != 0 }) ?? 0
        return c.allSatisfy { $0 == b || $0 == 0 }
    }

    /// v11.8：前 3 个相同（从最左边开始）= 小奖（原来任意连续 3 个都算，中奖太频繁、奖金又小）
    private func checkThreeMatch(row: [Int]) -> Bool {
        let c = Array(row[0..<3])
        let b = c.first(where: { $0 != 0 }) ?? 0
        return c.allSatisfy { $0 == b || $0 == 0 }
    }

    /// v11.6 终极大奖：派出顶部 JACKPOT 奖池全部金币，满屏金币雨和粒子
    private func ultimateJackpot() {
        currentWin = .jackpot; slotFlashColumns = [0,1,2,3,4]; showJackpotExplosion = true
        ultimateJackpotCount += 1
        HapticManager.shared.jackpot(); AudioManager.shared.play(.jackpot)
        // v11.7：派出整个累积奖池（取整），奖池回到起始值
        let pay = Int(jackpotPool.rounded(.down))
        lastJackpotPayout = pay
        jackpotExplosionAmount = pay
        jackpotPool = GameConstants.jackpotSeed
        payReward(pay, source: .jackpot)
        // 金额由 JACKPOT 爆炸画面显示（v11.7 去掉重复的飘字，两行 JACKPOT 叠在一起看不清）
        celebrate(jackpot: true)
        spawnParticles(count: 200, x: layout.slotMachine.midX, y: layout.slotMachine.midY, colors: [.yellow, Color(red: 1.0, green: 0.84, blue: 0.0), .pink, .white])
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { self.showJackpotExplosion = false; self.slotFlashColumns.removeAll() }
    }
    // MARK: v11.7 大奖庆祝：兔女郎从一侧闪现，随机做一个动作（欢呼 / 拍手 / 飞吻 / 跳），约 2.6 秒，不挡操作
    struct BunnyCelebration: Identifiable, Equatable {
        let id = UUID()
        let pose: BunnyPose
        let fromLeft: Bool
        let jackpot: Bool
    }
    @Published private(set) var celebration: BunnyCelebration?
    /// 庆祝次数（测试用）
    private(set) var celebrationCount = 0

    /// 大奖（≥ bigWinCelebrationThreshold 金币）和 JACKPOT 时调用
    func celebrate(jackpot: Bool) {
        let pose = BunnyPose.celebrationPoses[Int(randomUnit() * Double(BunnyPose.celebrationPoses.count)) % BunnyPose.celebrationPoses.count]
        let c = BunnyCelebration(pose: pose, fromLeft: randomUnit() < 0.5, jackpot: jackpot)
        celebration = c
        celebrationCount += 1
        AudioManager.shared.play(.cheer)
        AudioManager.shared.play(jackpot ? .jackpotFanfare : .applause)
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConstants.celebrationSeconds) { [weak self] in
            if self?.celebration?.id == c.id { self?.celebration = nil }
        }
    }

    /// JACKPOT 爆炸画面上显示的金额（老虎机 JACKPOT 500；兔女郎终极大奖是派出的整个奖池）
    private(set) var jackpotExplosionAmount = GameConstants.slotJackpotReward
    /// 上一次终极大奖派出的金币（测试和庆祝动画用）
    private(set) var lastJackpotPayout = 0
    /// 终极大奖次数（测试和统计用）
    private(set) var ultimateJackpotCount = 0

    private func slotJackpot() {
        jackpotExplosionAmount = GameConstants.slotJackpotReward
        currentWin = .jackpot; slotFlashColumns = [0,1,2,3,4]; showJackpotExplosion = true
        HapticManager.shared.jackpot(); AudioManager.shared.play(.jackpot); payReward(GameConstants.slotJackpotReward, source: .jackpot)
        celebrate(jackpot: true)
        // V9.4 Particle Explosion
        spawnParticles(count: 100, x: layout.slotMachine.midX, y: layout.slotMachine.midY, colors: [.yellow, Color(red: 1.0, green: 0.84, blue: 0.0), .red])
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.showJackpotExplosion = false; self.slotFlashColumns.removeAll() }
    }

    private func slotBigWin() {
        currentWin = .bigWin(coins: GameConstants.slotBigWinReward); slotFlashColumns = [0,1,2,3,4]
        HapticManager.shared.bigWin(); AudioManager.shared.play(.winBig); payReward(GameConstants.slotBigWinReward); addFloatingScore(text: "+\(GameConstants.slotBigWinReward)", x: layout.slotMachine.midX, y: layout.slotMachine.maxY, color: .orange, big: true)
        if GameConstants.slotBigWinReward >= GameConstants.bigWinCelebrationThreshold { celebrate(jackpot: false) }
        // V9.4 Particle Explosion
        spawnParticles(count: 50, x: layout.slotMachine.midX, y: layout.slotMachine.midY, colors: [.orange, .yellow, .white])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.slotFlashColumns.removeAll() }
    }

    private func slotSmallWin() {
        currentWin = .smallWin(coins: GameConstants.slotSmallWinReward); HapticManager.shared.smallWin(); AudioManager.shared.play(.winSmall)
        payReward(GameConstants.slotSmallWinReward); addFloatingScore(text: "+\(GameConstants.slotSmallWinReward)", x: layout.slotMachine.midX, y: layout.slotMachine.maxY, color: .green, big: true)
    }

    // MARK: - 卡牌三选一

    /// 7 水果全亮：三张卡背面朝上展示（金币 / 免费转 / 勇士重击，顺序和金额随机）
    func presentCardPick() {
        guard !showCardSelection else { return }
        offeredCards = CardPool.draw(random: randomUnit)
        pickedCard = nil
        showCardSelection = true
    }

    /// 选中一张卡：立即生效，水果重置；界面把三张一起翻开展示后调用 finishCardPick() 关闭
    func pickCard(_ kind: CardKind, now: Date = Date()) {
        guard showCardSelection, pickedCard == nil, let card = offeredCards.first(where: { $0.kind == kind }) else { return }
        pickedCard = kind
        fruitsLit = SaveData.fresh.fruitsLit
        switch kind {
        case .coins:
            payReward(card.amount, source: .card)
            addFloatingScore(text: "+\(card.amount)", x: layout.centerX, y: layout.slotMachine.maxY, color: .yellow, big: true)
        case .freeSpins:
            // 免费转：排队自动转，不用穿过 BONUS，照常派奖
            freeSpinsGranted += card.amount
            queueSpins(card.amount)
        case .warriorStrike:
            warriorStrike(percent: card.amount)
        }
        AudioManager.shared.play(.winSmall)
    }

    func finishCardPick(schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }) {
        showCardSelection = false
        offeredCards = []
        pickedCard = nil
        // v11.7：选卡后翻牌展示的 1.9 秒里，快速投币可能又把 7 个水果全点亮——那时弹卡被「已在显示」挡掉，
        // 之后再没有新的水果点亮去触发，水果灯就一直全亮。关闭时再检查一次
        if fruitsLit.allSatisfy({ $0 }) {
            schedule(0.4) { [weak self] in
                guard let self, !self.showCardSelection, self.fruitsLit.allSatisfy({ $0 }) else { return }
                self.presentCardPick()
            }
        }
    }

    /// 计时效果到期检查（每帧调用）
    func updateCardEffects(now: Date) {
        let fast = (fastPusherUntil ?? .distantPast) > now
        let speed = fast ? 1.6 : 1   // v11.8 起没有加速卡，保留计时接口
        if pusherSpeedMultiplier != speed { pusherSpeedMultiplier = speed }
        let wide = (wideMouthUntil ?? .distantPast) > now
        if wideMouthActive != wide { wideMouthActive = wide }
    }
    
    func lightUpFruit(at index: Int) {
        guard index >= 0 && index < fruitsLit.count else { return }
        fruitsLit[index] = true
        fruitPulseIndex = index
        HapticManager.shared.fruitLit()
        checkAllFruitsLit()
        
        // 0.5秒后重置缩放效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.fruitPulseIndex == index { self.fruitPulseIndex = nil }
        }
    }
    
    #if DEBUG
    /// 商店截图用：把奖池设成一个玩得久的玩家能看到的值
    func debugSetJackpotPool(_ value: Double) { jackpotPool = value }
    #endif

    func checkAllFruitsLit() {
        if fruitsLit.allSatisfy({ $0 }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.presentCardPick(); HapticManager.shared.allFruitsLit() }
        }
    }

}

/// v11.7：奖池数字单独的观察对象（只让 JACKPOT 牌的数字刷新）
final class JackpotMeter: ObservableObject {
    @Published var value: Double = GameConstants.jackpotSeed
}

/// v12.0：还没落下的奖励金币数（顶部「+N」提示用）
final class RewardMeter: ObservableObject {
    @Published var pending = 0
}

// MARK: - 颜色扩展
extension Color {
    static let arcadeGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let panelPink = Color(red: 1.0, green: 0.4, blue: 0.6)
    static let panelBlue = Color(red: 0.3, green: 0.6, blue: 1.0)
}
