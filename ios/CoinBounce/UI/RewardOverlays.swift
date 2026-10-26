import SwiftUI

// MARK: - 7 水果全亮：二选一卡牌
struct CardSelectionView: View {
    let onSelect: (GameState.CardReward) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 18) {
                Text("水果全亮！选择奖励")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black, radius: 3)

                HStack(spacing: 16) {
                    card(icon: "💰", title: "+\(GameConstants.cardCoinsReward)", subtitle: "金币", choice: .coins)
                    card(icon: "🍓", title: "×\(GameConstants.cardFruitsToLight)", subtitle: "点亮水果", choice: .fruits)
                }
            }
            .padding(24)
        }
        .transition(.opacity)
    }

    private func card(icon: String, title: String, subtitle: String, choice: GameState.CardReward) -> some View {
        Button { onSelect(choice) } label: {
            VStack(spacing: 6) {
                Text(icon).font(.system(size: 40))
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(width: 120, height: 160)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.25, blue: 0.08), Color(red: 0.22, green: 0.12, blue: 0.04)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom), lineWidth: 3)
            )
            .shadow(color: .orange.opacity(0.5), radius: 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 奖励弹窗
struct RewardModalView: View {
    let amount: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 8) {
                Text(amount > 0 ? "💰" : "🍓").font(.system(size: 48))
                Text(amount > 0 ? "+\(amount) 金币" : "点亮 \(GameConstants.cardFruitsToLight) 个水果")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.18, green: 0.10, blue: 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.arcadeGold, lineWidth: 3))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.scale.combined(with: .opacity))
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
