import SwiftUI
import SpriteKit

// MARK: - V20 稳定版 (基于V16结构)
// 修复编译错误，使用正确的GameState属性

struct CoinPusherView: View {
    @StateObject private var gameState = GameState.shared
    @State private var pusherOffset: CGFloat = 0
    @State private var showArrow = true
    @State private var arrowBounce = false
    @State private var fallingCoins: [FallingCoin] = []
    @State private var showNoCoinsHint = false

    var body: some View {
        GeometryReader { geo in
            let sw = geo.size.width
            let sh = geo.size.height

            ZStack(alignment: .top) {
                // 主内容
                VStack(spacing: 0) {
                    // ── Jackpot金色区域 + 过渡色 (8%) ──
                    jackpotWithTransition(w: sw, h: sh * 0.080)

                    // ── V9: 老虎机 (15%) ──
                    SlotMachineView(
                        reels: gameState.slotReels,
                        spinState: gameState.slotSpinState,
                        onSpin: { gameState.spinSlot() }
                    )
                    .frame(height: sh * 0.150)
                    .padding(.horizontal, 10)

                    // ── COIN滑块 + BONUS滑块轨道 (4.5%) ──
                    coinBonusSliderTrack(w: sw, h: sh * 0.045)

                    // ── 战斗场景 (15%) - 压缩以容纳投币按钮 ──
                    battleArea(w: sw, h: sh * 0.150)

                    // ── 水果收集栏 (8%) ──
                    fruitCollectionBar(w: sw, h: sh * 0.080)

                    // ── 推币台 (33%) ──
                    pusherAreaSection(w: sw, h: sh * 0.330)

                    // ── 投币按钮 (9.5%) ──
                    coinDropButton(w: sw, h: sh * 0.095)

                    Spacer(minLength: 0)
                }
                
                // V9.3: 全局 2D 金币渲染层 (覆盖全屏，防止在 Battle/Slider 区域被截断)
                LocalCoinCanvasLayer(bounds: CGSize(width: sw, height: sh))
                    .frame(width: sw, height: sh)

                // 飞分特效层
                ForEach(gameState.floatingScores) { score in
                    FloatingScoreView(score: score)
                        .position(x: sw/2 + score.x, y: sh * 0.7 + score.y)
                }

                // 奖励/庆祝层
                if gameState.showJackpotExplosion {
                    JackpotCelebrationView(amount: GameConstants.slotJackpotReward)
                        .frame(width: sw, height: sh)
                }
                if gameState.showCardSelection {
                    CardSelectionView { choice in
                        withAnimation(.easeOut(duration: 0.2)) { gameState.selectCardReward(choice) }
                    }
                    .frame(width: sw, height: sh)
                }
                if gameState.showRewardModal {
                    RewardModalView(amount: gameState.rewardAmount) {
                        withAnimation(.easeOut(duration: 0.2)) { gameState.showRewardModal = false }
                    }
                    .frame(width: sw, height: sh)
                }
            }
            .background(Color(red: 0.05, green: 0.04, blue: 0.02))
            .animation(.easeOut(duration: 0.25), value: gameState.showJackpotExplosion)
            .animation(.easeOut(duration: 0.25), value: gameState.showCardSelection)
            .animation(.easeOut(duration: 0.25), value: gameState.showRewardModal)
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - 动画控制
    private func startAnimations() {
        // 推块往复动画
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: true)) {
            pusherOffset = 1.0
        }

        // 箭头跳动
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            arrowBounce = true
        }

