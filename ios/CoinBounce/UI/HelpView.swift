import SwiftUI

// MARK: - 玩法与奖励说明
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("How to Play") {
                    row("hand.tap.fill", "Tap the $ button to drop a coin. Hold it to keep dropping.")
                    row("arrow.down.circle.fill", "Coins fall from the slider at the top, bounce through the slot machine, the battle and the fruit row, then land on the pusher.")
                    row("arrow.left.and.right", "The pusher moves back and forth. Coins pushed off the front edge are yours.")
                }
                Section("Rewards") {
                    row("dollarsign.circle.fill", "Each coin pushed off the front edge pays 1 coin. Coins that slide off the sides are lost.")
                    row("rectangle.split.3x1.fill", "A coin passing through the BONUS slider spins the slot machine. Three or more matching symbols in the middle row, starting from the left, win coins; a full row is the JACKPOT.")
                    row("circle.grid.3x3.fill", "A coin passing through the middle of a fruit lights it. Light all 7 fruits to pick a reward card, then the fruits reset.")
                    row("crown.fill", "Coins crossing the battle make the King hit the BOSS. Knock it out to free the Queen, and 50 coins fall from the top. Tap the battle to skip the celebration.")
                    row("arrow.down.to.line", "Every prize falls from the top as real coins. They are yours once they drop off the front edge.")
                    row("sparkles", "Glowing coins are special: each one pushed off pays 2 coins.")
                    row("play.rectangle.fill", "Tap ▶ +50 at the top to watch a short ad for 50 coins, once every 90 seconds, up to 10 times a day.")
                }
                Section("Roulette") {
                    row("circle.circle.fill", "Pick a chip, tap the table to place bets, then tap SPIN. You can bet up to 50 coins per spin.")
                    row("list.number", "A single number pays 35 to 1. A dozen or a column pays 2 to 1. Red or black, odd or even, 1–18 or 19–36 pay 1 to 1. Zero wins only for a bet on 0.")
                }
                Section("Pachinko") {
                    row("circle.fill", "One coin buys one ball. Tap +1, +2, +5 or +10 to load balls, then hold the handle to shoot. Slide the handle to change strength; the gold zone works best. Balls that fall short come back for free.")
                    row("target", "Pockets: the center start pocket pays 1 and spins the reels. Tulips pay 3 and open or close each time. Side pockets pay 2.")
                    row("star.circle.fill", "Jackpot: three matching symbols open the big gate for 2, 5 or 10 rounds. Each ball in the gate pays 4; a round ends after 5 balls.")
                    row("flame.fill", "Fever time (after K, Q or 7): 12 spins at 1 in 8. Chance time (after other jackpots): 12 quick spins at normal odds.")
                    row("percent", "Odds: jackpot 1 in 22.2 per spin. Expected return is about 96% at the recommended strength and lower at other strengths.")
                }
                if let st = PachinkoSaveStore().load()?.stats, st.ballsFired > 0 {
                    Section("Pachinko stats") {
                        stat("Balls shot", "\(st.ballsFired)")
                        stat("Coins won", "\(st.coinsWon)")
                        if st.ballsFired >= 1000 {
                            stat("Return", String(format: "%.1f%%", 100 * Double(st.coinsWon) / Double(st.ballsFired)))
                        }
                        stat("Jackpots", "\(st.jackpots)")
                        stat("Longest chain", "\(st.bestChain)")
                        stat("Best streak win", "\(st.biggestWin)")
                    }
                }
                Section {
                    Text("Coins are virtual and have no real-world value.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color(red: 0.85, green: 0.6, blue: 0.1))
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
        }
    }

    private func row(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundColor(ArtPalette.gold)
        }
    }
}

// MARK: - 帮助按钮（与设置按钮同款）
struct HelpButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .overlay(Circle().stroke(Color.arcadeGold.opacity(0.8), lineWidth: 1))
        }
        .accessibilityLabel("Help")
    }
}
