import SwiftUI
import StoreKit

// MARK: - v13 老虎机「财神到」整屏：顶部四档奖池、5×3 转轮、锁定重转、天降财神、分档的大奖演出
/// v13.2：同一套画面和玩法带三个主题（财神、西游记、雅典娜），见 SlotTheme
struct CaishenView: View {
    let theme: SlotTheme
    let onExit: () -> Void
    @StateObject private var game: CaishenGame

    init(theme: SlotTheme = .caishen, onExit: @escaping () -> Void) {
        self.theme = theme
        self.onExit = onExit
        // 每台机器各存各的下注、统计和 GRAND 奖池
        _game = StateObject(wrappedValue: CaishenGame(wallet: .slots(), store: CaishenSaveStore(key: theme.saveKey)))
    }

    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview
    @State private var spinStart: Date?
    @State private var stopTimes: [Double] = []
    @State private var spinToken = 0
    @State private var showAdUnavailableHint = false
    @State private var showSettings = false
    @State private var showPaytable = false
    @State private var coinFlyToken = 0
    @State private var coinFlyActive = false
    /// 财神正在撒钱：这次给多少金币
    @State private var gift: Int?
    @State private var giftShown = 0.0
    /// 大奖演出
    @State private var celebration: Celebration?
    @State private var celebrationShown = 0.0
    /// 锁定重转：空格正在转
    @State private var respinning = false
    @State private var featureBanner = false
    @State private var bob = false
    /// 大奖出来时字弹一下、屏幕闪一下
    /// 机器旁边的财神现在是哪个动作
    @State private var mascot: SlotTheme.Pose = .hold
    @State private var mascotPop: CGFloat = 1
    @State private var mascotToken = 0
    @State private var punch: CGFloat = 1
    /// v13.7 分享大奖：演出里数字滚完时截的图和这次的奖；演出结束后「分享」按钮亮几秒
    @State private var shareShot: UIImage?
    @State private var shareOffer: Celebration?
    @State private var shareToken = 0
    @State private var flash = 0.0

