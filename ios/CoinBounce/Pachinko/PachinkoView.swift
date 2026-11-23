import SwiftUI
import SceneKit

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
    @State private var scene3D: Pachinko3DScene?
    @State private var rects = Pachinko3DScene.Rects()
    @State private var floaters: [Floater] = []
    @State private var showAdUnavailableHint = false
    @State private var showSettings = false
    @State private var line: BunnyLine?
    @State private var lineAt = Date.distantPast
    @State private var dimmed = false
    @State private var flash = false
    @State private var coinFlyToken = 0
    @State private var firstFrame = false
    @State private var machineSize: CGSize = .zero
    @State private var showerBanner = false
    @State private var lampPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Floater: Identifiable { let id = UUID(); let point: CGPoint; let amount: Int }

    static let topBarHeight: CGFloat = 36

    /// 机器在屏幕上占多大（content = 去掉安全区以后的画面）。大厅预热时也用它，快照和进场后的视图才一样大
    static func machineSize(in content: CGSize) -> CGSize {
        let availH = max(200, content.height - topBarHeight - 12)
        let layout = Pachinko3DScene.Layout.fitting(CGSize(width: content.width, height: availH))
        return CGSize(width: content.width, height: min(availH, content.width / layout.aspect))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let size = Self.machineSize(in: geo.size)
            ZStack {
                RouletteBackdrop().ignoresSafeArea()
                LightPool(strength: 0.14).frame(width: w * 1.1, height: size.height * 0.7).position(x: w / 2, y: 40 + size.height * 0.4)
                VStack(spacing: 4) {
                    topBar.padding(.horizontal, 10).padding(.top, 4)
                    cabinet(width: size.width, height: size.height)
                    Spacer(minLength: 0)
                }
                // 兔女郎：站在面板左边，气泡朝右上
                let apron = shownRects.apron
                let bunnyH = apron.height > 10 ? min(250, apron.height * 1.18) : 170
                BunnyHostess(line: line, height: bunnyH, bubbleOnRight: true, bubbleWidth: 150)
                    .frame(width: bunnyH * 1.4, height: bunnyH, alignment: .bottomLeading)
                    .position(x: 2 + bunnyH * 0.7, y: min(h - bunnyH / 2 - 2, Self.topBarHeight + 8 + size.height - bunnyH / 2 - 6))
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("pachinkoBunny")
                if flash && !reduceMotion {
                    ArtPalette.goldLight.opacity(0.55).ignoresSafeArea().allowsHitTesting(false)
                }
                if showerBanner {
                    Text("GOLDEN SHOWER!")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                        .shadow(color: ArtPalette.gold.opacity(0.9), radius: 12)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: w - 40)
                        .position(x: w / 2, y: Self.topBarHeight + size.height * 0.2)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("pachinkoShower")
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
                        .position(x: w / 2, y: Self.topBarHeight + size.height * 0.2)
                        .transition(.opacity)
                        .allowsHitTesting(false)
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
            .onAppear {
                machineSize = size
                // 有预热快照时，转场先用快照（便宜），0.3 秒后再建 3D 视图：
                // 建 SCNView / Metal 层会卡主线程一下，放在转场里会让大厅先淡出、中间露出几帧黑底
                if Pachinko3DScene.placeholder != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { makeScene() }
                } else {
                    makeScene()
                }
            }
        }
        .overlay(FilmOverlay())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onDisappear { leave() }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                leave()
            } else {
                scene3D?.start()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: game.notice)
        .animation(.easeInOut(duration: 0.3), value: dimmed)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: showerBanner)
        .onReceive(game.cues) { handle($0) }
    }

    /// 3D 视图报上来之前，先用大厅预热时量好的位置
    private var shownRects: Pachinko3DScene.Rects {
        if rects.lcd.width > 10 { return rects }
        if let r = Pachinko3DScene.placeholderRects, let img = Pachinko3DScene.placeholder,
           img.size.height > 0, machineSize.height > 0,
           abs(img.size.width / img.size.height - machineSize.width / machineSize.height) < 0.01 { return r }   // 快照的 size 是像素，比比例
        return rects
    }

    // MARK: 事件 → 兔女郎、声音、触感、特效
    private func handle(_ cue: PachinkoCue) {
        let audio = AudioManager.shared, haptic = HapticManager.shared
        switch cue {
        case .launched: audio.play(.pkLaunch); haptic.coinFall()
        case .startHit: audio.play(.pkStart); haptic.coinFall()
        case .tulipOpened, .smallWin: audio.play(.winSmall)
        case .catcherSaved: audio.play(.winSmall); haptic.coinFall()
        case .lampLit: audio.play(.pkCount); lampPulse += 1
        case .showerStarted:
            audio.play(.winBig)
            audio.play(.cheer)
            haptic.bigWin()
            lampPulse += 1
            scene3D?.flashBulbs(seconds: 3)
            showerBanner = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showerBanner = false }
        case .spinStarted: audio.play(.slotSpin); dimmed = false
        case .reelStopped: audio.play(.slotStop); haptic.slotColumnStop()
        case .reach(let r):
            audio.play(.pkReach)
            if r == .superReach { dimmed = !reduceMotion; haptic.slotStart() }
        case .reachMissed: dimmed = false
        case .jackpot(let kind, _):
            dimmed = false
            audio.play(kind == .bonus ? .winBig : .jackpotFanfare)
            audio.play(.cheer)
            if kind == .bonus { haptic.bigWin() } else { haptic.jackpot() }
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { flash = false }
        case .roundStarted: audio.play(.pkAttacker); haptic.bonusTriggered()
        case .attackerBall: audio.play(.pkCount); haptic.coinFall(); coinFlyToken += 1
        case .jackpotEnded: audio.play(.applause)
        case .outOfCoins: audio.play(.noCoins)
        default: break
        }
        guard let l = PachinkoScript.line(for: cue) else { return }
        // 进口、郁金香这种高频小事不打断正在说的话
        let minor: Bool = {
            switch cue {
            case .startHit, .tulipOpened, .foul, .tooHard, .trayEmpty, .idle, .catcherSaved, .lampLit: return true
            default: return false
            }
        }()
        if minor, line != nil, Date().timeIntervalSince(lineAt) < 3 { return }
        say(l)
    }

    private func say(_ l: PachinkoScript.Line) {
        let pose: BunnyPose
        switch l.pose {
        case .idle: pose = .idle
        case .blowKiss: pose = .blowKiss
        case .clap: pose = .clap
        case .cheer: pose = .cheer
        case .jump: pose = .jump
        case .headshot: pose = .headshot
        case .celebrate: pose = BunnyPose.celebrationPoses.randomElement() ?? .cheer
        }
        let new = BunnyLine(text: l.text, pose: pose)
        line = new
        lineAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if line?.id == new.id { line = nil }
        }
    }

    private func makeScene() {
        guard scene3D == nil else { return }
        game.reduceMotion = reduceMotion
        // 等 onReceive 订阅上了再打招呼
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { game.entered() }
        let s = Pachinko3DScene(game: game, layout: .fitting(machineSize))
        s.onRects = { r in rects = r }
        s.onFirstFrame = { firstFrame = true }
        s.onPayout = { pt, amount in
            let f = Floater(point: pt, amount: amount)
            floaters.append(f)
            if floaters.count > 8 { floaters.removeFirst(floaters.count - 8) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { floaters.removeAll { $0.id == f.id } }
        }
        scene3D = s
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-pachinkoDemo") || args.contains("-pachinkoStress") {
            // 截图 / 量帧率：余额补到 200，上皿装满，AUTO 连发
            if gameState.availableCoins < 200 { gameState.addCoins(200 - gameState.availableCoins, source: .other) }
            game.chip = 10
            for _ in 0..<5 { game.buy() }
            game.auto = true
            if args.contains("-pachinkoStress") { game.debugStress = true }
            // 录屏 / 截图：-pachinkoJackpot 塞一张 ROYAL 中奖票（普通リーチ 7 秒）；-pachinkoReach 塞一张没中的超级リーチ
            if args.contains("-pachinkoJackpot") { game.debugInsertTicket(PachinkoTicket(hit: 0, kind: 20, show: 800)) }
            if args.contains("-pachinkoReach") { game.debugInsertTicket(PachinkoTicket(hit: 60000, kind: 0, show: 5)) }
            // -pachinkoLamps N：先点亮 N 盏水果灯（6 = 再进一球就下金珠雨）
            if let i = args.firstIndex(of: "-pachinkoLamps"), i + 1 < args.count, let n = Int(args[i + 1]) { game.debugLightLamps(n) }
        }
        // -pachinkoPull 0.65：拉杆停在这个位置不放（截图用）；-pachinkoShot 0.65：每 2 秒手动拉一次
        if let i = args.firstIndex(of: "-pachinkoPull"), i + 1 < args.count, let v = Double(args[i + 1]) {
            if gameState.availableCoins < 50 { gameState.addCoins(50, source: .other) }
            game.buy()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { game.pull = v }
        }
        if let i = args.firstIndex(of: "-pachinkoShot"), i + 1 < args.count, let v = Double(args[i + 1]) {
            if gameState.availableCoins < 50 { gameState.addCoins(50, source: .other) }
            debugShoot(v)
        }
        #endif
    }

    #if DEBUG
    private func debugShoot(_ v: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard scene3D != nil else { return }
            game.pull = v
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                game.releasePlunger()
                debugShoot(v)
            }
        }
    }
    #endif

    /// 离开（回大厅、切后台）：在飞的珠子结算，存档
    private func leave() {
        game.settleInFlight()
        gameState.saveNow()
        scene3D?.stop()
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
        .frame(height: Self.topBarHeight)
    }

    // MARK: 3D 机器 + 叠在上面的液晶数字盘、水果灯、面板按钮、拉杆
    private func cabinet(width w: CGFloat, height h: CGFloat) -> some View {
        let r = shownRects
        return ZStack(alignment: .topLeading) {
            // 第一帧出来之前：大厅预热时拍的机器快照（第一次进来不会看到空白）
            if !firstFrame, let img = Pachinko3DScene.placeholder {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
            }
            if let scene3D {
                Pachinko3DView(scene3D: scene3D)
            }
            if r.lcd.width > 10 {
                PachinkoReelView(machine: game.machine, spinStartedAt: game.spinStartedAt)
                    .frame(width: r.lcd.width - 6, height: r.lcd.height - 6)
                    .rotation3DEffect(.radians(Double(-Pachinko3DScene.tilt) * 0.9), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.35)
                    .position(x: r.lcd.midX, y: r.lcd.midY)
                    .allowsHitTesting(false)
                PachinkoMarquee(lamps: game.features.lamps, pulse: lampPulse)
                    .frame(width: r.marquee.width, height: r.marquee.height)
                    .position(x: r.marquee.midX, y: r.marquee.midY)
                    .allowsHitTesting(false)
                controls(in: r.apron)
                    .frame(width: r.apron.width, height: r.apron.height)
                    .position(x: r.apron.midX, y: r.apron.midY)
                plungerArea(r.plunger)
            }
            ForEach(floaters) { f in
                FloatingPayout(amount: f.amount)
                    .position(f.point)
                    .allowsHitTesting(false)
            }
            if dimmed {
                // 超级リーチ：整块台面压暗 40%，只留液晶亮
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .mask(
                        Rectangle()
                            .overlay(RoundedRectangle(cornerRadius: 6).frame(width: r.lcd.width + 8, height: r.lcd.height + 8)
                                .position(x: r.lcd.midX, y: r.lcd.midY).blendMode(.destinationOut))
                            .compositingGroup()
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if coinFlyToken > 0, let from = scene3D?.project(0.5, PachinkoBoard.attackerY1) {
                WinCoinFly(from: from, to: CGPoint(x: 70, y: -24))
                    .id(coinFlyToken)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h)
        .accessibilityIdentifier("pachinkoBoard")
    }

    // MARK: 面板：上皿、AUTO、买珠、力度表（左边留给兔女郎）
    private func controls(in apron: CGRect) -> some View {
        let bunnyW = min(84, apron.width * 0.25)
        let chipW = max(38, min(50, (apron.width - bunnyW - 30 - 3 * 6) / 4))
        return HStack(alignment: .center, spacing: 6) {
            Spacer(minLength: bunnyW)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    trayBadge
                    autoButton
                }
                HStack(spacing: 6) {
                    ForEach(PachinkoConstants.chips, id: \.self) { v in
                        Button {
                            AudioManager.shared.play(.coinDrop)
                            game.chip = v
                            game.buy()
                        } label: {
                            Text("+\(v)")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(Color(red: 0.35, green: 0.18, blue: 0.0))
                                .frame(width: chipW, height: 38)
                                .background(GoldGloss(shape: Capsule()))
                                .overlay(Capsule().stroke(game.chip == v ? Color.white : ArtPalette.goldDeep, lineWidth: game.chip == v ? 2.5 : 1))
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pachinkoBuy_\(v)")
                    }
                }
            }
            Spacer(minLength: 0)
            PachinkoPowerGauge(pull: game.pull, lastPull: PachinkoConstants.pull(forPower: game.power))
                .frame(width: 16, height: min(118, apron.height * 0.74))
                .accessibilityIdentifier("pachinkoGauge")
        }
        .padding(.trailing, 4)
    }

    /// 拉杆的触摸区：按住往下拖，松手发射。头一次进来有「往下拉」的提示
    private func plungerArea(_ r: CGRect) -> some View {
        ZStack(alignment: .top) {
            Color.clear
            if game.stats.ballsFired == 0 && game.pull == 0 && !game.auto {
                PullHint().offset(x: -r.width * 0.42, y: r.height * 0.18)
            }
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if game.auto { game.auto = false }
                    let p = min(1, max(0, Double(v.translation.height) / Double(max(44, r.height * 0.3))))
                    // 过了推荐区的两条边各震一下
                    let z = PachinkoConstants.pullSweet
                    if (game.pull < z.lowerBound) != (p < z.lowerBound) || (game.pull > z.upperBound) != (p > z.upperBound) {
                        HapticManager.shared.slotColumnStop()
                    }
                    game.pull = p
                }
                .onEnded { _ in game.releasePlunger() }
        )
        .position(x: r.midX, y: r.midY)
        .accessibilityElement()
        .accessibilityIdentifier("pachinkoPlunger")
        .accessibilityLabel(Text("Spring launcher"))
        .accessibilityHint(Text("Drag down and release to shoot a ball"))
        .accessibilityAction { game.pull = PachinkoConstants.defaultPull; game.releasePlunger() }
    }

    private var trayBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(RadialGradient(colors: [.white, Color(white: 0.55), Color(white: 0.25)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9))
                .frame(width: 14, height: 14)
            Text("Tray")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
            Text("\(game.tray)/\(PachinkoConstants.trayCapacity)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(ArtPalette.goldLight)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 9).frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.7), lineWidth: 1))
        .accessibilityIdentifier("pachinkoTray")
    }

    private var autoButton: some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            game.auto.toggle()
            if game.auto {
                // 没手动打过（或上一发力度不在推荐区）就回到推荐区中间
                if !PachinkoConstants.sweetZone.contains(game.power) { game.resetPower() }
                if game.tray == 0 { game.buy() }
            }
        } label: {
            Text("AUTO")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(game.auto ? Color(red: 0.35, green: 0.18, blue: 0.0) : ArtPalette.goldLight)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12).frame(height: 32)
                .background(Group {
                    if game.auto { GoldGloss(shape: Capsule()) } else { Capsule().fill(Color.black.opacity(0.6)) }
                })
                .overlay(Capsule().stroke(ArtPalette.gold, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pachinkoAuto")
    }
}

/// v12.6 灯牌：7 盏水果灯（郁金香、幸运杯每进一球亮一盏，全亮下金珠雨）
struct PachinkoMarquee: View {
    let lamps: Int
    let pulse: Int
    @State private var bump = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let d = min(h * 0.86, (w * 0.66) / 7.5)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LUCKY LAMPS")
                        .font(.system(size: max(10, h * 0.36), weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: ArtPalette.outline, radius: 0, x: 1, y: 1)
                    Text("Light all 7 for a golden shower")
                        .font(.system(size: max(8, h * 0.2), weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1, green: 0.7, blue: 0.82))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: w * 0.3, alignment: .leading)
                Spacer(minLength: 2)
                HStack(spacing: d * 0.09) {
                    ForEach(0..<PachinkoConstants.lampCount, id: \.self) { i in
                        let lit = i < lamps
                        ZStack {
                            Circle()
                                .fill(RadialGradient(colors: lit ? [Color.white, ArtPalette.goldLight, ArtPalette.gold] : [Color(white: 0.28), Color(white: 0.08)],
                                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: d * 0.6))
                            FruitIcon(index: i, size: d * 0.68)
                                .saturation(lit ? 1 : 0)
                                .opacity(lit ? 1 : 0.35)
                            Circle().stroke(lit ? Color.white : ArtPalette.goldDeep, lineWidth: lit ? 2 : 1.2)
                        }
                        .frame(width: d, height: d)
                        .shadow(color: lit ? ArtPalette.gold.opacity(0.95) : .clear, radius: lit ? 7 : 0)
                        .scaleEffect(lit && i == lamps - 1 && bump ? 1.28 : 1)
                    }
                }
                .accessibilityElement()
                .accessibilityIdentifier("pachinkoLamps")
                .accessibilityLabel(Text("Lucky lamps"))
                .accessibilityValue(Text(verbatim: "\(lamps)/\(PachinkoConstants.lampCount)"))
            }
            .padding(.horizontal, 6)
            .frame(width: w, height: h)
        }
        .onChange(of: pulse) { _ in
            bump = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { bump = false }
        }
    }
}

