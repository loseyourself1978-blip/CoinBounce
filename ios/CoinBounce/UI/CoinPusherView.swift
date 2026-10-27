import SwiftUI
import SpriteKit

// MARK: - V20 稳定版 (基于V16结构)
// 修复编译错误，使用正确的GameState属性

struct CoinPusherView: View {
    @StateObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @State private var arrowBounce = false
    @State private var showNoCoinsHint = false
    @State private var showSettings = false
    /// 下落区物理场景（SpriteKit），整屏透明覆盖在各区域之上
    @State private var dropScene = DropFieldScene(gameState: GameState.shared)
    /// 3D 推币台（SceneKit）
    @State private var pusher3D = PusherScene3D()
    @State private var holdDropTimer: Timer?
    // 战斗区动画
    @State private var warriorLunge: CGFloat = 0
    @State private var bossShake: CGFloat = 0
    @State private var bossFlash = false
    @State private var bossKO = false

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
                    stoppedColumns: gameState.stoppedColumns,
                    winLineActive: gameState.currentWin != .none && gameState.slotSpinState == .spinIdle,
                    reelsFrame: layout.slotReels.offsetBy(dx: -layout.slotMachine.minX, dy: -layout.slotMachine.minY)
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
                PusherSceneView(pusher: pusher3D)
                    .place(in: layout.pusher)

                // ── 投币按钮（背景延伸到底部安全区）──
                Color(red: 0.06, green: 0.05, blue: 0.03)
                    .place(in: CGRect(x: 0, y: layout.dropButton.minY, width: sw, height: sh - layout.dropButton.minY))
                coinDropButton(w: layout.dropButton.width, h: layout.dropButton.height)
                    .place(in: layout.dropButton)

                // 粒子：与物理同一坐标，直接按点绘制
                LocalCoinCanvasLayer(layout: layout)
                    .frame(width: sw, height: sh)

                // 下落中的金币（SpriteKit）：画在老虎机、战斗区、水果灯排之上
                SpriteView(scene: dropScene, options: [.allowsTransparency])
                    .frame(width: sw, height: sh)
                    .allowsHitTesting(false)