    struct Celebration: Equatable {
        var amount: Int
        /// 0 大奖、1 巨奖、2 超级大奖、3 GRAND
        var tier: Int
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let frameW = w - 16
            let cell = min((frameW - 28) / 5, (h * 0.34) / 3)
            let cellH = cell * (h > 760 ? 1.32 : (h > 700 ? 1.18 : 1.05))
            ZStack {
                CaishenBackdrop(theme: theme).ignoresSafeArea()
                if !reduceMotion { GoldSparks().ignoresSafeArea().allowsHitTesting(false) }
                VStack(spacing: 6) {
                    topBar.padding(.horizontal, 10).padding(.top, 4)
                    CaishenJackpots(game: game)
                        .frame(height: min(h * 0.135, 108))
                        .padding(.horizontal, 10)
                    CaishenTitle(theme: theme)
                        .frame(height: min(h * 0.06, 46))
                    Spacer(minLength: 2)
                    ZStack {
                        CaishenReels(game: game, spinStart: spinStart, stopTimes: stopTimes, cell: cell, cellH: cellH,
                                     respinning: respinning, reduceMotion: reduceMotion)
                        if featureBanner {
                            VStack(spacing: -2) {
                                Title3D(text: String(localized: "HOLD & RESPIN"), tint: UIColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 1))
                                    .frame(width: frameW * 0.8)
                                Text("Fill all 15 for the GRAND")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                            .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color(theme.enamel).opacity(0.95)).overlay(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.45))))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ArtPalette.gold, lineWidth: 3))
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            .accessibilityIdentifier("caishenFeatureBanner")
                        }
                    }
                    .frame(width: frameW, height: cellH * 3 + 30)
                    Spacer(minLength: 2)
                    HStack(alignment: .bottom, spacing: 0) {
                        // 财神站在左下角（撒钱时飞到上面去，这里先藏起来）
                        // v13.1c：财神本人（hj 出的图）。平时捧着元宝，小奖挥手，大奖欢呼，锁定重转时拱手
                        Group {
                            if theme.art(mascot) != nil {
                                MascotArtView(theme: theme, pose: mascot)
                            } else {
                                // 角色图还没到：先放这台机器最值钱的图案
                                Icon3DView(kind: .symbol(.ingot, theme), size: w * 0.26)
                            }
                        }
                            .id(mascot)
                            .transition(.identity)
                            .frame(width: w * 0.3, height: min(h * 0.24, 200), alignment: .bottom)
                            .scaleEffect(bob ? 1.025 : 0.985, anchor: .bottom)
                            .scaleEffect(mascotPop, anchor: .bottom)
                            .shadow(color: .black.opacity(0.5), radius: 5, y: 4)
                            .opacity(gift == nil && celebration == nil ? 1 : 0)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("caishenMascot")
                        controls(width: w * 0.7 - 12)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                if coinFlyActive {
                    WinCoinFly(from: CGPoint(x: w / 2, y: h * 0.5), to: CGPoint(x: 60, y: 22))
                        .id(coinFlyToken)
                        .allowsHitTesting(false)
                }
                if let gift { giftOverlay(gift, w: w, h: h) }
                if let celebration { celebrationOverlay(celebration, w: w, h: h) }
                if let offer = shareOffer, celebration == nil {
                    Button {
                        let card = ShareCard.render(shot: shareShot, headline: String(localized: "BIG WIN!"), amount: offer.amount, machine: theme.title)
                        shareOffer = nil
                        ShareCard.present(card, amount: offer.amount, machine: theme.title)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .black))
                            Text("Share this win").font(.system(size: 18, weight: .black, design: .rounded))
                        }
                        .foregroundColor(Color(red: 0.25, green: 0.1, blue: 0))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(GoldGloss(shape: Capsule()))
                        .overlay(Capsule().stroke(ArtPalette.outline, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                    }
                    .accessibilityIdentifier("slotsShareWin")
                    .position(x: w / 2, y: h * 0.715)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
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
        .sheet(isPresented: $showPaytable) { CaishenPaytable().environment(\.slotTheme, theme) }
        .environment(\.slotTheme, theme)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { bob = true }
            #if DEBUG
            Icon3D.debugDumpIfAsked()
            debugStart()
            #endif
        }
        .onDisappear { leave() }
        .onChange(of: scenePhase) { if $0 != .active { leave() } }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: featureBanner)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: gift)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: celebration)
        .animation(.easeInOut(duration: 0.25), value: game.phase)
        .onReceive(game.cues) { handle($0) }
    }

    // MARK: 天降财神
    private func giftOverlay(_ amount: Int, w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            // 财神身后的金光
            RadialGradient(colors: [ArtPalette.goldLight.opacity(0.85), ArtPalette.gold.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: w * 0.62)
                .frame(width: w * 1.3, height: w * 1.3)
                .position(x: w / 2, y: h * 0.36)
            if !reduceMotion {
                SunRays(color: ArtPalette.goldLight)
                    .frame(width: w * 2.2, height: w * 2.2)
                    .position(x: w / 2, y: h * 0.34)
                    .blendMode(.plusLighter)
            }
            CoinRain()
            if !reduceMotion { CoinBurst(count: 36).position(x: w / 2, y: h * 0.34) }
            VStack(spacing: -6) {
                if theme.art(.cheer) != nil {
                    MascotArtView(theme: theme, pose: .cheer)
                        .frame(height: h * 0.4)
                        .shadow(color: ArtPalette.gold, radius: 24)
                } else {
                    // 角色图还没到：先放这台机器最值钱的图案
                    Icon3DView(kind: .symbol(.ingot, theme), size: h * 0.3)
                        .shadow(color: ArtPalette.gold, radius: 24)
                }
                Title3D(text: theme.giftTitle, tint: theme == .caishen ? UIColor(red: 0.95, green: 0.1, blue: 0.08, alpha: 1) : UIColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 1))
                    .frame(width: w * 0.86)
                HStack(spacing: 8) {
                    Icon3DView(kind: .symbol(.coin), size: 58)
                    CountingText(value: giftShown, prefix: "+")
                        .font(.system(size: 62, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color(red: 0.55, green: 0.02, blue: 0.04), radius: 0, x: 3, y: 3)
                        .shadow(color: ArtPalette.gold.opacity(0.9), radius: 12)
                }
            }
            .padding(.horizontal, 10)
            .scaleEffect(punch)
            .position(x: w / 2, y: h * 0.42)
            // 从屏幕上面降下来
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .accessibilityElement()
        .accessibilityIdentifier("caishenGift")
        .accessibilityLabel(Text(verbatim: theme.giftTitle))
    }

    // MARK: 大奖演出
    private func celebrationOverlay(_ c: Celebration, w: CGFloat, h: CGFloat) -> some View {
        let title: String = [String(localized: "BIG WIN!"), String(localized: "MEGA WIN!"), String(localized: "SUPER WIN!"), "GRAND JACKPOT"][min(3, c.tier)]
        let hot = theme == .caishen ? UIColor(red: 0.95, green: 0.1, blue: 0.08, alpha: 1) : UIColor(red: 0.95, green: 0.1, blue: 0.08, alpha: 1)
        let tint: UIColor = [hot, hot,
                             UIColor(red: 0.62, green: 0.12, blue: 0.9, alpha: 1), UIColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 1)][min(3, c.tier)]
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            // 字后面：一团火色的光 + 慢慢转的光芒
            RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.1).opacity(0.85), Color(red: 1, green: 0.2, blue: 0.05).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: w * 0.75)
                .frame(width: w * 1.5, height: w * 1.5)
                .position(x: w / 2, y: h * 0.4)
            if !reduceMotion {
                FestivalOverlay(festival: Festival.current).ignoresSafeArea()   // v13.9：圣诞飘雪、新年烟花
                SunRays(color: ArtPalette.goldLight)
                    .frame(width: w * 2.2, height: w * 2.2)
                    .position(x: w / 2, y: h * 0.4)
                    .blendMode(.plusLighter)
            }
            CoinRain(count: 30 + c.tier * 22)
            if !reduceMotion { CoinBurst(count: 26 + c.tier * 12).position(x: w / 2, y: h * 0.4) }
            VStack(spacing: -4) {
                if theme.art(.cheer) != nil {
                    MascotArtView(theme: theme, pose: .cheer)
                        .frame(height: h * 0.26)
                        .shadow(color: ArtPalette.gold.opacity(0.9), radius: 18)
                        .padding(.bottom, 2)
                }
                Title3D(text: title, tint: tint)
                    .frame(width: w * (0.92 + CGFloat(c.tier) * 0.02))
                    .accessibilityIdentifier("caishenCelebration")
                HStack(spacing: 8) {
                    Icon3DView(kind: .symbol(.coin), size: 64)
                    CountingText(value: celebrationShown, prefix: "+")
                        .font(.system(size: 70, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color(red: 0.55, green: 0.02, blue: 0.04), radius: 0, x: 3.5, y: 3.5)
                        .shadow(color: ArtPalette.gold.opacity(0.9), radius: 14)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .padding(.horizontal, 10)
            .scaleEffect(punch)
            .position(x: w / 2, y: h * 0.4)
            .transition(.scale(scale: 0.2).combined(with: .opacity))
            // 出来的一瞬间闪一下白
            Color.white.opacity(flash).ignoresSafeArea().allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { endCelebration() }
    }

    // MARK: 转
    private func spin() {
        guard game.startSpin() else { return }
        beginReels()
    }

    /// 前四列在任意一条中奖线上从左连成四个相同图案（百搭可以替）
    static func fourInARow(_ win: [[CaishenSymbol]]) -> Bool {
        for line in CaishenMath.lines {
            var sym: CaishenSymbol?
            var ok = true
            for r in 0..<4 {
                let x = win[r][line[r]]
                if x == .wild { continue }
                guard x.isLine else { ok = false; break }
                if let s = sym, s != x { ok = false; break }
                sym = x
            }
            if ok && sym != nil { return true }
        }
        return false
    }

    private func beginReels() {
        guard let s = game.spin else { return }
        shareOffer = nil
        spinToken += 1
        let token = spinToken
        let fast = reduceMotion || game.auto
        // 前面已经出了 4 枚以上金币：后面的轮子多转一会儿
        var times: [Double] = []
        var time = fast ? 0.45 : 0.85
        var coins = 0
        let win = CaishenMath.window(s.stops)
        for r in 0..<CaishenMath.reels {
            if coins >= 4 && !fast { time += 0.7 }
            // v13.7 大奖爽感：前四列已经在某条线上连成四个（只差最后一列就是五连），最后一列多转一会儿吊一下胃口
            else if r == CaishenMath.reels - 1 && !fast && Self.fourInARow(win) { time += 0.9 }
            times.append(time)
            time += fast ? 0.16 : 0.3
            coins += win[r].filter { $0 == .coin }.count
        }
        stopTimes = times
        spinStart = Date()
        for (i, t) in times.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { if spinToken == token { game.reelStopped(i) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (times.last ?? 1) + SlotsTiming.bounce) {
            guard spinToken == token else { return }
            game.reelsStopped()
            if game.phase == .showing { holdThenProceed(token: token) }
        }
    }

    /// 展示一会儿中奖，然后（自动）接着转
    private func holdThenProceed(token: Int, extra: Double = 0) {
        let win = game.lastWin
        let multiple = game.bet > 0 ? win / game.bet : 0
        let hold = (win == 0 ? 0.25 : (multiple >= 10 ? 0.6 : 1.3)) + extra
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            guard spinToken == token, celebration == nil else { return }
            proceed(token: token)
        }
    }

    private func proceed(token: Int) {
        guard spinToken == token else { return }
        game.finishShowing()
        if game.auto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if spinToken == token && game.phase == .idle { spin() } }
        }
    }

    private func handle(_ cue: CaishenCue) {
        let audio = AudioManager.shared, haptic = HapticManager.shared
        let token = spinToken
        switch cue {
        case .spinStarted: audio.play(.slotSpin); haptic.slotStart(); setMascot(.hold)
        case .reelStopped: audio.play(.slotStop); haptic.slotColumnStop()
        case .result(let win, let multiple):
            guard win > 0 else { return }
            flyCoins()
            if multiple >= 10 {
                // 有财神或锁定重转在后面排着：这里只响一声，演出留给后面
                if game.spin?.gift == nil && game.spin?.feature == nil { celebrate(amount: win, multiple: multiple, grand: false) }
                else { audio.play(.winBig); haptic.bigWin() }
            } else {
                audio.play(.winSmall); haptic.smallWin()
                setMascot(.wave, backAfter: 1.8)
            }
        case .gift(let win):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard spinToken == token else { return }
                audio.play(.jackpotFanfare); audio.play(.cheer); haptic.jackpot()
                giftShown = 0
                gift = win
                punchIn()
                withAnimation(.easeOut(duration: 1.6).delay(0.5)) { giftShown = Double(win) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                    guard spinToken == token else { return }
                    gift = nil
                    flyCoins()
                    game.collectGift()
                    if game.phase == .showing { holdThenProceed(token: token, extra: 0.6) }
                }
            }
        case .featureStarted:
            audio.play(.pkAttacker); haptic.bonusTriggered()
            setMascot(.greet)
            featureBanner = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard spinToken == token else { return }
                featureBanner = false
                respinRound(token: token)
            }
        case .respin(let landed, _):
            if landed > 0 { audio.play(.coinDrop); audio.play(.winSmall); haptic.coinDrop() } else { audio.play(.slotStop) }
        case .featureEnded(let win, let full):
            respinning = false
            flyCoins()
            let multiple = game.bet > 0 ? win / game.bet : 0
            celebrate(amount: win, multiple: max(10, multiple), grand: full)
        case .outOfCoins: audio.play(.noCoins)
        }
    }

    /// 锁定重转的一轮：空格转一会儿，然后看落了几枚
    private func respinRound(token: Int) {
        guard spinToken == token, game.phase == .feature else { return }
        respinning = true
        AudioManager.shared.play(.slotSpin)
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.5 : 0.95)) {
            guard spinToken == token, game.phase == .feature else { return }
            respinning = false
            if game.nextRespin() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { respinRound(token: token) }
            }
        }
    }

    private func celebrate(amount: Int, multiple: Int, grand: Bool) {
        let audio = AudioManager.shared, haptic = HapticManager.shared
        let tier = grand ? 3 : (multiple >= 80 ? 2 : (multiple >= 30 ? 1 : 0))
        if tier >= 1 { audio.play(.jackpotFanfare); haptic.jackpot() } else { audio.play(.winBig); haptic.bigWin() }
        audio.play(.cheer)
        if tier >= 2 { audio.play(.applause) }
        celebrationShown = 0
        celebration = Celebration(amount: amount, tier: tier)
        GameCenter.shared.report(amount, to: GameCenter.slotsBiggestWin)
        GameCenter.shared.bigWin(onMachine: theme.rawValue)
        if grand { GameCenter.shared.unlock(GameCenter.achGrand) }
        punchIn()
        flash = 0.75
        withAnimation(.easeOut(duration: 0.45)) { flash = 0 }
        let roll = 1.2 + Double(tier) * 0.6
        withAnimation(.easeOut(duration: roll).delay(0.3)) { celebrationShown = Double(amount) }
        let token = spinToken
        // 数字滚完、金币还在飞的时候截一张图，留给分享卡片
        shareShot = nil
        if tier >= 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + roll + 0.7) {
                guard spinToken == token, celebration != nil else { return }
                shareShot = ShareCard.windowShot()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + roll + 1.6) {
            guard spinToken == token else { return }
            endCelebration()
        }
    }

    /// 换财神的动作（换的时候弹一下）；backAfter 秒后回到捧元宝
    private func setMascot(_ pose: SlotTheme.Pose, backAfter: Double? = nil) {
        mascotToken += 1
        let token = mascotToken
        if mascot != pose {
            mascot = pose
            mascotPop = 1.12
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 10)) { mascotPop = 1 }
        }
        if let backAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + backAfter) { if mascotToken == token { setMascot(.hold) } }
        }
    }

    /// 字先放大再弹回来
    private func punchIn() {
        punch = 1.35
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 9).delay(0.12)) { punch = 1 }
    }

    private func endCelebration() {
        guard let ended = celebration else { return }
        celebration = nil
        setMascot(.cheer, backAfter: 2.2)
        // 大奖演出结束后，合适的时候请玩家评分（自动转的时候不打断）
        if !game.auto, ReviewPrompt().recordBigWin() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { requestReview() }
        } else if !game.auto, ended.tier >= 1, shareShot != nil {
            // v13.7：同一次大奖只出一样——没请评分的时候，亮 8 秒「分享」按钮（下一转开始就收起）
            shareToken += 1
            let t = shareToken
            shareOffer = ended
            #if DEBUG
            // -dumpShareCard <路径>：把分享卡片写成 PNG（模拟器上检查卡片长什么样）
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-dumpShareCard"), i + 1 < args.count {
                let card = ShareCard.render(shot: shareShot, headline: String(localized: "BIG WIN!"), amount: ended.amount, machine: theme.title)
                try? card.pngData()?.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { if shareToken == t { shareOffer = nil } }
        }
        let token = spinToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proceed(token: token) }
    }

    private func flyCoins() {
        coinFlyToken += 1
        coinFlyActive = true
        let token = coinFlyToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if coinFlyToken == token { coinFlyActive = false } }
    }

    private func leave() {
        spinToken += 1
        respinning = false
        featureBanner = false
        gift = nil
        celebration = nil
        game.settle()
        gameState.saveNow()
    }

    #if DEBUG
    /// -slotsDemo [feature | gift | big | super]：第一转直接出锁定重转 / 财神 / 大奖；不带参数就自动转
    private func debugStart() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-slotsDemo") else { return }
        if gameState.availableCoins < 200 { gameState.addCoins(200 - gameState.availableCoins, source: .other) }
        var want: ((CaishenMath.Outcome) -> Bool)?
        if args.contains("feature") { want = { $0.triggers } }
        if args.contains("big") { want = { $0.linePay >= 15 && !$0.triggers } }
        if args.contains("gift") { want = { $0.linePay == 0 && !$0.triggers } }
        // super：中奖线合计 80 倍以上（超级大奖的演出；商店预览视频用）
        if args.contains("super") { want = { $0.linePay >= 80 && !$0.triggers } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let want {
                game.changeBet(args.contains("super") ? 3 : 2)
                var rng = PachinkoRandom(seed: 5)
                for _ in 0..<(args.contains("super") ? 6_000_000 : 400_000) {
                    let stops = CaishenMath.randomStops(&rng)
                    if want(CaishenMath.evaluate(CaishenMath.window(stops))) {
                        if game.debugSpin(stops: stops, gift: args.contains("gift") ? 20 : nil, noGift: !args.contains("gift")) { beginReels() }
                        return
                    }
                }
            } else {
                game.auto = true
                spin()
            }
        }
    }
    #endif

    // MARK: 顶栏、显示屏、下注和 SPIN
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
            if game.phase == .feature {
                Text("RESPINS")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                HStack(spacing: 4) {
                    ForEach(0..<CaishenMath.respins, id: \.self) { i in
                        Circle()
                            .fill(i < game.respinsLeft ? ArtPalette.gold : Color.white.opacity(0.18))
                            .frame(width: 12, height: 12)
                    }
                }
                .accessibilityElement()
                .accessibilityIdentifier("caishenRespins")
                .accessibilityLabel(Text(verbatim: "\(game.respinsLeft)"))
                ArtCoin(size: 20)
                Text(verbatim: "\(game.lockedTotal)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ArtPalette.goldLight)
            } else if game.lastWin > 0 && game.phase != .spinning {
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
            } else {
                Text("6 coins start Hold & Respin")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func controls(width: CGFloat) -> some View {
        let busy = !game.canSpin
        return VStack(spacing: 10) {
            winLine
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.02, blue: 0.02), .black], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                )
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    betStep(icon: "minus") { game.changeBet(-1) }
                        .disabled(busy)
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
                        .disabled(busy)
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
                    Text("SPIN")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.45, green: 0.05, blue: 0.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(GoldGloss(shape: RoundedRectangle(cornerRadius: 18)))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                        .specularSweep()
                }
                .buttonStyle(PressScaleStyle())
                .disabled(busy || celebration != nil)
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

