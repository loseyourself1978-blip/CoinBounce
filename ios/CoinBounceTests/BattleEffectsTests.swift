import XCTest
@testable import CoinBounce

// ============================================================
// MARK: - 战斗区、特殊金币、中奖金币雨
// ============================================================

final class BattleEffectsTests: XCTestCase {
    var state: GameState!
    private var originalRandom: (() -> Double)!

    override func setUp() {
        super.setUp()
        state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "BattleEffectsTests")!, key: "BattleEffectsTests.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.availableCoins = 100
        state.pendingDrops.removeAll()
        state.pendingCoinRain = 0
        state.bossHealth = 1
        originalRandom = state.randomUnit
    }

    override func tearDown() {
        state.randomUnit = originalRandom
        state.onCoinToPusher = nil
        state.bossHealth = 1
        state.pendingCoinRain = 0
        state.clearRewardQueueForTesting()
        super.tearDown()
    }

    // MARK: 特殊金币
    func test_dropCoin_specialWhenRandomBelowChance() {
        state.randomUnit = { 0 }
        state.dropCoin()
        XCTAssertTrue(state.pendingDrops.last!.isSpecial)
        state.randomUnit = { 0.99 }
        state.dropCoin()
        XCTAssertFalse(state.pendingDrops.last!.isSpecial)
    }

    func test_specialFlag_passesToPusher() {
        var flags: [Bool] = []
        state.onCoinToPusher = { _, _, special in flags.append(special) }
        state.coinReachedPusher(x: state.layout.centerX, isSpecial: true)
        state.coinReachedPusher(x: state.layout.centerX)
        XCTAssertEqual(flags, [true, false])
    }

    /// v12.0：掉下来的那一枚入账，特殊金币多出来的部分变成奖励金币从顶部落下
    func test_specialCoinFallingOff_paysMore() {
        let before = state.availableCoins
        state.coinFellOffPusher(isSpecial: true)
        XCTAssertEqual(state.availableCoins, before + GameConstants.bedDropReward)
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.specialCoinReward - GameConstants.bedDropReward)
        state.coinFellOffPusher()
        XCTAssertEqual(state.availableCoins, before + 2 * GameConstants.bedDropReward)
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.specialCoinReward - GameConstants.bedDropReward, "普通金币没有额外奖励")
    }

    // MARK: 战斗区
    func test_coinThroughBattle_attacksAndDamagesBoss() {
        let t0 = Date()
        let attacks = state.warriorAttackCount
        state.coinCrossedBattle(now: t0)
        XCTAssertEqual(state.warriorAttackCount, attacks + 1)
        XCTAssertEqual(state.bossHealth, 1 - GameConstants.bossDamagePerHit, accuracy: 1e-9)
    }

    func test_attackCooldown_limitsRapidHits() {
        let t0 = Date()
        state.coinCrossedBattle(now: t0)
        state.coinCrossedBattle(now: t0.addingTimeInterval(GameConstants.battleAttackCooldown / 2))
        XCTAssertEqual(state.bossHealth, 1 - GameConstants.bossDamagePerHit, accuracy: 1e-9, "冷却时间内不重复攻击")
        state.coinCrossedBattle(now: t0.addingTimeInterval(GameConstants.battleAttackCooldown * 1.1))
        XCTAssertEqual(state.bossHealth, 1 - 2 * GameConstants.bossDamagePerHit, accuracy: 1e-9)
    }

    func test_bossKO_thenRevives() throws {
        var t = Date()
        let kos = state.bossDefeatedCount
        let coinsBefore = state.availableCoins
        let hitsNeeded = Int(ceil(1 / GameConstants.bossDamagePerHit))
        for _ in 0..<hitsNeeded {
            state.coinCrossedBattle(now: t)
            t = t.addingTimeInterval(GameConstants.battleAttackCooldown * 1.1)
        }
        XCTAssertEqual(state.bossHealth, 0)
        XCTAssertEqual(state.bossDefeatedCount, kos + 1)
        XCTAssertEqual(state.availableCoins, coinsBefore, "v12.0：KO 奖励不直接入账")
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.bossKOReward, "KO 奖励变成金币从顶部落下")
        state.coinCrossedBattle(now: t)
        XCTAssertEqual(state.bossDefeatedCount, kos + 1, "KO 期间不再计算")
        // v12.2：K.O. 过场。不到 2 秒不能跳过；之后点一下，BOSS 立刻满血，过场接到「复位」那一段
        let start = try XCTUnwrap(state.koSequenceStart, "K.O. 后开始过场")
        XCTAssertFalse(state.skipKOSequence(now: start.addingTimeInterval(1.0)), "不到 2 秒不能跳过")
        XCTAssertEqual(state.bossHealth, 0)
        XCTAssertTrue(state.skipKOSequence(now: start.addingTimeInterval(2.5)))
        XCTAssertEqual(state.bossHealth, 1, "跳过后满血复活")
        XCTAssertFalse(state.skipKOSequence(now: start.addingTimeInterval(2.6)), "已经在复位，不能再跳")
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.bossKOReward, "跳过不影响 +50")
        let ended = expectation(description: "sequence ends")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { ended.fulfill() }
        wait(for: [ended], timeout: 5)
        XCTAssertNil(state.koSequenceStart, "复位 1 秒后过场结束")
    }

    // MARK: 金币雨与飞字
    func test_bigFloatingScore_isMarkedBig() {
        state.floatingScores.removeAll()
        state.addFloatingScore(text: "+500", x: 0, y: 0, color: .yellow, big: true)
        XCTAssertTrue(state.floatingScores.last!.big)
    }

    // MARK: 下落不旋转
    func test_fallingCoins_neverRotateOrFlip() {
        let scene = DropFieldScene(gameState: state)
        scene.apply(layout: state.layout)
        state.randomUnit = { 0 }   // 包含特殊金币
        for _ in 0..<5 { state.dropCoin() }
        state.pendingCoinRain = 6
        var t: TimeInterval = 1
        for _ in 0..<30 {
            scene.update(t)
            t += 1.0 / 60
            for node in scene.fallingCoinNodes {
                XCTAssertEqual(node.xScale, 1, "下落中不翻转")
                XCTAssertEqual(node.zRotation, 0, "下落中不旋转")
                XCTAssertEqual(node.physicsBody?.allowsRotation, false)
            }
        }
        XCTAssertGreaterThan(scene.fallingCoinNodes.count, 0)
    }
}
