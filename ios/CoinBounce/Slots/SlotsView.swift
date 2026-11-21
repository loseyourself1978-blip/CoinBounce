import SwiftUI

// MARK: - v12.8 老虎机整屏：招牌、5×3 转轮、中奖线、下注和 SPIN、免费转、宝箱
extension PachinkoWallet {
    static func slots(_ s: GameState = .shared) -> PachinkoWallet {
        PachinkoWallet(balance: { s.availableCoins },
                       spend: { s.spendCoins($0) },
                       credit: { s.addCoins($0, source: .slot) })
    }
}

/// 转轮的时间表：第 i 列在开转后多少秒停
enum SlotsTiming {
    static let speed = 24.0          // 每秒滚过几格
    static let bounce = 0.2
    static func stopTimes(spin: SlotsSpin, fast: Bool) -> [Double] {
        var t: [Double] = []
        var time = fast ? 0.45 : 0.85
        var scatters = 0
        for r in 0..<SlotsMath.reels {
            // 前面已经出了两个免费转图案：后面的轮子多转一会儿（吊胃口）
            if scatters >= 2 && !spin.free && !fast { time += 0.8 }
            t.append(time)
            time += fast ? 0.16 : 0.3
            let w = SlotsMath.window(spin.stops)[r]
            if w.contains(.scatter) { scatters += 1 }
        }
        return t
    }
}

