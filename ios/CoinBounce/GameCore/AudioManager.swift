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
    /// v11.7：中奖时的人群欢呼、掌声，终极大奖的号角
    case cheer = "cheer"
    case applause = "applause"
    case jackpotFanfare = "jackpot_fanfare"

    /// 音量（和其他音效、背景音乐平衡）
    var volume: Float {
        switch self {
        case .cheer: return 0.7
        case .applause: return 0.6
        case .jackpotFanfare: return 0.85
        // v11.8：高频金币声压低一点，不盖过背景的赌场氛围
        case .coinDrop, .bedDrop: return 0.6
        case .baffleHit: return 0.5
        default: return 1
        }
    }

    /// 同一音效两次播放的最小间隔（秒），高频碰撞音不会叠成噪音
    var minInterval: CFTimeInterval {
        switch self {
        case .baffleHit: return 0.08
        case .bedDrop: return 0.12
        case .coinDrop: return 0.05
        default: return 0
        }
    }

    /// v11.8：播放时把背景音乐和环境音压低多久（秒）；0 = 不压
    var duckSeconds: Double {
        switch self {
        case .winBig: return 1.2
        case .jackpot: return 2.8
        case .cheer: return 2.2
        case .applause: return 2.2
        case .jackpotFanfare: return 3.4
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
                player?.volume = effect.volume
                player?.prepareToPlay()
                return player
            }
        }
        if let url = Bundle.main.url(forResource: "bgm_loop", withExtension: "wav") {
            musicPlayer = try? AVAudioPlayer(contentsOf: url)
            musicPlayer?.numberOfLoops = -1
            musicPlayer?.volume = AudioManager.musicVolume
            musicPlayer?.prepareToPlay()
        }
        // 赌场环境音（v11.8：20 秒无缝循环，人声、远处老虎机叮当声、铃声、金币声），和背景音乐一起开关
        if let url = Bundle.main.url(forResource: "amb_crowd_loop", withExtension: "wav") {
            ambiencePlayer = try? AVAudioPlayer(contentsOf: url)
            ambiencePlayer?.numberOfLoops = -1
            ambiencePlayer?.volume = AudioManager.ambienceVolume
            ambiencePlayer?.prepareToPlay()
        }
    }
    private var ambiencePlayer: AVAudioPlayer?

    /// 播放音效；关闭音效或在限流间隔内时返回 false
    @discardableResult
    func play(_ effect: SoundEffect, now: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        guard SettingsStore.shared.settings.soundEnabled else { return false }
        if let last = lastPlayed[effect], now >= last, now - last < effect.minInterval { return false }
        lastPlayed[effect] = now
        playCount += 1
        guard let pool = players[effect], !pool.isEmpty else { return true }
        // v11.6 性能：AVAudioPlayer.play 每次要几毫秒（准备音频队列），放到串行的后台队列，不占主线程
        playQueue.async {
            let player = pool.first(where: { !$0.isPlaying }) ?? pool[0]
            player.currentTime = 0
            player.play()
        }
        if effect.duckSeconds > 0 { duck(for: effect.duckSeconds, now: now) }
        return true
    }

    // MARK: v11.8 闪避（ducking）：中奖音效播放时背景音乐和环境音降到 30%，结束后 0.6 秒内恢复
    // v11.8：音乐和环境音文件已按响度做过母带（约 -18 / -21 LUFS），满音量播放，合起来约 -16.5 LUFS
    static let musicVolume: Float = 1.0
    static let ambienceVolume: Float = 1.0
    static let duckFactor: Float = 0.3
    private(set) var duckedUntil: CFTimeInterval = 0
    var isDucked: Bool { CACurrentMediaTime() < duckedUntil }

    func duck(for seconds: Double, now: CFTimeInterval = CACurrentMediaTime()) {
        let until = now + seconds
        guard until > duckedUntil else { return }
        let wasDucked = now < duckedUntil
        duckedUntil = until
        if !wasDucked {
            musicPlayer?.setVolume(AudioManager.musicVolume * AudioManager.duckFactor, fadeDuration: 0.15)
            ambiencePlayer?.setVolume(AudioManager.ambienceVolume * AudioManager.duckFactor, fadeDuration: 0.15)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, CACurrentMediaTime() >= self.duckedUntil - 0.01 else { return }
            self.musicPlayer?.setVolume(AudioManager.musicVolume, fadeDuration: 0.6)
            self.ambiencePlayer?.setVolume(AudioManager.ambienceVolume, fadeDuration: 0.6)
        }
    }
    private let playQueue = DispatchQueue(label: "coinbounce.audio.play", qos: .userInitiated)

    /// 按设置开关背景音乐（App 回到前台时也调用）
    func updateMusic() {
        let on = SettingsStore.shared.settings.musicEnabled
        for player in [musicPlayer, ambiencePlayer].compactMap({ $0 }) {
            if on {
                if !player.isPlaying { player.play() }
            } else {
                player.pause()
            }
        }
    }
    var isAmbiencePlaying: Bool { ambiencePlayer?.isPlaying ?? false }

    var isMusicPlaying: Bool { musicPlayer?.isPlaying ?? false }
}
