import UIKit
import CoreHaptics

// MARK: - 触觉反馈管理器（精细化游戏手感）
class HapticManager {
    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    /// 实际触发的次数（关闭震动时不增加，供测试使用）
    private(set) var playCount = 0

    /// 设置里关闭震动时不触发
    private func shouldPlay() -> Bool {
        guard SettingsStore.shared.settings.hapticsEnabled else { return false }
        playCount += 1
        return true
    }

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
        } catch {}
    }

    // MARK: - 投币（中等冲击）
    func coinDrop() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
    }

    // MARK: - 格挡碰撞（轻微短促）
    func baffleHit() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    // MARK: - 水果点亮（清脆）
    func fruitLit() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
    }

    // MARK: - 全部水果点亮（强烈震动序列）
    func allFruitsLit() {
        guard shouldPlay() else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    // MARK: - 老虎机旋转结束（每列停止）
    func slotColumnStop() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }
    
    // MARK: - 老虎机开始旋转
    func slotStart() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
    }
    
    // MARK: - 老虎机停止
    func slotStop() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }

    // MARK: - 老虎机中奖
    func slotJackpot() {
        guard shouldPlay() else { return }
        playCustomPattern([
            (0.0, 1.0, 0.3),
            (0.1, 0.8, 0.2),
            (0.2, 1.0, 0.35),
            (0.35, 0.6, 0.2),
            (0.45, 1.0, 0.4),
        ])
    }
    
    // MARK: - Jackpot大奖
    func jackpot() {
        guard shouldPlay() else { return }
        playCustomPattern([
            (0.0, 1.0, 0.5),
            (0.1, 0.9, 0.4),
            (0.2, 1.0, 0.5),
            (0.3, 0.8, 0.3),
            (0.4, 1.0, 0.5),
        ])
    }
    
    // MARK: - Big Win
    func bigWin() {
        guard shouldPlay() else { return }
        playCustomPattern([
            (0.0, 0.9, 0.4),
            (0.15, 0.8, 0.3),
            (0.3, 0.9, 0.4),
        ])
    }
    
    // MARK: - Small Win
    func smallWin() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
    }

    // MARK: - 金币推落边缘
    func coinFall() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
    }

    // MARK: - BONUS触发
    func bonusTriggered() {
        guard shouldPlay() else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - 连击
    func combo(level: Int) {
        guard shouldPlay() else { return }
        let intensity = min(1.0, 0.5 + Double(level) * 0.1)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: intensity)
    }

    // MARK: - 自定义震动序列
    private func playCustomPattern(_ events: [(time: Double, intensity: Float, sharpness: Float)]) {
        guard let engine,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        do {
            let hapticEvents = events.map { e in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: e.intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: e.sharpness)
                    ],
                    relativeTime: e.time
                )
            }
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {}
    }
}