struct SlotsView: View {
    let onExit: () -> Void
    @StateObject private var game = SlotsGame(wallet: .slots())
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinStart: Date?
    @State private var stopTimes: [Double] = []
    @State private var spinToken = 0
    @State private var showAdUnavailableHint = false
    @State private var showSettings = false
    @State private var showPaytable = false
    @State private var banner: String?
    @State private var freeIntro: Int?
    @State private var coinFlyToken = 0
    @State private var coinFlyActive = false
    @State private var bunny = BunnyLine(text: "", pose: .idle)
    @State private var glow = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let frameW = w - 16
            let cell = min((frameW - 28) / 5, (h * 0.36) / 3)
            // 格子比图案高一点（转轮更大，上下两行有地方做圆筒的透视）
            let cellH = cell * (h > 700 ? 1.3 : 1.12)
            let free = game.inFreeSpins
            ZStack {
                SlotsBackdrop(free: free).ignoresSafeArea()
                LightPool(strength: 0.16).frame(width: w * 1.1, height: h * 0.3).position(x: w / 2, y: h * 0.2)
                VStack(spacing: 6) {
                    topBar.padding(.horizontal, 10).padding(.top, 4)
                    SlotsMarquee(free: free, freeLeft: game.freeSpinsLeft, glow: glow)
                        .frame(height: min(h * 0.11, 92))
                        .padding(.horizontal, 14)
                    if h > 640 {
                        SlotsPayStrip()
                            .frame(height: 40)
                            .padding(.horizontal, 12)
                    }
                    Spacer(minLength: 2)
                    ZStack {
                        SlotsReels(game: game, spinStart: spinStart, stopTimes: stopTimes, cell: cell, cellH: cellH, reduceMotion: reduceMotion)
                        if game.phase == .bonusPick || game.chestPrize != nil && game.phase == .showing {
                            SlotsChestPick(prize: game.chestPrize, cell: cell) { game.openChest() }
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        if let n = freeIntro {
                            VStack(spacing: 2) {
                                Text("FREE SPINS")
                                    .font(.system(size: 30, weight: .black, design: .rounded))
                                Text(verbatim: "× \(n)")
                                    .font(.system(size: 44, weight: .black, design: .rounded))
                                Text("All wins doubled")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                            .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                            .padding(.horizontal, 26).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.3, green: 0.05, blue: 0.4).opacity(0.94)))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ArtPalette.gold, lineWidth: 3))
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            .accessibilityIdentifier("slotsFreeIntro")
                        }
                        if let banner {
                            Text(banner)
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                                .shadow(color: ArtPalette.outline, radius: 0, x: 2.5, y: 2.5)
                                .shadow(color: ArtPalette.gold.opacity(0.9), radius: 14)
                                .lineLimit(1).minimumScaleFactor(0.5)
                                .padding(.horizontal, 20)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                                .allowsHitTesting(false)
                                .accessibilityIdentifier("slotsBanner")
                        }
                    }
                    .frame(width: frameW, height: cellH * 3 + 30)
                    Spacer(minLength: 2)
                    HStack(alignment: .bottom, spacing: 0) {
                        BunnyHostess(line: bunny, height: min(h * 0.26, 230), showBubble: false, groundShadow: true)
                            .frame(width: w * 0.3, alignment: .bottom)
                            .allowsHitTesting(false)
                        controls(width: w * 0.7 - 12)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                // 赢了：金币从转轮飞到左上角的余额
                if coinFlyActive {
                    WinCoinFly(from: CGPoint(x: w / 2, y: h * 0.45), to: CGPoint(x: 60, y: 22))
                        .id(coinFlyToken)
                        .allowsHitTesting(false)
                }
                if game.outOfCoins {
                    Text("Not enough coins. Watch an ad for +50!")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.8), lineWidth: 1))
                        .position(x: w / 2, y: h * 0.5)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("slotsNotice")
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
        .sheet(isPresented: $showPaytable) { SlotsPaytable() }
        .onAppear {
            glow = true
            #if DEBUG
            if debugStart() { return }
            #endif
            // 上次留下的免费转：接着转
            if game.freeSpinsLeft > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { spin() } }
        }
        .onDisappear { leave() }
        .onChange(of: scenePhase) { if $0 != .active { leave() } }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: banner)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: freeIntro)
        .animation(.easeInOut(duration: 0.25), value: game.phase)
        .onReceive(game.cues) { handle($0) }
    }

    // MARK: 转
    private func spin() {
        guard game.startSpin() else { return }
        beginReels()
    }

    /// 按时间表停轮；停稳后展示中奖，然后（自动 / 免费转）接着转
    private func beginReels() {
        guard let s = game.spin else { return }
        spinToken += 1
        let token = spinToken
        let fast = reduceMotion || game.auto || s.free
        let times = SlotsTiming.stopTimes(spin: s, fast: fast)
        stopTimes = times
        spinStart = Date()
        for (i, t) in times.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { if spinToken == token { game.reelStopped(i) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (times.last ?? 1) + SlotsTiming.bounce) {
            guard spinToken == token else { return }
            game.reelsStopped()
            afterStop(token: token)
        }
    }

    private func afterStop(token: Int) {
        guard let s = game.spin else { return }
        // 出了宝箱：等玩家开，开完由 chestOpened 那边接着往下走
        if s.bonus { return }
        let multiple = s.bet > 0 ? s.win / s.bet : 0
        var hold = s.win == 0 ? 0.25 : (multiple >= 10 ? 2.6 : 1.3)
        if s.freeSpinsAwarded > 0 { hold += 2.2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            guard spinToken == token else { return }
            proceed(token: token)
        }
    }

    private func proceed(token: Int) {
        guard spinToken == token else { return }
        game.finishShowing()
        if game.freeSpinsLeft > 0 || game.auto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if spinToken == token && game.phase == .idle { spin() } }
        }
    }

    private func handle(_ cue: SlotsCue) {
        let audio = AudioManager.shared, haptic = HapticManager.shared
        switch cue {
        case .spinStarted: audio.play(.slotSpin); haptic.slotStart()
        case .reelStopped: audio.play(.slotStop); haptic.slotColumnStop()
        case .result(let win, let multiple):
            guard win > 0 else { setPose(.idle); return }
            flyCoins()
            if multiple >= 30 {
                audio.play(.jackpotFanfare); audio.play(.cheer); haptic.jackpot()
                show(String(localized: "MEGA WIN!")); setPose(.jump)
            } else if multiple >= 10 {
                audio.play(.winBig); audio.play(.cheer); haptic.bigWin()
                show(String(localized: "BIG WIN!")); setPose(.cheer)
            } else {
                audio.play(.winSmall); haptic.smallWin(); setPose(.clap)
            }
        case .freeSpinsAwarded(let n):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                audio.play(.winBig); haptic.bonusTriggered()
                freeIntro = n
                setPose(.jump)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { freeIntro = nil }
            }
        case .freeSpinsEnded(let total):
            audio.play(.applause)
            show(String(localized: "FREE SPINS WON \(total)"))
            setPose(.cheer)
        case .bonusStarted:
            audio.play(.pkAttacker); haptic.bonusTriggered(); setPose(.blowKiss)
            #if DEBUG
            // 录屏：-slotsDemo bonus autopick 两秒后自动开一个
            if ProcessInfo.processInfo.arguments.contains("autopick") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { game.openChest() }
            }
            #endif
        case .chestOpened:
            audio.play(.winBig); audio.play(.cheer); haptic.bigWin()
            flyCoins()
            setPose(.cheer)
            let token = spinToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { proceed(token: token) }
        case .outOfCoins: audio.play(.noCoins)
        }
    }

    /// 金币飞向余额；飞完把这一层撤掉（不然会在余额上留几枚半透明的金币）
    private func flyCoins() {
        coinFlyToken += 1
        coinFlyActive = true
        let token = coinFlyToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if coinFlyToken == token { coinFlyActive = false } }
    }

    private func setPose(_ p: BunnyPose) {
        if bunny.pose != p { bunny = BunnyLine(text: "", pose: p) }
    }

    private func show(_ text: String) {
        banner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { if banner == text { banner = nil } }
    }

    private func leave() {
        spinToken += 1
        game.settle()
        gameState.saveNow()
    }

    #if DEBUG
    /// 返回 true = 这次是演示（不接着转上次留下的免费转）
    private func debugStart() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-slotsDemo") else { return false }
        game.debugReset()
        if gameState.availableCoins < 200 { gameState.addCoins(200 - gameState.availableCoins, source: .other) }
        // -slotsDemo free / bonus / big：第一转直接出免费转 / 宝箱 / 大奖
        var want: ((SlotsSpin) -> Bool)?
        if args.contains("free") { want = { $0.freeSpinsAwarded > 0 } }
        if args.contains("bonus") { want = { $0.bonus } }
        if args.contains("big") { want = { $0.win >= 15 && !$0.bonus && $0.freeSpinsAwarded == 0 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let want {
                var rng = PachinkoRandom(seed: 5)
                for _ in 0..<200_000 {
                    let stops = SlotsMath.randomStops(&rng)
                    if want(SlotsSpin.make(stops: stops, bet: 1, free: false)) {
                        if game.debugSpin(stops: stops) { beginReels() }
                        return
                    }
                }
            } else {
                game.auto = true
                spin()
            }
        }
        return true
    }
    #endif

    // MARK: 顶栏、赢了多少、下注和 SPIN
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

    private var winLine: some View {
        HStack(spacing: 8) {
            if game.lastWin > 0 && game.phase != .spinning {
                Text("WIN")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                ArtCoin(size: 24)
                Text(verbatim: "+\(game.lastWin)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: ArtPalette.outline, radius: 0, x: 1.5, y: 1.5)
                    .accessibilityIdentifier("slotsWin")
            } else if game.inFreeSpins {
                Text("FREE SPINS LEFT: \(game.freeSpinsLeft)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 1, green: 0.7, blue: 0.95))
                if game.freeWin > 0 {
                    Text(verbatim: "+\(game.freeWin)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ArtPalette.goldLight)
                }
            } else {
                Text("10 lines · wins pay ×bet")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func controls(width: CGFloat) -> some View {
        let busy = game.phase == .spinning || game.phase == .bonusPick
        return VStack(spacing: 10) {
            // 显示屏：赢了多少 / 还剩几次免费转
            winLine
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.04, blue: 0.02), .black], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                )
            HStack(spacing: 8) {
                // 下注
                HStack(spacing: 6) {
                    betStep(icon: "minus") { game.changeBet(-1) }
                        .disabled(busy || game.inFreeSpins)
                        .accessibilityIdentifier("slotsBetDown")
                    VStack(spacing: 0) {
                        Text("BET")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        Text(verbatim: "\(game.bet)")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(ArtPalette.goldLight)
                            .accessibilityIdentifier("slotsBet")
                    }
                    .frame(width: 40)
                    betStep(icon: "plus") { game.changeBet(1) }
                        .disabled(busy || game.inFreeSpins)
                        .accessibilityIdentifier("slotsBetUp")
                }
                .padding(.horizontal, 6).frame(height: 44)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.7), lineWidth: 1))
                Spacer(minLength: 0)
                Button {
                    AudioManager.shared.play(.buttonTap)
                    showPaytable = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .overlay(Circle().stroke(ArtPalette.gold.opacity(0.8), lineWidth: 1.5))
                }
                .accessibilityIdentifier("slotsPaytable")
                .accessibilityLabel(Text("Paytable"))
            }
            HStack(spacing: 8) {
                Button {
                    AudioManager.shared.play(.buttonTap)
                    game.auto.toggle()
                    if game.auto && game.phase == .idle { spin() }
                } label: {
                    Text("AUTO")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(game.auto ? Color(red: 0.35, green: 0.18, blue: 0.0) : ArtPalette.goldLight)
                        .frame(width: 58, height: 44)
                        .background(Group {
                            if game.auto { GoldGloss(shape: Capsule()) } else { Capsule().fill(Color.black.opacity(0.6)) }
                        })
                        .overlay(Capsule().stroke(ArtPalette.gold, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("slotsAuto")
                Button {
                    if game.phase == .showing { game.finishShowing() }
                    spin()
                } label: {
                    Text(game.inFreeSpins ? "FREE" : "SPIN")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.35, green: 0.18, blue: 0.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(GoldGloss(shape: RoundedRectangle(cornerRadius: 18)))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                        .specularSweep()
                }
                .buttonStyle(PressScaleStyle())
                .disabled(busy)
                .opacity(busy ? 0.6 : 1)
                .accessibilityIdentifier("slotsSpin")
            }
        }
        .frame(width: width)
    }

    private func betStep(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(Color(red: 0.35, green: 0.18, blue: 0.0))
                .frame(width: 30, height: 30)
                .background(GoldGloss(shape: Circle()))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 背景、招牌
struct SlotsBackdrop: View {
    let free: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: free ? [Color(red: 0.26, green: 0.04, blue: 0.4), Color(red: 0.08, green: 0.01, blue: 0.16)]
                                        : [Color(red: 0.05, green: 0.1, blue: 0.32), Color(red: 0.02, green: 0.02, blue: 0.1)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [(free ? Color(red: 1, green: 0.4, blue: 0.9) : Color(red: 0.3, green: 0.6, blue: 1)).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 420)
        }
        .animation(.easeInOut(duration: 0.6), value: free)
    }
}

struct SlotsMarquee: View {
    let free: Bool
    let freeLeft: Int
    let glow: Bool
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.3)
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.05, blue: 0.2), Color(red: 0.2, green: 0.02, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: h * 0.3).stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 4))
                    .shadow(color: ArtPalette.gold.opacity(glow ? 0.7 : 0.25), radius: glow ? 16 : 6)
                VStack {
                    MarqueeLights(count: 16).frame(height: 7)
                    Spacer(minLength: 0)
                    MarqueeLights(count: 16, phaseOffset: 1).frame(height: 7)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                VStack(spacing: -2) {
                    Text("BUNNY FORTUNE")
                        .font(.system(size: h * 0.36, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                        .specularSweep()
                    Text(free ? "FREE SPINS · ALL WINS ×2" : "5 REELS · 10 LINES")
                        .font(.system(size: h * 0.17, weight: .heavy, design: .rounded))
                        .kerning(h * 0.03)
                        .foregroundColor(Color(red: 1, green: 0.55, blue: 0.75))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 20)
            }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: glow)
        }
    }
}