// MARK: - 背景：深红的殿堂，上面两盏灯笼的暖光，底下一层金色的回纹
struct CaishenBackdrop: View {
    var theme: SlotTheme = .caishen
    var body: some View {
        ZStack {
            LinearGradient(colors: theme.backdrop, startPoint: .top, endPoint: .bottom)
            if let bg = theme.background {
                // v13.3：背景画。上面压一层暗色，转轮、奖池和按钮上的字才清楚
                GeometryReader { geo in
                    Image(uiImage: bg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .black.opacity(0.12), location: 0.3),
                                       .init(color: .black.opacity(0.2), location: 0.7), .init(color: .black.opacity(0.6), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            RadialGradient(colors: [theme.glow.opacity(theme.background == nil ? 0.4 : 0.15), .clear], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 420)
            // 斜格的暗纹（窗棂）
            Canvas { ctx, size in
                let step: CGFloat = 34
                var p = Path()
                var x = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    p.move(to: CGPoint(x: x + size.height, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                ctx.stroke(p, with: .color(ArtPalette.gold.opacity(0.055)), lineWidth: 1)
            }
            RadialGradient(colors: [.clear, Color.black.opacity(0.5)], center: .center, startRadius: 220, endRadius: 620)
        }
    }
}

/// 机器的名字
struct CaishenTitle: View {
    var theme: SlotTheme = .caishen
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(spacing: h * 0.2) {
                Icon3DView(kind: .symbol(.ingot, theme), size: h * 1.25)
                Text(verbatim: theme.title)
                    .font(.system(size: h * 0.78, weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(red: 0.4, green: 0.0, blue: 0.02), radius: 0, x: 2, y: 2)
                    .shadow(color: ArtPalette.gold.opacity(0.7), radius: 8)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .specularSweep()
                Icon3DView(kind: .symbol(.ingot, theme), size: h * 1.25)
            }
            .frame(width: geo.size.width, height: h)
        }
    }
}

// MARK: - 顶部的四档奖池
struct CaishenJackpots: View {
    @ObservedObject var game: CaishenGame

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: h * 0.06) {
                plaque("GRAND", value: game.jackpot(CaishenMath.grandPrize), tint: FortuneCoin.tint("GRAND"), big: true)
                    .frame(height: h * 0.52)
                HStack(spacing: 6) {
                    plaque("MAJOR", value: game.jackpot(CaishenMath.majorPrize), tint: FortuneCoin.tint("MAJOR"), big: false)
                    plaque("MINOR", value: game.jackpot(CaishenMath.minorPrize), tint: FortuneCoin.tint("MINOR"), big: false)
                    plaque("MINI", value: game.jackpot(CaishenMath.miniPrize), tint: FortuneCoin.tint("MINI"), big: false)
                }
                .frame(height: h * 0.42)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("caishenJackpots")
    }

    private func plaque(_ name: String, value: Int, tint: Color, big: Bool) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.28)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.55), Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: h * 0.28)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    .padding(2)
                RoundedRectangle(cornerRadius: h * 0.28)
                    .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: big ? 3 : 2)
                HStack(spacing: h * 0.14) {
                    Text(verbatim: name)
                        .font(.system(size: h * (big ? 0.4 : 0.34), weight: .black, design: .rounded))
                        .foregroundColor(ArtPalette.goldLight)
                        .shadow(color: .black.opacity(0.7), radius: 0, x: 1, y: 1)
                    if big { Spacer(minLength: 0); ArtCoin(size: h * 0.5) }
                    CountingText(value: Double(value))
                        .font(.system(size: h * (big ? 0.62 : 0.44), weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.7), radius: 0, x: 1, y: 1.5)
                        .animation(.easeOut(duration: 0.5), value: value)
                        .accessibilityIdentifier("jackpot_\(name)")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, h * (big ? 0.4 : 0.22))
            }
            .shadow(color: big ? ArtPalette.gold.opacity(0.55) : .clear, radius: 8)
        }
    }
}

