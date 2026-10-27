import XCTest
@testable import CoinBounce

// ============================================================
// MARK: - 激励广告领金币
// ============================================================

private final class FakeAdPresenter: RewardedAdPresenting {
    var adsEnabled = true
    var isAdReady = true
    var completes: Bool
    private(set) var shown = 0
    init(completes: Bool) { self.completes = completes }
    func showRewardedAd(onReward: @escaping () -> Void) {
        shown += 1
        if completes { onReward() }   // 用户看完；false 表示中途关闭
    }
}

final class AdRewardTests: XCTestCase {
    var state: GameState!
    private var originalPresenter: RewardedAdPresenting!
    let day1 = DateComponents(calendar: .current, year: 2026, month: 10, day: 26, hour: 23, minute: 50).date!
    let day2 = DateComponents(calendar: .current, year: 2026, month: 10, day: 27, hour: 0, minute: 5).date!

    override func setUp() {
        super.setUp()
        state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "AdRewardTests")!, key: "AdRewardTests.SaveData")
        state.saveStore.clear()
        originalPresenter = state.adPresenter
        state.availableCoins = 0
        state.adRewardDay = nil
        state.adRewardsClaimed = 0
    }

    override func tearDown() {
        state.adPresenter = originalPresenter
        state.adRewardDay = nil
        state.adRewardsClaimed = 0
        super.tearDown()
    }

    func test_adMobAppID_matchesInfoPlist() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String, AppConfig.adMobAppID)
        XCTAssertEqual(AppConfig.adMobAppID, "ca-app-pub-9469890002230148~5839128885")
    }

    func test_debugBuild_alwaysUsesTestAdUnit() {
        XCTAssertEqual(AppConfig.rewardedAdUnitID(isDebug: true, production: "ca-app-pub-9469890002230148/1234567890"), AppConfig.testRewardedAdUnitID)
        #if DEBUG
        XCTAssertEqual(AppConfig.rewardedAdUnitID, AppConfig.testRewardedAdUnitID)
        #endif
    }

    func test_releaseBuild_neverUsesTestOrPlaceholderAdUnit() {
        for bad in [AppConfig.productionRewardedAdUnitID, "", AppConfig.testRewardedAdUnitID, "ca-app-pub-9469890002230148/"] {
            XCTAssertNil(AppConfig.rewardedAdUnitID(isDebug: false, production: bad), "正式版不能用：\(bad)")
        }
        XCTAssertEqual(AppConfig.rewardedAdUnitID(isDebug: false, production: "ca-app-pub-9469890002230148/1234567890"),
                       "ca-app-pub-9469890002230148/1234567890")
    }

    func test_adsDisabled_hidesAdRewardButton() {
        let fake = FakeAdPresenter(completes: true)
        fake.adsEnabled = false
        state.adPresenter = fake
        state.availableCoins = 0
        XCTAssertFalse(state.canOfferAdReward(now: day1), "没有可用广告单元时不显示领币按钮")
        state.requestFreeCoins()
        XCTAssertEqual(fake.shown, 0)
    }

    func test_offer_onlyBelowThreshold() {
        state.adPresenter = FakeAdPresenter(completes: true)
        state.availableCoins = GameConstants.adRewardCoinThreshold - 1
        XCTAssertTrue(state.canOfferAdReward(now: day1))
        state.availableCoins = GameConstants.adRewardCoinThreshold
        XCTAssertFalse(state.canOfferAdReward(now: day1), "金币达到阈值时不显示领币按钮")
    }

    func test_completedAd_grantsCoins() {
        let fake = FakeAdPresenter(completes: true)
        state.adPresenter = fake
        state.requestFreeCoins()
        XCTAssertEqual(fake.shown, 1)
        XCTAssertEqual(state.availableCoins, GameConstants.adRewardCoins)
    }

    func test_closedEarly_grantsNothing() {
        let fake = FakeAdPresenter(completes: false)
        state.adPresenter = fake
        state.requestFreeCoins()
        XCTAssertEqual(fake.shown, 1)
        XCTAssertEqual(state.availableCoins, 0, "没看完不发金币")
        XCTAssertEqual(state.adRewardsUsed(), 0, "没看完不占用次数")
    }

    func test_adNotReady_doesNothing() {
        let fake = FakeAdPresenter(completes: true)
        fake.isAdReady = false
        state.adPresenter = fake
        state.requestFreeCoins()
        XCTAssertEqual(fake.shown, 0)
        XCTAssertEqual(state.availableCoins, 0)
    }

    func test_enoughCoins_doesNotShowAd() {
        let fake = FakeAdPresenter(completes: true)
        state.adPresenter = fake
        state.availableCoins = 500
        state.requestFreeCoins()
        XCTAssertEqual(fake.shown, 0)
        XCTAssertEqual(state.availableCoins, 500)
    }

    func test_dailyLimit() {
        state.adPresenter = FakeAdPresenter(completes: true)
        for _ in 0..<GameConstants.adRewardDailyLimit {
            XCTAssertTrue(state.grantAdReward(now: day1))
        }
        XCTAssertFalse(state.grantAdReward(now: day1), "超过每日上限不发")
        XCTAssertEqual(state.availableCoins, GameConstants.adRewardCoins * GameConstants.adRewardDailyLimit)
        state.availableCoins = 0
        XCTAssertFalse(state.canOfferAdReward(now: day1), "用完次数后不再显示领币按钮")
    }

    func test_limitResetsNextLocalDay() {
        state.adPresenter = FakeAdPresenter(completes: true)
        for _ in 0..<GameConstants.adRewardDailyLimit { state.grantAdReward(now: day1) }
        XCTAssertEqual(state.adRewardsUsed(on: day2), 0, "跨日归零")
        state.availableCoins = 0
        XCTAssertTrue(state.canOfferAdReward(now: day2))
        XCTAssertTrue(state.grantAdReward(now: day2))
        XCTAssertEqual(state.adRewardsUsed(on: day2), 1)
    }

    func test_adRewardCount_isSaved() {
        state.grantAdReward(now: day1)
        state.grantAdReward(now: day1)
        state.saveNow()
        let loaded = state.saveStore.load()
        XCTAssertEqual(loaded?.adRewardDay, GameState.dayKey(for: day1))
        XCTAssertEqual(loaded?.adRewardsClaimed, 2)
    }

    func test_oldSaveWithoutAdFields_loads() throws {
        let json = #"{"availableCoins":7,"totalCoinsWon":0,"fruitsLit":[false,false,false,false,false,false,false],"hasDroppedFirstCoin":true}"#
        let data = try JSONDecoder().decode(SaveData.self, from: Data(json.utf8))
        XCTAssertEqual(data.availableCoins, 7)
        XCTAssertNil(data.adRewardDay)
        state.applySave(data)
        XCTAssertEqual(state.adRewardsClaimed, 0)
    }
}