/// v12.6 力度表：往下拉越多填得越多；金色一段是推荐区；细白线是上一发的力度
struct PachinkoPowerGauge: View {
    let pull: Double
    let lastPull: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let z = PachinkoConstants.pullSweet
            let inZone = z.contains(pull)
            ZStack(alignment: .top) {
                Capsule().fill(Color.black.opacity(0.65))
                Capsule().stroke(ArtPalette.gold.opacity(0.7), lineWidth: 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(ArtPalette.gold.opacity(0.55))
                    .frame(width: w - 4, height: h * (z.upperBound - z.lowerBound))
                    .offset(y: h * z.lowerBound)
                if pull > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: inZone ? [ArtPalette.goldLight, ArtPalette.gold] : [ArtPalette.magenta, ArtPalette.magentaDeep], startPoint: .top, endPoint: .bottom))
                        .frame(width: w - 6, height: max(6, h * pull))
                        .padding(.top, 1)
                        .shadow(color: inZone ? ArtPalette.gold : .clear, radius: 5)
                } else {
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: w + 4, height: 2.5)
                        .offset(y: h * lastPull)
                }
            }
        }
    }
}

/// 头一次进来：拉杆旁边「往下拉」的提示
struct PullHint: View {
    @State private var down = false
    var body: some View {
        VStack(spacing: 1) {
            Text("PULL")
                .font(.system(size: 12, weight: .black, design: .rounded))
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .black))
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .black)).opacity(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(ArtPalette.magentaDeep.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.8), lineWidth: 1))
        .offset(y: down ? 10 : 0)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { down = true } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 金色亮面（按钮底）
struct GoldGloss<S: Shape>: View {
    let shape: S
    var body: some View {
        shape
            .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
            .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center)).padding(2))
    }
}

/// 落袋时飘起的「+N」
struct FloatingPayout: View {
    let amount: Int
    @State private var go = false
    var body: some View {
        Text("+\(amount)")
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
            .shadow(color: ArtPalette.outline, radius: 0, x: 1.2, y: 1.2)
            .offset(y: go ? -34 : -8)
            .opacity(go ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.75)) { go = true } }
    }
}
