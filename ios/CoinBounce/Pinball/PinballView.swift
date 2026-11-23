import SwiftUI
import SceneKit

// MARK: - v12.7 弹球台整屏：顶栏、显示屏、3D 台面、触摸（左右挡板 + 弹簧拉杆）
extension PachinkoWallet {
    static func pinball(_ s: GameState = .shared) -> PachinkoWallet {
        PachinkoWallet(balance: { s.availableCoins },
                       spend: { s.spendCoins($0) },
                       credit: { s.addCoins($0, source: .pinball) })
    }
}

struct PinballView: View {
    let onExit: () -> Void
    @StateObject private var game = PinballGame(wallet: .pinball())
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene3D: Pinball3DScene?
    @State private var showAdUnavailableHint = false
    @State private var showSettings = false
    @State private var flashText: String?
    @State private var flashToken = 0
    @State private var bigBanner: String?
    @State private var screenFlash = false
    @State private var coinFlyToken = 0
    @State private var pose: BunnyPose = .headshot

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RouletteBackdrop().ignoresSafeArea()
                VStack(spacing: 4) {
                    topBar.padding(.horizontal, 10).padding(.top, 4)
                    PinballDisplay(hud: game.hud, flash: flashText)
                        .frame(height: min(74, h * 0.1))
                        .padding(.horizontal, 8)
                    ZStack {
                        if let scene3D { Pinball3DView(scene3D: scene3D) }
                        PinballTouchSurface(
                            onFlipper: { side, down in
                                game.setFlipper(side, pressed: down)
                                if down {
                                    AudioManager.shared.play(.baffleHit)
                                    HapticManager.shared.baffleHit()
                                }
                            },
                            onPull: { game.pull = $0 },
                            onRelease: { game.releasePlunger() })
                            .accessibilityIdentifier("pinballTable")
                        hints
                        if let bigBanner {
                            Text(bigBanner)
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                                .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                                .shadow(color: ArtPalette.gold.opacity(0.9), radius: 12)
                                .lineLimit(1).minimumScaleFactor(0.5)
                                .padding(.horizontal, 20)
                                .offset(y: -h * 0.12)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                                .allowsHitTesting(false)
                                .accessibilityIdentifier("pinballBanner")
                        }
                        if coinFlyToken > 0 {
                            WinCoinFly(from: CGPoint(x: w / 2, y: h * 0.3), to: CGPoint(x: 70, y: -min(74, h * 0.1) - 30))
                                .id(coinFlyToken)
                                .allowsHitTesting(false)
                        }
                    }
                }
                if screenFlash && !reduceMotion {
                    ArtPalette.goldLight.opacity(0.5).ignoresSafeArea().allowsHitTesting(false)
                }
                if game.notice == .outOfCoins {
                    Text("Not enough coins. Watch an ad for +50!")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.8), lineWidth: 1))
                        .position(x: w / 2, y: h * 0.45)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("pinballNotice")
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
            .onAppear { makeScene() }
        }
        .overlay(FilmOverlay())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onDisappear { leave() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { leave() } else { scene3D?.start() }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: bigBanner)
        .onReceive(game.cues) { handle($0) }
    }

    // MARK: 提示：没开始时「下拉发射」，头几球提示点左右两边
    @ViewBuilder private var hints: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            if game.hud.ballOnPlunger && game.pull == 0 {
                VStack(spacing: 3) {
                    PullHint()
                    if !game.hud.turnActive {
                        HStack(spacing: 3) {
                            ArtCoin(size: 14)
                            Text(verbatim: "1").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                    }
                }
                .position(x: w * 0.78, y: h * 0.78)
                .allowsHitTesting(false)
            }
            if game.rules.stats.balls < 3 {
                HStack {
                    FlipHint(text: "TAP LEFT")
                    Spacer()
                    FlipHint(text: "TAP RIGHT")
                }
                .padding(.horizontal, w * 0.1)
                .padding(.trailing, w * 0.12)
                .position(x: w / 2, y: h * 0.93)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: 事件 → 声音、触感、显示屏
    private func handle(_ cue: PinballCue) {
        let audio = AudioManager.shared, haptic = HapticManager.shared
        switch cue {
        case .launched: audio.play(.pkLaunch); haptic.coinFall()
        case .bumper: audio.play(.pkNail3); haptic.coinFall()
        case .sling: audio.play(.pkNail2)
        case .topLane(_, let lit): if lit { audio.play(.pkCount) }
        case .topLanesComplete(let m):
            audio.play(.winSmall); haptic.smallWin()
            flash(String(localized: "BONUS ×\(m) · LUCKY HOLE LIT"))
        case .dropTarget: audio.play(.pkStart); haptic.coinFall()
        case .dropsComplete: audio.play(.winSmall); haptic.smallWin(); flash(String(localized: "K-Q-J DOWN!"))
        case .standup: audio.play(.pkCount)
        case .standupsComplete: audio.play(.winSmall); haptic.smallWin(); flash(String(localized: "ALL STARS LIT!"))
        case .hole: audio.play(.pkAttacker); haptic.bonusTriggered()
        case .mystery(let m):
            audio.play(.winSmall)
            switch m {
            case .points: flash(String(localized: "MYSTERY: +\(PinballConstants.mysteryPoints)"))
            case .superBumpers: flash(String(localized: "MYSTERY: SUPER BUMPERS ×3"))
            case .multiball: flash(String(localized: "MYSTERY: EXTRA BALL"))
            }
        case .jackpot:
            audio.play(.jackpotFanfare); audio.play(.cheer); haptic.jackpot()
            banner(String(localized: "JACKPOT!"))
            scene3D?.flashBulbs(seconds: 4)
            screenFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { screenFlash = false }
            pose = .cheer
        case .multiball(let n):
            audio.play(.winBig); haptic.bigWin()
            if n > 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { banner(String(localized: "MULTIBALL!")) } }
            scene3D?.flashBulbs(seconds: 4)
        case .missionAdvanced: audio.play(.pkReach)
        case .ballSaved: audio.play(.winSmall); flash(String(localized: "BALL SAVED"))
        case .coins: audio.play(.coinDrop); haptic.coinFall(); coinFlyToken += 1
        case .maxWin: flash(String(localized: "MAX WIN THIS BALL"))
        case .turnOver(_, let coins, _):
            if coins > 0 { audio.play(.applause) }
            flash(coins > 0 ? String(localized: "BALL OVER · +\(coins) COINS") : String(localized: "BALL OVER"))
            pose = .headshot
        case .outOfCoins: audio.play(.noCoins)
        case .returnedToPlunger: flash(String(localized: "TOO SOFT — PULL FURTHER"))
        case .inlane, .outlane, .flipper, .enteredField: break
        }
    }

    private func flash(_ text: String) {
        flashText = text
        flashToken += 1
        let token = flashToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { if flashToken == token { flashText = nil } }
    }

    private func banner(_ text: String) {
        bigBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if bigBanner == text { bigBanner = nil } }
    }

    private func makeScene() {
        guard scene3D == nil else { return }
        let s = Pinball3DScene(game: game)
        scene3D = s
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-pinballDemo") {
            // 截图 / 录屏：自动打球
            if gameState.availableCoins < 100 { gameState.addCoins(100 - gameState.availableCoins, source: .other) }
            if let i = args.firstIndex(of: "-pinballMission"), i + 1 < args.count, let n = Int(args[i + 1]), let m = PinballMission(rawValue: n) { game.debugSetMission(m) }
            debugAutoplay()
        }
        #endif
    }

    #if DEBUG
    private func debugAutoplay() {
        var bot = PinballBot.expert
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { t in
            guard scene3D != nil else { t.invalidate(); return }
            if game.ballOnPlunger && game.pull == 0 {
                game.pull = 0.85
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { game.releasePlunger() }
            }
            var e = game.engine
            bot.drive(&e)
            game.setFlipper(0, pressed: e.flippers[0].pressed)
            game.setFlipper(1, pressed: e.flippers[1].pressed)
        }
    }
    #endif

    private func leave() {
        game.settle()
        gameState.saveNow()
        scene3D?.stop()
    }

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
}