                // BONUS 牌画在下落金币之上：金币从中间穿过时被牌遮住一段，形成穿透效果
                bonusPlaque(layout: layout)

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
                    CardSelectionView(cards: gameState.offeredCards, picked: gameState.pickedCard,
                                      onPick: { gameState.pickCard($0) },
                                      onFinished: { gameState.finishCardPick() })
                    .frame(width: sw, height: sh)
                }
            }
            .frame(width: sw, height: sh)
            .animation(.easeOut(duration: 0.25), value: gameState.showJackpotExplosion)
            .animation(.easeOut(duration: 0.25), value: gameState.showCardSelection)
            .onAppear {
                gameState.updateLayout(layout)
                dropScene.apply(layout: layout)
                // 下落区 → 3D 推币台；3D 推币台掉落 → 计分
                gameState.onCoinToPusher = { [pusher3D] point, special in pusher3D.dropCoin(atViewPoint: point, special: special) }
                pusher3D.onCoinDropped = { special in gameState.coinFellOffPusher(isSpecial: special) }
            }
            .onChange(of: gameState.pusherSpeedMultiplier) { pusher3D.setPusherSpeed($0) }
            .onChange(of: gameState.wideMouthActive) { pusher3D.setEasyDrop($0) }
            .onAppear {
                startAnimations()
            }
            .onChange(of: layout) { newLayout in
                gameState.updateLayout(newLayout)
                dropScene.apply(layout: newLayout)
            }
    }

    private func dropOrHint() {
        if gameState.canDropCoin {
            gameState.dropCoin()
        } else {
            AudioManager.shared.play(.noCoins)
            gameState.requestFreeCoins()
            showNoCoinsHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showNoCoinsHint = false }
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
        // 预加载音效并按设置开始背景音乐
        AudioManager.shared.updateMusic()

        // 广告：UMP 同意 → ATT → 初始化 SDK → 预加载（等窗口就绪后开始）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { AdsManager.shared.start() }

        #if DEBUG
        // 截图用：-debugSetCoins N 把金币设为 N；-debugAutoAd 在广告加载好后自动点「看广告领金币」
        if UserDefaults.standard.object(forKey: "debugSetCoins") != nil {
            gameState.availableCoins = UserDefaults.standard.integer(forKey: "debugSetCoins")
        }
        // 截图用：-debugAutoSpin 每 4.5 秒自动转一次老虎机
        if ProcessInfo.processInfo.arguments.contains("-debugAutoSpin") {
            Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { _ in gameState.spinSlot() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { gameState.spinSlot() }
        }
        if ProcessInfo.processInfo.arguments.contains("-debugShowSettings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showSettings = true }
        }
        if ProcessInfo.processInfo.arguments.contains("-debugAutoAd") {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                guard AdsManager.shared.isAdReady else { return }
                timer.invalidate()
                gameState.requestFreeCoins()
            }
        }
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

            // Jackpot 标题框
            JackpotMarquee(width: min(w * 0.46, h * 3.2), height: h * 0.82)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Spacer()
                Text("JACKPOT")
                    .font(.system(size: max(8, h * 0.15), weight: .black, design: .rounded))
                    .foregroundColor(ArtPalette.goldLight)
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
        .overlay(alignment: .topTrailing) {
            SettingsButton { showSettings = true }
                .padding(.trailing, 10)
                .padding(.top, 4)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - COIN滑块轨道
    @ViewBuilder
    func coinSliderTrack(layout: GameLayout) -> some View {
        let h = layout.sliderTrack.height
        let slider = layout.coinSliderCenter(offset: gameState.coinSliderOffset)

        ZStack(alignment: .topLeading) {
            // 投币口轨道：深色槽 + 上下两排跑马灯
            Color(red: 0.12, green: 0.07, blue: 0.05)
            RoundedRectangle(cornerRadius: h * 0.25)
                .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.03, blue: 0.02), Color(red: 0.2, green: 0.12, blue: 0.06)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: h * 0.25).stroke(ArtPalette.gold, lineWidth: 2))
                .frame(width: layout.fieldMaxX - layout.fieldMinX + layout.coinRadius * 2, height: h * 0.5)
                .position(x: layout.centerX - layout.sliderTrack.minX, y: h / 2)
            MarqueeLights(count: 14)
                .frame(width: layout.fieldMaxX - layout.fieldMinX, height: h * 0.14)
                .position(x: layout.centerX - layout.sliderTrack.minX, y: h * 0.1)
            MarqueeLights(count: 14, phaseOffset: 1)
                .frame(width: layout.fieldMaxX - layout.fieldMinX, height: h * 0.14)
                .position(x: layout.centerX - layout.sliderTrack.minX, y: h * 0.9)

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
                            .font(.system(size: min(h * 0.4, w * 0.11)))
                    }
                }
                // 固定为区域宽度：树太宽时不能把整个战斗区撑宽
                .frame(width: max(0, w - 20))
                .clipped()
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
                    WarriorFigure(size: figure * 0.85)
                }
                .offset(x: warriorLunge)
                Text("Warrior")
                    .font(.system(size: min(w * 0.035, h * 0.12), weight: .black))
                    .foregroundColor(.white)
                    .shadow(radius: 2)

                // 血条
                HealthBar(progress: 1, color: .green, width: w * 0.18)
            }
            .position(x: w * 0.13, y: h * 0.5)

            // 顶部中间：VS，连击时换成连击文字（格挡在它下方，不重叠）
            if gameState.combo.isActive {
                Text(gameState.combo.message)
                    .font(.system(size: min(w * 0.05, h * 0.15), weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.red, .orange, .yellow], startPoint: .top, endPoint: .bottom))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: w * 0.5)
                    .position(x: w * 0.50, y: h * 0.14)
            } else {
                Text("VS")
                    .font(.system(size: min(w * 0.08, h * 0.2), weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                    .italic()
                    .shadow(color: .black, radius: 4)
                    .position(x: w * 0.50, y: h * 0.14)
            }

            // 右侧敌人
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.red.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 20))
                        .frame(width: figure, height: figure)
                    BossFigure(size: figure * 0.85)
                        .colorMultiply(bossFlash ? Color(red: 1, green: 0.45, blue: 0.45) : .white)
                }
                .offset(x: bossShake)
                .rotationEffect(.degrees(bossKO ? 80 : 0), anchor: .bottom)
                .opacity(bossKO ? 0.3 : 1)
                Text("BOSS")
                    .font(.system(size: min(w * 0.030, h * 0.12), weight: .black))
                    .foregroundColor(.white)
                    .shadow(radius: 2)

                // 血条
                HealthBar(progress: CGFloat(gameState.bossHealth), color: .red, width: w * 0.18)
                    .animation(.easeOut(duration: 0.25), value: gameState.bossHealth)
            }
            .position(x: w * 0.87, y: h * 0.5)
        }
        .frame(width: w, height: h)
        // 攻击：勇士向前冲、BOSS 抖动并闪红
        .onChange(of: gameState.warriorAttackCount) { _ in
            withAnimation(.easeOut(duration: 0.1)) { warriorLunge = w * 0.08 }
            withAnimation(.easeIn(duration: 0.15).delay(0.12)) { warriorLunge = 0 }
            bossFlash = true
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 6)) { bossShake = 6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) { bossShake = 0 }
                bossFlash = false
            }
        }
        // KO：BOSS 倒下，1.2 秒后站起
        .onChange(of: gameState.bossDefeatedCount) { _ in
            withAnimation(.easeIn(duration: 0.3)) { bossKO = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { bossKO = false }
            }
        }
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

                    // 水果（矢量绘制）
                    FruitIcon(index: index, size: iconSize * 0.78)
                        .saturation(gameState.fruitsLit[index] ? 1 : 0.35)
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
            // BONUS 牌后面的「孔洞」：金币从这里穿过
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: layout.bonusSliderWidth * 0.8, height: lane.height * 0.35)
                .position(x: slider.x - lane.minX, y: lane.height / 2)
        }
    }

    /// BONUS 牌（整屏坐标），叠在下落金币之上
    @ViewBuilder
    func bonusPlaque(layout: GameLayout) -> some View {
        let slider = layout.bonusSliderCenter(offset: gameState.bonusSliderOffset)
        HollowBonusSliderTarget(width: layout.bonusSliderWidth, maxHeight: layout.bonusLane.height * 0.9)
            .position(x: slider.x, y: slider.y)
            .allowsHitTesting(false)
    }

    // MARK: - 投币按钮
    @ViewBuilder
    func coinDropButton(w: CGFloat, h: CGFloat) -> some View {
        // 按钮略偏下，引导箭头和提示放在按钮上方、本区域之内，不被推币台盖住
        let buttonSize = min(w * 0.2, h * 0.88)
        let buttonY = h * 0.02

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
                    .offset(y: buttonY - buttonSize * 0.7 + (arrowBounce ? 5 : 0))
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
                    .offset(y: buttonY)

                Hexagon()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: buttonSize * 0.72, height: buttonSize * 0.66)
                    .overlay(
                        Text("$")
                            .font(.system(size: buttonSize * 0.28, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.yellow, .white], startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    )
                    .offset(y: buttonY)
            }
            .opacity(gameState.canDropCoin ? 1 : 0.5)
            // 点一下投一枚；按住不放每 0.22 秒连投一枚
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard holdDropTimer == nil else { return }
                        dropOrHint()
                        holdDropTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { _ in
                            if gameState.canDropCoin { gameState.dropCoin() }
                        }
                    }
                    .onEnded { _ in
                        holdDropTimer?.invalidate()
                        holdDropTimer = nil
                    }
            )

            // 金币不足时：看激励广告领金币（广告没加载好时显示加载中，不影响游戏）
            if gameState.canOfferAdReward() {
                adRewardButton(width: min(w * 0.3, 130), height: min(44, h * 0.5))
                    .offset(x: min(w * 0.34, w / 2 - 75), y: buttonY)
            }

            // 金币用完提示
            if showNoCoinsHint {
                Text("Not enough coins")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .offset(y: buttonY - buttonSize * 0.7)
                    .transition(.opacity)
            }
        }
        .frame(width: w, height: h)
    }
}

