import SwiftUI

// MARK: - v12.1 大厅导航：大厅 / 推币机 / 轮盘
/// 推币机第一次进入时才创建，之后一直留着（不显示时暂停物理和渲染），台面上的金币、奖励队列都不丢
final class AppRouter: ObservableObject {
    enum Screen: String, CaseIterable { case lobby, pusher, roulette }

    @Published private(set) var screen: Screen
    /// 推币机画面已经创建（创建后不再销毁）
    @Published private(set) var pusherMounted: Bool
    private let gameState: GameState

    init(gameState: GameState = .shared, start: Screen = AppRouter.launchScreen()) {
        self.gameState = gameState
        screen = start
        pusherMounted = start == .pusher
        apply()
    }

    func open(_ target: Screen) {
        guard target != screen else { return }
        screen = target
        if target == .pusher { pusherMounted = true }
        apply()
    }

    func backToLobby() { open(.lobby) }

    private func apply() {
        // 离开推币机：物理、放币时钟、3D 渲染都停住；回来接着走
        gameState.setPaused(screen != .pusher)
        // 看广告的 +50：推币机里从顶部落下，大厅和轮盘里直接入账（那里没有台面可落）
        gameState.creditAdRewardDirectly = screen != .pusher
        ScreenAwake.setGameVisible(screen != .lobby)
    }

    /// 启动后先到哪里：正常是大厅。自动化测试和调试参数（-autoplay…、-debug…）直接进推币机，原来的验收脚本和测试不用改
    static func launchScreen(arguments: [String] = ProcessInfo.processInfo.arguments,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> Screen {
        if arguments.contains("-startLobby") { return .lobby }
        if arguments.contains("-startRoulette") { return .roulette }
        if arguments.contains("-startPusher") { return .pusher }
        if environment["XCTestConfigurationFilePath"] != nil { return .pusher }
        if arguments.contains(where: { $0.hasPrefix("-autoplay") || $0.hasPrefix("-debug") }) { return .pusher }
        return .lobby
    }
}