/// 显示屏：分数、任务、倍数、这一球赢的金币、离下一枚金币的进度
struct PinballDisplay: View {
    let hud: PinballHUD
    let flash: String?

    static func missionText(_ hud: PinballHUD) -> String {
        switch hud.mission {
        case .drops: return String(localized: "Mission 1/4: knock down K, Q, J")
        case .bumpers: return String(localized: "Mission 2/4: bumpers \(hud.missionHits)/\(PinballConstants.missionBumperHits)")
        case .standups: return String(localized: "Mission 3/4: light the 3 stars")
        case .hole: return String(localized: "Mission 4/4: shoot the Lucky Hole!")
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let amber = Color(red: 1, green: 0.62, blue: 0.12)
            HStack(spacing: 8) {
                BunnyArt(pose: .headshot)
                    .frame(width: h * 0.86, height: h * 0.86)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ArtPalette.gold, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: hud.score.formatted())
                        .font(.system(size: h * 0.42, weight: .black, design: .monospaced))
                        .foregroundColor(amber)
                        .shadow(color: amber.opacity(0.8), radius: 5)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityIdentifier("pinballScore")
                    Text(verbatim: flash ?? (hud.turnActive ? Self.missionText(hud) : String(localized: "Pull the spring · 1 coin per ball")))
                        .font(.system(size: max(10, h * 0.19), weight: .heavy, design: .rounded))
                        .foregroundColor(flash != nil ? .white : Color(red: 1, green: 0.8, blue: 0.5))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityIdentifier("pinballMessage")
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 5) {
                        if hud.multiplier > 1 {
                            Text(verbatim: "×\(hud.multiplier)")
                                .font(.system(size: h * 0.24, weight: .black, design: .rounded))
                                .foregroundColor(ArtPalette.magenta)
                        }
                        ArtCoin(size: h * 0.26)
                        Text(verbatim: "+\(hud.coins)")
                            .font(.system(size: h * 0.28, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(hud.maxWin ? ArtPalette.magenta : ArtPalette.goldLight)
                            .accessibilityIdentifier("pinballCoins")
                    }
                    // 离下一枚金币还差多少
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, 78 * hud.bank))
                    }
                    .frame(width: 78, height: 7)
                    Text("NEXT COIN")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 8)
            .frame(width: geo.size.width, height: h)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.04, blue: 0.02), .black], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            )
        }
    }
}

