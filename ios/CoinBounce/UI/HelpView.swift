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
                    row("dollarsign.circle.fill", "Each coin pushed off the edge pays 1 coin.")
                    row("rectangle.split.3x1.fill", "A coin passing through the BONUS slider spins the slot machine. Three or more matching symbols in the middle row win coins; a full row is the JACKPOT.")
                    row("circle.grid.3x3.fill", "A coin passing through the middle of a fruit lights it. Light all 7 fruits to pick a reward card, then the fruits reset.")
                    row("shield.fill", "Coins crossing the battle hit the BOSS. Knock it out for 20 coins.")
                    row("sparkles", "Glowing coins are special: each one pushed off pays 10 coins.")
                    row("play.rectangle.fill", "Out of coins? Watch a short ad for 50 coins, up to 5 times a day.")
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
