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
    @State private var lcdRect: CGRect = .zero
    @State private var floaters: [Floater] = []
    @State private var showAdUnavailableHint = false
    @State private var showSettings = false
    @State private var line: BunnyLine?
    @State private var lineAt = Date.distantPast
    @State private var dimmed = false
    @State private var flash = false
    @State private var coinFlyToken = 0
    @State private var firstFrame = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Floater: Identifiable { let id = UUID(); let point: CGPoint; let amount: Int }

    /// 机器（含外框）的宽高比：相机按这个比例把整台机器放进 3D 视图
    static let cabinetAspect: CGFloat = 0.8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad: CGFloat = 10
            let controlsH: CGFloat = 112
            let cabH = max(200, min(h - 36 - controlsH - 22, w / Self.cabinetAspect))
            ZStack {
                RouletteBackdrop().ignoresSafeArea()
                LightPool(strength: 0.14).frame(width: w * 1.1, height: cabH).position(x: w / 2, y: 40 + cabH / 2)
                let spare = max(0, h - 36 - controlsH - 22 - cabH)
                let bunnyH = min(190, max(150, spare + 70))
                VStack(spacing: 6) {
                    topBar.padding(.horizontal, pad).padding(.top, 4)
                    cabinet(width: w, height: cabH)
                    Spacer(minLength: 0)
                    controls
                        .frame(height: controlsH)
                        .padding(.horizontal, pad + 4)
                        .padding(.bottom, 4)
                }
                // 兔女郎：站在操作区上方左侧，气泡朝右上（大屏在机器下面的空位里，SE 压在机器左下角）
                BunnyHostess(line: line, height: bunnyH, bubbleOnRight: true, bubbleWidth: 150)
                    .frame(width: bunnyH * 1.4, height: bunnyH, alignment: .bottomLeading)
                    .position(x: 4 + bunnyH * 0.7, y: h - controlsH - 6 - bunnyH / 2)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("pachinkoBunny")
                if flash && !reduceMotion {
                    ArtPalette.goldLight.opacity(0.55).ignoresSafeArea().allowsHitTesting(false)
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
                        .position(x: w / 2, y: 40 + cabH * 0.1)
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
            .onAppear { makeScene() }
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
        .onReceive(game.cues) { handle($0) }
    }

    // MARK: 事件 → 兔女郎、声音、触感、特效
    private func handle(_ cue: PachinkoCue) {
        let audio = AudioManager.shared, haptic = HapticManager.shared
        switch cue {
        case .launched: audio.play(.pkLaunch)
        case .startHit: audio.play(.pkStart); haptic.coinFall()
        case .tulipOpened, .smallWin: audio.play(.winSmall)
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
            case .startHit, .tulipOpened, .foul, .tooHard, .trayEmpty, .idle: return true
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
        let s = Pachinko3DScene(game: game)
        s.onLCDRect = { r in lcdRect = r }
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
        }
        #endif
    }

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
        .frame(height: 36)
    }

    // MARK: 3D 机器 + 液晶数字盘 + 飘字
    private func cabinet(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // 第一帧出来之前：大厅预热时拍的机器快照（第一次进来不会看到空白）
            if !firstFrame, let img = Pachinko3DScene.placeholder {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
            }
            if let scene3D {
                Pachinko3DView(scene3D: scene3D)
            }
            if lcdRect.width > 10 {
                PachinkoReelView(machine: game.machine, spinStartedAt: game.spinStartedAt)
                    .frame(width: lcdRect.width - 6, height: lcdRect.height - 6)
                    .rotation3DEffect(.radians(Double(-Pachinko3DScene.tilt) * 0.9), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.35)
                    .position(x: lcdRect.midX, y: lcdRect.midY)
                    .allowsHitTesting(false)
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
                            .overlay(RoundedRectangle(cornerRadius: 6).frame(width: lcdRect.width + 8, height: lcdRect.height + 8)
                                .position(x: lcdRect.midX, y: lcdRect.midY).blendMode(.destinationOut))
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

    // MARK: 上皿、买珠、AUTO、手柄（金色亮面，和轮盘同一套）
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
                            AudioManager.shared.play(.coinDrop)
                            game.chip = v
                            game.buy()
                        } label: {
                            Text("+\(v)")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(Color(red: 0.35, green: 0.18, blue: 0.0))
                                .frame(width: 50, height: 40)
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
            PachinkoHandle(power: $game.power, isDown: $game.handleDown, size: 100)
                .accessibilityIdentifier("pachinkoHandle")
        }
    }

    private var trayBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(RadialGradient(colors: [.white, Color(white: 0.55), Color(white: 0.25)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9))
                .frame(width: 15, height: 15)
            Text("Tray")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
            Text("\(game.tray)/\(PachinkoConstants.trayCapacity)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(ArtPalette.goldLight)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .overlay(Capsule().stroke(ArtPalette.gold.opacity(0.7), lineWidth: 1))
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
                .foregroundColor(game.auto ? Color(red: 0.35, green: 0.18, blue: 0.0) : ArtPalette.goldLight)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Group {
                    if game.auto { GoldGloss(shape: Capsule()) } else { Capsule().fill(Color.black.opacity(0.6)) }
                })
                .overlay(Capsule().stroke(ArtPalette.gold, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pachinkoAuto")
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

/// 发射手柄（2.2 节）：镀铬旋钮，按住连发，上下拖改力度；外圈金色一段是推荐区
struct PachinkoHandle: View {
    @Binding var power: Double
    @Binding var isDown: Bool
    let size: CGFloat
    @State private var dragStart: (y: CGFloat, power: Double)?

    /// 力度 0…1 对应 -135°…+135°（0° 朝上）
    private func angle(_ p: Double) -> Angle { .degrees(-135 + 270 * p) }

    var body: some View {
        ZStack {
            // 外圈底座：黑色烤漆 + 刻度槽
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.04)], center: .center, startRadius: size * 0.3, endRadius: size * 0.52))
                .shadow(color: .black.opacity(0.6), radius: 6, y: 4)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(5)
            Circle()
                .trim(from: PachinkoConstants.sweetZone.lowerBound * 0.75, to: PachinkoConstants.sweetZone.upperBound * 0.75)
                .stroke(ArtPalette.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .shadow(color: ArtPalette.gold.opacity(0.9), radius: 4)
                .rotationEffect(.degrees(135))
                .padding(5)
            Circle()
                .trim(from: 0, to: power * 0.75)
                .stroke(ArtPalette.magenta.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(12)
            // 镀铬旋钮：锥形渐变做出金属拉丝反光，顶上一块高光
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [Color(white: 0.95), Color(white: 0.45), Color(white: 0.9), Color(white: 0.35), Color(white: 0.98), Color(white: 0.5), Color(white: 0.95)], center: .center))
                Circle()
                    .stroke(LinearGradient(colors: [.white, Color(white: 0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                Ellipse()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.38, height: size * 0.2)
                    .offset(y: -size * 0.14)
                // 指针
                Capsule()
                    .fill(LinearGradient(colors: [ArtPalette.magenta, ArtPalette.magentaDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 7, height: size * 0.22)
                    .offset(y: -size * 0.13)
                    .rotationEffect(angle(power))
                Circle()
                    .fill(RadialGradient(colors: [isDown ? ArtPalette.goldLight : Color(white: 0.9), isDown ? ArtPalette.gold : Color(white: 0.5)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.1))
                    .frame(width: size * 0.16, height: size * 0.16)
            }
            .frame(width: size * 0.66, height: size * 0.66)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            .scaleEffect(isDown ? 0.96 : 1)
        }
        .frame(width: size, height: size)
        .shadow(color: isDown ? ArtPalette.gold.opacity(0.6) : .clear, radius: 10)
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
        .accessibilityValue(Text(verbatim: "\(Int((power * 100).rounded()))%"))
    }
}