/// 招牌下面的一条：最值钱的三样东西
struct SlotsPayStrip: View {
    var body: some View {
        HStack(spacing: 6) {
            badge(.seven, "5 IN A ROW", "×\(SlotsMath.pay(.seven, count: 5))")
            badge(.scatter, "3 OR MORE", String(localized: "FREE SPINS"))
            badge(.bonus, "3 CHESTS", "×\(SlotsMath.chestPrizes.max() ?? 0)")
        }
    }

    private func badge(_ s: SlotsSymbol, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 5) {
            SlotsSymbolView(symbol: s, size: 28, showRibbon: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                Text(verbatim: value)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(ArtPalette.goldLight)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ArtPalette.gold.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - 转轮
struct SlotsReels: View {
    @ObservedObject var game: SlotsGame
    let spinStart: Date?
    let stopTimes: [Double]
    let cell: CGFloat
    let cellH: CGFloat
    let reduceMotion: Bool

    static let lineColors: [Color] = [.red, .yellow, .green, .cyan, .orange, .pink, .mint, .purple, .blue, .white]

    var body: some View {
        let spinning = game.phase == .spinning
        let showing = game.phase == .showing || game.phase == .bonusPick
        let wins = showing ? (game.spin?.outcome.lineWins ?? []) : []
        let lit = showing ? litCells() : []
        return ZStack {
            // 机壳：金框 + 深色内胆
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 8, y: 5)
            RoundedRectangle(cornerRadius: 11)
                .fill(Color(red: 0.03, green: 0.02, blue: 0.08))
                .padding(7)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !spinning)) { ctx in
                let t = spinStart.map { ctx.date.timeIntervalSince($0) } ?? 1000
                HStack(spacing: 2) {
                    ForEach(0..<SlotsMath.reels, id: \.self) { r in
                        reel(r, time: t, spinning: spinning, lit: lit, dim: showing && !lit.isEmpty)
                    }
                }
            }
            .frame(width: cell * 5 + 8, height: cellH * 3)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // 转轮是圆筒：上下两头暗下去，中间一道高光
            LinearGradient(stops: [.init(color: .black.opacity(0.62), location: 0), .init(color: .clear, location: 0.2),
                                   .init(color: Color.white.opacity(0.06), location: 0.5),
                                   .init(color: .clear, location: 0.8), .init(color: .black.opacity(0.62), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: cell * 5 + 8, height: cellH * 3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            // 中奖线
            if !wins.isEmpty {
                Canvas { ctx, size in
                    let x0 = (size.width - (cell * 5 + 8)) / 2, y0 = (size.height - cellH * 3) / 2
                    for w in wins {
                        var p = Path()
                        let line = SlotsMath.lines[w.line]
                        for r in 0..<w.count {
                            let pt = CGPoint(x: x0 + (cell + 2) * CGFloat(r) + cell / 2, y: y0 + cellH * (CGFloat(line[r]) + 0.5))
                            if r == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                        let col = Self.lineColors[w.line % Self.lineColors.count]
                        ctx.stroke(p, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                .allowsHitTesting(false)
                .opacity(0.9)
            }
        }
        .accessibilityElement()
        .accessibilityIdentifier("slotsReels")
        .accessibilityLabel(Text("Reels"))
    }

    /// 亮起来的格子：中奖线上的、3 个以上的免费转图案、凑齐的宝箱
    private func litCells() -> Set<Int> {
        guard let s = game.spin else { return [] }
        var set = Set<Int>()
        for w in s.outcome.lineWins {
            for r in 0..<w.count { set.insert(r * 3 + SlotsMath.lines[w.line][r]) }
        }
        let win = SlotsMath.window(s.stops)
        if !s.free && s.outcome.scatters >= 3 {
            for r in 0..<5 { for k in 0..<3 where win[r][k] == .scatter { set.insert(r * 3 + k) } }
        }
        if s.bonus {
            for r in [0, 2, 4] { for k in 0..<3 where win[r][k] == .bonus { set.insert(r * 3 + k) } }
        }
        return set
    }

    private func reel(_ r: Int, time t: Double, spinning: Bool, lit: Set<Int>, dim: Bool) -> some View {
        let strip = SlotsMath.strips[r]
        let n = strip.count
        let stopAt = r < stopTimes.count ? stopTimes[r] : 0
        let final = Double((spinning ? game.spin?.stops[r] : nil) ?? game.stops[r])
        var p = final
        var rolling = false
        var bounce: CGFloat = 0
        if spinning {
            if t < stopAt {
                p = final + SlotsTiming.speed * (stopAt - t)
                rolling = true
            } else {
                // 落位：往下多冲一点再弹回来
                let u = min(1, (t - stopAt) / SlotsTiming.bounce)
                bounce = reduceMotion ? 0 : cellH * 0.16 * CGFloat(sin(u * .pi) * (1 - u))
            }
        }
        let base = Int(floor(p)), frac = CGFloat(p - floor(p))
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.9), Color(red: 0.82, green: 0.8, blue: 0.78)], startPoint: .leading, endPoint: .trailing)
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { k in
                    let sym = strip[((base + k) % n + n) % n]
                    let isLit = !rolling && k < 3 && lit.contains(r * 3 + k)
                    // 圆筒的透视：离窗口中线越远，图案越往后仰、越扁
                    let centerY = (CGFloat(k) + 0.5 - frac) * cellH + bounce
                    let rel = max(-1.4, min(1.4, (centerY - cellH * 1.5) / (cellH * 1.5)))
                    SlotsSymbolView(symbol: sym, size: cell * 0.8)
                        .frame(width: cell, height: cellH)
                        .scaleEffect(isLit ? 1.1 : 1)
                        .opacity(dim && !isLit ? 0.4 : 1)
                        .background(isLit ? RoundedRectangle(cornerRadius: 8).fill(ArtPalette.goldLight.opacity(0.55)).padding(3) : nil)
                        .overlay(isLit ? RoundedRectangle(cornerRadius: 8).stroke(ArtPalette.gold, lineWidth: 3).padding(3) : nil)
                        .blur(radius: rolling && !reduceMotion ? 1.6 : 0)
                        .rotation3DEffect(.degrees(Double(rel) * 30), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
                }
            }
            .offset(y: -frac * cellH + bounce)
        }
        .frame(width: cell, height: cellH * 3, alignment: .top)
        .clipped()
    }
}

// MARK: - 图案（全部用代码画）
struct SlotsSymbolView: View {
    let symbol: SlotsSymbol
    let size: CGFloat
    /// 小图标（赔付条里）不画下面的字带
    var showRibbon = true

    var body: some View {
        ZStack {
            switch symbol {
            case .cherry: FruitIcon(index: 5, size: size * 0.9)
            case .lemon: FruitIcon(index: 1, size: size * 0.9)
            case .grapes: FruitIcon(index: 2, size: size * 0.9)
            case .strawberry: FruitIcon(index: 3, size: size * 0.9)
            case .diamond:
                DiamondGemShape()
                    .fill(LinearGradient(colors: [Color(red: 0.7, green: 0.95, blue: 1), Color(red: 0.2, green: 0.6, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)], startPoint: .top, endPoint: .bottom))
                    .overlay(DiamondGemShape().stroke(ArtPalette.outline, lineWidth: max(1, size * 0.04)))
                    .overlay(DiamondGemShape().fill(LinearGradient(colors: [.white.opacity(0.7), .clear], startPoint: .topLeading, endPoint: .center)).padding(size * 0.12))
                    .frame(width: size * 0.84, height: size * 0.72)
            case .crown:
                CrownShape()
                    .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                    .overlay(CrownShape().stroke(ArtPalette.outline, lineWidth: max(1, size * 0.04)))
                    .frame(width: size * 0.86, height: size * 0.62)
                HStack(spacing: size * 0.13) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(i == 1 ? Color.red : Color(red: 0.2, green: 0.7, blue: 1)).frame(width: size * 0.1, height: size * 0.1)
                    }
                }
                .offset(y: size * 0.16)
            case .seven:
                Text(verbatim: "7")
                    .font(.system(size: size * 1.0, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.85, green: 0.05, blue: 0.15), Color(red: 0.5, green: 0, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: ArtPalette.goldLight, radius: 0, x: 1.5, y: 1.5)
                    .shadow(color: ArtPalette.outline, radius: 0, x: 2.5, y: 2.5)
            case .wild:
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.6, blue: 0.85), ArtPalette.magenta, ArtPalette.magentaDeep], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.6))
                    .overlay(Circle().stroke(ArtPalette.goldLight, lineWidth: max(1.5, size * 0.05)))
                BunnyArt(pose: .headshot)
                    .frame(width: size * 0.82, height: size * 0.82)
                    .clipShape(Circle())
                ribbon("WILD", color: ArtPalette.magentaDeep)
            case .scatter:
                StarShape()
                    .fill(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                    .overlay(StarShape().stroke(ArtPalette.outline, lineWidth: max(1, size * 0.04)))
                    .frame(width: size * 0.98, height: size * 0.98)
                    .shadow(color: ArtPalette.gold.opacity(0.9), radius: 5)
                ribbon("FREE", color: Color(red: 0.1, green: 0.5, blue: 0.2))
            case .bonus:
                // 宝箱
                VStack(spacing: 0) {
                    UnevenRoundedRectangle(topLeadingRadius: size * 0.2, topTrailingRadius: size * 0.2)
                        .fill(LinearGradient(colors: [Color(red: 0.75, green: 0.4, blue: 0.15), Color(red: 0.5, green: 0.22, blue: 0.06)], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.84, height: size * 0.3)
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(red: 0.6, green: 0.3, blue: 0.1), Color(red: 0.38, green: 0.16, blue: 0.04)], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.84, height: size * 0.36)
                }
                .overlay(Rectangle().fill(ArtPalette.gold).frame(width: size * 0.84, height: size * 0.06).offset(y: -size * 0.03))
                .overlay(RoundedRectangle(cornerRadius: 2).fill(ArtPalette.goldLight).frame(width: size * 0.16, height: size * 0.2).offset(y: size * 0.0))
                .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(ArtPalette.outline, lineWidth: max(1, size * 0.04)))
                .offset(y: -size * 0.06)
                ribbon("BONUS", color: Color(red: 0.7, green: 0.1, blue: 0.1))
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private func ribbon(_ text: String, color: Color) -> some View {
        if showRibbon {
            ribbonBody(text, color: color)
        }
    }

