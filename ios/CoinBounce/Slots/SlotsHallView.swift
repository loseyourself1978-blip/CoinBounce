import SwiftUI

// MARK: - v13.2 老虎机厅：进门先选机器（财神到、大圣闹天宫、雅典娜的神殿），选好了进那一台
struct SlotsHallView: View {
    let onExit: () -> Void
    @ObservedObject private var gameState = GameState.shared
    @State private var selected: SlotTheme? = SlotsHallView.initialTheme
    @State private var showSettings = false

    /// 调试参数直接进某一台：-slotTheme wukong；老的 -slotsDemo、-dumpIcons 不带主题时进财神这一台
    static var initialTheme: SlotTheme? {
        if let t = SlotTheme.launchTheme { return t }
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-slotsDemo") || args.contains("-dumpIcons") ? .caishen : nil
    }

    var body: some View {
        ZStack {
            if let theme = selected {
                CaishenView(theme: theme, onExit: { withAnimation(.easeInOut(duration: 0.25)) { selected = nil } })
                    .id(theme)
                    .transition(.opacity)
            } else {
                picker.transition(.opacity)
            }
        }
        .onAppear { Icon3D.preload() }
    }

    private var picker: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cardH = min(210, (h - 86) / 3 - 10)
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.02, blue: 0.06), Color(red: 0.07, green: 0.01, blue: 0.05), Color(red: 0.02, green: 0.0, blue: 0.02)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                RadialGradient(colors: [ArtPalette.gold.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 420)
                    .ignoresSafeArea()
                GoldSparks().ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        LobbyBackButton { onExit() }
                        CoinBalanceView(coins: gameState.availableCoins, height: 30, width: 130)
                        Spacer(minLength: 0)
                        SettingsButton { showSettings = true }
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 10).padding(.top, 4)
                    Text("Choose a machine")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.6), radius: 0, x: 1.5, y: 1.5)
                    ForEach(SlotTheme.allCases) { theme in
                        Button {
                            AudioManager.shared.play(.buttonTap)
                            HapticManager.shared.slotStart()
                            withAnimation(.easeInOut(duration: 0.25)) { selected = theme }
                        } label: {
                            SlotMachineCard(theme: theme, width: w - 24, height: cardH)
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityIdentifier("slotMachine_\(theme.rawValue)")
                        .accessibilityLabel(Text(verbatim: theme.title))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay(FilmOverlay())
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

/// 一台机器的招牌：主题色的底、金边、左边是角色（图没到时是最值钱的图案）、右边是名字、四个高分图案和「开玩」
struct SlotMachineCard: View {
    let theme: SlotTheme
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: theme.backdrop, startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 22)
                .fill(RadialGradient(colors: [theme.glow.opacity(0.5), .clear], center: UnitPoint(x: 0.22, y: 0.5), startRadius: 0, endRadius: width * 0.5))
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center))
                .padding(3)
            RoundedRectangle(cornerRadius: 22)
                .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 4)
            HStack(spacing: 6) {
                Group {
                    if theme.art(.hold) != nil {
                        MascotArtView(theme: theme, pose: .hold)
                            .frame(height: height * 1.06)
                            .shadow(color: .black.opacity(0.5), radius: 5, y: 4)
                    } else {
                        Icon3DView(kind: .symbol(.ingot, theme), size: height * 0.8)
                            .shadow(color: ArtPalette.gold.opacity(0.7), radius: 12)
                    }
                }
                .frame(width: width * 0.34, height: height, alignment: .bottom)
                VStack(alignment: .leading, spacing: height * 0.035) {
                    Text(verbatim: theme.title)
                        .font(.system(size: height * 0.19, weight: .black, design: .serif))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.7), radius: 0, x: 2, y: 2)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(verbatim: theme.tagline)
                        .font(.system(size: height * 0.075, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 2) {
                        ForEach([CaishenSymbol.ingot, .fu, .redEnvelope, .lantern], id: \.rawValue) { s in
                            Icon3DView(kind: .symbol(s, theme), size: height * 0.27)
                        }
                    }
                    Text("PLAY")
                        .font(.system(size: height * 0.1, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.4, green: 0.12, blue: 0))
                        .padding(.horizontal, height * 0.16).padding(.vertical, height * 0.03)
                        .background(GoldGloss(shape: Capsule()))
                        .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
            }
            .padding(.leading, 6)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.55), radius: 8, y: 5)
    }
}
