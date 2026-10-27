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
        card.rarity == .rare ? [ArtPalette.magenta, ArtPalette.magentaDeep] : [ArtPalette.teal, ArtPalette.tealDeep]
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
            Text(card.rarity == .rare ? LocalizedStringKey("RARE") : LocalizedStringKey("COMMON"))
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(frameColors[0]))
            CardIcon(kind: card.kind).frame(height: 48)
            Text(card.kind.title)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(card.kind.detail)
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
        case .coins100: ArtCoin(size: 40)
        case .coins200: ZStack { ArtCoin(size: 36).offset(x: -8, y: 4); ArtCoin(size: 36).offset(x: 8, y: -4) }
        case .freeSpins: ReelsIcon(size: 56)
        case .specialCoins: ArtCoin(size: 40).shadow(color: .white, radius: 8).saturation(0.4).brightness(0.15)
        case .fastPusher: Image(systemName: "hare.fill").font(.system(size: 34, weight: .bold)).foregroundColor(ArtPalette.teal)
        case .wideMouth: Image(systemName: "arrow.left.and.right").font(.system(size: 34, weight: .black)).foregroundColor(ArtPalette.gold)
        case .lightFruits: HStack(spacing: -6) { FruitIcon(index: 3, size: 34); FruitIcon(index: 5, size: 34) }
        }
    }
}

extension CardKind {
    var title: LocalizedStringKey {
        switch self {
        case .coins100: return "+100 Coins"
        case .coins200: return "+200 Coins"
        case .freeSpins: return "3 Free Spins"
        case .specialCoins: return "Lucky Coins"
        case .fastPusher: return "Turbo Pusher"
        case .wideMouth: return "Easy Drop"
        case .lightFruits: return "Fruit Head Start"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .coins100, .coins200: return "Added to your balance"
        case .freeSpins: return "The slot spins 3 times"
        case .specialCoins: return "Next 10 drops are glowing coins"
        case .fastPusher: return "Pusher moves faster for 30s"
        case .wideMouth: return "Coins slide off easier for 30s"
        case .lightFruits: return "2 fruits start lit"
        }
    }
}

// MARK: - JACKPOT 全屏庆祝（由 GameState 定时关闭）
struct JackpotCelebrationView: View {
    let amount: Int
    @State private var pulse = false
    @State private var spin = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.yellow.opacity(0.55), Color.orange.opacity(0.25), .clear],
                           center: .center, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()

            // 旋转光芒
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Color.yellow.opacity(0.35))
                    .frame(width: 10, height: 260)
                    .offset(y: -130)
                    .rotationEffect(.degrees(Double(i) * 30 + (spin ? 30 : 0)))
            }

            VStack(spacing: 6) {
                Text("JACKPOT!")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .white, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .red, radius: 8)
                Text("+\(amount)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .orange, radius: 6)
            }
            .scaleEffect(pulse ? 1.12 : 0.92)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}
