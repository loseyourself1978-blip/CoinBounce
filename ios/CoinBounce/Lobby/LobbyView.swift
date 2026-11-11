import SwiftUI

// MARK: - v12.1 大厅：启动后的第一个画面（全部用代码画）
struct LobbyView: View {
    @ObservedObject var router: AppRouter
    @ObservedObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @State private var line: BunnyLine? = nil
    @State private var showSettings = false
    @State private var showAdUnavailableHint = false
    @State private var glow = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = w * 0.045 + 10   // 两侧立柱里面再留一点
            let doorW = min((w - side * 2 - 8 * 2) / 3, 150)
            let doorH = doorW * 1.7
            let bunnyH = min(h * 0.42, 380)
            ZStack {
                LobbyBackdrop().ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, side)
                        .padding(.top, 6)
                    LobbySign(glow: glow)
                        .frame(height: min(h * 0.13, 110))
                        .padding(.horizontal, 22)
                        .padding(.top, h * 0.02)
                    Spacer(minLength: 8)
                    HStack(alignment: .bottom, spacing: 8) {
                        LobbyDoor(title: String(localized: "Coin Pusher"), tint: ArtPalette.gold, icon: .pusher, locked: false, width: doorW, height: doorH) {
                            router.open(.pusher)
                        }
                        .accessibilityIdentifier("doorPusher")
                        LobbyDoor(title: String(localized: "Roulette"), tint: Color(red: 0.2, green: 0.75, blue: 0.45), icon: .roulette, locked: false, width: doorW, height: doorH) {
                            router.open(.roulette)
                        }
                        .accessibilityIdentifier("doorRoulette")
                        LobbyDoor(title: String(localized: "Pachinko"), tint: Color(red: 0.45, green: 0.6, blue: 1.0), icon: .pachinko, locked: true, width: doorW, height: doorH) {
                            say(String(localized: "Pachinko opens soon!"), pose: .blowKiss)
                        }
                        .accessibilityIdentifier("doorPachinko")
                    }
                    Spacer(minLength: 8)
                    // 兔女郎迎宾：点她换一句话、换一个动作
                    HStack(alignment: .bottom, spacing: 0) {
                        BunnyHostess(line: line, height: bunnyH)
                            .contentShape(Rectangle())
                            .onTapGesture { greet() }
                            .accessibilityIdentifier("lobbyBunny")
                            .padding(.leading, w * 0.12)
                        Spacer(minLength: 0)
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
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            glow = true
            greet()
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            CoinBalanceView(coins: gameState.availableCoins, height: 30, width: 150)
            Spacer(minLength: 0)
            if ads.adsEnabled {
                AdHUDButton(ads: ads, gameState: gameState, showUnavailableHint: $showAdUnavailableHint)
                    .frame(width: AdHUDButton.size.width, height: AdHUDButton.size.height)
            }
            SettingsButton { showSettings = true }
        }
        .frame(height: 36)
    }

    private func greet() { line = BunnyScript.greeting() }
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
    enum Icon { case pusher, roulette, pachinko }
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
                        .frame(width: width * 0.62, height: width * 0.62)
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
        case .roulette:
            RouletteWheelFace()
                .overlay(Circle().stroke(ArtPalette.goldLight, lineWidth: 2))
        case .pachinko:
            Canvas { ctx, size in
                let rows = 4
                for r in 0..<rows {
                    let cols = r.isMultiple(of: 2) ? 4 : 3
                    for c in 0..<cols {
                        let x = size.width * (CGFloat(c) + (r.isMultiple(of: 2) ? 0.5 : 1.0)) / 4
                        let y = size.height * (CGFloat(r) + 0.6) / CGFloat(rows + 1)
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(.white))
                    }
                }
                let b = CGRect(x: size.width * 0.42, y: size.height * 0.78, width: size.width * 0.16, height: size.width * 0.16)
                ctx.fill(Path(ellipseIn: b), with: .color(Color(red: 0.8, green: 0.85, blue: 0.95)))
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