extension CoinPusherView {
    @ViewBuilder
    func adRewardButton(width: CGFloat, height: CGFloat) -> some View {
        Button {
            AudioManager.shared.play(.buttonTap)
            gameState.requestFreeCoins()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ads.isAdReady ? "play.rectangle.fill" : "hourglass")
                    .font(.system(size: height * 0.4, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(ads.isAdReady ? LocalizedStringKey("Watch ad") : LocalizedStringKey("Loading ad…"))
                        .font(.system(size: height * 0.27, weight: .bold, design: .rounded))
                    Text("Get \(GameConstants.adRewardCoins) coins")
                        .font(.system(size: height * 0.3, weight: .black, design: .rounded))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(width: width, height: height)
            .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 0.3), Color(red: 0.1, green: 0.45, blue: 0.2)],
                                                      startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
            .opacity(ads.isAdReady ? 1 : 0.6)
        }
        .disabled(!ads.isAdReady)
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
                .overlay(ArtCoin(size: 18))
                .frame(width: 18, height: 18)
            // 余额滚动计数：数字变化时逐位滚动
            Text("\(coins)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.35), value: coins)
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
    @State private var popped = false

    var body: some View {
        if score.big {
            // 中奖大号飞字：金色渐变 + 深色描边，弹出放大
            Text(score.text)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [ArtPalette.goldLight, score.color, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                .shadow(color: ArtPalette.outline, radius: 0, x: 2, y: 2)
                .shadow(color: ArtPalette.outline, radius: 0, x: -1, y: -1)
                .shadow(color: score.color.opacity(0.8), radius: 12)
                .scaleEffect((popped ? 1 : 0.3) * score.scale)
                .opacity(score.opacity)
                .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { popped = true } }
        } else {
            Text(score.text)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(score.color)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
                .opacity(score.opacity)
                .scaleEffect(score.scale)
        }
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
                ArtCoin(size: h * 0.5)
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