        // 启动显示链路
        GameState.shared.startDisplayLink()
    }

    // MARK: - Jackpot + 过渡色组合
    @ViewBuilder
    func jackpotWithTransition(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // 渐变背景 - 参考图: 顶部红色(0-15%) → 金棕色(15-60%) → 白色(60-100%)
            LinearGradient(stops: [
                .init(color: Color(red: 0.96, green: 0.22, blue: 0.21), location: 0.00),  // 红色 y=0-15%
                .init(color: Color(red: 0.64, green: 0.57, blue: 0.45), location: 0.15),  // 过渡到金棕
                .init(color: Color(red: 0.68, green: 0.57, blue: 0.45), location: 0.30),  // 金棕色
                .init(color: Color(red: 0.83, green: 0.78, blue: 0.80), location: 0.60), // 浅色过渡
                .init(color: Color(red: 0.95, green: 0.92, blue: 0.95), location: 0.80), // 接近白色
                .init(color: Color(red: 0.98, green: 0.95, blue: 0.97), location: 1.00)   // 白色
            ], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                Spacer()
                Text("JACKPOT")
                    .font(.system(size: max(8, h * 0.15), weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.35, green: 0.18, blue: 0.05))
                    .tracking(3)

                Text("100000")
                    .font(.system(size: max(24, h * 0.35), weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [
                        Color(red: 0.95, green: 0.75, blue: 0.15),
                        Color(red: 1.00, green: 0.98, blue: 0.65),
                        Color(red: 0.90, green: 0.70, blue: 0.10)
                    ], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .orange.opacity(0.5), radius: 4)
                Spacer()
            }
        }
        .frame(height: h)
        .overlay(alignment: .topLeading) {
            CoinBalanceView(coins: gameState.availableCoins)
                .padding(.leading, 10)
                .padding(.top, 6)
        }
    }

    // MARK: - COIN滑块 + BONUS滑块轨道
    @ViewBuilder
    func coinBonusSliderTrack(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // 白色轨道背景
            LinearGradient(stops: [
                .init(color: Color(red: 0.92, green: 0.92, blue: 0.88), location: 0.0),
                .init(color: Color(red: 1.0, green: 1.0, blue: 0.98), location: 1.0)
            ], startPoint: .leading, endPoint: .trailing)
            .frame(height: h * 0.5)

            // BONUS滑块 (空心触发)
            bonusSlider(w: w, h: h * 0.45, offset: gameState.bonusSliderOffset)

            // COIN滑块 (金币出口)
            coinSlider(w: w, h: h * 0.40, offset: gameState.coinSliderOffset)
        }
        .frame(height: h)
    }

    // MARK: - COIN滑块 (金币出口)
    @ViewBuilder
    func coinSlider(w: CGFloat, h: CGFloat, offset: CGFloat) -> some View {
        let sliderW: CGFloat = w * 0.055  // 56/960 ≈ 5.5%
        let sliderH: CGFloat = h
        let travelRange: CGFloat = w * 0.015 // 14/960 ≈ 1.5%
        let baseX: CGFloat = w * 0.228 // 218/960 ≈ 22.8%

        HStack(spacing: 0) {
            // 金棕色盾牌主体
            ZStack {
                // 盾牌背景
                RoundedRectangle(cornerRadius: sliderW * 0.15)
                    .fill(LinearGradient(stops: [
                        .init(color: Color(red: 0.52, green: 0.38, blue: 0.12), location: 0.0),
                        .init(color: Color(red: 0.42, green: 0.30, blue: 0.07), location: 0.5),
                        .init(color: Color(red: 0.52, green: 0.38, blue: 0.12), location: 1.0)
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(width: sliderW * 0.8, height: sliderH)

                // 金色边框
                RoundedRectangle(cornerRadius: sliderW * 0.15)
                    .stroke(Color(red: 0.82, green: 0.66, blue: 0.31), lineWidth: 1)

                // 1 COIN 文字
                Text("1 COIN")
                    .font(.system(size: sliderW * 0.22, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.05))
            }
            .frame(width: sliderW, height: sliderH)
        }
        .offset(x: baseX + offset * travelRange)
    }

    // MARK: - BONUS滑块 (空心触发)
    @ViewBuilder
    func bonusSlider(w: CGFloat, h: CGFloat, offset: CGFloat) -> some View {
        // V9.0: 此函数已废弃，由 fruitCollectionBar 内部的 overlay 替代
        EmptyView()
    }

    // MARK: - 战斗场景
    @ViewBuilder
    func battleArea(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // 1. 外部精美边框
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.2, blue: 0.1), Color(red: 0.15, green: 0.1, blue: 0.05)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom), lineWidth: 3)
                )
                .padding(4)
            
            // 2. 内部场景 (森林 + 地面)
            ZStack {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color(red: 0.02, green: 0.15, blue: 0.02), Color(red: 0.1, green: 0.25, blue: 0.1)], startPoint: .top, endPoint: .bottom)
                    Color(red: 0.25, green: 0.18, blue: 0.1)
                        .frame(height: h * 0.3)
                }
                
                // 简单的树林装饰
                HStack(spacing: 40) {
                    ForEach(0..<4) { _ in
                        Image(systemName: "tree.fill")
                            .foregroundColor(Color.black.opacity(0.3))
                            .font(.system(size: h * 0.4))
                    }
                }
                .offset(y: -h * 0.1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(10)

            // 左侧勇士
            VStack {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 20))
                        .frame(width: w * 0.2, height: w * 0.2)
                    Text("🛡️")
                        .font(.system(size: w * 0.12))
                }
                Text("勇士")
                    .font(.system(size: w * 0.035, weight: .black))
                    .foregroundColor(.white)
                    .shadow(radius: 2)

                // 血条
                HealthBar(progress: 0.8, color: .green, width: w * 0.18)
            }
            .position(x: w * 0.22, y: h * 0.5)

            // VS 文字
            Text("VS")
                .font(.system(size: w * 0.08, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                .italic()
                .shadow(color: .black, radius: 4)
                .position(x: w * 0.50, y: h * 0.45)

            // 右侧敌人
            VStack {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.red.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 20))
                        .frame(width: w * 0.2, height: w * 0.2)
                    Text("👺")
                        .font(.system(size: w * 0.12))
                }
                Text("BOSS")
                    .font(.system(size: w * 0.030, weight: .black))
                    .foregroundColor(.white)
                    .shadow(radius: 2)

                // 血条
                HealthBar(progress: 0.6, color: .red, width: w * 0.18)
            }
            .position(x: w * 0.78, y: h * 0.5)

            // 连击文字
            if gameState.combo.isActive {
                Text(gameState.combo.message)
                    .font(.system(size: w * 0.05, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.red, .orange, .yellow], startPoint: .top, endPoint: .bottom))
                    .position(x: w * 0.50, y: h * 0.75)
            }
        }
        .frame(height: h)
    }

    struct HealthBar: View {
        let progress: CGFloat
        let color: Color
        let width: CGFloat
        var body: some View {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: width, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: width * progress, height: 6)
            }
        }
    }

    // MARK: - 水果收集栏
    @ViewBuilder
    func fruitCollectionBar(w: CGFloat, h: CGFloat) -> some View {
        let fruits = ["🍎", "🍋", "🍇", "🍓", "🍑", "🍒", "🥝"]
        let lampWidth = w / 7.0
        let iconSize = min(lampWidth * 0.65, h * 0.55)

        ZStack(alignment: .top) {
            // 深色背景
            LinearGradient(stops: [
                .init(color: Color(red: 0.08, green: 0.06, blue: 0.04), location: 0.0),
                .init(color: Color(red: 0.12, green: 0.10, blue: 0.06), location: 0.5),
                .init(color: Color(red: 0.08, green: 0.06, blue: 0.04), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            // 上边框（红色装饰线）
            Rectangle()
                .fill(Color(red: 0.55, green: 0.15, blue: 0.10))
                .frame(height: 3)

            // 7个水果灯 — 等分全屏宽度，每个占 1/7
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    ZStack {
                        // 外圈
                        Circle()
                            .fill(Color.black)
                            .frame(width: iconSize * 1.15, height: iconSize * 1.15)

                        // 内圈 (点亮/暗灭)
                        Circle()
                            .fill(gameState.fruitsLit[index] ?
                                  LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom) :
                                  LinearGradient(colors: [Color.gray.opacity(0.3), Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                            .frame(width: iconSize, height: iconSize)

                        // 水果emoji
                        Text(fruits[index])
                            .font(.system(size: iconSize * 0.5))
                    }
                    .frame(width: lampWidth, height: h * 0.8)
                    .opacity(gameState.fruitsLit[index] ? 1.0 : 0.6)
                    .scaleEffect(gameState.fruitPulseIndex == index ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: gameState.fruitPulseIndex)
                    .shadow(color: gameState.fruitsLit[index] ? .yellow.opacity(0.8) : .clear, radius: 6)
                }
            }
            .frame(width: w)
            .padding(.top, 5)
        }
        .frame(height: h)
        // BONUS滑块在水果灯下方 0.6 coin height (16.8pt)
        .overlay(alignment: .bottom) {
            GeometryReader { _ in
                HollowBonusSliderTarget(screenWidth: w)
                    .position(x: w / 2, y: h + iconSize * 0.35 + 16.8)
            }
            .frame(height: 0) // Don't consume layout space
        }
    }

    // MARK: - 推币台区域
    @ViewBuilder
    func pusherAreaSection(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // 参考推币台背景图（用于对齐参考App的材质/细节）
            Image("coin_pusher_ref")
                .resizable()
                .scaledToFill()
                .frame(height: h)
                .clipped()

            // 推块组件
            pusherAssembly(w: w, h: h * 0.22)

            // 左右斜坡
            ramps(w: w, h: h * 0.40)

            // 喷币管
            coinSprayers(w: w, h: h * 0.40)

            // BONUS滑块
            bonusSlideTrigger(w: w, h: h * 0.15)
        }
        .frame(height: h)
    }

    // MARK: - 推块组件
    @ViewBuilder
    func pusherAssembly(w: CGFloat, h: CGFloat) -> some View {
        let pusherW: CGFloat = w * 0.91  // 872/960 ≈ 91%
        let pusherH: CGFloat = h * 0.90

        ZStack(alignment: .top) {
            // 红色格挡（在推块上方）
            Rectangle()
                .fill(Color(red: 0.65, green: 0.10, blue: 0.10))
                .frame(width: pusherW * 1.02, height: h * 0.15)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(red: 0.45, green: 0.05, blue: 0.05))
                        .frame(height: h * 0.03)
                }

            // 棕色推块
            VStack(spacing: 0) {
                // 上方金棕色 (86,56,18)
                Rectangle()
                    .fill(LinearGradient(stops: [
                        .init(color: Color(red: 0.40, green: 0.26, blue: 0.10), location: 0.0),
                        .init(color: Color(red: 0.34, green: 0.22, blue: 0.07), location: 0.5),
                        .init(color: Color(red: 0.40, green: 0.26, blue: 0.10), location: 1.0)
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.51)

                // 中间金线 (210,168,78)
                Rectangle()
                    .fill(Color(red: 0.82, green: 0.66, blue: 0.31))
                    .frame(height: h * 0.04)

                // 下方深色 (30,22,23)
                Rectangle()
                    .fill(Color(red: 0.12, green: 0.09, blue: 0.09))
                    .frame(height: h * 0.45)
            }
            .frame(width: pusherW, height: pusherH)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            .offset(y: pusherOffset * h * 0.08)
        }
        .frame(height: h)
    }

    // MARK: - 金币堆
    @ViewBuilder
    func coinPile(w: CGFloat, h: CGFloat) -> some View {
        let coinSize: CGFloat = w * 0.035  // 42/960 ≈ 4.5%
        let cols = 14
        let rows = 4

        ZStack {
            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<cols, id: \.self) { col in
                    let offsetX = CGFloat(col - cols/2) * coinSize * 1.05
                    let offsetY = CGFloat(row) * coinSize * 0.50
                    let brightness = 1.0 - Double(row) * 0.08

                    Circle()
                        .fill(Color(red: 0.92 * brightness, green: 0.59 * brightness, blue: 0.04 * brightness))
                        .frame(width: coinSize, height: coinSize)
                        .overlay {
                            Circle()
                                .stroke(Color(red: 0.80 * brightness, green: 0.50 * brightness, blue: 0.02), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                        .offset(x: offsetX, y: offsetY)
                }
            }
        }
        .position(x: w/2, y: h * 0.60)
    }

    // MARK: - 左右斜坡
    @ViewBuilder
    func ramps(w: CGFloat, h: CGFloat) -> some View {
        // 左侧斜坡 (46-139像素)
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w * 0.145, y: h * 0.6))
            path.addLine(to: CGPoint(x: 0, y: h * 0.6))
            path.closeSubpath()
        }
        .fill(LinearGradient(stops: [
            .init(color: Color(red: 0.20, green: 0.32, blue: 0.28), location: 0.0),
            .init(color: Color(red: 0.16, green: 0.25, blue: 0.22), location: 1.0)
        ], startPoint: .top, endPoint: .bottom))

        // 右侧斜坡 (330-431像素)
        Path { path in
            path.move(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w - w * 0.145, y: h * 0.6))
            path.addLine(to: CGPoint(x: w, y: h * 0.6))
            path.closeSubpath()
        }
        .fill(LinearGradient(stops: [
            .init(color: Color(red: 0.20, green: 0.32, blue: 0.28), location: 0.0),
            .init(color: Color(red: 0.16, green: 0.25, blue: 0.22), location: 1.0)
        ], startPoint: .top, endPoint: .bottom))
    }

    // MARK: - 喷币管
    @ViewBuilder
    func coinSprayers(w: CGFloat, h: CGFloat) -> some View {
        // 左侧喷币管
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 0.30, green: 0.55, blue: 0.35), location: 0.0),
                    .init(color: Color(red: 0.20, green: 0.40, blue: 0.25), location: 0.5),
                    .init(color: Color(red: 0.30, green: 0.55, blue: 0.35), location: 1.0)
                ], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.035, height: h * 0.35)

            // 喷口
            Circle()
                .fill(Color(red: 0.15, green: 0.30, blue: 0.20))
                .frame(width: w * 0.045, height: w * 0.045)
        }
        .position(x: w * 0.11, y: h * 0.20)

        // 右侧喷币管
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 0.30, green: 0.55, blue: 0.35), location: 0.0),
                    .init(color: Color(red: 0.20, green: 0.40, blue: 0.25), location: 0.5),
                    .init(color: Color(red: 0.30, green: 0.55, blue: 0.35), location: 1.0)
                ], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.035, height: h * 0.35)

            Circle()
                .fill(Color(red: 0.15, green: 0.30, blue: 0.20))
                .frame(width: w * 0.045, height: w * 0.045)
        }
        .position(x: w * 0.89, y: h * 0.20)
    }

    // MARK: - BONUS滑块触发区
    @ViewBuilder
    func bonusSlideTrigger(w: CGFloat, h: CGFloat) -> some View {
        // 六边形收集槽
        Path { path in
            let cx = w / 2
            let cy = h * 0.95
            let size = w * 0.08

            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 6
                let x = cx + size * cos(angle)
                let y = cy + size * sin(angle)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
        }
        .fill(Color(red: 0.25, green: 0.35, blue: 0.25))
        .overlay(
            Path { path in
                let cx = w / 2
                let cy = h * 0.95
                let size = w * 0.08

                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 3 - .pi / 6
                    let x = cx + size * cos(angle)
                    let y = cy + size * sin(angle)
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                path.closeSubpath()
            }
            .stroke(Color(red: 0.50, green: 0.70, blue: 0.50), lineWidth: 2)
        )
    }

    // MARK: - 投币按钮
    @ViewBuilder
    func coinDropButton(w: CGFloat, h: CGFloat) -> some View {
        let buttonSize = min(w * 0.22, h * 0.85)

        ZStack {
            // 投币按钮（居中，贴近参考App）
            ZStack {
                // 新手引导箭头（严格按状态位控制）
                if gameState.showTutorialArrow {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.down")
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: buttonSize * 0.18, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .white], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .yellow.opacity(0.8), radius: 8)
                    .offset(y: -buttonSize * 0.75 + (arrowBounce ? 6 : 0))
                }

                // 六边形投币按钮（对齐参考App）
                Hexagon()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.78, blue: 0.10),
                                Color(red: 0.65, green: 0.45, blue: 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: buttonSize, height: buttonSize * 0.92)
                    .overlay(
                        Hexagon().stroke(Color(red: 0.98, green: 0.90, blue: 0.55), lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
                    .saturation(gameState.canDropCoin ? 1 : 0)

                Hexagon()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: buttonSize * 0.72, height: buttonSize * 0.66)
                    .overlay(
                        Text("$")
                            .font(.system(size: buttonSize * 0.28, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.yellow, .white], startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    )
            }
            .opacity(gameState.canDropCoin ? 1 : 0.5)
            .onTapGesture {
                if gameState.canDropCoin {
                    gameState.dropCoin()
                } else {
                    gameState.requestFreeCoins()
                    showNoCoinsHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showNoCoinsHint = false }
                }
            }

            // 金币用完提示
            if showNoCoinsHint {
                Text("金币不足")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .offset(y: -buttonSize * 0.75)
                    .transition(.opacity)
            }
        }
        .frame(height: h)
        .background(Color(red: 0.06, green: 0.05, blue: 0.03))
    }
}

