import SwiftUI
import SpriteKit

// MARK: - v12.5 弹子机整屏：顶栏、台面 + 液晶、上皿、买珠、AUTO、手柄
extension PachinkoWallet {
    static func gameState(_ s: GameState = .shared) -> PachinkoWallet {
        PachinkoWallet(balance: { s.availableCoins },
                       spend: { s.spendCoins($0) },
                       credit: { s.addCoins($0, source: .pachinko) })
    }
}

struct PachinkoView: View {
    let onExit: () -> Void
    @StateObject private var game = PachinkoGame(wallet: .gameState())
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene: PachinkoScene?
    @State private var showAdUnavailableHint = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad: CGFloat = 10
            let controlsH: CGFloat = 112
            let bw = max(100, min(w - pad * 2, (h - 36 - controlsH - 24) / CGFloat(PachinkoConstants.boardAspect)))
            let bh = bw * CGFloat(PachinkoConstants.boardAspect)
            ZStack {
                RouletteBackdrop().ignoresSafeArea()
                LightPool(strength: 0.12).frame(width: bw * 1.2, height: bh).position(x: w / 2, y: 50 + bh / 2)
                VStack(spacing: 6) {
                    topBar.padding(.horizontal, pad).padding(.top, 4)
                    // 台面贴着顶栏；大屏多出来的高度留在台面和手柄之间（下一步放兔女郎）
                    board(width: bw, height: bh).padding(.top, 4)
                    Spacer(minLength: 0)
                    controls
                        .frame(height: controlsH)
                        .padding(.horizontal, pad + 4)
                        .padding(.bottom, 4)
                }
                if let text = noticeText {
                    Text(text)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.8), lineWidth: 1))
                        .frame(maxWidth: w - 40)
                        .position(x: w / 2, y: 50 + bh * 0.06 + 24)
                        .transition(.opacity)
                        .accessibilityIdentifier("pachinkoNotice")
                }
                if showAdUnavailableHint {
                    Text("No ad available right now. Check your connection and try again.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.85)))
                        .frame(maxWidth: w - 40)
                        .position(x: w / 2, y: 84)
                }
            }
            .onAppear { makeScene(bw: bw, bh: bh) }
            .onChange(of: bw) { _ in scene?.size = CGSize(width: bw, height: bh) }
        }
        .overlay(FilmOverlay())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onDisappear { leave() }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                leave()
            } else {
                scene?.resetClock()
                scene?.isPaused = false
            }
        }
        .animation(.easeInOut(duration: 0.2), value: game.notice)
    }

    private func makeScene(bw: CGFloat, bh: CGFloat) {
        guard scene == nil else { return }
        scene = PachinkoScene(game: game, size: CGSize(width: bw, height: bh))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-pachinkoDemo") {
            // 截图：余额补到 200，上皿装满，AUTO 连发
            if gameState.availableCoins < 200 { gameState.addCoins(200 - gameState.availableCoins, source: .other) }
            game.chip = 10
            for _ in 0..<5 { game.buy() }
            game.auto = true
        }
        #endif
    }

    /// 离开（回大厅、切后台）：在飞的珠子结算，存档
    private func leave() {
        game.settleInFlight()
        gameState.saveNow()
        scene?.isPaused = true
    }

    private var noticeText: String? {
        switch game.notice {
        case .outOfCoins: return String(localized: "Not enough coins. Watch an ad for +50!")
        case .foul: return String(localized: "Too weak — the ball rolled back.")
        case nil: return nil
        }
    }

    // MARK: 顶栏：回大厅、余额、看广告、设置
    private var topBar: some View {
        HStack(spacing: 8) {
            LobbyBackButton {
                leave()
                onExit()
            }
            CoinBalanceView(coins: gameState.availableCoins, height: 30, width: 130)
            Spacer(minLength: 0)
            if ads.adsEnabled {
                AdHUDButton(ads: ads, gameState: gameState, showUnavailableHint: $showAdUnavailableHint)
                    .frame(width: AdHUDButton.size.width, height: AdHUDButton.size.height)
            }
            SettingsButton { showSettings = true }
        }
        .frame(height: 36)
    }

    // MARK: 台面 + 液晶
    private func board(width bw: CGFloat, height bh: CGFloat) -> some View {
        typealias B = PachinkoBoard
        let lw = CGFloat(B.lcdX1 - B.lcdX0) * bw, lh = CGFloat(B.lcdY1 - B.lcdY0) * bw
        let lx = CGFloat(B.lcdX0) * bw + lw / 2
        let ly = (CGFloat(PachinkoConstants.boardAspect) - CGFloat(B.lcdY1)) * bw + lh / 2
        return ZStack {
            if let scene {
                SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
            }
            PachinkoReelView(machine: game.machine, spinStartedAt: game.spinStartedAt)
                .frame(width: lw - 4, height: lh - 4)
                .position(x: lx, y: ly)
                .allowsHitTesting(false)
        }
        .frame(width: bw, height: bh)
        .accessibilityIdentifier("pachinkoBoard")
    }

    // MARK: 上皿、买珠、AUTO、手柄
    private var controls: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    trayBadge
                    autoButton
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    ForEach(PachinkoConstants.chips, id: \.self) { v in
                        Button {
                            AudioManager.shared.play(.buttonTap)
                            game.chip = v
                            game.buy()
                        } label: {
                            Text("+\(v)")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 48, height: 40)
                                .background(Capsule().fill(LinearGradient(colors: [ArtPalette.magenta, ArtPalette.magentaDeep], startPoint: .top, endPoint: .bottom)))
                                .overlay(Capsule().stroke(ArtPalette.goldLight, lineWidth: game.chip == v ? 2.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pachinkoBuy_\(v)")
                    }
                }
            }
            Spacer(minLength: 0)
            PachinkoHandle(power: $game.power, isDown: $game.handleDown, size: 96)
                .accessibilityIdentifier("pachinkoHandle")
        }
    }

    private var trayBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(RadialGradient(colors: [.white, Color(white: 0.6)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9))
                .frame(width: 14, height: 14)
            Text("Tray")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
            Text("\(game.tray)/\(PachinkoConstants.trayCapacity)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(ArtPalette.goldLight)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.6), lineWidth: 1))
        .accessibilityIdentifier("pachinkoTray")
    }

    private var autoButton: some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            game.auto.toggle()
            if game.auto {
                game.resetPower()
                if game.tray == 0 { game.buy() }
            }
        } label: {
            Text("AUTO")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(game.auto ? .black : .white)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Capsule().fill(game.auto ? ArtPalette.gold : Color.black.opacity(0.55)))
                .overlay(Capsule().stroke(ArtPalette.gold, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pachinkoAuto")
    }
}