struct FlipHint: View {
    let text: LocalizedStringKey
    @State private var on = false
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
            .opacity(on ? 1 : 0.45)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true } }
            .accessibilityHidden(true)
    }
}

/// 触摸层：多点触控。从右下角（拉杆那一块）开始的触摸是拉弹簧；其余的按左半边 / 右半边打挡板
struct PinballTouchSurface: UIViewRepresentable {
    let onFlipper: (Int, Bool) -> Void
    let onPull: (Double) -> Void
    let onRelease: () -> Void

    final class Surface: UIView {
        var onFlipper: ((Int, Bool) -> Void)?
        var onPull: ((Double) -> Void)?
        var onRelease: (() -> Void)?
        private var sides: [ObjectIdentifier: Int] = [:]
        private var plungerTouch: ObjectIdentifier?
        private var plungerStartY: CGFloat = 0
        private var count = [0, 0]

        /// 拉杆区：右边 26%、下面 42%
        func inPlungerZone(_ p: CGPoint) -> Bool { p.x > bounds.width * 0.74 && p.y > bounds.height * 0.58 }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                let p = t.location(in: self), id = ObjectIdentifier(t)
                if plungerTouch == nil && inPlungerZone(p) {
                    plungerTouch = id
                    plungerStartY = p.y
                    onPull?(0.02)
                } else {
                    let side = p.x < bounds.width / 2 ? 0 : 1
                    sides[id] = side
                    count[side] += 1
                    if count[side] == 1 { onFlipper?(side, true) }
                }
            }
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches where ObjectIdentifier(t) == plungerTouch {
                let dy = t.location(in: self).y - plungerStartY
                onPull?(Double(min(1, max(0.02, dy / max(60, bounds.height * 0.13)))))
            }
        }
        private func end(_ touches: Set<UITouch>, cancelled: Bool) {
            for t in touches {
                let id = ObjectIdentifier(t)
                if id == plungerTouch {
                    plungerTouch = nil
                    if cancelled { onPull?(0) } else { onRelease?() }
                } else if let side = sides.removeValue(forKey: id) {
                    count[side] = max(0, count[side] - 1)
                    if count[side] == 0 { onFlipper?(side, false) }
                }
            }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: false) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: true) }
    }

    func makeUIView(context: Context) -> Surface {
        let v = Surface()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        v.onFlipper = onFlipper
        v.onPull = onPull
        v.onRelease = onRelease
        return v
    }
    func updateUIView(_ v: Surface, context: Context) {
        v.onFlipper = onFlipper
        v.onPull = onPull
        v.onRelease = onRelease
    }
}
