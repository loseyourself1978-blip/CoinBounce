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
    var hasBounced: [Int] = []
    var fruitTriggered = false
    var bonusTriggered = false
    var trailPositions: [(x: CGFloat, y: CGFloat)] = []
    var age: CGFloat = 0
}

// MARK: - 推币床金币 (V8.0: 支持 Z 轴叠加)
struct PusherCoin: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat = 0      // Z 轴高度 (叠放)
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var scale: CGFloat = 1.0
    var radius: CGFloat = 14
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
        case 2: return "NICE! x2"
        case 3: return "COMBO! x3 🔥"
        case 4: return "HOT! x4 🔥🔥"
        case 5: return "FEVER! x5 ⚡"
        case 6...9: return "BLAZING! x\(count) 💥"
        default: return "MAX COMBO! x\(count) 🌟"
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
}

// MARK: - GameState V8.0 - 超高性能物理驱动版
class GameState: ObservableObject {
    static let shared = GameState()

    // MARK: - 核心数值
    @Published var availableCoins: Int = GameConstants.initialCoins { didSet { scheduleSave() } }
    @Published var totalCoinsWon: Int = 0 { didSet { scheduleSave() } }
    @Published var currentLevel: Int = 3

    // MARK: - 激励广告领币
    @Published var adRewardDay: String? = nil { didSet { scheduleSave() } }
    @Published var adRewardsClaimed: Int = 0 { didSet { scheduleSave() } }
    /// 激励广告来源，测试里可替换
    var adPresenter: RewardedAdPresenting = AdsManager.shared

    // MARK: - 新手引导
    @Published var showTutorialArrow: Bool = true
    @Published var hasDroppedFirstCoin: Bool = false { didSet { scheduleSave() } }

    // MARK: - 滑块系统
    @Published var coinSliderOffset: CGFloat = 0.0
    @Published var bonusSliderOffset: CGFloat = 0.0
    
    private var sliderTime: CGFloat = 0
    private let coinSliderSpeed: Double = 1.0
    private let bonusSliderSpeed: Double = 1.2

    // MARK: - 布局（物理坐标 = 屏幕坐标）
    /// 由 CoinPusherView 根据真实屏幕传入；之前使用参考尺寸
    private(set) var layout: GameLayout = .reference

    // MARK: - 水果系统
    @Published var fruitsLit: [Bool] = Array(repeating: false, count: 7) { didSet { scheduleSave() } }
    @Published var litFruitIndex: Int? = nil
    @Published var fruitBounceIndex: Int? = nil
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
    var particles: [Particle] = []
    
    // MARK: - 2D 金币
    // V9.0: 移除 @Published 以优化 60fps 渲染 (TimelineView 驱动)
    var active2DCoins: [Active2DCoin] = []
    
    // MARK: - 老虎机
    @Published var slotSpinState: SlotSpinState = .spinIdle
    @Published var slotReels: [[SlotSymbol]] = [] // V9.0: 用于 SlotMachineView 的精美符号
    @Published var slotValues: [Int] = (0..<15).map { _ in Int.random(in: 0...8) }
    @Published var slotScrollOffsets: [CGFloat] = Array(repeating: 0, count: 5)
    @Published var stoppedColumns: Set<Int> = []
    @Published var currentWin: WinType = .none
    @Published var slotFlashColumns: Set<Int> = []

    var isSpinning: Bool { slotSpinState != .spinIdle }

    // MARK: - 特效
    @Published var combo: ComboData = ComboData()
    @Published var showComboText: Bool = false
    @Published var floatingScores: [FloatingScore] = []
    @Published var baffleHitPositions: [(x: CGFloat, y: CGFloat, time: Date)] = []
    
    // 推币床金币池
    // V9.0: 移除 @Published 以优化 60fps
    var bedCoins: [PusherCoin] = []
    /// 累计从推币台掉落得分的金币数
    private(set) var bedDropCount = 0
    private var bedIsUntouchedPrefill = false
    private var isNextDropRight: Bool = false

