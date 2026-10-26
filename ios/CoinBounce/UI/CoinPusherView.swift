import SwiftUI
import SpriteKit

// MARK: - V20 稳定版 (基于V16结构)
// 修复编译错误，使用正确的GameState属性

struct CoinPusherView: View {
    @StateObject private var gameState = GameState.shared
    @State private var arrowBounce = false
    @State private var showNoCoinsHint = false

    var body: some View {
        // 外层不忽略安全区，才能读到真实的安全区边距；内容再铺满整屏
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)
            gameScreen(layout: GameLayout(size: full, safeArea: insets))
                .frame(width: full.width, height: full.height)
                .offset(x: -insets.leading, y: -insets.top)
        }
    }

    @ViewBuilder
    private func gameScreen(layout: GameLayout) -> some View {
            // 唯一布局来源：区域摆放、物理、金币绘制都用它（整屏坐标）
            let sw = layout.size.width
            let sh = layout.size.height

            ZStack(alignment: .topLeading) {
                Color(red: 0.05, green: 0.04, blue: 0.02)

                // ── Jackpot ──
                jackpotWithTransition(w: layout.jackpot.width, h: layout.jackpot.height)
                    .place(in: layout.jackpot)

                // ── 老虎机（SPIN 在转轴右侧）──
                SlotMachineView(
                    reels: gameState.slotReels,
                    spinState: gameState.slotSpinState,
                    reelsFrame: layout.slotReels.offsetBy(dx: -layout.slotMachine.minX, dy: -layout.slotMachine.minY),
                    spinFrame: layout.spinButton.offsetBy(dx: -layout.slotMachine.minX, dy: -layout.slotMachine.minY),
                    onSpin: { gameState.spinSlot() }
                )
                .place(in: layout.slotMachine)

                // ── COIN 滑块轨道 ──
                coinSliderTrack(layout: layout)
                    .place(in: layout.sliderTrack)

                // ── 战斗场景（下落金币区）──
                battleArea(w: layout.dropField.width, h: layout.dropField.height)
                    .place(in: layout.dropField)

                // ── 水果收集栏 ──
                fruitCollectionBar(layout: layout)
                    .place(in: layout.fruitBar)

                // ── BONUS 滑块轨道 ──
                bonusLane(layout: layout)
                    .place(in: layout.bonusLane)

                // ── 推币台 ──
                pusherAreaSection(layout: layout)
                    .place(in: layout.pusher)

                // ── 投币按钮（背景延伸到底部安全区）──
                Color(red: 0.06, green: 0.05, blue: 0.03)
                    .place(in: CGRect(x: 0, y: layout.dropButton.minY, width: sw, height: sh - layout.dropButton.minY))
                coinDropButton(w: layout.dropButton.width, h: layout.dropButton.height)
                    .place(in: layout.dropButton)

                // 金币、格挡、粒子：与物理同一坐标，直接按点绘制
                LocalCoinCanvasLayer(layout: layout)
                    .frame(width: sw, height: sh)

                // 飞分特效层
                ForEach(gameState.floatingScores) { score in
                    FloatingScoreView(score: score)
                        .position(x: score.x, y: score.y)
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
            .frame(width: sw, height: sh)
            .animation(.easeOut(duration: 0.25), value: gameState.showJackpotExplosion)
            .animation(.easeOut(duration: 0.25), value: gameState.showCardSelection)
            .animation(.easeOut(duration: 0.25), value: gameState.showRewardModal)
            .onAppear {
                gameState.updateLayout(layout)
                startAnimations()
            }
            .onChange(of: layout) { newLayout in
                gameState.updateLayout(newLayout)
            }
    }

    // MARK: - 动画控制
    private func startAnimations() {
        // 箭头跳动
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            arrowBounce = true
        }

        // 启动显示链路
        GameState.shared.startDisplayLink()

        #if DEBUG
        // 截图用：启动参数 -debugAutoDrop N 会自动投 N 枚币
        let autoDrop = UserDefaults.standard.integer(forKey: "debugAutoDrop")
        for i in 0..<autoDrop {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(i) * 0.35) { gameState.dropCoin() }
        }
        #endif
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

    // MARK: - COIN滑块轨道
    @ViewBuilder
    func coinSliderTrack(layout: GameLayout) -> some View {
        let h = layout.sliderTrack.height
        let slider = layout.coinSliderCenter(offset: gameState.coinSliderOffset)

        ZStack(alignment: .topLeading) {
            // 白色轨道背景
            LinearGradient(stops: [
                .init(color: Color(red: 0.92, green: 0.92, blue: 0.88), location: 0.0),
                .init(color: Color(red: 1.0, green: 1.0, blue: 0.98), location: 1.0)
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: layout.sliderTrack.width, height: h * 0.5)
            .position(x: layout.sliderTrack.width / 2, y: h / 2)

            // COIN滑块 (金币出口)，与 dropCoin 的落点同一位置
            coinSlider(w: layout.coinSliderWidth, h: h * 0.8)
                .position(x: slider.x - layout.sliderTrack.minX, y: h / 2)
        }
    }

    // MARK: - COIN滑块 (金币出口)
    @ViewBuilder
    func coinSlider(w sliderW: CGFloat, h sliderH: CGFloat) -> some View {
        ZStack {
            // 盾牌背景
            RoundedRectangle(cornerRadius: sliderH * 0.2)
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 0.52, green: 0.38, blue: 0.12), location: 0.0),
                    .init(color: Color(red: 0.42, green: 0.30, blue: 0.07), location: 0.5),
                    .init(color: Color(red: 0.52, green: 0.38, blue: 0.12), location: 1.0)
                ], startPoint: .top, endPoint: .bottom))

            // 金色边框
            RoundedRectangle(cornerRadius: sliderH * 0.2)
                .stroke(Color(red: 0.82, green: 0.66, blue: 0.31), lineWidth: 1)

            // 1 COIN 文字
            Text("1 COIN")
                .font(.system(size: min(sliderW * 0.22, sliderH * 0.6), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.95, green: 0.85, blue: 0.55))
        }
        .frame(width: sliderW, height: sliderH)
    }

    // MARK: - 战斗场景
    @ViewBuilder
    func battleArea(w: CGFloat, h: CGFloat) -> some View {
        // 人物大小同时受宽、高限制，矮屏不溢出
        let figure = min(w * 0.2, h * 0.5)
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
                HStack(spacing: w * 0.1) {
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
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 20))
                        .frame(width: figure, height: figure)
                    Text("🛡️")
                        .font(.system(size: figure * 0.6))
                }
                Text("勇士")
                    .font(.system(size: min(w * 0.035, h * 0.12), weight: .black))
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
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.red.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 20))
                        .frame(width: figure, height: figure)
                    Text("👺")
                        .font(.system(size: figure * 0.6))
                }
                Text("BOSS")
                    .font(.system(size: min(w * 0.030, h * 0.12), weight: .black))
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
        .frame(width: w, height: h)
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
    func fruitCollectionBar(layout: GameLayout) -> some View {
        let fruits = ["🍎", "🍋", "🍇", "🍓", "🍑", "🍒", "🥝"]
        let bar = layout.fruitBar
        let iconSize = min(layout.fruitLampWidth * 0.8, bar.height * 0.6)

        ZStack(alignment: .topLeading) {
            // 深色背景
            LinearGradient(stops: [
                .init(color: Color(red: 0.08, green: 0.06, blue: 0.04), location: 0.0),
                .init(color: Color(red: 0.12, green: 0.10, blue: 0.06), location: 0.5),
                .init(color: Color(red: 0.08, green: 0.06, blue: 0.04), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            // 上边框（红色装饰线）
            Rectangle()
                .fill(Color(red: 0.55, green: 0.15, blue: 0.10))
                .frame(width: bar.width, height: 3)

            // 7个水果灯 — 中心与物理判定 layout.fruitCenters 相同
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
                .opacity(gameState.fruitsLit[index] ? 1.0 : 0.6)
                .scaleEffect(gameState.fruitPulseIndex == index ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: gameState.fruitPulseIndex)
                .shadow(color: gameState.fruitsLit[index] ? .yellow.opacity(0.8) : .clear, radius: 6)
                .position(x: layout.fruitCenters[index].x - bar.minX, y: layout.fruitCenters[index].y - bar.minY)
            }
        }
    }

    // MARK: - BONUS 滑块轨道
    @ViewBuilder
    func bonusLane(layout: GameLayout) -> some View {
        let lane = layout.bonusLane
        let slider = layout.bonusSliderCenter(offset: gameState.bonusSliderOffset)

        ZStack(alignment: .topLeading) {
            Color(red: 0.10, green: 0.07, blue: 0.04)
            // 滑轨
            Capsule()
                .fill(Color(red: 0.35, green: 0.25, blue: 0.10))
                .frame(width: layout.fieldMaxX - layout.fieldMinX + layout.coinRadius * 2, height: 4)
                .position(x: layout.centerX - lane.minX, y: lane.height / 2)
            HollowBonusSliderTarget(width: layout.bonusSliderWidth, maxHeight: lane.height * 0.9)
                .position(x: slider.x - lane.minX, y: slider.y - lane.minY)
        }
    }

    // MARK: - 推币台区域
    @ViewBuilder
    func pusherAreaSection(layout: GameLayout) -> some View {
        let w = layout.pusher.width
        let h = layout.pusher.height

        ZStack(alignment: .top) {
            // 台面、侧栏、后挡板、掉落口（不画金币，金币全部由物理绘制）
            PusherBedBackground(layout: layout)
                .frame(width: w, height: h)

            // 推块组件：前沿 = 物理里的 pusherFrontRestY + pusherOffset
            pusherAssembly(w: w, frontY: layout.pusherFrontRestY - layout.pusher.minY + gameState.pusherOffset)

            // 左右引导斜坡
            ramps(w: w, h: h * 0.40)
        }
        .frame(width: w, height: h)
        .clipped()
    }

    // MARK: - 推块组件
    @ViewBuilder
    func pusherAssembly(w: CGFloat, frontY: CGFloat) -> some View {
        let pusherW: CGFloat = w * 0.91  // 与 layout.bedMinX/bedMaxX 相同
        let pusherH = max(0, frontY)

        ZStack(alignment: .top) {
            // 棕色推块
            VStack(spacing: 0) {
                // 红色格挡
                Rectangle()
                    .fill(Color(red: 0.65, green: 0.10, blue: 0.10))
                    .frame(height: pusherH * 0.15)
                // 上方金棕色
                Rectangle()
                    .fill(LinearGradient(stops: [
                        .init(color: Color(red: 0.40, green: 0.26, blue: 0.10), location: 0.0),
                        .init(color: Color(red: 0.34, green: 0.22, blue: 0.07), location: 0.5),
                        .init(color: Color(red: 0.40, green: 0.26, blue: 0.10), location: 1.0)
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(height: pusherH * 0.45)

                // 中间金线
                Rectangle()
                    .fill(Color(red: 0.82, green: 0.66, blue: 0.31))
                    .frame(height: pusherH * 0.04)

                // 下方深色
                Rectangle()
                    .fill(Color(red: 0.12, green: 0.09, blue: 0.09))
                    .frame(height: pusherH * 0.36)
            }
            .frame(width: pusherW, height: pusherH)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .frame(width: w, height: pusherH, alignment: .top)
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
        .fill(PusherBedBackground.rampGradient)

        // 右侧斜坡 (330-431像素)
        Path { path in
            path.move(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w - w * 0.145, y: h * 0.6))
            path.addLine(to: CGPoint(x: w, y: h * 0.6))
            path.closeSubpath()
        }
        .fill(PusherBedBackground.rampGradient)
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
        .frame(width: w, height: h)
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
    let layout: GameLayout
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // 每个动画帧重画：显式依赖 timeline.date，否则 Canvas 可能不刷新
                _ = timeline.date
                let state = GameState.shared
                // 物理坐标就是屏幕坐标，直接绘制

                // 战斗区格挡
                for peg in layout.pegRows.joined() {
                    let r = layout.pegRadius
                    let pegRect = CGRect(x: peg.x - r, y: peg.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: pegRect), with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.95, blue: 0.7), Color(red: 0.7, green: 0.5, blue: 0.1)]),
                        center: CGPoint(x: pegRect.midX - r * 0.3, y: pegRect.midY - r * 0.3), startRadius: 0, endRadius: r * 1.4))
                    context.stroke(Path(ellipseIn: pegRect), with: .color(.black.opacity(0.5)), lineWidth: 1)
                }

                // 推床金币（先画，下落金币在上层）
                for coin in state.bedCoins.sorted(by: { $0.y < $1.y }) {
                    let coinRect = CGRect(
                        x: coin.x - coin.radius,
                        y: coin.y - coin.z * 0.5 - coin.radius,
                        width: coin.radius * 2,
                        height: coin.radius * 2
                    )
                    
                    // 底层阴影 (深度感)
                    context.fill(Path(ellipseIn: coinRect.offsetBy(dx: 2, dy: 2)), with: .color(Color.black.opacity(0.4)))
                    
                    // 动态光泽渐变 (根据 Y 轴微调色温)
                    let brightnessShift = Double((coin.y - layout.bedTopY) / layout.pusher.height) * 0.1
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

                // 下落金币
                for coin in state.active2DCoins.sorted(by: { $0.y < $1.y }) {
                    let coinRect = CGRect(
                        x: coin.x - coin.radius,
                        y: coin.y - coin.radius,
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
                
                // 粒子 (V9.4)
                for particle in state.particles {
                    let pRect = CGRect(x: particle.x - 3, y: particle.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: pRect), with: .color(particle.color.opacity(Double(particle.life))))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct HollowBonusSliderTarget: View {
    let width: CGFloat
    let maxHeight: CGFloat
    
    var body: some View {
        // 宽度 = layout.bonusSliderWidth，与物理命中范围一致
        let exactWidth = width
        let h = min(exactWidth * 0.45, maxHeight)
        
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
            
            HStack(spacing: 1) {
                Text("💰")
                    .font(.system(size: h * 0.45))
                Text("BONUS")
                    .font(.system(size: min(exactWidth * 0.2, h * 0.4), weight: .black))
                    .foregroundColor(.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: exactWidth, height: h)
    }
}

extension View {
    /// 按布局里的整屏 frame 摆放（父视图需为整屏、左上角为原点）
    func place(in rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - 预览
#Preview {
    CoinPusherView()
}
