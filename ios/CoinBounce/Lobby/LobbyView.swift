import SwiftUI

// MARK: - v12.1 大厅：启动后的第一个画面（全部用代码画）
struct LobbyView: View {
    @ObservedObject var router: AppRouter
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @State private var line: BunnyLine? = nil
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showAdUnavailableHint = false
    @State private var glow = false
    @State private var hallReady = false
    @State private var doorRects: [CGRect] = []
    @State private var signRect: CGRect = .zero
    @State private var placeholderGone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = w * 0.045 + 10   // 两侧立柱里面再留一点
            let doorW = min((w - side * 2 - 6 * 3) / 4, 150)
            let doorH = min(doorW * 2.1, h * 0.3)
            // v12.9：大厅是一个 3D 场景（-fxOff 时退回原来的 2D 画法）
            let use3D = VisualFX.enabled
            let bunnyH = use3D ? min(h * 0.38, 340) : min(h * 0.42, 380)
            ZStack {
                LobbyBackdrop().ignoresSafeArea()
                if use3D {
                    // 3D 画面第一帧出来之前，下面的 2D 背景先顶着；出来以后淡入
                    hall3D(topInset: geo.safeAreaInsets.top + 46)
                        .ignoresSafeArea()
                } else {
                    // v12.3：吊灯照下来的光柱，招牌和地毯中间各一圈光
                    LightShafts()
                    LightPool(strength: 0.16).frame(width: w * 1.1, height: h * 0.22).position(x: w / 2, y: h * 0.16)
                    LightPool(strength: 0.14).frame(width: w * 0.9, height: h * 0.2).position(x: w / 2, y: h * 0.86)
                }
                VStack(spacing: 0) {
                    topBar(width: w - side * 2)
                        .padding(.horizontal, side)
                        .padding(.top, 6)
                    if !use3D {
                        LobbySign(glow: glow)
                            .frame(height: min(h * 0.13, 110))
                            .padding(.horizontal, 22)
                            .padding(.top, h * 0.02)
                        Spacer(minLength: 8)
                        HStack(alignment: .bottom, spacing: 6) {
                            LobbyDoor(title: String(localized: "Coin Pusher"), tint: ArtPalette.gold, icon: .pusher, locked: false, width: doorW, height: doorH) {
                                router.open(.pusher)
                            }
                            .accessibilityIdentifier("doorPusher")
                            if AppRouter.isAvailable(.roulette) {
                            LobbyDoor(title: String(localized: "Roulette"), tint: Color(red: 0.2, green: 0.75, blue: 0.45), icon: .roulette, locked: false, width: doorW, height: doorH) {
                                router.open(.roulette)
                            }
                            .accessibilityIdentifier("doorRoulette")
                            }
                            // v12.7：第三扇门换成弹球台（弹子机的代码还在，-startPachinko 能进）
                            if AppRouter.isAvailable(.pinball) {
                            LobbyDoor(title: String(localized: "Pinball"), tint: Color(red: 0.45, green: 0.6, blue: 1.0), icon: .pachinko, locked: false, width: doorW, height: doorH) {
                                router.open(.pinball)
                            }
                            .accessibilityIdentifier("doorPachinko")
                            }
                            // v12.8：第四扇门，老虎机
                            LobbyDoor(title: String(localized: "Slots"), tint: Color(red: 0.85, green: 0.3, blue: 0.75), icon: .slots, locked: false, width: doorW, height: doorH) {
                                router.open(.slots)
                            }
                            .accessibilityIdentifier("doorSlots")
                        }
                    }
                    Spacer(minLength: 8)
                    // 兔女郎迎宾：点她换一句话、换一个动作
                    HStack(alignment: .bottom, spacing: 0) {
                        BunnyHostess(line: line, height: bunnyH, groundShadow: true)
                            .contentShape(Rectangle())
                            .onTapGesture { greet() }
                            .accessibilityIdentifier("lobbyBunny")
                            .padding(.leading, use3D ? w * 0.04 : w * 0.12)
                        Spacer(minLength: 0)
                        // v13 定时送币：每 4 小时领一次
                        TimedGiftButton { say(String(localized: "A little gift for you. Come back in 4 hours for more!"), pose: .blowKiss) }
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                    }
                    .frame(height: bunnyH)
                    .padding(.bottom, 4)
                }
                if showAdUnavailableHint {
                    Text("No ad available right now. Check your connection and try again.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.8)))
                        .frame(maxWidth: w - 40)
                        .position(x: w / 2, y: 80)
                        .transition(.opacity)
                }
            }
        }
        .overlay(FestivalOverlay(festival: Festival.current))
        .overlay(FilmOverlay())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHelp) { HelpView() }
        .onReceive(MotionParallax.shared.$offset) { Lobby3DScene.shared.setTilt($0) }
        .onReceive(Timer.publish(every: 7, on: .main, in: .common).autoconnect()) { _ in greet() }
        .onAppear {
            glow = true
            greet()
            testerTopUp()
            dailyBonus()
            GameCenter.shared.authenticate()
            GameCenter.shared.report(gameState.totalCoinsWon, to: GameCenter.totalCoinsWon)
            #if DEBUG
            // 量首次进入时间：-debugEnterPachinkoAfter 5 → 5 秒后自动进弹子机
            let args = ProcessInfo.processInfo.arguments
            // -lobbyBunnyCycle：每 0.6 秒换一句话、换一个动作（逐帧检查换动作时有没有重影）
            if args.contains("-lobbyBunnyCycle") {
                Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in greet() }
            }
            // -debugLobbyReturn：3 秒后进老虎机、再过 3 秒回大厅（检查回来以后 3D 大厅还在）
            if args.contains("-debugLobbyReturn") && !Self.debugReturned {
                Self.debugReturned = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { router.open(.slots) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { router.backToLobby() }
            }
            if let i = args.firstIndex(of: "-debugEnterPachinkoAfter"), i + 1 < args.count, let t = Double(args[i + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { router.open(.pachinko) }
            }
            #endif
        }
    }

    private static var debugReturned = false
    /// 调试：-debugLobbyRects 把四扇门的点按区域用绿框画出来
    private static let debugRects = ProcessInfo.processInfo.arguments.contains("-debugLobbyRects")

    /// v12.9 3D 大厅 + 四扇门的点按区域（透明按钮，位置是从 3D 场景里投影出来的）。
    /// 3D 画面的第一帧要等着色器编译（模拟器上几秒，真机不到一秒）：这段时间先在同样的位置画 2D 的招牌和门，
    /// 门马上就能点；3D 出来以后原地淡入盖住它们
    private func hall3D(topInset: CGFloat) -> some View {
        let scene = Lobby3DScene.shared
        let refresh = {
            doorRects = scene.doorRects()
            signRect = scene.signRect()
        }
        return ZStack(alignment: .topLeading) {
            if !placeholderGone {
                if signRect.width > 10 {
                    LobbySign(glow: glow)
                        .frame(width: signRect.width, height: signRect.height)
                        .position(x: signRect.midX, y: signRect.midY)
                }
                ForEach(Array(scene.doors.enumerated()), id: \.offset) { i, door in
                    if i < doorRects.count {
                        let r = doorRects[i]
                        LobbyDoor(title: door.title, tint: Color(door.tint), icon: Self.icon(for: door.screen), locked: false, width: r.width - 6, height: r.height) {}
                            .allowsHitTesting(false)
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
            Lobby3DView(topInset: topInset, reduceMotion: reduceMotion,
                        onLayout: { DispatchQueue.main.async { refresh() } },
                        onFirstFrame: {
                            refresh()
                            withAnimation(.easeOut(duration: 0.35)) { hallReady = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { placeholderGone = true }
                        })
                .opacity(hallReady ? 1 : 0)
            ForEach(Array(scene.doors.enumerated()), id: \.offset) { i, door in
                if i < doorRects.count {
                    let r = doorRects[i]
                    Button {
                        AudioManager.shared.play(.buttonTap)
                        scene.pulse(door.screen)
                        router.open(door.screen)
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .frame(width: r.width, height: r.height)
                    .border(Self.debugRects ? Color.green : Color.clear, width: 2)
                    .accessibilityIdentifier(door.identifier)
                    .accessibilityLabel(Text(verbatim: door.title))
                    .position(x: r.midX, y: r.midY)
                }
            }
        }
    }

    private static func icon(for screen: AppRouter.Screen) -> LobbyDoor.Icon {
        switch screen {
        case .pusher: return .pusher
        case .roulette: return .roulette
        case .slots: return .slots
        default: return .pachinko
        }
    }

    /// v12.6：余额框的宽度按屏幕算（SE 上固定 150 会把顶栏撑出屏幕，整个大厅跟着偏到右边）
    private func topBar(width: CGFloat) -> some View {
        let fixed: CGFloat = (ads.adsEnabled ? AdHUDButton.size.width + 8 : 0) + 30 + 30 + 16 + 32 + 8 + 6   // v13.8：多了奖杯按钮
        return HStack(spacing: 8) {
            CoinBalanceView(coins: gameState.availableCoins, height: 30, width: max(90, min(150, width - fixed)))
            Spacer(minLength: 0)
            if ads.adsEnabled {
                AdHUDButton(ads: ads, gameState: gameState, showUnavailableHint: $showAdUnavailableHint)
                    .frame(width: AdHUDButton.size.width, height: AdHUDButton.size.height)
            }
            // v13.8 排行榜（Game Center）
            Button { GameCenter.shared.showLeaderboards() } label: {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(ArtPalette.goldLight)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .overlay(Circle().stroke(ArtPalette.gold.opacity(0.85), lineWidth: 1.5))
            }
            .accessibilityIdentifier("lobbyLeaderboards")
            .accessibilityLabel(Text("Leaderboards"))
            HelpButton { showHelp = true }
            SettingsButton { showSettings = true }
        }
        .frame(height: 36)
    }

    private func greet() {
        line = BunnyScript.greeting(jackpot: Int(gameState.jackpotPool), giftReady: TimedGift.shared.ready())
    }

    /// 测试模式（只在调试版里有，商店版没有）：回到大厅时金币不到 100 就补到 100
    private func testerTopUp() {
        guard TesterMode.enabled, gameState.availableCoins < TesterMode.coins else { return }
        gameState.addCoins(TesterMode.coins - gameState.availableCoins, source: .other)
        gameState.saveNow()
        say(String(localized: "Test mode: coins topped up to \(TesterMode.coins)."), pose: .clap)
    }
    /// v13.5：每天第一次进大厅送 DailyBonus.coins 枚，兔女郎说一句（XCTest 里不发，免得改动测试的余额）
    private func dailyBonus() {
        guard NSClassFromString("XCTestCase") == nil, DailyBonus.shared.claimIfNew() else { return }
        gameState.addCoins(DailyBonus.coins, source: .other)
        gameState.saveNow()
        say(String(localized: "Daily bonus: \(DailyBonus.coins) coins! See you tomorrow."), pose: .clap)
    }
    private func say(_ text: String, pose: BunnyPose) { line = BunnyLine(text: text, pose: pose) }
}

// MARK: - 背景：深红墙、金色壁灯光晕、菱形地毯
struct LobbyBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.02, blue: 0.08), Color(red: 0.36, green: 0.05, blue: 0.12), Color(red: 0.12, green: 0.02, blue: 0.06)],
                               startPoint: .top, endPoint: .bottom)
                // 墙面竖条纹
                Canvas { ctx, size in
                    let step = size.width / 14
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: step / 2, height: size.height * 0.62)), with: .color(Color.black.opacity(0.10)))
                        x += step
                    }
                }
                // 吊灯的光
                RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.5).opacity(0.38), .clear], center: .top, startRadius: 0, endRadius: h * 0.55)
                // 地毯：透视的菱形格
                Canvas { ctx, size in
                    let top = size.height * 0.62
                    let floor = CGRect(x: 0, y: top, width: size.width, height: size.height - top)
                    ctx.fill(Path(floor), with: .linearGradient(Gradient(colors: [Color(red: 0.30, green: 0.03, blue: 0.10), Color(red: 0.50, green: 0.06, blue: 0.14)]),
                                                                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
                    var path = Path()
                    let n = 9
                    for i in -n...(2 * n) {
                        let x0 = size.width * CGFloat(i) / CGFloat(n)
                        path.move(to: CGPoint(x: size.width / 2 + (x0 - size.width / 2) * 0.35, y: top))
                        path.addLine(to: CGPoint(x: x0 + size.width * 0.5, y: size.height))
                        path.move(to: CGPoint(x: size.width / 2 + (x0 - size.width / 2) * 0.35, y: top))
                        path.addLine(to: CGPoint(x: x0 - size.width * 0.5, y: size.height))
                    }
                    ctx.stroke(path, with: .color(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.16)), lineWidth: 1.2)
                    // 踢脚线
                    ctx.fill(Path(CGRect(x: 0, y: top - 5, width: size.width, height: 6)), with: .color(Color(red: 0.75, green: 0.55, blue: 0.2)))
                }
                // 两侧立柱
                HStack {
                    LobbyPillar().frame(width: w * 0.045)
                    Spacer()
                    LobbyPillar().frame(width: w * 0.045)
                }
            }
        }
    }
}