// MARK: - 金币余额
struct CoinBalanceView: View {
    let coins: Int
    @State private var bump = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.9, blue: 0.4), Color(red: 0.8, green: 0.5, blue: 0.1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color(red: 0.5, green: 0.3, blue: 0.0), lineWidth: 1))
                .overlay(Text("¥").font(.system(size: 10, weight: .black)).foregroundColor(Color(red: 0.4, green: 0.2, blue: 0.0)))
                .frame(width: 18, height: 18)
            Text("\(coins)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Color.arcadeGold.opacity(0.8), lineWidth: 1))
        .scaleEffect(bump ? 1.12 : 1.0)
        .onChange(of: coins) { _ in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.2)) { bump = false }
            }
        }
    }
}

// MARK: - 飞分特效
struct FloatingScoreView: View {
    let score: FloatingScore

    var body: some View {
        Text(score.text)
            .font(.system(size: 36, weight: .black, design: .rounded))
            .foregroundStyle(score.color)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
            .opacity(score.opacity)
            .scaleEffect(score.scale)
    }
}

// MARK: - 六边形
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let dx = w * 0.22
        return Path { p in
            p.move(to: CGPoint(x: dx, y: 0))
            p.addLine(to: CGPoint(x: w - dx, y: 0))
            p.addLine(to: CGPoint(x: w, y: h * 0.5))
            p.addLine(to: CGPoint(x: w - dx, y: h))
            p.addLine(to: CGPoint(x: dx, y: h))
            p.addLine(to: CGPoint(x: 0, y: h * 0.5))
            p.closeSubpath()
        }
    }
}

