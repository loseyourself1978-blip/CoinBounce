import XCTest
@testable import CoinBounce

/// v12.1 大厅导航：离开推币机时暂停、状态和奖励队列留着；看广告的 +50 在大厅和轮盘里直接入账
final class LobbyTests: XCTestCase {
    private var state: GameState!
    private var originalStore: SaveStore!

    override func setUp() {
        super.setUp()
        state = GameState.shared
        originalStore = state.saveStore
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "LobbyTests")!, key: "LobbyTests.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.availableCoins = 100
    }

    override func tearDown() {
        state.adRewardDay = nil; state.adRewardsClaimed = 0; state.lastAdRewardAt = nil
        state.resetForTesting()   // 回到「在推币机里」：不暂停、广告奖励走掉落
        state.saveStore.clear()
        state.saveStore = originalStore
        ScreenAwake.setGameVisible(true)
        super.tearDown()
    }

    func test_launchScreen_defaultsToLobby_testsAndDebugFlagsGoToPusher() {
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce"], environment: [:]), .lobby)
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-autoplay"], environment: [:]), .pusher)
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-autoplayBurst10"], environment: [:]), .pusher)
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-debugReward", "60"], environment: [:]), .pusher)
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce"], environment: ["XCTestConfigurationFilePath": "/x"]), .pusher, "测试宿主照旧直接是推币机")
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-startRoulette"], environment: [:]), .roulette)
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-startLobby", "-autoplay"], environment: ["XCTestConfigurationFilePath": "/x"]), .lobby)
        XCTAssertEqual(AppRouter.launchScreen(arguments: ["CoinBounce", "-startPusher"], environment: [:]), .pusher)
    }

    func test_lobbyStart_pusherNotMounted_paused() {
        let router = AppRouter(gameState: state, start: .lobby)
        XCTAssertEqual(router.screen, .lobby)
        XCTAssertFalse(router.pusherMounted, "第一次进推币机时才创建")
        XCTAssertTrue(state.isPaused)
        XCTAssertTrue(state.creditAdRewardDirectly)
        XCTAssertFalse(ScreenAwake.gameVisible)
    }

    func test_navigation_keepsPusherMounted_andPausesOutsideIt() {
        let router = AppRouter(gameState: state, start: .lobby)
        var pauses: [Bool] = []
        state.onPauseChanged = { pauses.append($0) }
        defer { state.onPauseChanged = nil }
        router.open(.pusher)
        XCTAssertTrue(router.pusherMounted)
        XCTAssertFalse(state.isPaused)
        XCTAssertFalse(state.creditAdRewardDirectly)
        XCTAssertTrue(ScreenAwake.gameVisible)
        router.backToLobby()
        XCTAssertEqual(router.screen, .lobby)
        XCTAssertTrue(router.pusherMounted, "回大厅后推币机画面留着")
        XCTAssertTrue(state.isPaused)
        router.open(.roulette)
        XCTAssertTrue(state.isPaused, "轮盘里推币机也停着")
        XCTAssertTrue(router.pusherMounted)
        XCTAssertTrue(ScreenAwake.gameVisible)
        router.backToLobby()
        router.open(.pusher)
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(pauses, [false, true, false], "只在进出推币机时通知 3D 场景")
        router.open(.pusher)
        XCTAssertEqual(pauses.count, 3, "重复打开不重复通知")
    }

    /// 离开推币机再回来：余额、水果灯、BOSS 血量、奖池、还没落下的奖励金币都在
    func test_leavingAndReturning_keepsPusherState_andRewardQueue() {
        let router = AppRouter(gameState: state, start: .pusher)
        state.payReward(40, source: .jackpot)
        state.fruitsLit[2] = true
        state.bossHealth = 0.42
        let pool = state.jackpotPool
        router.backToLobby()
        XCTAssertEqual(state.saveStore.load()?.pendingRewardDrops, 40, "离开时存档")
        router.open(.roulette)
        router.backToLobby()
        router.open(.pusher)
        XCTAssertEqual(state.pendingRewardDrops, 40, "奖励队列一枚不少")
        XCTAssertEqual(state.availableCoins, 100)
        XCTAssertTrue(state.fruitsLit[2])
        XCTAssertEqual(state.bossHealth, 0.42)
        XCTAssertEqual(state.jackpotPool, pool)
        // 回来后接着落
        var released = 0
        let original = state.onRewardDrop
        state.onRewardDrop = { _ in released += 1 }
        defer { state.onRewardDrop = original }
        for _ in 0..<8 { state.step(dt: CGFloat(GameConstants.batchDropInterval) / 2) }
        XCTAssertEqual(released, 4)
        XCTAssertEqual(state.pendingRewardDrops, 36)
    }

    func test_adReward_creditsDirectlyOutsideThePusher_dropsInsideIt() {
        let router = AppRouter(gameState: state, start: .lobby)
        XCTAssertTrue(state.grantAdReward(now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(state.availableCoins, 100 + GameConstants.adRewardCoins, "大厅里：直接入账")
        XCTAssertEqual(state.pendingRewardDrops, 0)
        router.open(.roulette)
        state.lastAdRewardAt = nil
        XCTAssertTrue(state.grantAdReward(now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(state.availableCoins, 100 + 2 * GameConstants.adRewardCoins, "轮盘里：直接入账")
        router.backToLobby()
        router.open(.pusher)
        state.lastAdRewardAt = nil
        XCTAssertTrue(state.grantAdReward(now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(state.availableCoins, 100 + 2 * GameConstants.adRewardCoins)
        XCTAssertEqual(state.pendingRewardDrops, GameConstants.adRewardCoins, "推币机里：从顶部落下")
        XCTAssertEqual(state.adRewardsUsed(on: Date(timeIntervalSince1970: 1_800_000_000)), 3, "同一个每日次数")
    }

    func test_bunnyGreeting_isRandomLineAndPose() {
        var seen = Set<String>(), poses = Set<BunnyPose>()
        var seed = 0.0
        for _ in 0..<60 {
            let line = BunnyScript.greeting(random: { seed += 0.137; return seed.truncatingRemainder(dividingBy: 1) })
            seen.insert(line.text); poses.insert(line.pose)
            XCTAssertFalse(line.text.isEmpty)
        }
        XCTAssertEqual(seen.count, BunnyScript.lobbyGreetings.count, "每一句都会出现")
        XCTAssertEqual(poses.count, BunnyScript.greetingPoses.count, "每个动作都会出现")
        XCTAssertNotEqual(BunnyScript.greeting().id, BunnyScript.greeting().id, "每次都是新的一句（动作重播）")
        for pose in BunnyScript.greetingPoses { XCTAssertNotNil(pose.image, "\(pose) 的图在") }
    }
}