struct LobbyPillar: View {
    var body: some View {
        LinearGradient(colors: [ArtPalette.goldDeep, ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .leading, endPoint: .trailing)
            .overlay(Rectangle().stroke(ArtPalette.outline.opacity(0.6), lineWidth: 1))
            .opacity(0.85)
    }
}

// MARK: - 招牌：一圈灯泡的霓虹牌
struct LobbySign: View {
    let glow: Bool
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.28)
                    .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.05, blue: 0.2), Color(red: 0.2, green: 0.02, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: h * 0.28).stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 4))
                    .shadow(color: ArtPalette.gold.opacity(glow ? 0.7 : 0.25), radius: glow ? 16 : 6)
                // 灯泡
                Canvas { ctx, size in
                    let inset: CGFloat = 9
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                    let n = 16
                    for i in 0..<n {
                        let x = rect.minX + rect.width * CGFloat(i) / CGFloat(n - 1)
                        for y in [rect.minY, rect.maxY] {
                            let r: CGFloat = 2.6
                            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                                     with: .color(i.isMultiple(of: 2) == glow ? Color.white : ArtPalette.gold))
                        }
                    }
                }
                VStack(spacing: 0) {
                    Text("COIN BOUNCE")
                        .font(.system(size: h * 0.36, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color.white, ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .specularSweep()
                        .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                    Text("CASINO")
                        .font(.system(size: h * 0.22, weight: .heavy, design: .rounded))
                        .kerning(h * 0.08)
                        .foregroundColor(Color(red: 1, green: 0.55, blue: 0.75))
                        .shadow(color: Color(red: 1, green: 0.3, blue: 0.6).opacity(glow ? 0.9 : 0.4), radius: glow ? 8 : 3)
                }
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 18)
            }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: glow)
        }
    }
}