// MARK: - 转轮
struct CaishenReels: View {
    @ObservedObject var game: CaishenGame
    let spinStart: Date?
    let stopTimes: [Double]
    let cell: CGFloat
    let cellH: CGFloat
    let respinning: Bool
    let reduceMotion: Bool
    @Environment(\.slotTheme) private var theme
    @State private var pulse = false

    var body: some View {
        let spinning = game.phase == .spinning
        let feature = game.phase == .feature || (game.phase == .showing && game.spin?.feature != nil)
        let showing = game.phase == .showing || game.phase == .gift
        let wins = showing && !feature ? (game.spin?.outcome.lineWins ?? []) : []
        let lit = showing && !feature ? litCells() : []
        return ZStack {
            // 内胆：深色的底（3D 的金框在最上面一层盖住边）
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.05, green: 0.0, blue: 0.01))
                .frame(width: cell * 5 + 16, height: cellH * 3 + 8)
                .shadow(color: .black.opacity(0.7), radius: 10, y: 6)
            // 转轮和锁定重转的格子直接换，不淡入淡出：整屏对 phase 有 0.25 秒动画，
            // 淡入淡出时两边都半透明，中间会露出深色内胆，录屏里看到的就是黑一帧（v13.4，hj 11-24）
            if feature {
                featureGrid
                    .frame(width: cell * 5 + 8, height: cellH * 3)
                    .transition(.identity)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !spinning)) { ctx in
                    let t = spinStart.map { ctx.date.timeIntervalSince($0) } ?? 1000
                    HStack(spacing: 2) {
                        ForEach(0..<CaishenMath.reels, id: \.self) { r in
                            reel(r, time: t, spinning: spinning, lit: lit, dim: showing && !lit.isEmpty)
                        }
                    }
                }
                .frame(width: cell * 5 + 8, height: cellH * 3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.identity)
                LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .clear, location: 0.14),
                                       .init(color: Color.white.opacity(0.06), location: 0.5),
                                       .init(color: .clear, location: 0.86), .init(color: .black.opacity(0.3), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: cell * 5 + 8, height: cellH * 3)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
            ReelFrame3D(reels: CGSize(width: cell * 5 + 8, height: cellH * 3))
                .allowsHitTesting(false)
            if !wins.isEmpty {
                Canvas { ctx, size in
                    let x0 = (size.width - (cell * 5 + 8)) / 2, y0 = (size.height - cellH * 3) / 2
                    for w in wins {
                        var p = Path()
                        let line = CaishenMath.lines[w.line]
                        for r in 0..<w.count {
                            let pt = CGPoint(x: x0 + (cell + 2) * CGFloat(r) + cell / 2, y: y0 + cellH * (CGFloat(line[r]) + 0.5))
                            if r == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                        let col = SlotsReels.lineColors[w.line % SlotsReels.lineColors.count]
                        ctx.stroke(p, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                .allowsHitTesting(false)
                .opacity(0.9)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) { pulse = true } }
        .accessibilityElement()
        .accessibilityIdentifier("slotsReels")
        .accessibilityLabel(Text("Reels"))
    }

    private func litCells() -> Set<Int> {
        guard let s = game.spin else { return [] }
        var set = Set<Int>()
        for w in s.outcome.lineWins {
            for r in 0..<w.count { set.insert(r * 3 + CaishenMath.lines[w.line][r]) }
        }
        return set
    }

    /// 锁定重转：锁住的金币留在格子里，空格在转
    private var featureGrid: some View {
        let coins = Dictionary(uniqueKeysWithValues: game.locked.map { ($0.cell, $0.value) })
        return HStack(spacing: 2) {
            ForEach(0..<CaishenMath.reels, id: \.self) { r in
                VStack(spacing: 0) {
                    ForEach(0..<CaishenMath.rows, id: \.self) { k in
                        let c = r * CaishenMath.rows + k
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [theme.reelLight.opacity(0.7), theme.reelDark], startPoint: .top, endPoint: .bottom))
                                .padding(2)
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ArtPalette.gold.opacity(coins[c] == nil ? 0.25 : 0.9), lineWidth: 1.5)
                                .padding(2)
                            if let v = coins[c] {
                                CaishenSymbolView(symbol: .coin, size: cell * 0.94, coinValue: v, coinBet: game.spin?.bet ?? 1)
                                    .shadow(color: ArtPalette.gold.opacity(0.8), radius: 6)
                                    .transition(.scale(scale: 1.8).combined(with: .opacity))
                            } else if respinning && !reduceMotion {
                                SpinBlur(seed: c).padding(4)
                            }
                        }
                        .frame(width: cell, height: cellH)
                    }
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: game.locked.count)
    }

    private func reel(_ r: Int, time t: Double, spinning: Bool, lit: Set<Int>, dim: Bool) -> some View {
        let strip = CaishenMath.strips[r]
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
                let u = min(1, (t - stopAt) / SlotsTiming.bounce)
                bounce = reduceMotion ? 0 : cellH * 0.16 * CGFloat(sin(u * .pi) * (1 - u))
            }
        }
        let base = Int(floor(p)), frac = CGFloat(p - floor(p))
        return ZStack(alignment: .top) {
            // 转轮带：深红的绒面，中间亮一点（v13.1：深色的底，金色的立体图案才跳得出来）
            LinearGradient(colors: [theme.reelDark, theme.reelLight, theme.reelDark], startPoint: .leading, endPoint: .trailing)
            Rectangle().fill(LinearGradient(colors: [ArtPalette.gold.opacity(0.5), ArtPalette.goldDeep.opacity(0.2)], startPoint: .top, endPoint: .bottom)).frame(width: 1.5).frame(maxWidth: .infinity, alignment: .trailing)
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { k in
                    let sym = strip[((base + k) % n + n) % n]
                    let isLit = !rolling && k < 3 && lit.contains(r * 3 + k)
                    // v13.1b：图案一律正面朝前，不再做「圆筒」的后仰（上下两行会歪，hj 说不自然）
                    CaishenSymbolView(symbol: sym, size: cell * 0.98)
                        .frame(width: cell, height: cellH)
                        .scaleEffect(isLit ? (pulse && !reduceMotion ? 1.2 : 1.04) : 1)
                        .shadow(color: isLit ? ArtPalette.goldLight.opacity(pulse ? 0.95 : 0.4) : .clear, radius: isLit ? 12 : 0)
                        .zIndex(isLit ? 1 : 0)
                        .opacity(dim && !isLit ? 0.4 : 1)
                        .background(isLit ? RoundedRectangle(cornerRadius: 8).fill(RadialGradient(colors: [ArtPalette.goldLight.opacity(0.75), ArtPalette.gold.opacity(0.15)], center: .center, startRadius: 2, endRadius: cell * 0.7)).padding(3) : nil)
                        .overlay(isLit ? RoundedRectangle(cornerRadius: 8).stroke(ArtPalette.goldLight, lineWidth: 3).padding(3) : nil)
                        .blur(radius: rolling && !reduceMotion ? 1.6 : 0)
                }
            }
            .offset(y: -frac * cellH + bounce)
        }
        .frame(width: cell, height: cellH * 3, alignment: .top)
        .clipped()
    }
}