/// 发射手柄（2.2 节）：按住连发，上下拖改力度；外圈金色一段是推荐区
struct PachinkoHandle: View {
    @Binding var power: Double
    @Binding var isDown: Bool
    let size: CGFloat
    @State private var dragStart: (y: CGFloat, power: Double)?

    /// 力度 0…1 对应 -135°…+135°（0° 朝上）
    private func angle(_ p: Double) -> Angle { .degrees(-135 + 270 * p) }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.35), Color(white: 0.08)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.6))
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(4)
            Circle()
                .trim(from: PachinkoConstants.sweetZone.lowerBound * 0.75, to: PachinkoConstants.sweetZone.upperBound * 0.75)
                .stroke(ArtPalette.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(4)
            Capsule()
                .fill(isDown ? ArtPalette.gold : ArtPalette.goldLight)
                .frame(width: 8, height: size * 0.34)
                .offset(y: -size * 0.17)
                .rotationEffect(angle(power))
            Circle()
                .fill(isDown ? ArtPalette.magenta : ArtPalette.magentaDeep)
                .frame(width: size * 0.3, height: size * 0.3)
                .overlay(Circle().stroke(ArtPalette.goldLight, lineWidth: 1.5))
        }
        .frame(width: size, height: size)
        .shadow(color: isDown ? ArtPalette.gold.opacity(0.6) : .clear, radius: 8)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragStart == nil {
                        dragStart = (v.startLocation.y, power)
                        isDown = true
                    }
                    if let d = dragStart {
                        power = min(1, max(0, d.power + Double(d.y - v.location.y) / 160))
                    }
                }
                .onEnded { _ in
                    dragStart = nil
                    isDown = false
                }
        )
        .accessibilityLabel(Text("Power"))
        .accessibilityValue(Text("\(Int((power * 100).rounded()))%"))
    }
}
