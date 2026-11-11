import SwiftUI

// MARK: - v12.1 兔女郎迎宾 / 荷官：现有的 6 张图 + 位移缩放动画 + 对话气泡
/// 一次「说话 + 动作」。id 变了就重新播一遍动作
struct BunnyLine: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let pose: BunnyPose
    static func == (a: BunnyLine, b: BunnyLine) -> Bool { a.id == b.id }
}

enum BunnyScript {
    /// 大厅迎宾：随机一句 + 随机动作
    static let lobbyGreetings: [String] = [
        String(localized: "Welcome! Pick a game."),
        String(localized: "Feeling lucky today?"),
        String(localized: "The roulette table is open!"),
        String(localized: "Coins are falling at the pusher!"),
        String(localized: "Out of coins? Watch a short ad for 50."),
    ]
    static let greetingPoses: [BunnyPose] = [.idle, .blowKiss, .clap, .cheer, .jump]

    static func greeting(random: () -> Double = { Double.random(in: 0..<1) }) -> BunnyLine {
        BunnyLine(text: pick(lobbyGreetings, random), pose: pick(greetingPoses, random))
    }
    static func pick<T>(_ items: [T], _ random: () -> Double) -> T {
        items[min(items.count - 1, Int(random() * Double(items.count)))]
    }
}

struct BunnyHostess: View {
    let line: BunnyLine?
    let height: CGFloat
    /// 气泡在兔女郎的哪一边
    var bubbleOnRight = true
    /// 轮盘里气泡单独摆（在兔女郎上面），这里就不画
    var showBubble = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    var body: some View {
        let pose = line?.pose ?? .idle
        ZStack(alignment: bubbleOnRight ? .topLeading : .topTrailing) {
            BunnyArt(pose: pose)
                .frame(height: height)
                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 4)
                .offset(y: beat ? lift(pose) : 0)
                .rotationEffect(.degrees(beat ? tilt(pose) : -tilt(pose)), anchor: .bottom)
                .animation(reduceMotion ? nil : rhythm(pose), value: beat)
            if let line, showBubble {
                SpeechBubble(text: line.text, tailOnLeft: bubbleOnRight)
                    .frame(maxWidth: height * 0.62)
                    .offset(x: (bubbleOnRight ? 1 : -1) * height * 0.26, y: -height * 0.02)
                    .id(line.id)
                    .transition(.scale(scale: 0.6, anchor: bubbleOnRight ? .bottomLeading : .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: line?.id)
        .onAppear { beat = true }
    }

    private func lift(_ pose: BunnyPose) -> CGFloat {
        switch pose {
        case .jump: return -height * 0.06
        case .cheer: return -height * 0.025
        default: return -height * 0.008
        }
    }
    private func tilt(_ pose: BunnyPose) -> Double {
        switch pose {
        case .blowKiss, .clap: return 1.6
        case .cheer: return 2.2
        default: return 0.6
        }
    }
    private func rhythm(_ pose: BunnyPose) -> Animation {
        switch pose {
        case .jump: return .easeOut(duration: 0.34).repeatForever(autoreverses: true)
        case .cheer, .clap: return .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
        default: return .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        }
    }
}

struct SpeechBubble: View {
    let text: String
    var tailOnLeft = true
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundColor(Color(red: 0.22, green: 0.08, blue: 0.12))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.arcadeGold, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
            )
            .overlay(alignment: tailOnLeft ? .bottomLeading : .bottomTrailing) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.arcadeGold, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .offset(x: tailOnLeft ? -4 : 4, y: 6)
            }
            .accessibilityIdentifier("bunnyBubble")
    }
}