// MARK: - 游戏入口：拱门 + 图标 + 名牌
struct LobbyDoor: View {
    enum Icon { case pusher, roulette, pachinko, slots }
    let title: String
    let tint: Color
    let icon: Icon
    let locked: Bool
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    DoorArch()
                        .fill(LinearGradient(colors: [tint.opacity(locked ? 0.25 : 0.95), Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    DoorArch()
                        .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                    DoorArch()
                        .stroke(ArtPalette.outline.opacity(0.7), lineWidth: 1)
                        .padding(5)
                    iconView
                        .frame(width: width * 0.68, height: width * (icon == .pachinko ? 0.86 : 0.68))
                        .offset(y: height * 0.04)
                        .saturation(locked ? 0.2 : 1)
                        .opacity(locked ? 0.6 : 1)
                    if locked {
                        Text("COMING SOON")
                            .font(.system(size: max(9, width * 0.105), weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .frame(width: width * 0.96)
                            .background(Color(red: 0.75, green: 0.1, blue: 0.2))
                            .overlay(Rectangle().stroke(ArtPalette.goldLight, lineWidth: 1))
                            .rotationEffect(.degrees(-12))
                    }
                }
                .frame(width: width, height: height - 34)
                .shadow(color: tint.opacity(locked ? 0 : 0.55), radius: 10)
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(locked ? Color.white.opacity(0.6) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: width - 6, height: 26)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .overlay(Capsule().stroke(ArtPalette.gold.opacity(locked ? 0.4 : 0.9), lineWidth: 1.5))
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Text(title))
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .pusher:
            ZStack {
                ArtCoin(size: width * 0.30).offset(x: -width * 0.14, y: width * 0.12)
                ArtCoin(size: width * 0.30).offset(x: width * 0.14, y: width * 0.12)
                ArtCoin(size: width * 0.36).offset(y: -width * 0.06)
            }
        case .slots:
            // 三格小转轮：7 7 7
            HStack(spacing: width * 0.02) {
                ForEach(0..<3, id: \.self) { _ in
                    Text(verbatim: "7")
                        .font(.system(size: width * 0.26, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.4, blue: 0.4), Color(red: 0.7, green: 0, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                        .frame(width: width * 0.2, height: width * 0.36)
                        .background(RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(white: 0.75), .white, Color(white: 0.75)], startPoint: .top, endPoint: .bottom)))
                }
            }
            .padding(width * 0.035)
            .background(RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ArtPalette.outline.opacity(0.7), lineWidth: 1))
        case .roulette:
            RouletteWheelFace()
                .overlay(Circle().stroke(ArtPalette.goldLight, lineWidth: 2))
        case .pachinko:
            // v12.6：小弹子机——拱形台面、钉子、液晶屋檐、钢珠，右边一根红头弹簧拉杆
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let board = CGRect(x: w * 0.08, y: h * 0.02, width: w * 0.68, height: h * 0.96)
                var arch = Path()
                let r = board.width / 2
                arch.move(to: CGPoint(x: board.minX, y: board.maxY))
                arch.addLine(to: CGPoint(x: board.minX, y: board.minY + r))
                arch.addArc(center: CGPoint(x: board.midX, y: board.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                arch.addLine(to: CGPoint(x: board.maxX, y: board.maxY))
                arch.closeSubpath()
                ctx.fill(arch, with: .linearGradient(Gradient(colors: [Color(red: 0.24, green: 0.16, blue: 0.6), Color(red: 0.05, green: 0.04, blue: 0.2)]),
                                                     startPoint: CGPoint(x: 0, y: board.minY), endPoint: CGPoint(x: 0, y: board.maxY)))
                ctx.stroke(arch, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.55)]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)), lineWidth: max(2, w * 0.035))
                // 液晶屋檐
                let lcd = CGRect(x: board.midX - board.width * 0.24, y: board.minY + board.height * 0.3, width: board.width * 0.48, height: board.height * 0.2)
                var roof = Path()
                roof.move(to: CGPoint(x: lcd.minX - 3, y: lcd.minY))
                roof.addLine(to: CGPoint(x: lcd.midX, y: lcd.minY - lcd.height * 0.45))
                roof.addLine(to: CGPoint(x: lcd.maxX + 3, y: lcd.minY))
                let pink = Color(red: 1, green: 0.3, blue: 0.7)
                ctx.fill(Path(roundedRect: lcd, cornerRadius: 2), with: .color(Color(red: 0.06, green: 0.03, blue: 0.14)))
                ctx.stroke(Path(roundedRect: lcd, cornerRadius: 2), with: .color(pink), lineWidth: 1.6)
                ctx.stroke(roof, with: .color(pink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                for i in 0..<3 {
                    let c = CGRect(x: lcd.minX + lcd.width * (0.08 + 0.3 * CGFloat(i)), y: lcd.minY + lcd.height * 0.22, width: lcd.width * 0.24, height: lcd.height * 0.56)
                    ctx.fill(Path(roundedRect: c, cornerRadius: 1), with: .color(i == 1 ? ArtPalette.goldLight : ArtPalette.gold))
                }
                // 钉子
                let pin = max(1.3, w * 0.022)
                func nail(_ x: CGFloat, _ y: CGFloat) {
                    ctx.fill(Path(ellipseIn: CGRect(x: board.minX + board.width * x - pin, y: board.minY + board.height * y - pin, width: 2 * pin, height: 2 * pin)), with: .color(ArtPalette.goldLight))
                }
                for (x, y) in [(0.36, 0.1), (0.64, 0.1), (0.22, 0.2), (0.5, 0.18), (0.78, 0.2), (0.13, 0.36), (0.87, 0.36), (0.13, 0.5), (0.87, 0.5),
                               (0.25, 0.62), (0.5, 0.6), (0.75, 0.62), (0.14, 0.74), (0.38, 0.74), (0.62, 0.74), (0.86, 0.74), (0.26, 0.86), (0.74, 0.86)] as [(CGFloat, CGFloat)] {
                    nail(x, y)
                }
                // 始动口
                let cup = CGRect(x: board.midX - w * 0.05, y: board.minY + board.height * 0.83, width: w * 0.1, height: w * 0.08)
                ctx.fill(Path(roundedRect: cup, cornerRadius: 2), with: .color(Color(red: 0.3, green: 0.95, blue: 1)))
                // 钢珠
                let rb = max(2.6, w * 0.045)
                for (x, y) in [(0.3, 0.27), (0.7, 0.44), (0.5, 0.68)] as [(CGFloat, CGFloat)] {
                    let c = CGPoint(x: board.minX + board.width * x, y: board.minY + board.height * y)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - rb, y: c.y - rb, width: 2 * rb, height: 2 * rb)),
                             with: .radialGradient(Gradient(colors: [.white, Color(white: 0.75), Color(white: 0.35)]), center: CGPoint(x: c.x - rb * 0.3, y: c.y - rb * 0.35), startRadius: 0, endRadius: rb * 1.3))
                }
                // 弹簧拉杆
                let px = w * 0.88
                var spring = Path()
                let top = h * 0.42, bottomY = h * 0.8
                spring.move(to: CGPoint(x: px, y: top))
                let turns = 7
                for i in 1...turns {
                    spring.addLine(to: CGPoint(x: px + (i.isMultiple(of: 2) ? -1 : 1) * w * 0.045, y: top + (bottomY - top) * CGFloat(i) / CGFloat(turns)))
                }
                ctx.stroke(spring, with: .color(Color(white: 0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: px - rb, y: top - 2 * rb - 1, width: 2 * rb, height: 2 * rb)), with: .color(Color(white: 0.92)))
                let knob = w * 0.075
                ctx.fill(Path(ellipseIn: CGRect(x: px - knob, y: bottomY, width: 2 * knob, height: 2 * knob)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.5, blue: 0.5), Color(red: 0.85, green: 0.08, blue: 0.2)]), center: CGPoint(x: px - knob * 0.3, y: bottomY + knob * 0.6), startRadius: 0, endRadius: knob * 1.4))
            }
        }
    }
}

struct DoorArch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width / 2
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
