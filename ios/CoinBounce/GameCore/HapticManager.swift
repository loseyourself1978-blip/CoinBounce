import UIKit
import CoreHaptics

// MARK: - 触觉反馈管理器（精细化游戏手感）
class HapticManager {
    static let shared = HapticManager()

    private var engine: CHHapticEngine?

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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
    }

    // MARK: - 格挡碰撞（轻微短促）
    func baffleHit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    // MARK: - 水果点亮（清脆）
    func fruitLit() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
    }

    // MARK: - 全部水果点亮（强烈震动序列）
    func allFruitsLit() {
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
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }
    
    // MARK: - 老虎机开始旋转
    func slotStart() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
    }
    
    // MARK: - 老虎机停止
    func slotStop() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }

    // MARK: - 老虎机中奖
    func slotJackpot() {
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
        playCustomPattern([
            (0.0, 0.9, 0.4),
            (0.15, 0.8, 0.3),
            (0.3, 0.9, 0.4),
        ])
    }
    
    // MARK: - Small Win
    func smallWin() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
    }

    // MARK: - 金币推落边缘
    func coinFall() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
    }

    // MARK: - BONUS触发
    func bonusTriggered() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - 连击
    func combo(level: Int) {
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