/// 锁定重转里空格的「在转」：几道往下流的金色光带
private struct SpinBlur: View {
    let seed: Int
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate * 2.6 + Double(seed) * 0.37
                for i in 0..<3 {
                    let u = (t + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let y = CGFloat(u) * (size.height + 30) - 30
                    let rect = CGRect(x: size.width * 0.2, y: y, width: size.width * 0.6, height: 26)
                    ctx.fill(Path(ellipseIn: rect), with: .color(ArtPalette.gold.opacity(0.28)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .blur(radius: 3)
    }
}

// MARK: - 赔付表
struct CaishenPaytable: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Line wins (× total bet)") {
                    ForEach([CaishenSymbol.ingot, .fu, .redEnvelope, .lantern, .ace, .kingCard, .queenCard, .jack], id: \.rawValue) { s in
                        HStack(spacing: 12) {
                            CaishenSymbolView(symbol: s, size: 38)
                            Spacer()
                            ForEach([3, 4, 5], id: \.self) { n in
                                VStack(spacing: 0) {
                                    Text(verbatim: "\(n)×").font(.caption2).foregroundColor(.secondary)
                                    Text(verbatim: "\(CaishenMath.pay(s, count: n))").font(.headline).monospacedDigit()
                                }
                                .frame(width: 44)
                            }
                        }
                    }
                }
                Section("Special symbols") {
                    special(.wild, "Wild: replaces any symbol on a line. Appears on reels 2, 3 and 4.")
                    special(.coin, "Coins: 6 or more at once lock in place and start Hold & Respin with 3 respins. Each new coin resets the respins to 3. Every coin pays the number on it × your bet, or the MINI, MINOR or MAJOR jackpot. Fill all 15 spaces to win the GRAND.")
                }
                Section("Jackpots") {
                    Text("MINI ×\(CaishenMath.miniPrize), MINOR ×\(CaishenMath.minorPrize), MAJOR ×\(CaishenMath.majorPrize) and GRAND ×\(CaishenMath.grandPrize) of your bet. One hundredth of every bet is added to the GRAND until you win it.")
                        .font(.subheadline)
                    Text("On any spin a surprise visit may scatter coins worth ×\(CaishenMath.giftMin) to ×\(CaishenMath.giftMax) of your bet.")
                        .font(.subheadline)
                }
                Section {
                    Text("10 fixed lines pay from the leftmost reel. Every win is a multiple of your total bet. Expected return is about 95%. Coins are virtual and have no real-world value.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Paytable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func special(_ s: CaishenSymbol, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            CaishenSymbolView(symbol: s, size: 44).padding(.bottom, 6)
            Text(text).font(.subheadline)
        }
    }
}

// MARK: - v13.1 用 3D 渲染图的小部件
/// 一个 3D 渲染的图案（图渲染不出来时是空的）
struct Icon3DView: View {
    let kind: Icon3D.Kind
    let size: CGFloat
    var body: some View {
        Group {
            if let img = Icon3D.image(kind) {
                Image(uiImage: img).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

/// 一堆元宝和金币
struct TreasurePile: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            Icon3DView(kind: .pile, size: s * 1.02)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 转轮外面的 3D 金框。reels = 转轮窗口的大小；框比窗口大一圈，上面正中有一只元宝
struct ReelFrame3D: View {
    let reels: CGSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.slotTheme) private var theme
    var body: some View {
        // 图的四周留白：左右下各 16，上面 34（放元宝）
        let size = CGSize(width: reels.width + 32, height: reels.height + 50)
        let window = CGRect(x: 16, y: 34, width: reels.width, height: reels.height)
        Group {
            if let img = Icon3D.frame(size: size, window: window, scale: displayScale, theme: theme) {
                Image(uiImage: img).resizable()
            } else {
                RoundedRectangle(cornerRadius: 14).stroke(ArtPalette.gold, lineWidth: 8).padding(8)
            }
        }
        .frame(width: size.width, height: size.height)
        // 窗口的中心对着转轮的中心
        .offset(y: -9)
    }
}

/// 背景里慢慢往上飘的金色光点
struct GoldSparks: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<34 {
                    let a = Double((i * 7919) % 1000) / 1000, b = Double((i * 104729) % 1000) / 1000, c = Double((i * 1299709) % 1000) / 1000
                    let period = 9 + 9 * b
                    let u = ((t / period) + c).truncatingRemainder(dividingBy: 1)
                    let x = a * Double(size.width) + sin(t * 0.6 + Double(i)) * 14
                    let y = Double(size.height) * (1.05 - u * 1.1)
                    let r = 1.5 + 3.5 * b
                    // 两头淡入淡出，中间一闪一闪
                    let alpha = sin(u * .pi) * (0.35 + 0.3 * sin(t * 3 + Double(i)))
                    let rect = CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)
                    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [ArtPalette.goldLight.opacity(max(0, alpha)), .clear]),
                                                                          center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 3))
                }
            }
        }
    }
}

