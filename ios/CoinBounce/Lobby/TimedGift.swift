import SwiftUI
import Combine

// MARK: - v13 定时送币：每 4 小时可以在大厅领 20 枚（hj 2026-11-21 定）
/// 只记「上次什么时候领的」。第一次打开就能领；领完以后 4 小时再来
final class TimedGift: ObservableObject {
    static let shared = TimedGift()
    static let coins = 20
    static let interval: TimeInterval = 4 * 3600

    private let defaults: UserDefaults
    private let key: String
    private let credit: (Int) -> Void
    @Published private(set) var lastClaim: Date?

    init(defaults: UserDefaults = .standard, key: String = "CoinBounce.TimedGift.lastClaim",
         credit: @escaping (Int) -> Void = { n in GameState.shared.addCoins(n, source: .other); GameState.shared.saveNow() }) {
        self.defaults = defaults
        self.key = key
        self.credit = credit
        let t = defaults.double(forKey: key)
        lastClaim = t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// 还要等多少秒（0 = 现在能领）。时钟被往回拨了（上次领的时间在将来）时，最多也只等一个周期
    func remaining(now: Date = Date()) -> TimeInterval {
        guard let last = lastClaim else { return 0 }
        let since = now.timeIntervalSince(last)
        if since < 0 { return TimedGift.interval }
        return max(0, TimedGift.interval - since)
    }

    func ready(now: Date = Date()) -> Bool { remaining(now: now) <= 0 }

    @discardableResult
    func claim(now: Date = Date()) -> Bool {
        guard ready(now: now) else { return false }
        lastClaim = now
        defaults.set(now.timeIntervalSince1970, forKey: key)
        credit(TimedGift.coins)
        return true
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}

/// 大厅里的礼物：能领时是一只会晃的红包，领过以后显示倒计时
struct TimedGiftButton: View {
    @ObservedObject var gift = TimedGift.shared
    var onClaim: () -> Void = {}
    @State private var wiggle = false
    @State private var burst = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let left = gift.remaining(now: tl.date)
            let ready = left <= 0
            Button {
                guard gift.claim() else { return }
                AudioManager.shared.play(.winSmall)
                AudioManager.shared.play(.coinDrop)
                HapticManager.shared.smallWin()
                burst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { burst = false }
                onClaim()
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        if ready {
                            Circle().fill(RadialGradient(colors: [ArtPalette.gold.opacity(0.7), .clear], center: .center, startRadius: 2, endRadius: 44))
                                .frame(width: 88, height: 88)
                        }
                        CaishenSymbolView(symbol: .redEnvelope, size: 58)
                            .saturation(ready ? 1 : 0.35)
                            .opacity(ready ? 1 : 0.75)
                            .rotationEffect(.degrees(ready && wiggle ? 7 : (ready ? -7 : 0)))
                        if burst {
                            Text(verbatim: "+\(TimedGift.coins)")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(ArtPalette.goldLight)
                                .shadow(color: ArtPalette.outline, radius: 0, x: 1.5, y: 1.5)
                                .offset(y: -48)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(width: 70, height: 64)
                    Group {
                        if ready {
                            Text("FREE +\(TimedGift.coins)")
                        } else {
                            Text(verbatim: TimedGift.clock(left))
                        }
                    }
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ready ? Color(red: 0.35, green: 0.12, blue: 0) : .white.opacity(0.85))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Group {
                        if ready { GoldGloss(shape: Capsule()) } else { Capsule().fill(Color.black.opacity(0.6)) }
                    })
                    .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.8), lineWidth: 1))
                }
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!ready)
            .accessibilityIdentifier("timedGift")
            .accessibilityLabel(Text("Free coins"))
            .accessibilityValue(Text(verbatim: ready ? "ready" : TimedGift.clock(left)))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: burst)
        .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { wiggle = true } }
    }
}

// MARK: - v13.5 不靠广告补币（hj 11-24 同意）：金币少时自动回补 + 每日登录奖励
/// 余额低于 cap（30）时开始计时，每 15 分钟送 10 枚，补到 30 为止；离开 App 的时间也算。
/// 余额回到 30 以上时停表，下次再低于 30 重新计时。只记计时起点（存 UserDefaults）
final class CoinRefill: ObservableObject {
    static let shared = CoinRefill()
    static let cap = 30
    static let step = 10
    static let interval: TimeInterval = 15 * 60

    private let defaults: UserDefaults
    private let key: String
    @Published private(set) var anchor: Date?

    init(defaults: UserDefaults = .standard, key: String = "CoinBounce.CoinRefill.anchor") {
        self.defaults = defaults
        self.key = key
        let t = defaults.double(forKey: key)
        anchor = t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// 按现在的余额走一次表，返回这次该送几枚（0 = 不送）。调用方负责把金币加上
    func tick(balance: Int, now: Date = Date()) -> Int {
        guard balance < CoinRefill.cap else { setAnchor(nil); return 0 }
        guard let a = anchor, a <= now else { setAnchor(now); return 0 }   // 刚开始计时，或时钟被往回拨
        let n = Int(now.timeIntervalSince(a) / CoinRefill.interval)
        guard n > 0 else { return 0 }
        let give = min(n * CoinRefill.step, CoinRefill.cap - balance)
        let next = a.addingTimeInterval(Double(n) * CoinRefill.interval)
        setAnchor(balance + give >= CoinRefill.cap ? nil : next)
        return give
    }

    /// 离下一次送币还有几秒；余额够了（不计时）时为 nil
    func remaining(balance: Int, now: Date = Date()) -> TimeInterval? {
        guard balance < CoinRefill.cap else { return nil }
        guard let a = anchor else { return CoinRefill.interval }
        let since = max(0, now.timeIntervalSince(a))
        return CoinRefill.interval - since.truncatingRemainder(dividingBy: CoinRefill.interval)
    }

    private func setAnchor(_ d: Date?) {
        guard d != anchor else { return }
        anchor = d
        if let d { defaults.set(d.timeIntervalSince1970, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// 每天第一次进大厅送 30 枚（按本地日期）
final class DailyBonus {
    static let shared = DailyBonus()
    static let coins = 30
    /// v13.9 节日期间每日奖励加码：圣诞 50，新年 60
    static func amount(_ festival: Festival = .current) -> Int { festival == .christmas ? 50 : festival == .newYear ? 60 : coins }
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "CoinBounce.DailyBonus.day") {
        self.defaults = defaults
        self.key = key
    }

    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 今天还没领就记下并返回 true（调用方加金币、播提示）
    func claimIfNew(now: Date = Date()) -> Bool {
        let today = DailyBonus.dayKey(now)
        guard defaults.string(forKey: key) != today else { return false }
        defaults.set(today, forKey: key)
        return true
    }
}