    private func ribbonBody(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: size * 0.22, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, size * 0.08).padding(.vertical, size * 0.02)
            .background(RoundedRectangle(cornerRadius: size * 0.06).fill(color))
            .overlay(RoundedRectangle(cornerRadius: size * 0.06).stroke(ArtPalette.goldLight, lineWidth: 1))
            .offset(y: size * 0.36)
    }
}

// MARK: - 宝箱小游戏：三个里点一个
struct SlotsChestPick: View {
    let prize: Int?
    let cell: CGFloat
    let onPick: () -> Void
    @State private var picked: Int?

    var body: some View {
        // 没人点（自动 / 离开时替玩家开）就算中间那个
        let shown = picked ?? (prize == nil ? nil : 1)
        return VStack(spacing: 8) {
            Text(prize == nil ? "PICK A CHEST" : "YOU WON")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
            if let prize {
                HStack(spacing: 5) {
                    ArtCoin(size: 30)
                    Text(verbatim: "+\(prize)")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                        .accessibilityIdentifier("slotsChestPrize")
                }
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    Button {
                        guard prize == nil, picked == nil else { return }
                        picked = i
                        onPick()
                    } label: {
                        SlotsSymbolView(symbol: .bonus, size: cell * 1.05)
                            .opacity(shown == nil || shown == i ? 1 : 0.35)
                            .scaleEffect(shown == i ? 1.12 : 1)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("slotsChest_\(i)")
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ArtPalette.gold, lineWidth: 3))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: prize)
        .accessibilityIdentifier("slotsChestPick")
    }
}