// MARK: - v13.1 中奖特效
/// 立体的大字（3D 渲染的图；渲染不出来时退回普通的金字）
struct Title3D: View {
    let text: String
    let tint: UIColor
    var body: some View {
        if let img = Icon3D.title(text, front: tint) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(3, contentMode: .fit)
                .shadow(color: .black.opacity(0.6), radius: 5, y: 5)
                .shadow(color: ArtPalette.gold.opacity(0.8), radius: 16)
                .accessibilityLabel(Text(verbatim: text))
        } else {
            Text(verbatim: text)
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(red: 0.6, green: 0.02, blue: 0.05), radius: 0, x: 3, y: 3)
                .lineLimit(1).minimumScaleFactor(0.4)
        }
    }
}

/// 从中心放射出去、慢慢旋转的光芒
struct SunRays: View {
    var color: Color = ArtPalette.goldLight
    var rays = 18
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = min(size.width, size.height) / 2
                for k in 0..<rays {
                    // 宽窄相间的两组光，转的方向相反
                    let wide = k % 2 == 0
                    let a = Double(k) / Double(rays) * 2 * .pi + t * (wide ? 0.25 : -0.18)
                    let half = wide ? 0.085 : 0.04
                    var p = Path()
                    p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - half)) * R, y: c.y + CGFloat(sin(a - half)) * R))
                    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + half)) * R, y: c.y + CGFloat(sin(a + half)) * R))
                    p.closeSubpath()
                    ctx.fill(p, with: .radialGradient(Gradient(colors: [color.opacity(wide ? 0.55 : 0.4), color.opacity(0)]), center: c, startRadius: R * 0.08, endRadius: R))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 金币从中间爆开：往四面飞出去，再被重力拉下来（只放一次）
