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
        state.onCoinToPusher = { _, special in flags.append(special) }
        state.coinReachedPusher(x: state.layout.centerX, isSpecial: true)
        state.coinReachedPusher(x: state.layout.centerX)
        XCTAssertEqual(flags, [true, false])
    }

    func test_specialCoinFallingOff_paysMore() {
        let before = state.availableCoins
        state.coinFellOffPusher(isSpecial: true)
        XCTAssertEqual(state.availableCoins, before + GameConstants.specialCoinReward)
        state.coinFellOffPusher()
        XCTAssertEqual(state.availableCoins, before + GameConstants.specialCoinReward + GameConstants.bedDropReward)
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

    func test_bossKO_thenRevives() {
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
        XCTAssertEqual(state.availableCoins, coinsBefore + GameConstants.bossKOReward, "KO 奖励计入余额")
        state.coinCrossedBattle(now: t)
        XCTAssertEqual(state.bossDefeatedCount, kos + 1, "KO 期间不再计算")
        let revived = expectation(description: "revive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { revived.fulfill() }
        wait(for: [revived], timeout: 5)
        XCTAssertEqual(state.bossHealth, 1, "1.2 秒后满血复活")
    }

    // MARK: 金币雨与飞字
    func test_bigFloatingScore_isMarkedBig() {
        state.floatingScores.removeAll()
        state.addFloatingScore(text: "+500", x: 0, y: 0, color: .yellow, big: true)
        XCTAssertTrue(state.floatingScores.last!.big)
    }

    func test_coinRainCounts_increaseWithWinSize() {
        XCTAssertLessThan(GameConstants.coinRainSmallWin, GameConstants.coinRainBigWin)
        XCTAssertLessThan(GameConstants.coinRainBigWin, GameConstants.coinRainJackpot)
    }
}
