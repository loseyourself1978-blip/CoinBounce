import SwiftUI

@main
struct CoinBounceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CoinPusherView()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { GameState.shared.saveNow() }
        }
    }
}
