import AVFoundation
import Combine
import QuartzCore

// MARK: - 音效
enum SoundEffect: String, CaseIterable {
    case coinDrop = "coin_drop"
    case baffleHit = "baffle_hit"
    case fruitLit = "fruit_lit"
    case bedDrop = "bed_drop"
    case slotSpin = "slot_spin"
    case slotStop = "slot_stop"
    case winSmall = "win_small"
    case winBig = "win_big"
    case jackpot = "jackpot"
    case buttonTap = "button_tap"
    case noCoins = "no_coins"

    /// 同一音效两次播放的最小间隔（秒），高频碰撞音不会叠成噪音
    var minInterval: CFTimeInterval {
        switch self {
        case .baffleHit: return 0.08
        case .bedDrop: return 0.12
        case .coinDrop: return 0.05
        default: return 0
        }
    }

    /// 可同时播放的份数
    var voices: Int {
        switch self {
        case .baffleHit, .coinDrop, .bedDrop: return 3
        default: return 1
        }
    }
}

// MARK: - 音频管理
// AVAudioSession 用 .ambient：与用户自己的音乐混音、不打断它，静音键打开时不出声。
// 所有音效启动时预加载，避免第一次播放卡顿。
final class AudioManager {
    static let shared = AudioManager()

    private var players: [SoundEffect: [AVAudioPlayer]] = [:]
    private var lastPlayed: [SoundEffect: CFTimeInterval] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var settingsObserver: AnyCancellable?

    /// 实际播放的音效次数（关闭音效或被限流时不增加，供测试使用）
    private(set) var playCount = 0

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        preload()
        settingsObserver = SettingsStore.shared.$settings
            .map(\.musicEnabled)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMusic() }
    }

    private func preload() {
        for effect in SoundEffect.allCases {
            guard let url = Bundle.main.url(forResource: "sfx_\(effect.rawValue)", withExtension: "wav") else { continue }
            players[effect] = (0..<effect.voices).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                return player
            }
        }
        if let url = Bundle.main.url(forResource: "bgm_loop", withExtension: "wav") {
            musicPlayer = try? AVAudioPlayer(contentsOf: url)
            musicPlayer?.numberOfLoops = -1
            musicPlayer?.volume = 0.35
            musicPlayer?.prepareToPlay()
        }
    }

    /// 播放音效；关闭音效或在限流间隔内时返回 false
    @discardableResult
    func play(_ effect: SoundEffect, now: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        guard SettingsStore.shared.settings.soundEnabled else { return false }
        if let last = lastPlayed[effect], now >= last, now - last < effect.minInterval { return false }
        lastPlayed[effect] = now
        playCount += 1
        guard let pool = players[effect], !pool.isEmpty else { return true }
        let player = pool.first(where: { !$0.isPlaying }) ?? pool[0]
        player.currentTime = 0
        player.play()
        return true
    }

    /// 按设置开关背景音乐（App 回到前台时也调用）
    func updateMusic() {
        guard let musicPlayer else { return }
        if SettingsStore.shared.settings.musicEnabled {
            if !musicPlayer.isPlaying { musicPlayer.play() }
        } else {
            musicPlayer.pause()
        }
    }

    var isMusicPlaying: Bool { musicPlayer?.isPlaying ?? false }
}