// MARK: - 赔付表
struct SlotsPaytable: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Line wins (× total bet)") {
                    ForEach([SlotsSymbol.seven, .crown, .diamond, .strawberry, .grapes, .lemon, .cherry], id: \.rawValue) { s in
                        HStack(spacing: 12) {
                            SlotsSymbolView(symbol: s, size: 38)
                            Spacer()
                            ForEach([3, 4, 5], id: \.self) { n in
                                VStack(spacing: 0) {
                                    Text(verbatim: "\(n)×").font(.caption2).foregroundColor(.secondary)
                                    Text(verbatim: "\(SlotsMath.pay(s, count: n))").font(.headline).monospacedDigit()
                                }
                                .frame(width: 44)
                            }
                        }
                    }
                }
                Section("Special symbols") {
                    special(.wild, "Wild: replaces any fruit, gem, crown or 7 on a line. Appears on reels 2, 3 and 4.")
                    special(.scatter, "Free: 3, 4 or 5 anywhere pay ×2, ×5 or ×20 and give 8, 12 or 20 free spins. Free-spin wins are doubled.")
                    special(.bonus, "Bonus: chests on reels 1, 3 and 5 together open the chest game. Pick one chest for ×4 to ×25.")
                }
                Section {
                    Text("10 fixed lines pay from the leftmost reel. Every win is a multiple of your total bet. Expected return is about 94%. Coins are virtual and have no real-world value.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Paytable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func special(_ s: SlotsSymbol, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            SlotsSymbolView(symbol: s, size: 44).padding(.bottom, 6)
            Text(text).font(.subheadline)
        }
    }
}
