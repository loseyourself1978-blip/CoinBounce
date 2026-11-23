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
                Section("Slots") {
                    row("square.grid.3x3.fill", "Pick one of three machines. Set your bet and tap SPIN. Matching symbols on any of 10 lines, starting from the left reel, win a multiple of your bet.")
                    row("circle.hexagongrid.fill", "Six or more coins lock in place and start Hold & Respin. Fill all 15 spaces to win the GRAND jackpot.")
                }
                if AppRouter.isAvailable(.roulette) {
                Section("Roulette") {
                    row("circle.circle.fill", "Pick a chip, tap the table to place bets, then tap SPIN. You can bet up to 50 coins per spin.")
                    row("hand.draw.fill", "Press and slide on the table to aim: on a line between two numbers, on a corner of four, or on the left edge of a row. The covered numbers light up with the payout. Release to place the chip.")
                    row("list.number", "A single number pays 35 to 1. A dozen or a column pays 2 to 1. Red or black, odd or even, 1–18 or 19–36 pay 1 to 1. Zero wins only for a bet on 0.")
                }
                }
                if AppRouter.isAvailable(.pinball) {
                Section("Pinball") {
                    row("circle.fill", "One coin buys one ball. Drag the spring at the bottom right down and let go to launch. Tap the left or right half of the screen to swing that flipper and keep the ball in play.")
                    row("target", "Score by hitting bumpers, slingshots, the 7-7-7 lanes, the K-Q-J drop targets, the three stars and the Lucky Hole. Every 9,500 points pays 1 coin, and leftover points carry over to your next ball. One ball can win at most 15 coins.")
                    row("star.circle.fill", "Missions: knock down K-Q-J, hit bumpers 12 times, light the three stars, then shoot the Lucky Hole for the jackpot and a 3-ball multiball. Lighting 7-7-7 raises the bonus multiplier (up to ×5) and lights the Lucky Hole for a mystery prize.")
                    row("percent", "A ball lost in the first 7 seconds is returned once for free. Return depends on skill: about 50% without flipping, about 95% for average play.")
                }
                }
                if AppRouter.isAvailable(.pinball), let st = PinballSaveStore().load()?.stats, st.balls > 0 {
                    Section("Pinball stats") {
                        stat("Balls played", "\(st.balls)")
                        stat("Coins won", "\(st.coinsWon)")
                        stat("High score", st.highScore.formatted())
                        stat("Jackpots", "\(st.jackpots)")
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