    // MARK: - 状态位
    @Published var showCardSelection: Bool = false
    @Published var showRewardModal: Bool = false
    @Published var rewardAmount: Int = 0
    @Published var showJackpotExplosion: Bool = false
    @Published var pusherOffset: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var comboResetTimer: Timer?

    // MARK: - 存档
    var saveStore = SaveStore()
    private var savePending = false

    // MARK: - 物理常量（纵向数值按 layout.fallScale / bedScale 换算）
    private let gravityBase: CGFloat = 920.0


    private init() {
        applySave(saveStore.load() ?? .fresh)
        // 上次退出时水果已全亮但未选奖励：重新弹出选择
        if fruitsLit.allSatisfy({ $0 }) { showCardSelection = true }
        initializeSlotReels()
        prefillBed()
        startDisplayLink()
    }
    
    // V9.0: 为自动化测试提供的重置接口
    func resetForTesting() {
        layout = .reference
        sliderTime = 0
        pusherOffset = 0
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
            adRewardsClaimed: adRewardsClaimed
        )
    }

    func applySave(_ data: SaveData) {
        availableCoins = max(0, data.availableCoins)
        totalCoinsWon = max(0, data.totalCoinsWon)
        fruitsLit = data.fruitsLit.count == SaveData.fresh.fruitsLit.count ? data.fruitsLit : SaveData.fresh.fruitsLit
        hasDroppedFirstCoin = data.hasDroppedFirstCoin
        adRewardDay = data.adRewardDay
        adRewardsClaimed = max(0, data.adRewardsClaimed ?? 0)
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
        let old = layout
        layout = newLayout
        // 已在场上的金币夹回新边界内
        for i in active2DCoins.indices {
            active2DCoins[i].x = min(max(active2DCoins[i].x, layout.fieldMinX), layout.fieldMaxX)
        }
        // 预铺后还没有金币落上去：按新布局重新预铺；否则按比例换算到新推币台
        if bedIsUntouchedPrefill {
            prefillBed()
            return
        }
        for i in bedCoins.indices {
            let fx = (bedCoins[i].x - old.bedMinX) / max(1, old.bedMaxX - old.bedMinX)
            let fy = (bedCoins[i].y - old.bedTopY) / max(1, old.bedDropY - old.bedTopY)
            bedCoins[i].x = min(max(layout.bedMinX + fx * (layout.bedMaxX - layout.bedMinX), layout.bedMinX), layout.bedMaxX)
            bedCoins[i].y = min(layout.bedTopY + fy * (layout.bedDropY - layout.bedTopY), layout.bedDropY - 1)
        }
    }

    /// 开局在推币台上预铺一层金币（六边形密排，从掉落线往回铺），数量和位置见 GameConstants
    func prefillBed() {
        bedCoins = GameState.prefillPositions(for: layout).map { PusherCoin(x: $0.x, y: $0.y) }
        bedIsUntouchedPrefill = true
    }

    static func prefillPositions(for L: GameLayout) -> [CGPoint] {
        let d = L.coinRadius * 2 + 0.5
        let rowStep = d * 0.866   // 六边形密排的排距
        let frontY = L.bedDropY - GameConstants.prefillEdgeGap * d
        // 最后一排与推板最远处之间至少留出 prefillBackGap 个金币直径
        let backLimit = L.pusherFrontRestY + L.pusherStroke + L.coinRadius + GameConstants.prefillBackGap * d
        guard frontY > backLimit else { return [] }
        // 排数取整后均匀分布：最前排贴着掉落线，最后一排贴着推板最远处，各尺寸屏幕一致
        let rows = min(GameConstants.prefillMaxRows, Int(floor((frontY - backLimit) / (rowStep * GameConstants.prefillRowLooseness))) + 1)
        let step = rows > 1 ? (frontY - backLimit) / CGFloat(rows - 1) : 0
        var points: [CGPoint] = []
        for row in 0..<rows {
            let y = frontY - CGFloat(row) * step
            let offset = row % 2 == 0 ? 0 : d / 2
            var x = L.bedMinX + offset
            while x <= L.bedMaxX + 0.001 {
                points.append(CGPoint(x: x, y: y))
                x += d
            }
        }
        return points
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
        coinSliderOffset = layout.coinSliderTravel * CGFloat(sin(Double(sliderTime) * coinSliderSpeed))
        bonusSliderOffset = layout.bonusSliderTravel * CGFloat(sin(Double(sliderTime) * bonusSliderSpeed + .pi / 3))
        
        // 推子正弦运动（0…pusherStroke）
        let lastPusherOffset = pusherOffset
        pusherOffset = (CGFloat(sin(Double(sliderTime) * 2.32)) + 1.0) * layout.pusherStroke / 2
        let pusherVelocity = (pusherOffset - lastPusherOffset) / dt
        
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
        
        // === 3. 2D 掉落金币物理 ===
        let L = layout
        let gravity = gravityBase * L.fallScale
        let friction2D: CGFloat = 0.992

        for i in 0..<active2DCoins.count {
            active2DCoins[i].age = min(1.0, active2DCoins[i].age + dt * 4)
            active2DCoins[i].vy += gravity * dt
            active2DCoins[i].y  += active2DCoins[i].vy * dt
            active2DCoins[i].x  += active2DCoins[i].vx * dt
            active2DCoins[i].vx *= friction2D

            // 轨迹
            if Int(active2DCoins[i].age * 60) % 4 == 0 {
                active2DCoins[i].trailPositions.append((x: active2DCoins[i].x, y: active2DCoins[i].y))
                if active2DCoins[i].trailPositions.count > 5 {
                    active2DCoins[i].trailPositions.removeFirst()
                }
            }

            let coin = active2DCoins[i]

            // 边界
            if coin.x < L.fieldMinX {
                active2DCoins[i].x = L.fieldMinX
                active2DCoins[i].vx = abs(active2DCoins[i].vx) * 0.65
            } else if coin.x > L.fieldMaxX {
                active2DCoins[i].x = L.fieldMaxX
                active2DCoins[i].vx = -abs(active2DCoins[i].vx) * 0.65
            }

            // 推币台前缘挤压
            let squeezeY = L.bedEntryY - 40 * L.fallScale
            if coin.y > squeezeY {
                active2DCoins[i].vy += pusherOffset / L.bedScale * 0.1 * L.fallScale
                for j in 0..<active2DCoins.count {
                    if i != j && active2DCoins[j].y > squeezeY {
                        let dx = active2DCoins[i].x - active2DCoins[j].x
                        let dy = active2DCoins[i].y - active2DCoins[j].y
                        let distSq = dx*dx + dy*dy
                        if distSq < 784 { // 28^2
                            let force: CGFloat = 15.0
                            active2DCoins[i].vx += dx > 0 ? force : -force
                            active2DCoins[i].vy += dy > 0 ? force : -force
                        }
                    }
                }
            }

            // 交互格挡
            for (row, pegs) in L.pegRows.enumerated() {
                handleBaffle(i: i, pegs: pegs, idOffset: row * 4)
            }

            // 水果行区域判定
            if coin.y > L.fruitBar.minY && coin.y < L.fruitBar.maxY {
                for (baffleIdx, baffleX) in L.fruitBaffleXs.enumerated() {
                    let dx = coin.x - baffleX
                    if abs(dx) < L.fruitBaffleHalfWidth && !coin.hasBounced.contains(baffleIdx + 20) {
                        active2DCoins[i].vx += dx > 0 ? 90 : -90
                        active2DCoins[i].vy *= 0.7
                        active2DCoins[i].hasBounced.append(baffleIdx + 20)
                        HapticManager.shared.baffleHit()
                        AudioManager.shared.play(.baffleHit)
                        break
                    }
                }
                
                if !coin.fruitTriggered {
                    for (idx, fruit) in L.fruitCenters.enumerated() {
                        let dx = coin.x - fruit.x
                        if abs(dx) < L.fruitHitHalfWidth {
                            active2DCoins[i].fruitTriggered = true
                            triggerFruitHit(index: idx)
                            combo.hit(type: "fruit")
                            showComboText = combo.isActive
                            resetComboTimer()
                            break
                        }
                    }
                }
            }

            // BONUS 滑块命中：金币穿过 BONUS 轨道时落在滑块范围内
            if !coin.bonusTriggered && coin.y > L.bonusLane.minY && coin.y < L.bonusLane.maxY
                && abs(coin.x - L.bonusSliderCenter(offset: bonusSliderOffset).x) < L.bonusSliderWidth / 2 {
                active2DCoins[i].bonusTriggered = true
                triggerBonusHit()
            }

            // 转移到推币床
            if coin.y > L.bedEntryY {
                active2DCoins[i].y = .infinity
                spawnBedCoin(x: coin.x)
            }
        }
        active2DCoins.removeAll { $0.y > L.bedEntryY }

        // === 2. 推币床物理核心 (空间网格 + 真实骑跨 + 波浪推动) ===
        updatePusherBedPhysics(dt: dt, pusherVelocity: pusherVelocity)
        
        // === 3. 动画辅助 ===
        updateSlotAnimation(dt: dt)
    }

    private func updatePusherBedPhysics(dt: CGFloat, pusherVelocity: CGFloat) {
        let L = layout
        let friction: CGFloat = 0.93 // 增加摩擦力，增加“厚重感”
        let pusherLimitY = L.pusherFrontRestY + pusherOffset // 推板前沿
        let cellW: CGFloat = 32
        var grid: [String: [Int]] = [:]
        
        // 1. 基础位移 & 填充网格
        for i in 0..<bedCoins.count {
            // 波浪推动 (Wave-style push)
            if bedCoins[i].y - bedCoins[i].radius < pusherLimitY && pusherVelocity > 0 {
                bedCoins[i].vy = max(bedCoins[i].vy, pusherVelocity * 0.9)
                bedCoins[i].vx += CGFloat.random(in: -10...10)
            }
            
            bedCoins[i].x += bedCoins[i].vx * dt
            bedCoins[i].y += bedCoins[i].vy * dt
            bedCoins[i].vx *= friction
            bedCoins[i].vy *= friction
            
            let gx = Int(floor(bedCoins[i].x / cellW))
            let gy = Int(floor(bedCoins[i].y / cellW))
            grid["\(gx),\(gy)", default: []].append(i)
        }
        
        // 2. 空间局部碰撞 (带有骑跨逻辑)；位置分离迭代多次，推力能传到金币堆前排
        for pass in 0..<GameConstants.bedSolverPasses {
        for i in 0..<bedCoins.count {
            let gx = Int(floor(bedCoins[i].x / cellW))
            let gy = Int(floor(bedCoins[i].y / cellW))
            
            for ox in -1...1 {
                for oy in -1...1 {
                    let key = "\(gx+ox),\(gy+oy)"
                    guard let neighbors = grid[key] else { continue }
                    for j in neighbors {
                        if i >= j { continue }
                        let dx = bedCoins[i].x - bedCoins[j].x
                        let dy = bedCoins[i].y - bedCoins[j].y
                        let distSq = dx*dx + dy*dy
                        let dMin: CGFloat = 28
                        
                        if distSq < dMin * dMin {
                            let dist = sqrt(distSq)
                            let overlap = dMin - dist
                            
                            // 骑跨逻辑 (Climbing)
                            if pass == 0 && overlap > 3 {
                                if bedCoins[i].y < bedCoins[j].y {
                                    bedCoins[i].z = min(18, bedCoins[i].z + overlap * 0.5)
                                } else {
                                    bedCoins[j].z = min(18, bedCoins[j].z + overlap * 0.5)
                                }
                            }
                            
                            // 挤压力 (受 Z 轴差影响)
                            let zDiff = abs(bedCoins[i].z - bedCoins[j].z)
                            let forceScale: CGFloat = zDiff > 10 ? 0.2 : 1.0
                            let force = (overlap / dMin) * 45.0 * forceScale
                            let angle = atan2(dy, dx)
                            
                            if pass == 0 {
                                bedCoins[i].vx += cos(angle) * force
                                bedCoins[i].vy += sin(angle) * force
                                bedCoins[j].vx -= cos(angle) * force
                                bedCoins[j].vy -= sin(angle) * force
                            }

                            // 位置分离：重叠的金币各退一半，推板的推力才能沿着金币堆传下去
                            let separation = overlap * 0.5 * forceScale
                            bedCoins[i].x += cos(angle) * separation
                            bedCoins[i].y += sin(angle) * separation
                            bedCoins[j].x -= cos(angle) * separation
                            bedCoins[j].y -= sin(angle) * separation
                        }
                    }
                }
            }
            // Z 轴平稳回落 (增加重力感)
            if pass == 0 { bedCoins[i].z = max(0, bedCoins[i].z - 6.0 * dt) }
        }
        }
        
        // 3. 约束与掉落
        for i in 0..<bedCoins.count {
            if bedCoins[i].x < L.bedMinX || bedCoins[i].x > L.bedMaxX {
                bedCoins[i].x = min(max(bedCoins[i].x, L.bedMinX), L.bedMaxX)
                bedCoins[i].vx *= -0.3
            }
            // 不会被推回推板后面
            if bedCoins[i].y - bedCoins[i].radius < pusherLimitY {
                bedCoins[i].y = pusherLimitY + bedCoins[i].radius
            }
        }
        
        let dropped = bedCoins.filter { $0.y > L.bedDropY }
        if !dropped.isEmpty {
            bedDropCount += dropped.count
            AudioManager.shared.play(.bedDrop)
            addCoins(dropped.count * GameConstants.bedDropReward)
            bedCoins.removeAll { $0.y > L.bedDropY }
        }

        if bedCoins.count > 120 { bedCoins.removeFirst(bedCoins.count - 120) }
    }

    private func handleBaffle(i: Int, pegs: [CGPoint], idOffset: Int) {
        let coin = active2DCoins[i]
        guard let pegY = pegs.first?.y, abs(coin.y - pegY) < 15 else { return }
        
        for (idx, peg) in pegs.enumerated() {
            let uniqueId = idOffset + idx
            let bx = peg.x
            if !coin.hasBounced.contains(uniqueId) {
                let dx = coin.x - bx
                if abs(dx) < (coin.radius + layout.pegRadius + 4) {
                    active2DCoins[i].vx += dx > 0 ? 110 : -110
                    active2DCoins[i].vy *= -0.3
                    active2DCoins[i].hasBounced.append(uniqueId)
                    HapticManager.shared.baffleHit()
                    AudioManager.shared.play(.baffleHit)
                    baffleHitPositions.append((x: bx, y: coin.y, time: Date()))
                    combo.hit(type: "baffle")
                    showComboText = combo.isActive
                    resetComboTimer()
                }
            }
        }
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

    func dropCoin(atX explicitX: CGFloat? = nil) {
        guard canDropCoin else { return }
        availableCoins -= 1
        hasDroppedFirstCoin = true
        showTutorialArrow = false
        HapticManager.shared.coinDrop()
        AudioManager.shared.play(.coinDrop)

        let sideOffset: CGFloat = isNextDropRight ? 26 : -26
        isNextDropRight.toggle()
        let slider = layout.coinSliderCenter(offset: coinSliderOffset)
        let dropX = min(max(slider.x + sideOffset, layout.fieldMinX), layout.fieldMaxX)
        
        let newCoin = Active2DCoin(
            x: dropX,
            y: layout.coinSpawnY, // 从 COIN 滑块中心落下
            vx: CGFloat.random(in: -3...3),
            vy: CGFloat.random(in: 120...180) * layout.fallScale
        )
        active2DCoins.append(newCoin)
    }

    private func spawnBedCoin(x: CGFloat) {
        bedIsUntouchedPrefill = false
        let newCoin = PusherCoin(
            x: min(max(x, layout.bedMinX), layout.bedMaxX),
            y: layout.bedEntryY,
            vx: CGFloat.random(in: -10...10),
            vy: 50 * layout.bedScale
        )
        bedCoins.append(newCoin)
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

    /// 是否显示「看广告领金币」：金币低于阈值且今天还有次数
    func canOfferAdReward(now: Date = Date()) -> Bool {
        availableCoins < GameConstants.adRewardCoinThreshold
            && adRewardsUsed(on: now) < GameConstants.adRewardDailyLimit
    }

    /// 金币不足时的补币入口：播放激励广告，只有看完（SDK 发放奖励回调）才加金币
    func requestFreeCoins() {
        guard canOfferAdReward(), adPresenter.isAdReady else { return }
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
        addCoins(GameConstants.adRewardCoins)
        #if DEBUG
        NSLog("[Ads] granted %d coins, balance %d, today %d", GameConstants.adRewardCoins, availableCoins, adRewardsClaimed)
        #endif
        return true
    }

    func addCoins(_ amount: Int) {
        availableCoins += amount
        totalCoinsWon += amount
    }

    private func triggerFruitHit(index: Int) {
        guard index < fruitsLit.count else { return }
        if !fruitsLit[index] {
            fruitsLit[index] = true
            litFruitIndex = index
            fruitBounceIndex = index
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.litFruitIndex = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.fruitBounceIndex = nil }
            HapticManager.shared.fruitLit()
            AudioManager.shared.play(.fruitLit)
            addFloatingScore(text: "+\(GameConstants.fruitHitReward)", x: layout.fruitCenters[index].x, y: layout.fruitBar.minY, color: .yellow)
            addCoins(GameConstants.fruitHitReward)
            if fruitsLit.allSatisfy({ $0 }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showCardSelection = true }
            }
        }
    }

    func triggerBonusHit() {
        // 老虎机正在转时忽略
        guard !isSpinning else { return }
        HapticManager.shared.bonusTriggered()
        addFloatingScore(text: "BONUS!", x: layout.centerX, y: layout.bonusLane.minY, color: .orange)
        spinSlot()
    }

    private func resetComboTimer() {
        comboResetTimer?.invalidate()
        comboResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.combo.reset()
            self?.showComboText = false
        }
    }

    func addFloatingScore(text: String, x: CGFloat, y: CGFloat, color: Color) {
        let score = FloatingScore(text: text, x: x, y: y, color: color)
        floatingScores.append(score)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.8)) {
                if let idx = self.floatingScores.firstIndex(where: { $0.id == score.id }) {
                    self.floatingScores[idx].opacity = 0
                    self.floatingScores[idx].y -= 50
                    self.floatingScores[idx].scale = 1.3
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            self.floatingScores.removeAll { $0.id == score.id }
        }
    }

    func spinSlotMachine() { spinSlot() }
    func triggerBonusSlot() { spinSlot() }
    
    func spinSlot() {
        guard slotSpinState == .spinIdle else { return }
        slotSpinState = .spinning
        stoppedColumns.removeAll()
        slotFlashColumns.removeAll()
        currentWin = .none
        HapticManager.shared.slotStart()
        AudioManager.shared.play(.slotSpin)
        
        let symbolMap: [SymbolType] = SymbolType.allCases
        
        // 1. 生成 15 个物理格子结果 (5x3)
        let results = (0..<15).map { _ in 
            let r = Double.random(in: 0...1)
            if r < 0.03 { return 0 } else if r < 0.15 { return 1 }
            else if r < 0.30 { return 2 } else if r < 0.45 { return 3 }
            else if r < 0.58 { return 4 } else if r < 0.70 { return 5 }
            else if r < 0.82 { return 6 } else if r < 0.92 { return 7 }
            else { return 8 }
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
        
        // 3. 驱动各轴停止
        for col in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + Double(col) * 0.4) { [weak self] in
                guard let self = self else { return }
                self.slotSpinState = .stopping(column: col) // 使用带 column 的枚举触发视图特定轴停止
                self.stoppedColumns.insert(col)
                self.slotScrollOffsets[col] = 0
                HapticManager.shared.slotStop()
                AudioManager.shared.play(.slotStop)
                if col == 4 { 
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { 
                        self.evaluateWin()
                        self.slotSpinState = .spinIdle 
                    } 
                }
            }
        }
    }

    private func evaluateWin() {
        let middleRow = [slotValues[5], slotValues[6], slotValues[7], slotValues[8], slotValues[9]]
        if middleRow.allSatisfy({ $0 == middleRow[0] || $0 == 0 }) { slotJackpot() }
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

    private func checkFourMatch(row: [Int]) -> Bool {
        for skip in 0..<5 {
            var c = row; c.remove(at: skip)
            let b = c[0] == 0 ? c[1] : c[0]
            if c.allSatisfy({ $0 == b || $0 == 0 }) { return true }
        }
        return false
    }

    private func checkThreeMatch(row: [Int]) -> Bool {
        for s in 0...2 {
            let sl = Array(row[s..<s+3])
            let b = sl[0] == 0 ? sl[1] : sl[0]
            if sl.allSatisfy({ $0 == b || $0 == 0 }) { return true }
        }
        return false
    }

    private func slotJackpot() {
        currentWin = .jackpot; slotFlashColumns = [0,1,2,3,4]; showJackpotExplosion = true
        HapticManager.shared.jackpot(); AudioManager.shared.play(.jackpot); addCoins(GameConstants.slotJackpotReward); addFloatingScore(text: "+\(GameConstants.slotJackpotReward)", x: layout.slotMachine.midX, y: layout.slotMachine.maxY, color: .yellow)
        // V9.4 Particle Explosion
        spawnParticles(count: 100, x: layout.slotMachine.midX, y: layout.slotMachine.midY, colors: [.yellow, Color(red: 1.0, green: 0.84, blue: 0.0), .red])
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.showJackpotExplosion = false; self.slotFlashColumns.removeAll() }
    }

    private func slotBigWin() {
        currentWin = .bigWin(coins: GameConstants.slotBigWinReward); slotFlashColumns = [0,1,2,3,4]
        HapticManager.shared.bigWin(); AudioManager.shared.play(.winBig); addCoins(GameConstants.slotBigWinReward); addFloatingScore(text: "+\(GameConstants.slotBigWinReward)", x: layout.slotMachine.midX, y: layout.slotMachine.maxY, color: .orange)
        // V9.4 Particle Explosion
        spawnParticles(count: 50, x: layout.slotMachine.midX, y: layout.slotMachine.midY, colors: [.orange, .yellow, .white])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.slotFlashColumns.removeAll() }
    }

    private func slotSmallWin() {
        currentWin = .smallWin(coins: GameConstants.slotSmallWinReward); HapticManager.shared.smallWin(); AudioManager.shared.play(.winSmall)
        addCoins(GameConstants.slotSmallWinReward); addFloatingScore(text: "+\(GameConstants.slotSmallWinReward)", x: layout.slotMachine.midX, y: layout.slotMachine.maxY, color: .green)
    }

    func selectCardReward(_ choice: CardReward) {
        guard showCardSelection else { return }
        showCardSelection = false
        // 选完重置水果，「水果」奖励在新一轮开局直接点亮若干个
        fruitsLit = SaveData.fresh.fruitsLit
        rewardAmount = choice == .coins ? GameConstants.cardCoinsReward : 0
        showRewardModal = true
        if choice == .coins { addCoins(GameConstants.cardCoinsReward) }
        else {
            var un = fruitsLit.enumerated().filter({ !$0.element }).map({ $0.offset })
            if un.count >= GameConstants.cardFruitsToLight {
                un.shuffle()
                for idx in un.prefix(GameConstants.cardFruitsToLight) { fruitsLit[idx] = true }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.showRewardModal = false }
    }

    enum CardReward { case coins, fruits }
    
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
    
    func checkAllFruitsLit() {
        if fruitsLit.allSatisfy({ $0 }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showCardSelection = true; HapticManager.shared.allFruitsLit() }
        }
    }

}

// MARK: - 颜色扩展
extension Color {
    static let arcadeGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let panelPink = Color(red: 1.0, green: 0.4, blue: 0.6)
    static let panelBlue = Color(red: 0.3, green: 0.6, blue: 1.0)
}
