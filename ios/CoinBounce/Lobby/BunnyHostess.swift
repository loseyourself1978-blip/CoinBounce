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
    /// 气泡最大宽度（默认身高的 0.62；弹子机里兔女郎小，气泡要宽一点）
    var bubbleWidth: CGFloat? = nil
    /// v12.6：脚下一块落在地上的影子（大厅里站在地毯上用；原来像浮着）
    var groundShadow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 换动作时轻轻弹一下（代替两张图互相淡入淡出）
    @State private var pop = false

    var body: some View {
        let pose = line?.pose ?? .idle
        ZStack(alignment: bubbleOnRight ? .topLeading : .topTrailing) {
            // v12.6：两张不同姿势的图一起淡入淡出会出现重影。换图不做任何过渡（.id + 关掉动画），
            // 摇摆由时钟算出来（不再用隐式动画，换动作时不会把位移、角度和换图搅在一起）
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
                let m = Self.motion(pose, height: height, time: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate)
                BunnyArt(pose: pose)
                    .id(pose)
                    .transition(.identity)
                    .frame(height: height)
                    .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 4)
                    .offset(y: m.lift)
                    .rotationEffect(.degrees(m.tilt), anchor: .bottom)
            }
            // 宽度按这张图的比例定死：TimelineView 自己会把给它的宽度全占掉，把旁边的东西挤出屏幕
            .frame(width: height * Self.aspect(pose), height: height)
            .background(alignment: .bottom) {
                if groundShadow {
                    Ellipse()
                        .fill(RadialGradient(colors: [Color.black.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: height * 0.19))
                        .frame(width: height * 0.38, height: height * 0.06)
                        .offset(y: height * 0.018)
                }
            }
            .scaleEffect(pop ? 1.035 : 1, anchor: .bottom)
            .transaction { $0.animation = nil }
            if let line, showBubble {
                SpeechBubble(text: line.text, tailOnLeft: bubbleOnRight)
                    .frame(maxWidth: bubbleWidth ?? height * 0.62)
                    .offset(x: (bubbleOnRight ? 1 : -1) * height * 0.26, y: -height * 0.02)
                    .id(line.id)
                    // 旧气泡直接消失、新气泡弹出来：两个气泡一起淡入淡出，字会叠在一起
                    .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: bubbleOnRight ? .bottomLeading : .bottomTrailing).combined(with: .opacity),
                                            removal: .identity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: line?.id)
        .onChange(of: pose) { _ in
            guard !reduceMotion else { return }
            pop = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { pop = false }
        }
    }

    /// 这个姿势的图的宽高比
    static func aspect(_ pose: BunnyPose) -> CGFloat {
        guard let img = pose.image, img.size.height > 0 else { return 0.4 }
        return img.size.width / img.size.height
    }

    /// 某一时刻的抬起高度（向上为负）和倾斜角。纯函数，测试直接调
    static func motion(_ pose: BunnyPose, height: CGFloat, time: TimeInterval) -> (lift: CGFloat, tilt: Double) {
        let period: Double, lift: CGFloat, tilt: Double
        switch pose {
        case .jump: period = 0.68; lift = height * 0.06; tilt = 0.6
        case .cheer: period = 0.9; lift = height * 0.025; tilt = 2.2
        case .clap: period = 0.9; lift = height * 0.008; tilt = 1.6
        case .blowKiss: period = 2.8; lift = height * 0.008; tilt = 1.6
        default: period = 2.8; lift = height * 0.008; tilt = 0.6
        }
        let ph = time.truncatingRemainder(dividingBy: period) / period * 2 * .pi
        // 跳：|sin| 像落地弹起；其余：平滑来回
        let up = pose == .jump ? abs(sin(ph)) : (1 - cos(ph)) / 2
        return (-lift * CGFloat(up), tilt * sin(ph))
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