struct CoinBurst: View {
    var count = 30
    @Environment(\.slotTheme) private var theme
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t < 2.4 else { return }
                let coin = Icon3D.image(.symbol(.coin)).map { ctx.resolve(Image(uiImage: $0)) }
                let ingot = Icon3D.image(.symbol(.ingot, theme)).map { ctx.resolve(Image(uiImage: $0)) }
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<count {
                    let a = Double((i * 7919) % 1000) / 1000, b = Double((i * 104729) % 1000) / 1000, d = Double((i * 1299709) % 1000) / 1000
                    let angle = a * 2 * .pi
                    let speed = 380 + 520 * b
                    let x = cos(angle) * speed * t
                    let y = sin(angle) * speed * t * 0.8 - 260 * t + 900 * t * t
                    let r = 15 + 16 * d
                    var g = ctx
                    g.opacity = max(0, min(1, 2.4 - t))
                    g.translateBy(x: c.x + x, y: c.y + y)
                    g.rotate(by: .radians(t * (3 + 5 * d) + Double(i)))
                    if i % 6 == 0, let ingot {
                        g.draw(ingot, in: CGRect(x: -r * 1.3, y: -r * 1.3, width: r * 2.6, height: r * 2.6))
                    } else if let coin {
                        g.scaleBy(x: max(0.25, abs(cos(t * (4 + 5 * b) + Double(i)))), y: 1)
                        g.draw(coin, in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
                    }
                }
            }
        }
        .frame(width: 900, height: 1400)
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}
