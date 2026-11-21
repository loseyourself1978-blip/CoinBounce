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