// MARK: - V9.0 核心复原组件

struct LocalCoinCanvasLayer: View {
    let bounds: CGSize
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let state = GameState.shared
                let bedCoins = state.bedCoins
                let active2DCoins = state.active2DCoins
                
                // V9.5: 精准坐标映射
                // 物理坐标系: Y ∈ [-360, 20]. 屏幕映射:
                //   - 滑块轨道顶部 ≈ 0.275 sh (8% + 15% + 4.5%)
                //   - 推币台底部  ≈ 0.905 sh (+ 33% pusher + overlap)
                // 映射公式: screenY = originY + (physicsY / physicsRange) * sectionHeight
                let physicsTop: CGFloat = -360  // dropCoin Y
                let physicsBot: CGFloat = 20    // enter3DY
                let physicsRange = physicsBot - physicsTop // 380
                
                // 屏幕区域: 从滑块轨道(27.5% sh)到推币台结束(90.5% sh)
                let screenTopY = size.height * 0.275
                let screenBotY = size.height * 0.905
                let screenRange = screenBotY - screenTopY
                
                // 推币床: 在推币台区域内 (57.5% ~ 90.5% sh)
                let bedTopY = size.height * 0.60
                let bedBotY = size.height * 0.90
                let bedRange = bedBotY - bedTopY
                
