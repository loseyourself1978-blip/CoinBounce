import SwiftUI

// MARK: - 7 水果全亮：三选一卡牌（扇形展开、点选翻牌）
struct CardSelectionView: View {
    let cards: [RewardCard]
    let picked: CardKind?
    let onPick: (CardKind) -> Void
    let onFinished: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            VStack(spacing: 22) {
                Text(picked == nil ? LocalizedStringKey("All fruits lit! Pick a card") : LocalizedStringKey("Reward unlocked!"))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black, radius: 3)

                // 三张卡扇形展开
                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        let offset = CGFloat(index - 1)
                        FlipCard(card: card, revealed: picked != nil, isPicked: picked == card.kind)
                            .rotationEffect(.degrees(appeared ? Double(offset) * 12 : 0), anchor: .bottom)
                            .offset(x: appeared ? offset * 96 : 0, y: appeared ? abs(offset) * 14 : 40)
                            .scaleEffect(picked == card.kind ? 1.12 : 1)
                            .zIndex(picked == card.kind ? 2 : Double(1 - abs(offset)))
                            .onTapGesture {
                                guard picked == nil else { return }
                                AudioManager.shared.play(.buttonTap)
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { onPick(card.kind) }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                                    withAnimation(.easeOut(duration: 0.25)) { onFinished() }
                                }
                            }
                    }
                }
                .frame(height: 220)
            }
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) { appeared = true }
        }
    }
}

/// 一张可翻转的卡：背面是金色花纹，正面是奖励
struct FlipCard: View {
    let card: RewardCard
    let revealed: Bool
    let isPicked: Bool

    var body: some View {
        ZStack {
            back.opacity(revealed ? 0 : 1)
            front.opacity(revealed ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: 104, height: 150)
        .rotation3DEffect(.degrees(revealed ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .animation(.easeInOut(duration: 0.5), value: revealed)
        .shadow(color: (isPicked ? ArtPalette.gold : .black).opacity(isPicked ? 0.9 : 0.5), radius: isPicked ? 16 : 6)
    }

    private var frameColors: [Color] {
        switch card.kind {
        case .coins: return [ArtPalette.goldLight, ArtPalette.gold]
        case .freeSpins: return [ArtPalette.teal, ArtPalette.tealDeep]
        case .warriorStrike: return [ArtPalette.magenta, ArtPalette.magentaDeep]
        }
    }

    private var back: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(colors: [ArtPalette.magentaDeep, Color(red: 0.2, green: 0.04, blue: 0.14)], startPoint: .top, endPoint: .bottom))
            .overlay(StarShape().fill(ArtPalette.gold.opacity(0.85)).padding(30))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ArtPalette.gold.opacity(0.7), lineWidth: 1.5).padding(8))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ArtPalette.gold, lineWidth: 3))
    }

    private var front: some View {
        VStack(spacing: 6) {
            CardIcon(kind: card.kind).frame(height: 52)
            Text(card.title)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(card.detail)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(width: 104, height: 150)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(red: 0.25, green: 0.12, blue: 0.05), Color(red: 0.12, green: 0.06, blue: 0.03)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(colors: frameColors, startPoint: .top, endPoint: .bottom), lineWidth: 3))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ArtPalette.goldLight, lineWidth: isPicked ? 3 : 0).padding(-3))
    }
}

struct CardIcon: View {
    let kind: CardKind
    var body: some View {
        switch kind {
        case .coins: ZStack { ArtCoin(size: 36).offset(x: -8, y: 4); ArtCoin(size: 36).offset(x: 8, y: -4) }
        case .freeSpins: ReelsIcon(size: 56)
        case .warriorStrike: Image(RoyalAsset.kingAttack.rawValue).resizable().interpolation(.high).frame(width: 58, height: 58)
        }
    }
}

extension RewardCard {
    var title: LocalizedStringKey {
        switch kind {
        case .coins: return "+\(amount) Coins"
        case .freeSpins: return "\(amount) Free Spins"
        case .warriorStrike: return "King's Strike"
        }
    }

    var detail: LocalizedStringKey {
        switch kind {
        case .coins: return "Added to your balance"
        case .freeSpins: return "The slot spins \(amount) times for free"
        case .warriorStrike: return "BOSS loses \(amount)% HP"
        }
    }
}

// MARK: - JACKPOT 全屏庆祝（由 GameState 定时关闭）
struct JackpotCelebrationView: View {
    let amount: Int
    @State private var pulse = false
    // v13.7 大奖爽感（hj 11-28）：先闪白一下、字从大砸下来，数字越滚越快，震动越来越密，滚完再重重一下
    @State private var flash = 0.85
    @State private var slam: CGFloat = 2.6
    @State private var shown = 0.0
    @State private var landed = false
    private let roll = 2.2

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.yellow.opacity(0.55), Color.orange.opacity(0.28), .clear],
                           center: .center, startRadius: 10, endRadius: 460)
                .ignoresSafeArea()
            SunRays(color: ArtPalette.goldLight, rays: 20)
                .blendMode(.plusLighter)
                .opacity(0.8)
                .ignoresSafeArea()
            GoldSparks()
                .ignoresSafeArea()

            VStack(spacing: 2) {
                Text("JACKPOT!")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: ArtPalette.outline, radius: 0, x: 3, y: 4)
                    .shadow(color: .red.opacity(0.9), radius: 10)
                    .scaleEffect(slam)
                CountingText(value: shown, prefix: "+")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .fixedSize()
                    .scaleEffect(landed ? 1.18 : 1)   // 放大用缩放做：改字号做动画时，截图会截到排版到一半的字
                    .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight], startPoint: .top, endPoint: .bottom))
                    .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 3)
                    .shadow(color: .orange, radius: 8)
            }
            .scaleEffect(pulse ? 1.06 : 0.97)
            // 字放在老虎机屏上（屏幕上三分之一处）：兔女郎从侧面出场时站在下半屏，不再挡住字
            .offset(y: -UIScreen.main.bounds.height * 0.17)
            Color.white.opacity(flash).ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            withAnimation(.interpolatingSpring(stiffness: 220, damping: 11)) { slam = 1 }
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { pulse = true }
            // 数字先慢后快
            withAnimation(.easeIn(duration: roll).delay(0.25)) { shown = Double(amount) }
            // 震动：14 下，间隔从 0.3 秒缩到 0.05 秒；滚完时重重一下、数字放大
            var t = 0.3
            for k in 0..<14 {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { HapticManager.shared.coinDrop() }
                t += max(0.05, 0.3 - Double(k) * 0.022)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + roll + 0.3) {
                HapticManager.shared.jackpot()
                AudioManager.shared.play(.winBig)
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 9)) { landed = true }
            }
        }
    }
}
