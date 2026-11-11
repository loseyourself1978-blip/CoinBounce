import Foundation

// MARK: - v12.2 BOSS K.O. 之后的过场：BOSS 倒下 → 王后破涕为笑跑向国王 → 亲吻（爱心、K.O.! +N）→ 复位
/// 纯时间轴（不含界面），测试直接验证
enum KOSequence {
    enum Phase: String, CaseIterable, Equatable {
        case bossFalls   // BOSS 倒下淡出，国王弹跳
        case queenRuns   // 王后从哭变成笑，滑到国王身边
        case kiss        // 亲吻大图，爱心飘起，「K.O.! +N」
        case reset       // 大图淡出，BOSS 满血复活，王后回到 BOSS 后面
    }

    /// 每一段的时长（秒）。合计 7 秒（hj：5–10 秒）
    /// 调试参数 -debugKOSlow：亲吻那一段拉长到 30 秒（截图、手动检查「点一下跳过」用）
    static let durations: [(phase: Phase, seconds: Double)] = [
        (.bossFalls, 1.0), (.queenRuns, 1.5),
        (.kiss, ProcessInfo.processInfo.arguments.contains("-debugKOSlow") ? 30 : 3.5), (.reset, 1.0),
    ]
    static var total: Double { durations.reduce(0) { $0 + $1.seconds } }
    /// 开始 2 秒后点一下可以跳过
    static let skippableAfter: Double = 2.0

    /// t 秒时在哪一段、这一段走了多少（0…1）。还没开始或已经结束返回 nil
    static func state(at t: Double) -> (phase: Phase, progress: Double)? {
        guard t >= 0 else { return nil }
        var start = 0.0
        for (phase, seconds) in durations {
            if t < start + seconds { return (phase, (t - start) / seconds) }
            start += seconds
        }
        return nil
    }
    static func phase(at t: Double) -> Phase? { state(at: t)?.phase }
    static func start(of phase: Phase) -> Double {
        var start = 0.0
        for (p, seconds) in durations {
            if p == phase { return start }
            start += seconds
        }
        return start
    }
    static func canSkip(at t: Double) -> Bool { t >= skippableAfter && t < total }

    /// 王后的位置（0 = 国王身边，1 = BOSS 后面）
    static func queenPosition(at t: Double) -> Double {
        guard let s = state(at: t) else { return 1 }
        switch s.phase {
        case .bossFalls: return 1
        case .queenRuns: let u = s.progress; return 1 - u * u * (3 - 2 * u)
        case .kiss: return 0
        case .reset: let u = s.progress; return u * u * (3 - 2 * u)
        }
    }
    /// 王后是不是开心的（跑的时候开始变，复位的后半段变回哭）
    static func queenIsHappy(at t: Double) -> Bool {
        guard let s = state(at: t) else { return false }
        switch s.phase {
        case .bossFalls: return false
        case .queenRuns: return s.progress > 0.15
        case .kiss: return true
        case .reset: return s.progress < 0.5
        }
    }
    /// 亲吻大图的不透明度
    static func kissOpacity(at t: Double) -> Double {
        guard let s = state(at: t) else { return 0 }
        switch s.phase {
        case .kiss: return min(1, s.progress / 0.1)
        case .reset: return max(0, 1 - s.progress / 0.5)
        default: return 0
        }
    }
    /// BOSS 倒下的程度（0 = 站着，1 = 躺平）
    static func bossDown(at t: Double) -> Double {
        guard let s = state(at: t) else { return 0 }
        switch s.phase {
        case .bossFalls: return min(1, s.progress / 0.35)
        case .queenRuns, .kiss: return 1
        case .reset: return max(0, 1 - s.progress / 0.5)
        }
    }
    /// 国王在欢呼（举剑）
    static func kingCheers(at t: Double) -> Bool {
        guard let s = state(at: t) else { return false }
        return s.phase == .bossFalls || s.phase == .queenRuns
    }
    /// 亲吻这一段走了多少秒（没到或已过返回 nil），爱心和「+N」用
    static func kissTime(at t: Double) -> Double? {
        let start = start(of: .kiss)
        guard t >= start, t < total else { return nil }
        return t - start
    }
}