                let sortedActive = active2DCoins.sorted { $0.y < $1.y }
                let sortedBed = bedCoins.sorted { $0.y < $1.y }
                
                // 绘制下落金币
                for coin in sortedActive {
                    let normalizedY = (coin.y - physicsTop) / physicsRange
                    let screenY = screenTopY + normalizedY * screenRange
                    let coinRect = CGRect(
                        x: size.width / 2 + coin.x - coin.radius,
                        y: screenY - coin.radius,
                        width: coin.radius * 2,
                        height: coin.radius * 2
                    )
                    
                    // 金色渐变主体
                    let gradient = Gradient(colors: [
                        Color(red: 1.0, green: 0.9, blue: 0.4),
                        Color(red: 0.8, green: 0.5, blue: 0.1),
                        Color(red: 0.6, green: 0.3, blue: 0.0)
                    ])
                    context.fill(Path(ellipseIn: coinRect), with: .linearGradient(gradient, startPoint: CGPoint(x: coinRect.minX, y: coinRect.minY), endPoint: CGPoint(x: coinRect.maxX, y: coinRect.maxY)))
                    context.stroke(Path(ellipseIn: coinRect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.4)), lineWidth: 1)
                    context.stroke(Path(ellipseIn: coinRect), with: .color(.black.opacity(0.3)), lineWidth: 1.5)
                    context.draw(Text("¥").font(.system(size: coin.radius * 1.2, weight: .black)).foregroundColor(Color(red: 0.4, green: 0.2, blue: 0.0).opacity(0.6)), in: coinRect)
                }
                
                // 绘制推床金币
                for coin in sortedBed {
                    // bedCoins Y typically in [0..215]
                    let normalizedBedY = coin.y / 215.0
                    let screenY = bedTopY + normalizedBedY * bedRange
                    let coinRect = CGRect(
                        x: size.width / 2 + coin.x - coin.radius,
                        y: screenY - coin.radius,
                        width: coin.radius * 2,
                        height: coin.radius * 2
                    )
                    
                    // 底层阴影 (深度感)
                    context.fill(Path(ellipseIn: coinRect.offsetBy(dx: 2, dy: 2)), with: .color(Color.black.opacity(0.4)))
                    
                    // 动态光泽渐变 (根据 Y 轴微调色温)
                    let brightnessShift = Double(coin.y) / 500.0 * 0.1
                    let coinGradient = Gradient(colors: [
                        Color(red: 1.0, green: 0.98, blue: 0.8).opacity(1.0 - brightnessShift),
                        Color(red: 0.95, green: 0.75, blue: 0.1),
                        Color(red: 0.70, green: 0.45, blue: 0.05)
                    ])
                    
                    context.fill(Path(ellipseIn: coinRect), with: .linearGradient(coinGradient, startPoint: CGPoint(x: coinRect.minX, y: coinRect.minY), endPoint: CGPoint(x: coinRect.maxX, y: coinRect.maxY)))
                    context.stroke(Path(ellipseIn: coinRect), with: .color(Color(red: 0.5, green: 0.3, blue: 0.0)), lineWidth: 1.0)
                    
                    // 中心压印
                    context.draw(Text("§").font(.system(size: coin.radius * 1.1, weight: .heavy)).foregroundColor(Color.black.opacity(0.15)), in: coinRect)
                }
                
                // 绘制粒子 (V9.4)
                for particle in state.particles {
                    let normalizedPY = (particle.y - physicsTop) / physicsRange
                    let pScreenY = screenTopY + normalizedPY * screenRange
                    let pRect = CGRect(x: size.width/2 + particle.x - 3, y: pScreenY - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: pRect), with: .color(particle.color.opacity(Double(particle.life))))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct HollowBonusSliderTarget: View {
    let screenWidth: CGFloat
    @StateObject private var gameState = GameState.shared
    
    var body: some View {
        // V9.2: 严格遵守 1/7 屏宽规范 (约 14.28%)
        let exactWidth = screenWidth / 7.0
        let h = exactWidth * 0.45 // 略微压扁，保持精致感
        
        ZStack {
            // 黑底金边盾牌 (参考图)
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.2))
                p.addLine(to: CGPoint(x: exactWidth/2, y: 0))
                p.addLine(to: CGPoint(x: exactWidth, y: h * 0.2))
                p.addLine(to: CGPoint(x: exactWidth, y: h * 0.8))
                p.addLine(to: CGPoint(x: exactWidth/2, y: h))
                p.addLine(to: CGPoint(x: 0, y: h * 0.8))
                p.closeSubpath()
            }
            .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.2))
                    p.addLine(to: CGPoint(x: exactWidth/2, y: 0))
                    p.addLine(to: CGPoint(x: exactWidth, y: h * 0.2))
                    p.addLine(to: CGPoint(x: exactWidth, y: h * 0.8))
                    p.addLine(to: CGPoint(x: exactWidth/2, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h * 0.8))
                    p.closeSubpath()
                }
                .stroke(Color.yellow, lineWidth: 2)
            )
            
            VStack(spacing: -2) {
                Text("BONUS")
                    .font(.system(size: exactWidth * 0.2, weight: .black))
                    .foregroundColor(.yellow)
                Text("💰")
                    .font(.system(size: exactWidth * 0.3))
            }
        }
        .frame(width: exactWidth, height: h)
        .offset(x: gameState.bonusSliderOffset)
    }
}

struct AbsoluteGeometryOverlays {
    static func bonusSliderYOffset(fruitContainerHeight: CGFloat, iconSize: CGFloat) -> CGFloat {
        let iconBottomLocalY = (fruitContainerHeight / 2) + (iconSize / 2)
        let exactTargetGap: CGFloat = 16.8
        return iconBottomLocalY + exactTargetGap
    }
}
struct FallingCoin: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var velocityY: CGFloat = 0
    var bonusTriggered: Bool = false
    var fruitTriggered: Bool = false
}

// MARK: - 预览
#Preview {
    CoinPusherView()
}
