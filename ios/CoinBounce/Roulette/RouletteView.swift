import SwiftUI
import Combine

// MARK: - v12.1 轮盘画面：转盘 + 兔女郎荷官 + 下注台 + 筹码
struct RouletteView: View {
    let onExit: () -> Void
    @StateObject private var game = RouletteGame()
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var spinStart: Date?
    @State private var wheelStart: Double = 0
    /// 球所在的号码（转动中 = 这一转开出的；转完留着，下一转开始时换）
    @State private var ballNumber: Int?
    @State private var lastTickPocket = -1
    @State private var lastTickAt = Date.distantPast
    @State private var line: BunnyLine?
    @State private var toast: String?
    @State private var toastToken = 0
    @State private var winFly = false
    @State private var roundToken = 0
    @State private var showAdUnavailableHint = false
    @State private var showSettings = false

    private let ticker = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad: CGFloat = 10
            let wheelD = min(w * 0.62, h * 0.32)
            let fixed: CGFloat = 40 + wheelD + 26 + RouletteTableView.dozenHeight + RouletteTableView.evenHeight + 54 + 58 + 18 + 56
            let rowH = min(62, max(30, (h - fixed) / 3))
            ZStack {
                RouletteBackdrop().ignoresSafeArea()
                // v12.3：赌桌上方的吊灯——一道宽光柱加转盘上的一圈光
                LightShafts(strength: 0.06, beams: [(0.5, 0, 0.2), (0.1, 22, 0.07), (0.9, -22, 0.07)])
                LightPool(strength: 0.14).frame(width: wheelD * 1.7, height: wheelD * 1.4).position(x: w / 2, y: 40 + wheelD * 0.62)
                VStack(spacing: 6) {
                    topBar.padding(.horizontal, pad).padding(.top, 4)
                    // 转盘（左）+ 兔女郎荷官和气泡（右）
                    HStack(alignment: .bottom, spacing: 0) {
                        ZStack {
                            RouletteWheelView(spinStart: spinStart, wheelStart: wheelStart, result: ballNumber)
                                .frame(width: wheelD, height: wheelD)
                            if game.phase == .result, let n = game.result {
                                resultBadge(n).transition(.scale(scale: 0.4).combined(with: .opacity))
                            }
                        }
                        .frame(width: wheelD, height: wheelD)
                        .padding(.leading, pad)
                        Spacer(minLength: 0)
                        VStack(spacing: 2) {
                            if let line {
                                SpeechBubble(text: line.text, tailOnLeft: false)
                                    .id(line.id)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                            Spacer(minLength: 0)
                            BunnyHostess(line: line, height: wheelD * 0.84, showBubble: false)
                        }
                        .frame(width: max(60, w - wheelD - pad * 2 - 4), height: wheelD)
                        .padding(.trailing, pad)
                    }
                    .frame(height: wheelD)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: line?.id)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: game.phase)
                    historyStrip.frame(height: 22).padding(.horizontal, pad)
                    RouletteTableView(game: game, rowHeight: rowH) { place($0) }
                        .padding(.horizontal, pad)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(ArtPalette.goldLight.opacity(0.9), lineWidth: 2).padding(.horizontal, pad - 1))
                    Spacer(minLength: 0)
                    chipRow.padding(.horizontal, pad)
                    actionRow.padding(.horizontal, pad)
                    Text("Number 35:1 · Dozen / Column 2:1 · Others 1:1")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.bottom, 4)
                }
                if winFly {
                    WinCoinFly(from: CGPoint(x: pad + wheelD / 2, y: 44 + wheelD / 2), to: CGPoint(x: 70, y: 24))
                        .allowsHitTesting(false)
                }
                if let toast {
                    Text(toast)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.8), lineWidth: 1))
                        .position(x: w / 2, y: 44 + wheelD + 40)
                        .transition(.opacity)
                        .accessibilityIdentifier("rouletteToast")
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
        }
        .overlay(FilmOverlay())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            say(String(localized: "Place your bets!"), pose: .blowKiss)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-rouletteDemo") { runDemoRound() }
            #endif
        }
        .onDisappear { game.creditPending() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { game.creditPending(); gameState.saveNow() }
        }
        .onReceive(ticker) { now in tick(now) }
    }

    // MARK: 顶栏：回大厅、余额、看广告、设置
    private var topBar: some View {
        HStack(spacing: 8) {
            LobbyBackButton {
                game.creditPending()
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

    private func resultBadge(_ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 62, height: 62)
                .background(Circle().fill(RouletteWheelFace.fill(RouletteTable.color(of: n))))
                .overlay(Circle().stroke(ArtPalette.goldLight, lineWidth: 3))
                .shadow(color: .black.opacity(0.6), radius: 5)
                .accessibilityIdentifier("rouletteResult")
            if game.lastReturn > 0 {
                Text("+\(game.lastReturn)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, Color.arcadeGold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: ArtPalette.outline, radius: 0, x: 1.5, y: 1.5)
            }
        }
    }

    // MARK: 最近开出的号码
    private var historyStrip: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
            ForEach(Array(game.history.enumerated()), id: \.offset) { i, n in
                Text("\(n)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(RouletteWheelFace.fill(RouletteTable.color(of: n))))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(i == 0 ? 0.9 : 0.25), lineWidth: 1))
                    .opacity(i == 0 ? 1 : 0.8)
            }
            Spacer(minLength: 0)
        }
        .clipped()
    }

    // MARK: 筹码面值 + 下注总额
    private var chipRow: some View {
        HStack(spacing: 10) {
            ForEach(RouletteGame.chips, id: \.self) { v in
                Button {
                    AudioManager.shared.play(.buttonTap)
                    game.chip = v
                } label: {
                    RouletteChip(value: v, size: 40, tint: RouletteChip.tint(forChip: v))
                        .overlay(Circle().stroke(ArtPalette.goldLight, lineWidth: game.chip == v ? 3 : 0).padding(-3))
                        .offset(y: game.chip == v ? -4 : 0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: game.chip)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chip_\(v)")
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text("BET")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(game.totalBet) / \(RouletteGame.maxTotalBet)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ArtPalette.goldLight)
                    .accessibilityIdentifier("totalBet")
            }
        }
        .frame(height: 50)
        .opacity(game.phase == .betting ? 1 : 0.55)
    }

    // MARK: 撤销 / 清空 / 重复 / 开转
    private var actionRow: some View {
        HStack(spacing: 8) {
            smallAction("arrow.uturn.backward", id: "undoBet", label: Text("Undo"), enabled: game.phase == .betting && game.totalBet > 0) { game.undo() }
            smallAction("trash.fill", id: "clearBets", label: Text("Clear bets"), enabled: game.phase == .betting && game.totalBet > 0) { game.clearBets() }
            smallAction("arrow.clockwise", id: "rebet", label: Text("Repeat last bet"), enabled: game.canRebet) {
                if !game.rebet() { showToast(String(localized: "Not enough coins")) }
            }
            Button {
                startSpin()
            } label: {
                Text("SPIN")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.25, green: 0.12, blue: 0.0))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom)).specularSweep(period: 5))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(ArtPalette.outline, lineWidth: 2))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!game.canSpin)
            .opacity(game.canSpin ? 1 : 0.5)
            .accessibilityIdentifier("spinRoulette")
        }
        .frame(height: 54)
    }

    private func smallAction(_ symbol: String, id: String, label: Text, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ArtPalette.gold.opacity(0.8), lineWidth: 1.5))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    // MARK: - 流程
    private func place(_ bet: RouletteBet) {
        switch game.place(bet) {
        case .placed:
            AudioManager.shared.play(.coinDrop)
            HapticManager.shared.coinDrop()
        case .overTableLimit:
            showToast(String(localized: "Table limit: \(RouletteGame.maxTotalBet) coins per spin"))
        case .insufficientCoins:
            AudioManager.shared.play(.noCoins)
            showToast(String(localized: "Not enough coins"))
        case .closed:
            break
        }
    }

    private func startSpin() {
        guard let n = game.spin() else { return }
        AudioManager.shared.play(.slotSpin)
        ballNumber = n
        lastTickPocket = -1
        spinStart = Date()
        say(String(localized: "No more bets!"), pose: .clap)
    }

    /// 每 1/30 秒：转动中按球经过的格子放咔嗒声；转完结算
    private func tick(_ now: Date) {
        guard let start = spinStart, let n = ballNumber else { return }
        let t = now.timeIntervalSince(start)
        if t >= RouletteSpinMath.duration {
            finishSpin(result: n)
            return
        }
        let pocket = RouletteSpinMath.pocketUnderBall(at: t, wheelStart: wheelStart, result: n)
        if pocket != lastTickPocket, now.timeIntervalSince(lastTickAt) > 0.05 {
            lastTickPocket = pocket
            lastTickAt = now
            AudioManager.shared.play(.baffleHit)
        }
    }

    private func finishSpin(result n: Int) {
        // 转子停在转完的角度上，球留在开出的格子里
        wheelStart = RouletteSpinMath.wheelAngle(at: RouletteSpinMath.duration, start: wheelStart)
            .truncatingRemainder(dividingBy: 2 * .pi)
        spinStart = nil
        ballNumber = n
        game.settle()
        AudioManager.shared.play(.slotStop)
        if game.lastReturn > 0 {
            let big = game.lastNet >= 20
            AudioManager.shared.play(big ? .winBig : .winSmall)
            if big { AudioManager.shared.play(.cheer); HapticManager.shared.bigWin() } else { HapticManager.shared.smallWin() }
            say(String(localized: "You win \(game.lastReturn)!"), pose: BunnyScript.pick(BunnyPose.celebrationPoses, { Double.random(in: 0..<1) }))
            winFly = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { winFly = false }
        } else {
            say(String(localized: "Better luck next time!"), pose: .idle)
        }
        roundToken += 1
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            guard token == roundToken, game.phase == .result else { return }
            game.newRound()
            say(String(localized: "Place your bets!"), pose: .blowKiss)
        }
    }

    private func say(_ text: String, pose: BunnyPose) { line = BunnyLine(text: text, pose: pose) }

    #if DEBUG
    /// 调试：-rouletteDemo 自动下几注、开转，一局接一局（截图和录屏用）
    private func runDemoRound() {
        let picks: [(RouletteBet, Int)] = [(.red, 5), (.straight(17), 2), (.dozen(2), 5), (.column(1), 2), (.odd, 5), (.straight(0), 1), (.high, 2)]
        for (i, pick) in picks.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + Double(i) * 0.35) {
                guard game.phase == .betting else { return }
                game.chip = pick.1
                place(pick.0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            startSpin()
            DispatchQueue.main.asyncAfter(deadline: .now() + RouletteSpinMath.duration + 4.2) { runDemoRound() }
        }
    }
    #endif

    private func showToast(_ text: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if token == toastToken { withAnimation(.easeIn(duration: 0.2)) { toast = nil } }
        }
    }
}

// MARK: - 背景：深绿绒面 + 暗角
struct RouletteBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.22, blue: 0.13), Color(red: 0.03, green: 0.30, blue: 0.17), Color(red: 0.01, green: 0.14, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.45)], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 20, endRadius: 620)
        }
    }
}

/// 赢了：一串金币从转盘飞到余额
struct WinCoinFly: View {
    let from: CGPoint
    let to: CGPoint
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                ArtCoin(size: 20)
                    .position(go ? to : CGPoint(x: from.x + CGFloat((i % 3) - 1) * 16, y: from.y + CGFloat(i / 3 - 1) * 16))
                    .opacity(go ? 0.15 : 1)
                    .animation(.easeIn(duration: 0.6).delay(Double(i) * 0.05), value: go)
            }
        }
        .onAppear { go = true }
    }
}
