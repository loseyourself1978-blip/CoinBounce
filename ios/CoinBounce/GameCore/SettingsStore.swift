import Foundation
import Combine

// MARK: - 用户设置
struct GameSettings: Codable, Equatable {
    var soundEnabled = true
    var musicEnabled = true
    var hapticsEnabled = true

    static let defaults = GameSettings()
}

// MARK: - 设置读写 (UserDefaults + JSON)，修改即保存
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private let key: String

    @Published var settings: GameSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    init(defaults: UserDefaults = .standard, key: String = "CoinBounce.Settings.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(GameSettings.self, from: data) {
            settings = saved
        } else {
            settings = .defaults
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
