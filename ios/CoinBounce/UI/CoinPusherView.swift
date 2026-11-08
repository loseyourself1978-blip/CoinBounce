import SwiftUI
import SpriteKit

// MARK: - V20 稳定版 (基于V16结构)
// 修复编译错误，使用正确的GameState属性

struct CoinPusherView: View {
    @StateObject private var gameState = GameState.shared
    @ObservedObject private var ads = AdsManager.shared
    @ObservedObject private var parallax = MotionParallax.shared
    @State private var arrowBounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNoCoinsHint = false
    @State private var showSettings = false
    @State private var showHelp = false
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

                // ── Jackpot（v11.4 按参考：从屏幕最顶端开始的大牌，下面一行是金币余额和帮助 / 设置）──
                topBackdrop()
                    .place(in: CGRect(x: 0, y: 0, width: sw, height: layout.sliderTrack.minY))
                jackpotWithTransition(w: layout.jackpot.width, h: layout.jackpot.height)
                    .place(in: layout.jackpot)

                // ── 老虎机（SPIN 在转轴右侧）──
                SlotMachineView(
                    reels: gameState.slotReels,
                    spinState: gameState.slotSpinState,
                    stoppedColumns: gameState.stoppedColumns,
                    winLineActive: gameState.currentWin != .none && gameState.slotSpinState == .spinIdle,
                    reelsFrame: layout.slotReels.offsetBy(dx: -layout.slotMachine.minX, dy: -layout.slotMachine.minY),
                    pins: layout.slotPins.map { CGPoint(x: $0.x - layout.slotMachine.minX, y: $0.y - layout.slotMachine.minY) },
                    pinRadius: layout.slotPinRadius
                )
                .place(in: layout.slotMachine)
                // v11.7：还要转几次（BONUS 连续命中排队的转动），显示在转轴窗口右上角
                if gameState.queuedSpins > 0 {
                    SpinQueueBadge(count: gameState.queuedSpins)
                        .position(x: layout.slotReels.maxX - 6, y: layout.slotReels.minY + 4)
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
                }

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

                // ── v11.6 格挡钉：看得见的立体黄铜钉（和 3D 下落平面里的碰撞钉同一组位置）──
                PegsLayer(pegs: layout.slotObstacles + layout.fruitPins, radius: layout.slotObstacleRadius)
                    .frame(width: sw, height: sh)
                    .allowsHitTesting(false)

                // ── 推币台 ──
                // ── 机柜两侧金色立柱（带灯泡），把投币口到 BONUS 的区域框成一个有纵深的机柜 ──
                CabinetPillar()   // v11.6：灯泡两态各栅格化一次，闪烁只动不透明度（外面不能再包 drawingGroup，否则又每帧重画）
                    .place(in: CGRect(x: 0, y: layout.sliderTrack.minY, width: layout.sideMargin, height: layout.bonusLane.maxY - layout.sliderTrack.minY))
                CabinetPillar()
                    .place(in: CGRect(x: sw - layout.sideMargin, y: layout.sliderTrack.minY, width: layout.sideMargin, height: layout.bonusLane.maxY - layout.sliderTrack.minY))
                // 金币余额、帮助 / 设置叠在投币口区域上方两侧（v11.6，画在立柱之上），不挡 COIN 牌的往复范围
                topRow(layout: layout)
                    .place(in: layout.topRow)

                // 推币机后方的背景（红绒布、暗色机柜）：3D 视图是透明的，只画机器和金币
                MachineBackdrop()
                    .place(in: CGRect(x: 0, y: layout.pusherView.minY, width: sw, height: sh - layout.pusherView.minY))

                // 中奖金币雨（纯视觉，2D）
                if gameState.coinRainShowing {
                    SpriteView(scene: dropScene, options: [.allowsTransparency])
                        .frame(width: sw, height: sh)
                        .allowsHitTesting(false)
                }

                // v11.3：3D 视图铺满全屏，盖在 2D 界面上——每一枚金币从投币口到掉进接币槽都是同一个 3D 金币
                PusherSceneView(pusher: pusher3D, layout: layout)
                    .frame(width: sw, height: sh)
                    .allowsHitTesting(false)

                // 画在 3D 金币之上的部件（参考里它们挡住金币）：投币口滑块、BONUS 牌
                // v11.6：点 COIN 牌在 1 → 2 → 5 → 10 之间切换每次投币的枚数
                SliderReader(motion: gameState.sliders) { m in
                    coinSlider(w: layout.coinSliderWidth, h: ReferenceBoxes.y(ReferenceBoxes.coinPlate.height, layout.size))
                        .contentShape(Rectangle())
                        .onTapGesture { gameState.cycleCoinMultiplier() }
                        .accessibilityLabel(Text(verbatim: "\(gameState.coinMultiplier) COIN"))
                        .accessibilityAddTraits(.isButton)
                        .position(layout.coinSliderCenter(offset: m.coin))
                }
                bonusPlaque(layout: layout)
                // 两侧炮管（参考 x 40–160 / 1050–1170、y 1690–1830 像素）
                CannonView(right: false).place(in: ReferenceBoxes.rect(ReferenceBoxes.cannonLeft, layout.size)).allowsHitTesting(false)
                CannonView(right: true).place(in: ReferenceBoxes.rect(ReferenceBoxes.cannonRight, layout.size)).allowsHitTesting(false)

                // ── 底部面板和投币按钮（参考：深色框 + 金色标牌 + 六边形按钮）──
                coinDropButton(w: layout.dropButton.width, h: layout.dropButton.height, bottomInset: layout.safeArea.bottom)
                    .place(in: layout.dropButton)

                // 粒子：与物理同一坐标，直接按点绘制
                if gameState.hasParticles {
                    LocalCoinCanvasLayer(layout: layout)
                        .frame(width: sw, height: sh)
                }

                #if DEBUG
                // 调试：-refOverlay /绝对路径/frame.png [不透明度]——把本地的参考帧半透明叠在整屏上，逐像素对齐用。
                // 图片从仓库外的本地路径读取，不打包进 App；Release 版不编译这段
                ReferenceOverlay()
                    .frame(width: sw, height: sh)
                    .allowsHitTesting(false)
                #endif

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
                // 投币 → 3D 金币从投币口落下；按屏幕投影位置触发战斗区 / 水果 / BONUS；掉进接币槽 → 计分
                gameState.onDrop = { [pusher3D] coin in
                    pusher3D.spawnFallingCoin(atScreen: CGPoint(x: coin.x, y: coin.y), screenVelocity: CGVector(dx: coin.vx, dy: coin.vy), special: coin.isSpecial)
                }
                // v11.7：中奖金币也是真的 3D 金币，从顶部随机位置落下（不触发战斗、水果、BONUS）
                gameState.onRewardDrop = { [pusher3D] coin in
                    pusher3D.spawnFallingCoin(atScreen: CGPoint(x: coin.x, y: coin.y), screenVelocity: CGVector(dx: coin.vx, dy: coin.vy), reward: true)
                }
                gameState.fallingCountProvider = { [pusher3D] in pusher3D.fallingCount }
                pusher3D.onCrossBattle = { gameState.coinCrossedBattle() }
                pusher3D.onCrossFruit = { gameState.coinCrossedFruitRow(x: $0) }
                pusher3D.onCrossBonus = { gameState.coinCrossedBonusLane(x: $0, radius: $1, gateX: $2) }
                pusher3D.bonusOffsetProvider = { gameState.bonusSliderOffset }
                pusher3D.onCoinDropped = { special in gameState.coinFellOffPusher(isSpecial: special) }
            }
            .onChange(of: gameState.pusherSpeedMultiplier) { pusher3D.setPusherSpeed($0) }
            .onChange(of: gameState.wideMouthActive) { pusher3D.setEasyDrop($0) }
            .onAppear {
                startAnimations()
                ScreenAwake.setGameVisible(true)
            }
            .onDisappear { ScreenAwake.setGameVisible(false) }
            .onChange(of: layout) { newLayout in
                gameState.updateLayout(newLayout)
                dropScene.apply(layout: newLayout)
            }
    }

    private func dropOrHint() {
        switch gameState.dropBatch() {
        case .queued, .queueFull:
            break   // 队列满时这次点击不投（不是金币不足）
        case .insufficient:
            AudioManager.shared.play(.noCoins)
            gameState.requestFreeCoins()
            showNoCoinsHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showNoCoinsHint = false }
        }
    }

    // MARK: - 动画控制
    private func startAnimations() {
        // 箭头跳动
        withAnimation(.easeInOut(duration: reduceMotion ? 0.9 : 0.5).repeatForever(autoreverses: true)) {
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
        // 截图用：-debugResetFruits 清空水果进度，不弹出卡牌
        if ProcessInfo.processInfo.arguments.contains("-debugResetFruits") {
            gameState.fruitsLit = Array(repeating: false, count: 7)
            gameState.finishCardPick()
        }
        // 截图用：-debugAutoSpin 每 4.5 秒自动转一次老虎机
        if ProcessInfo.processInfo.arguments.contains("-debugAutoSpin") {
            Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { _ in gameState.spinSlot() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { gameState.spinSlot() }
        }
        // -debugResetTutorial：重新显示首次进入的投币引导箭头
        if ProcessInfo.processInfo.arguments.contains("-debugResetTutorial") {
            gameState.resetTutorial()
        }
        if ProcessInfo.processInfo.arguments.contains("-debugShowHelp") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showHelp = true }
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
        // 验证用：-autoplay 每 0.4 秒自动投一枚（落点随 COIN 滑块往复扫过），并每秒打印推币台统计
        if ProcessInfo.processInfo.arguments.contains("-autoplay") || ProcessInfo.processInfo.arguments.contains("-debugPhysicsLog") {
            pusher3D.logsPhysicsStats = true
        }
        // 玩家模式不做逐帧画面验收；-autoplay 验收时打开。-autoplayLite：和 -autoplay 一样自动投币，但不做验收（测真实玩家负载下的帧率）
        let autoplayLite = ProcessInfo.processInfo.arguments.contains("-autoplayLite")
        pusher3D.verifiesMotion = ProcessInfo.processInfo.arguments.contains("-autoplay")
        if autoplayLite {
            pusher3D.logsPhysicsStats = true
            PerfDebug.monitor.start()
            Timer.scheduledTimer(withTimeInterval: GameConstants.referenceDropInterval, repeats: true) { _ in
                if !gameState.canDropCoin { gameState.availableCoins += 100 }
                if gameState.showCardSelection, let card = gameState.offeredCards.first, gameState.pickedCard == nil {
                    gameState.pickCard(card.kind)
                    gameState.finishCardPick()
                }
                gameState.dropCoin()
            }
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [pusher3D] _ in
                func avg(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
                NSLog("LITE fallAvg=%.2f fallN=%d coins=%d", avg(pusher3D.fallTimes), pusher3D.fallTimes.count, pusher3D.coinCount)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-autoplay") {
            // 逐事件日志只在 -debugLifecycleLog 时打（日志在渲染线程上写，连着控制台时会拖慢帧率）；计数照常
            pusher3D.logsLifecycle = ProcessInfo.processInfo.arguments.contains("-debugLifecycleLog")
            // 每秒一次的验收日志：落点、下落时长、流转、连续性、立着的金币、遮挡、金币堆
            // 遮挡检查要逐枚做命中测试（会等渲染线程），放慢到每 5 秒一次，不拖慢主线程上的投币节奏
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [pusher3D] _ in
                guard let view = pusher3D.view else { return }
                let occ = pusher3D.occlusionReport(in: view, maxCoins: 20)
                let pile = pusher3D.pileStats()
                func avg(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
                NSLog("VERIFY life=%@ removed=%@ fallAvg=%.2f fallN=%d rampSlideAvg=%.2f pusherToPileAvg=%.2f rampTimeouts=%d continuity=%d maxSize=%.3f standing=%d occChecked=%d occProblems=%d %@ layersP90=%.1f coverage=%.3f pileN=%d",
                      pusher3D.lifecycleCounts.description, pusher3D.removalReasons.description,
                      avg(pusher3D.fallTimes), pusher3D.fallTimes.count, avg(pusher3D.rampSlideTimes), avg(pusher3D.pusherToPileTimes),
                      pusher3D.rampTimeouts, pusher3D.continuityViolations.count, pusher3D.maxSizeChange, pusher3D.standingViolations,
                      occ.checked, occ.problems.count, occ.problems.prefix(3).joined(separator: " | "),
                      pile.layersP90, pile.coverage, pile.count)
                if let first = pusher3D.continuityViolations.first { NSLog("VERIFY_CONT first=%@ last=%@", first, pusher3D.continuityViolations.last ?? "") }
            }
            // 投币频率按参考录屏实测：约 1.67 枚 / 秒
            Timer.scheduledTimer(withTimeInterval: GameConstants.referenceDropInterval, repeats: true) { _ in
                if !gameState.canDropCoin { gameState.availableCoins += 100 }
                // 水果全亮弹出选卡时自动选第一张，录屏不被遮住
                if gameState.showCardSelection, let card = gameState.offeredCards.first, gameState.pickedCard == nil {
                    gameState.pickCard(card.kind)
                    gameState.finishCardPick()
                }
                gameState.dropCoin()
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
    func topBackdrop() -> some View {
            // v11.4 参考：JACKPOT 牌后面是暗色机柜顶，往下过渡到投币口的深红
            LinearGradient(stops: [
                .init(color: Color(red: 0.16, green: 0.10, blue: 0.08), location: 0.00),
                .init(color: Color(red: 0.22, green: 0.17, blue: 0.15), location: 0.55),
                .init(color: Color(red: 0.25, green: 0.06, blue: 0.05), location: 1.00)
            ], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    func jackpotWithTransition(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Jackpot 标题框：参考大牌 50–1160 × 0–250 像素
            JackpotMarquee(width: w, height: h)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // v11.6：两行——「JACKPOT」和奖池数字，立体金色字、带闪光；整块放在灵动岛下面
            // （iPhone 17 录屏实测灵动岛下沿约 47% 牌高，两行字从约 52% 牌高开始）
            // v11.6 性能：字是静态的（栅格化一次），闪光用 Core Animation 光带扫过（不再每秒重画 30 次）
            let glints = !reduceMotion && !PerfDebug.freezeUI
            // v11.7：字加大；数字是累积奖池，每投一枚金币 +0.02，数字滚动上涨
            VStack(spacing: 0) {
                GoldText3D(text: "JACKPOT", size: h * 0.125, tracking: h * 0.03, glintStarts: glints ? GlintSchedule.bonusStarts(offset: 1.6) : nil)
                RollingJackpotNumber(meter: gameState.jackpotMeter, size: h * 0.29, glintStarts: glints ? GlintSchedule.bonusStarts(offset: 0) : nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, h * 0.05)
        }
        .frame(height: h)
    }

    /// 金币余额（参考 50–560 像素的长条）和帮助 / 设置按钮（右端对齐参考 1150 像素）
    @ViewBuilder
    func topRow(layout: GameLayout) -> some View {
        let pill = ReferenceBoxes.rect(ReferenceBoxes.balancePill, layout.size)
        let scale = pill.height / 30
        HStack(spacing: 0) {
            CoinBalanceView(coins: gameState.availableCoins, height: pill.height, width: pill.width)
            Spacer(minLength: 0)
            // 帮助在设置左边
            HStack(spacing: 8) {
                HelpButton { showHelp = true }
                SettingsButton { showSettings = true }
            }
            .scaleEffect(scale)
            .frame(width: (60 + 8) * scale, height: 30 * scale)
        }
        .frame(maxHeight: .infinity)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - COIN滑块轨道
    @ViewBuilder
    func coinSliderTrack(layout: GameLayout) -> some View {
        let h = layout.sliderTrack.height

        ZStack(alignment: .topLeading) {
            // v11.2 按参考：拱形投币口——深红底，金色拱形灯管（顶边水平、两侧圆弧向下），沿拱形一圈灯泡；
            // COIN 滑块在拱形里的深色横槽上往复
            Color(red: 0.25, green: 0.06, blue: 0.05)
            // 拱门：参考 246–920 像素宽，灯泡横条在 744 像素（拱顶在上一行按钮后面）
            let archW = ReferenceBoxes.x(ReferenceBoxes.archFrame.width, layout.size)
            let archBottom = ReferenceBoxes.y(ReferenceBoxes.archFrame.maxY, layout.size) - layout.sliderTrack.minY
            ArchTrack(bulbCount: 28)
                .frame(width: archW, height: archBottom)
                .position(x: layout.centerX - layout.sliderTrack.minX, y: archBottom / 2)
            RoundedRectangle(cornerRadius: h * 0.1)
                .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.03, blue: 0.02), Color(red: 0.18, green: 0.1, blue: 0.05)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: archW * 0.82, height: h * 0.12)
                .position(x: layout.centerX - layout.sliderTrack.minX, y: layout.coinPlateY - layout.sliderTrack.minY)

            // COIN滑块 (金币出口)，与 dropCoin 的落点同一位置
            SliderReader(motion: gameState.sliders) { m in
                let slider = layout.coinSliderCenter(offset: m.coin)
                coinSlider(w: layout.coinSliderWidth, h: ReferenceBoxes.y(ReferenceBoxes.coinPlate.height, layout.size))
                    .position(x: slider.x - layout.sliderTrack.minX, y: slider.y - layout.sliderTrack.minY)
            }
        }
    }

    // MARK: - COIN滑块 (金币出口)
    @ViewBuilder
    func coinSlider(w sliderW: CGFloat, h sliderH: CGFloat) -> some View {
        // v11.6 性能：牌面只由宽高和枚数决定；滑块每帧移动时不重算、不重画
        CoinPlate(w: sliderW, h: sliderH, multiplier: gameState.coinMultiplier).equatable()
    }
}

struct CoinPlate: View, Equatable {
    let w: CGFloat, h: CGFloat, multiplier: Int
    var body: some View {
        let sliderW = w, sliderH = h
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
            Text(verbatim: "\(multiplier) COIN")
                .font(.system(size: min(sliderW * 0.22, sliderH * 0.6), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.95, green: 0.85, blue: 0.55))
        }
        .frame(width: sliderW, height: sliderH)
        .drawingGroup()
    }
}

extension CoinPusherView {
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
                // 视差：远处树林随手机倾斜反向移动
                .offset(x: -parallax.offset.width * 1.5, y: -parallax.offset.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // 凹陷感：内阴影
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.7), lineWidth: 5).blur(radius: 3).clipShape(RoundedRectangle(cornerRadius: 8)))
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
        let iconSize = min(layout.fruitLampWidth * 0.78, bar.height * 0.7)

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
                    // v11.1 按参考：圆角方形水果牌，钢蓝色金属边框，深色底；点亮时底色变金
                    RoundedRectangle(cornerRadius: iconSize * 0.18)
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.70, blue: 0.80), Color(red: 0.25, green: 0.36, blue: 0.45)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: iconSize * 1.2, height: iconSize * 1.2)
                    RoundedRectangle(cornerRadius: iconSize * 0.14)
                        .fill(gameState.fruitsLit[index] ?
                              LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4), Color(red: 0.9, green: 0.55, blue: 0.1)], startPoint: .top, endPoint: .bottom) :
                              LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.24), Color(red: 0.08, green: 0.10, blue: 0.12)], startPoint: .top, endPoint: .bottom))
                        .frame(width: iconSize * 1.02, height: iconSize * 1.02)

                    // 水果（矢量绘制）
                    FruitIcon(index: index, size: iconSize * 0.78)
                        .saturation(gameState.fruitsLit[index] ? 1 : 0.35)
                }
                // v11.6 性能：水果牌栅格化一次；碰到水果时的弹跳放大只缩放栅格，不在主线程逐帧重画矢量图（径向渐变）
                .drawingGroup()
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

        ZStack(alignment: .topLeading) {
            Color(red: 0.10, green: 0.07, blue: 0.04)
            // v11.2 按参考：BONUS 轨道后面是红绒布，左边两张扑克牌、右边大金币和一叠金币、两侧炮管（全部原创矢量绘制）
            BonusBackdrop(size: lane.size)
            // 滑轨：参考 x 370–860、y 1748–1758 像素的深色细杆
            let bar = ReferenceBoxes.rect(ReferenceBoxes.bonusBar, layout.size)
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                .frame(width: bar.width, height: max(3, bar.height))
                .position(x: bar.midX - lane.minX, y: bar.midY - lane.minY)
            // BONUS 牌后面的「孔洞」：金币从这里穿过
            SliderReader(motion: gameState.sliders) { m in
            let slider = layout.bonusSliderCenter(offset: m.bonus)
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: layout.bonusOpeningWidth, height: lane.height * 0.35)
                .position(x: slider.x - lane.minX, y: lane.height / 2)
            }
        }
    }

    /// BONUS 牌（整屏坐标），叠在下落金币之上
    @ViewBuilder
    func bonusPlaque(layout: GameLayout) -> some View {
        // 牌随滑块移动；闪光由 Core Animation 播放（v11.6）
        SliderReader(motion: gameState.sliders) { m in
            let slider = layout.bonusSliderCenter(offset: m.bonus)
            HollowBonusSliderTarget(width: layout.bonusSliderWidth, postWidth: layout.bonusPostWidth, maxHeight: ReferenceBoxes.y(GameConstants.bonusPlaqueHeightPx, layout.size),
                                    time: reduceMotion || PerfDebug.freezeUI ? 0 : 1)
                .equatable()
                .position(x: slider.x, y: slider.y)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 投币按钮
    @ViewBuilder
    func coinDropButton(w: CGFloat, h: CGFloat, bottomInset: CGFloat = 0) -> some View {
        // 按钮贴在屏幕最下方（安全区之内，底边留 6 点），引导箭头和提示在按钮上方
        // 参考：六边形按钮 190×215 像素（约 15.8% 屏宽），中心在 (603, 2470)；按真实屏幕尺寸换算到本区域内的偏移
        let screen = gameState.layout.size
        let band = gameState.layout.dropButton
        let buttonSize = ReferenceBoxes.x(190, screen)
        let buttonY = ReferenceBoxes.y(2470, screen) - band.midY

        ZStack {
            // 底部金色面板（参考取色 #fcc54f，深色外框 #14100a）：从台面前沿一直到屏幕底部，台面掉下的金币落到面板后面
            // 参考：深色框 x 40–1168、y 2370–2580；金色标牌 x 150–1030、y 2410–2540
            let frameRect = ReferenceBoxes.rect(ReferenceBoxes.bottomFrame, screen)
            let labelRect = ReferenceBoxes.rect(ReferenceBoxes.bottomLabel, screen)
            BottomGoldPanel(frameRect: frameRect.offsetBy(dx: 0, dy: -band.minY), labelRect: labelRect.offsetBy(dx: 0, dy: -band.minY))
                .frame(width: w, height: h, alignment: .topLeading)
                .allowsHitTesting(false)
            // 投币按钮（居中，贴近参考App）
            ZStack {
                // 新手引导箭头（严格按状态位控制）
                // 首次进入：金色下指箭头闪动，点过投币按钮后永久消失（减少动态效果时只淡入淡出、不上下跳）
                if gameState.showTutorialArrow {
                    TutorialArrow(size: buttonSize * 0.55, pulse: arrowBounce)
                        .offset(y: buttonY - buttonSize * 1.05 + (arrowBounce && !reduceMotion ? 8 : 0))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // 六边形投币按钮（对齐参考App）
                Hexagon()
                    .fill(
                        LinearGradient(
                            // 参考：浅金外圈 + 深古铜内心
                            colors: [
                                Color(red: 1.0, green: 0.88, blue: 0.55),
                                Color(red: 0.72, green: 0.52, blue: 0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: buttonSize, height: buttonSize * Hexagon.heightRatio)   // 正六边形
                    .overlay(
                        Hexagon().stroke(Color(red: 0.98, green: 0.90, blue: 0.55), lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
                    .saturation(gameState.canDropCoin ? 1 : 0)
                    .offset(y: buttonY)

                Hexagon()
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.26, blue: 0.10), Color(red: 0.18, green: 0.12, blue: 0.05)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: buttonSize * 0.74, height: buttonSize * 0.74 * Hexagon.heightRatio)
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
                        // 按住连投：每次投当前倍数的一批（一批落完再投下一批）
                        let every = max(0.22, GameConstants.batchDropInterval * Double(gameState.coinMultiplier) + 0.1)
                        holdDropTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
                            if gameState.canDropBatch { gameState.dropBatch() }
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
    /// 整条高度、宽度（nil = 按内容）；默认与 v11.3 以前的小胶囊一样
    var height: CGFloat = 24
    var width: CGFloat? = nil
    @State private var bump = false

    var body: some View {
        let icon = height * 0.75
        HStack(spacing: 4) {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.9, blue: 0.4), Color(red: 0.8, green: 0.5, blue: 0.1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color(red: 0.5, green: 0.3, blue: 0.0), lineWidth: 1))
                .overlay(ArtCoin(size: icon))
                .frame(width: icon, height: icon)
            // 余额滚动计数：数字变化时逐位滚动
            Text("\(coins)")
                .font(.system(size: height * 0.62, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.35), value: coins)
        }
        .padding(.horizontal, height / 3)
        .frame(width: width, height: height, alignment: .leading)
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
/// v11.6：格挡钉——立体黄铜钉（投影、圆柱身、顶面高光），一次画完交给 GPU
struct PegsLayer: View {
    let pegs: [CGPoint]
    let radius: CGFloat
    var body: some View {
        Canvas { ctx, _ in
            let r = radius
            for p in pegs {
                // 投影
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.1 + r * 0.35, y: p.y - r * 0.4 + r * 0.9, width: r * 2.2, height: r * 1.1)),
                         with: .color(.black.opacity(0.45)))
                // 钉身（竖着的短圆柱：上下两个椭圆 + 中间矩形）
                let body = CGRect(x: p.x - r, y: p.y - r * 1.25, width: r * 2, height: r * 2.3)
                ctx.fill(Path(roundedRect: body, cornerRadius: r),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.27, blue: 0.05), Color(red: 1, green: 0.86, blue: 0.45),
                                                                 Color(red: 0.85, green: 0.6, blue: 0.15), Color(red: 0.4, green: 0.22, blue: 0.03)]),
                                               startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0)))
                // 顶面
                let top = CGRect(x: p.x - r * 0.9, y: p.y - r * 1.2, width: r * 1.8, height: r * 0.9)
                ctx.fill(Path(ellipseIn: top), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.75), Color(red: 0.9, green: 0.68, blue: 0.2)]),
                                                                     startPoint: CGPoint(x: 0, y: top.minY), endPoint: CGPoint(x: 0, y: top.maxY)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.45, y: p.y - r * 1.05, width: r * 0.5, height: r * 0.3)), with: .color(.white.opacity(0.85)))
                ctx.stroke(Path(roundedRect: body, cornerRadius: r), with: .color(Color(red: 0.3, green: 0.15, blue: 0.02)), lineWidth: max(0.6, r * 0.12))
            }
        }
        .drawingGroup()
    }
}

/// v11.5：只跟着滑块位置刷新的小视图（滑块每帧都在动，整个游戏画面不跟着重算）
struct SliderReader<Content: View>: View {
    @ObservedObject var motion: SliderMotion
    @ViewBuilder let content: (SliderMotion) -> Content
    var body: some View { content(motion) }
}

/// v11.5：等边六边形（尖顶朝上、六条边一样长），外框 宽 = 高。外框归一化到 1×1 时左右竖边从 a 到 1−a，
/// 斜边与竖边等长：1 − 2a = √(0.25 + a²) → a = (4 − √7) / 6 ≈ 0.2257，边长 ≈ 0.549，上下顶角约 131°、两侧顶角约 114°
struct Hexagon: Shape {
    static let heightRatio: CGFloat = 1
    static let shoulder: CGFloat = (4 - sqrt(7)) / 6
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, a = Hexagon.shoulder
        return Path { p in
            p.move(to: CGPoint(x: rect.minX + w / 2, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * a))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * (1 - a)))
            p.addLine(to: CGPoint(x: rect.minX + w / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * (1 - a)))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * a))
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

struct HollowBonusSliderTarget: View, Equatable {
    /// v11.6 性能：内容只由这几个数决定；滑块每帧移动时 SwiftUI 比较相等就不重算牌面（配合 .equatable()）
    static func == (a: Self, b: Self) -> Bool {
        a.width == b.width && a.postWidth == b.postWidth && a.maxHeight == b.maxHeight && a.time == b.time
    }
    let width: CGFloat
    /// v11.6：两侧立柱宽（有碰撞体）；正面黑底的宽度就是两柱之间的开口
    var postWidth: CGFloat = 0
    let maxHeight: CGFloat
    /// 闪光时间表：每 3.75 秒一格，格内起点随机偏移 0–0.65 秒 → 相邻两次闪光间隔 3.1–4.4 秒，每次持续 0.9 秒
    static let glintSlot = 3.75, glintJitter = 0.65, glintDuration = 0.9
    /// t 时刻闪光走到边框的哪里（0…1），不在闪光时返回 −1
    static func glintProgress(at t: TimeInterval) -> Double {
        let k = floor(t / glintSlot)
        // 每格一个固定的伪随机偏移（同一格每帧一样）
        var x = UInt64(bitPattern: Int64(k)) &* 0x9E3779B97F4A7C15
        x ^= x >> 31; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 29
        let jitter = Double(x % 10_000) / 10_000 * glintJitter
        let local = t - k * glintSlot - jitter
        return (0..<glintDuration).contains(local) ? local / glintDuration : -1
    }
    /// 当前时间（秒）；0 = 不闪（减少动态效果）
    var time: TimeInterval = 0

    /// 盾牌外形
    private func shield(_ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h * 0.2))
            p.addLine(to: CGPoint(x: w / 2, y: 0))
            p.addLine(to: CGPoint(x: w, y: h * 0.2))
            p.addLine(to: CGPoint(x: w, y: h * 0.8))
            p.addLine(to: CGPoint(x: w / 2, y: h))
            p.addLine(to: CGPoint(x: 0, y: h * 0.8))
            p.closeSubpath()
        }
    }

    var body: some View {
        // v11.5：高 135 像素（原 95）的立体铭牌——多层厚度（看得见的侧面）、倒角高光、投影、背后金色光晕；
        // 金色边框上一道高光每 3.1–4.4 秒（随机）绕边框闪过一次（减少动态效果时不闪）
        let w = width
        let depth = max(4, maxHeight * 0.13)
        let h = maxHeight - depth
        // v11.6 性能：整块牌是静态的（drawingGroup 栅格化一次，牌随滑块移动时不重画），
        // 边框闪光用 Core Animation 关键帧（CAGlintStroke）叠在上面，主线程不用每秒重画 30 次
        let glow = 0.45
        let pad = w * 0.3   // 光晕、投影超出牌面的部分也画进栅格
        Group {
            ZStack(alignment: .top) {
                // 背后的金色光晕（氛围）
                shield(w, h)
                    .fill(ArtPalette.goldLight.opacity(glow * 0.55))
                    .blur(radius: w * 0.16)
                    .scaleEffect(1.12)
                // 厚度：两层向下偏移的暗金侧面
                shield(w, h)
                    .fill(Color(red: 0.25, green: 0.14, blue: 0.02))
                    .offset(y: depth)
                    .shadow(color: .black.opacity(0.75), radius: 5, x: 0, y: 5)
                shield(w, h)
                    .fill(LinearGradient(colors: [ArtPalette.goldDeep, Color(red: 0.45, green: 0.27, blue: 0.04)], startPoint: .top, endPoint: .bottom))
                    .offset(y: depth * 0.55)
                // 金色外框（倒角）
                shield(w, h)
                    .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                // 黑金正面（内缩一圈，留出金边）；v11.6 宽度 = 两根立柱之间的开口
                let face = postWidth > 0 ? (w - 2 * postWidth) / w : 0.84
                shield(w * face, h * 0.84)
                    .fill(LinearGradient(colors: [Color(red: 0.26, green: 0.2, blue: 0.14), Color(red: 0.04, green: 0.03, blue: 0.02)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * face, height: h * 0.84)
                    .offset(y: h * 0.08)
                // 顶部高光
                shield(w, h)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)))
                shield(w, h)
                    .stroke(Color(red: 1, green: 0.95, blue: 0.7).opacity(0.9), lineWidth: 1)
                // v11.6 闸门立柱：和边框一样的金色倒角，贯穿整块牌的高度；闪光时一起提亮
                if postWidth > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { i in
                            if i == 1 { Spacer(minLength: 0) }
                            Capsule()
                                .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .leading, endPoint: .trailing))
                                .overlay(Capsule().stroke(Color(red: 0.45, green: 0.08, blue: 0.04), lineWidth: max(1, postWidth * 0.18)))
                                .frame(width: postWidth, height: h + depth)
                                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 2)
                        }
                    }
                    .frame(width: w, height: h + depth)
                }
                VStack(spacing: h * 0.02) {
                    ArtCoin(size: h * 0.34)
                        .shadow(color: ArtPalette.goldLight.opacity(glow), radius: 4)
                    Text("BONUS")
                        .font(.system(size: min(w * 0.22, h * 0.22), weight: .black))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.75), ArtPalette.gold], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black, radius: 0, x: 1, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(width: w, height: h)
            }
            .frame(width: w, height: h + depth, alignment: .top)
            .padding(pad)
            .drawingGroup()
            .padding(-pad)
            .overlay(alignment: .top) {
                // 闪光：整圈金边短暂提亮，一道白光沿边框扫过（和原来同样的时间表：每 3.1–4.4 秒一次、持续 0.9 秒）
                if time != 0 {
                    CAGlintStroke(path: { shield($0.width, $0.height).cgPath },
                                  starts: GlintSchedule.bonusStarts(offset: 0), period: GlintSchedule.bonusPeriod,
                                  duration: HollowBonusSliderTarget.glintDuration,
                                  borderWidth: max(2, w * 0.08), streakWidth: max(3, w * 0.11), borderPeak: 0.7, tail: 0.2, head: 0.03,
                                  borderColor: UIColor(red: 1, green: 0.97, blue: 0.8, alpha: 1))
                        .frame(width: w, height: h)
                }
            }
        }
        .frame(width: w, height: h + depth, alignment: .top)
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

/// 新手引导：金色下指箭头（原创矢量图形），pulse 时变亮、发光增强，配合外部的上下跳动形成闪动
struct TutorialArrow: View {
    let size: CGFloat
    let pulse: Bool

    var body: some View {
        ArrowShape()
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.55), Color(red: 0.95, green: 0.68, blue: 0.1)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(ArrowShape().stroke(Color(red: 0.55, green: 0.32, blue: 0.02), lineWidth: 2))
            .frame(width: size, height: size * 1.15)
            .shadow(color: Color(red: 1, green: 0.8, blue: 0.2).opacity(pulse ? 0.95 : 0.3), radius: pulse ? 12 : 4)
            .opacity(pulse ? 1 : 0.45)
    }

    struct ArrowShape: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let shaftW = r.width * 0.42, headH = r.height * 0.48
            p.move(to: CGPoint(x: r.midX - shaftW / 2, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX + shaftW / 2, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX + shaftW / 2, y: r.maxY - headH))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - headH))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - headH))
            p.addLine(to: CGPoint(x: r.midX - shaftW / 2, y: r.maxY - headH))
            p.closeSubpath()
            return p
        }
    }
}

/// 底部面板（原创绘制，按参考框摆放）：深色外框 + 金色标牌（带细横纹）
struct BottomGoldPanel: View {
    let frameRect: CGRect
    let labelRect: CGRect
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.09, blue: 0.05), Color(red: 0.05, green: 0.04, blue: 0.03)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: frameRect.width, height: frameRect.height)
                .offset(x: frameRect.minX, y: frameRect.minY)
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(red: 0.99, green: 0.84, blue: 0.45), Color(red: 0.93, green: 0.70, blue: 0.27),
                                              Color(red: 0.80, green: 0.55, blue: 0.18)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    VStack(spacing: 5) {
                        ForEach(0..<10, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                    }
                    .clipped()
                )
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.55, green: 0.36, blue: 0.10), lineWidth: 2))
                .frame(width: labelRect.width, height: labelRect.height)
                .offset(x: labelRect.minX, y: labelRect.minY)
        }
    }
}

/// BONUS 轨道背景装饰（参考布局，原创绘制）：红绒布底、左侧两张扑克牌、右侧大金币和一叠金币、两侧炮管
struct BonusBackdrop: View {
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.45, green: 0.07, blue: 0.04), Color(red: 0.55, green: 0.10, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
            // 扑克牌（左）
            ForEach(0..<2, id: \.self) { i in
                PlayingCardShape(red: i == 0)
                    .frame(width: h * 0.9, height: h * 1.25)
                    .rotationEffect(.degrees(i == 0 ? -14 : 8))
                    .position(x: w * (0.18 + 0.1 * CGFloat(i)), y: h * 0.62)
            }
            // 一叠金币 + 大金币（右）
            ForEach(0..<4, id: \.self) { k in
                Ellipse()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.82, blue: 0.35), Color(red: 0.78, green: 0.5, blue: 0.12)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(Color(red: 0.55, green: 0.33, blue: 0.08), lineWidth: 1))
                    .frame(width: h * 0.7, height: h * 0.22)
                    .position(x: w * 0.66, y: h * (0.88 - 0.12 * CGFloat(k)))
            }
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.88, blue: 0.4), Color(red: 0.95, green: 0.62, blue: 0.1)],
                                     center: .topLeading, startRadius: 0, endRadius: h))
                .overlay(Circle().stroke(Color(red: 0.7, green: 0.42, blue: 0.05), lineWidth: h * 0.06))
                .overlay(Text("$").font(.system(size: h * 0.6, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.85, green: 0.5, blue: 0.05)))
                .frame(width: h * 1.05, height: h * 1.05)
                .position(x: w * 0.8, y: h * 0.62)
        }
        .frame(width: w, height: h)
        .clipped()
    }
}

/// v11.6 立体金字：几层向右下偏移的暗金色叠出厚度，正面金色渐变 + 上半高光，闪光时一道白光从左往右扫过字面
struct GoldText3D: View {
    let text: String
    let size: CGFloat
    var tracking: CGFloat = 0
    /// v11.6 性能：一个周期（GlintSchedule.bonusPeriod）里每次闪光的起点；nil 表示不闪
    var glintStarts: [Double]? = nil
    var body: some View {
        let face = Text(verbatim: text).font(.system(size: size, weight: .black, design: .rounded)).tracking(tracking)
        let depth = max(1, size * 0.06)
        let pad = size * 0.3
        ZStack {
            ForEach(1..<4, id: \.self) { i in
                face.foregroundStyle(Color(red: 0.45 - 0.08 * Double(i), green: 0.26 - 0.05 * Double(i), blue: 0.03))
                    .offset(x: depth * CGFloat(i) * 0.6, y: depth * CGFloat(i))
            }
            face.foregroundStyle(LinearGradient(stops: [
                .init(color: Color(red: 1, green: 0.97, blue: 0.7), location: 0),
                .init(color: Color(red: 1, green: 0.84, blue: 0.3), location: 0.45),
                .init(color: Color(red: 0.86, green: 0.55, blue: 0.08), location: 0.55),
                .init(color: Color(red: 1, green: 0.8, blue: 0.25), location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .shadow(color: Color.orange.opacity(0.6), radius: size * 0.12)
        }
        .fixedSize()
        // 立体字只栅格化一次（留出光晕的边）
        .padding(pad)
        .drawingGroup()
        .padding(-pad)
        .overlay {
            // 闪光：一道斜白光，被字形遮住只在字上显示（Core Animation 播放）
            if let starts = glintStarts {
                CAGlintBand(starts: starts, period: GlintSchedule.bonusPeriod, duration: HollowBonusSliderTarget.glintDuration)
                    .mask(face)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// v11.6 原创扑克牌：红心 K（国王）、黑桃 Q（王后）——卡通人像、金色边框、有厚度的立体牌
struct PlayingCardShape: View {
    let red: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = red ? Color(red: 0.82, green: 0.08, blue: 0.12) : Color(red: 0.12, green: 0.1, blue: 0.16)
            let letter = red ? "K" : "Q"
            ZStack(alignment: .topLeading) {
                // 厚度：右下偏移的暗色层 + 投影
                RoundedRectangle(cornerRadius: w * 0.12)
                    .fill(Color(red: 0.62, green: 0.48, blue: 0.3))
                    .offset(x: w * 0.04, y: w * 0.05)
                    .shadow(color: .black.opacity(0.5), radius: w * 0.06, x: w * 0.04, y: w * 0.06)
                RoundedRectangle(cornerRadius: w * 0.12)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.98, blue: 0.92), Color(red: 0.93, green: 0.86, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: w * 0.1)
                    .stroke(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom), lineWidth: max(1.5, w * 0.035))
                    .padding(w * 0.05)
                // 角标
                VStack(spacing: 0) {
                    Text(verbatim: letter).font(.system(size: w * 0.24, weight: .black, design: .serif)).foregroundStyle(ink)
                    Image(systemName: red ? "suit.heart.fill" : "suit.spade.fill").resizable().scaledToFit().foregroundStyle(ink).frame(width: w * 0.14)
                }
                .padding(.leading, w * 0.1).padding(.top, w * 0.07)
                // 卡通人像：王冠、脸、（国王）胡子 / （王后）长发
                ZStack {
                    if !red {
                        Capsule().fill(LinearGradient(colors: [Color(red: 0.45, green: 0.22, blue: 0.1), Color(red: 0.25, green: 0.1, blue: 0.05)], startPoint: .top, endPoint: .bottom))
                            .frame(width: w * 0.5, height: w * 0.62).offset(y: w * 0.08)
                    }
                    Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.87, blue: 0.74), Color(red: 0.95, green: 0.72, blue: 0.56)], center: .topLeading, startRadius: 0, endRadius: w * 0.3))
                        .frame(width: w * 0.36, height: w * 0.36)
                    // 眼睛、腮红、笑
                    HStack(spacing: w * 0.08) { Circle().fill(Color.black).frame(width: w * 0.04); Circle().fill(Color.black).frame(width: w * 0.04) }.offset(y: -w * 0.02)
                    HStack(spacing: w * 0.16) { Circle().fill(Color.pink.opacity(0.5)).frame(width: w * 0.06); Circle().fill(Color.pink.opacity(0.5)).frame(width: w * 0.06) }.offset(y: w * 0.04)
                    if red {
                        // 国王的白胡子
                        Ellipse().fill(Color.white).overlay(Ellipse().stroke(Color(red: 0.7, green: 0.7, blue: 0.75), lineWidth: 0.8))
                            .frame(width: w * 0.3, height: w * 0.2).offset(y: w * 0.14)
                    } else {
                        Capsule().fill(Color(red: 0.85, green: 0.2, blue: 0.3)).frame(width: w * 0.08, height: w * 0.025).offset(y: w * 0.08)
                    }
                    // 王冠
                    CrownShape()
                        .fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold, ArtPalette.goldDeep], startPoint: .top, endPoint: .bottom))
                        .overlay(CrownShape().stroke(ArtPalette.outline, lineWidth: 0.8))
                        .frame(width: w * 0.34, height: w * 0.2)
                        .offset(y: -w * 0.24)
                }
                .position(x: w / 2, y: h * 0.56)
            }
        }
    }
}

/// 拱形投币口灯管（原创绘制）：顶边水平、两端大圆角向下，金色灯管上一圈交替闪烁的灯泡
struct ArchTrack: View {
    let bulbCount: Int

    struct ArchShape: Shape {
        func path(in r: CGRect) -> Path {
            let radius = min(r.height * 0.9, r.width * 0.2)
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
            p.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
            p.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            // v11.4 参考：拱门下沿是一排灯泡的横条（封闭的框）
            p.closeSubpath()
            return p
        }
    }

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 4, dy: 4)
            let path = ArchShape().path(in: rect)
            ZStack {
                ZStack {
                    path.stroke(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.4), Color(red: 0.85, green: 0.45, blue: 0.08)],
                                               startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    path.stroke(Color(red: 0.45, green: 0.2, blue: 0.03), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                .drawingGroup()
                // 灯泡两态闪烁，只动不透明度
                BlinkPair(duration: 0.5) { phase in
                ZStack {
                ForEach(0..<bulbCount, id: \.self) { i in
                    let t = (CGFloat(i) + 0.5) / CGFloat(bulbCount)
                    let pt = path.trimmedPath(from: 0, to: t).currentPoint ?? .zero
                    Circle()
                        .fill((i % 2 == 0) == phase ? Color(red: 1, green: 0.95, blue: 0.7) : Color(red: 0.95, green: 0.5, blue: 0.2))
                        .frame(width: 5, height: 5)
                        .shadow(color: Color(red: 1, green: 0.7, blue: 0.3).opacity(0.9), radius: 3)
                        .position(pt)
                }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }
}

/// 推币机后方背景（原创绘制，配色按参考取色）：上部红绒布、下部暗色机柜
struct MachineBackdrop: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(red: 0.45, green: 0.07, blue: 0.04), Color(red: 0.30, green: 0.05, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity)
            LinearGradient(colors: [Color(red: 0.16, green: 0.09, blue: 0.04), Color(red: 0.06, green: 0.04, blue: 0.02)],
                           startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity)
        }
    }
}

#if DEBUG
/// 调试用参考帧叠加（只在 Debug 编译）
struct ReferenceOverlay: View {
    private static let image: (UIImage, Double)? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-refOverlay"), i + 1 < args.count, let img = UIImage(contentsOfFile: args[i + 1]) else { return nil }
        let opacity = i + 2 < args.count ? Double(args[i + 2]) ?? 0.5 : 0.5
        return (img, opacity)
    }()
    var body: some View {
        if let (img, opacity) = Self.image {
            Image(uiImage: img).resizable().opacity(opacity)
        }
    }
}
#endif

/// 炮管（原创绘制）：深色炮身、金色环、炮口朝向中间
struct CannonView: View {
    let right: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.38), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.95, height: h * 0.42)
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45), Color(red: 0.7, green: 0.45, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.1, height: h * 0.5)
                        .offset(x: (right ? -1 : 1) * w * (0.18 + 0.2 * CGFloat(i)))
                }
                Ellipse()
                    .fill(Color.black)
                    .frame(width: w * 0.16, height: h * 0.34)
                    .offset(x: (right ? -1 : 1) * w * 0.44)
            }
            .rotationEffect(.degrees(right ? -18 : 18))
            .frame(width: w, height: h)
        }
    }
}

// MARK: - v11.6 性能：Core Animation 闪光（关键帧在渲染服务器上播放，主线程不用每帧重画 SwiftUI 视图）

/// 闪光时间表：在一个周期里按原来的进度函数找出每次闪光的起点（秒）
enum GlintSchedule {
    static func starts(period: Double, progress: (Double) -> Double) -> [Double] {
        var result: [Double] = []
        var previous = false, t = 0.0
        while t < period {
            let on = progress(t) >= 0
            if on && !previous { result.append(t) }
            previous = on
            t += 1.0 / 240
        }
        return result
    }
    /// BONUS 牌和 JACKPOT 字：每 3.75 秒一格、格内随机偏移（16 格 = 60 秒一个周期）
    static let bonusPeriod = HollowBonusSliderTarget.glintSlot * 16
    static func bonusStarts(offset: Double) -> [Double] {
        starts(period: bonusPeriod) { HollowBonusSliderTarget.glintProgress(at: $0 + offset) }
    }
}

/// 关键帧：周期内每次闪光按进度 p（0…1）采样 9 个点，闪光之外取 idle
private func glintKeyframes<T>(starts: [Double], period: Double, duration: Double, idle: T, value: (Double) -> T) -> (times: [NSNumber], values: [T]) {
    var times: [NSNumber] = [0], values: [T] = [idle]
    for s in starts where s > 0.002 && s + duration < period - 0.002 {
        times.append(NSNumber(value: (s - 0.001) / period)); values.append(idle)
        for i in 0...8 {
            let p = Double(i) / 8
            times.append(NSNumber(value: (s + duration * p) / period)); values.append(value(p))
        }
        times.append(NSNumber(value: (s + duration + 0.001) / period)); values.append(idle)
    }
    times.append(1); values.append(idle)
    return (times, values)
}

private func installKeyframes<T>(_ layer: CALayer, keyPath: String, period: Double, frames: (times: [NSNumber], values: [T])) {
    let a = CAKeyframeAnimation(keyPath: keyPath)
    a.keyTimes = frames.times
    a.values = frames.values
    a.duration = period
    a.repeatCount = .infinity
    a.calculationMode = .linear
    a.isRemovedOnCompletion = false
    // 所有闪光共用一个时间基准（和原来按绝对时间算的进度一样，不同元素不会同时闪）
    a.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: period)
    layer.add(a, forKey: keyPath)
}

/// 沿路径扫过的闪光：整圈边框短暂提亮 + 一道白光沿路径跑过
struct CAGlintStroke: UIViewRepresentable {
    let path: (CGRect) -> CGPath
    let starts: [Double]
    let period: Double
    let duration: Double
    let borderWidth: CGFloat
    let streakWidth: CGFloat
    var borderPeak: Float = 0.5
    var tail: Double = 0.18, head: Double = 0.02
    var borderColor = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)

    func makeUIView(context: Context) -> GlintStrokeView {
        let v = GlintStrokeView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: GlintStrokeView, context: Context) { v.config = self }
}

final class GlintStrokeView: UIView {
    // 每次 SwiftUI 更新都会调 updateUIView：只在第一次拿到配置时安装动画（之后只在尺寸变了时重装），不能每帧重装
    var config: CAGlintStroke? { didSet { if oldValue == nil { setNeedsLayout() } } }
    private let border = CAShapeLayer(), streak = CAShapeLayer()
    private var installedFor: CGSize = .zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        for l in [border, streak] {
            l.fillColor = nil; l.lineCap = .round; l.lineJoin = .round; l.opacity = 0
            layer.addSublayer(l)
        }
        streak.strokeColor = UIColor.white.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let c = config, bounds.width > 0, bounds.size != installedFor else { return }
        installedFor = bounds.size
        let p = c.path(bounds)
        for l in [border, streak] { l.frame = bounds; l.path = p }
        border.lineWidth = c.borderWidth; streak.lineWidth = c.streakWidth
        border.strokeColor = c.borderColor.cgColor
        let P = c.period, d = c.duration
        installKeyframes(border, keyPath: "opacity", period: P,
                         frames: glintKeyframes(starts: c.starts, period: P, duration: d, idle: Float(0)) { Float(sin($0 * .pi)) * c.borderPeak })
        installKeyframes(streak, keyPath: "opacity", period: P,
                         frames: glintKeyframes(starts: c.starts, period: P, duration: d, idle: Float(0)) { _ in Float(1) })
        installKeyframes(streak, keyPath: "strokeStart", period: P,
                         frames: glintKeyframes(starts: c.starts, period: P, duration: d, idle: CGFloat(0)) { CGFloat(max(0, $0 - c.tail)) })
        installKeyframes(streak, keyPath: "strokeEnd", period: P,
                         frames: glintKeyframes(starts: c.starts, period: P, duration: d, idle: CGFloat(0)) { CGFloat(min(1, $0 + c.head)) })
    }
}

/// 斜着扫过的白光带（JACKPOT 字上的闪光）：在 SwiftUI 里用字形 mask 住，只在字上显示
struct CAGlintBand: UIViewRepresentable {
    let starts: [Double]
    let period: Double
    let duration: Double
    func makeUIView(context: Context) -> GlintBandView {
        let v = GlintBandView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: GlintBandView, context: Context) { v.config = self }
}

final class GlintBandView: UIView {
    var config: CAGlintBand? { didSet { if oldValue == nil { setNeedsLayout() } } }
    private let band = CAGradientLayer()
    private var installedFor: CGSize = .zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        band.colors = [UIColor.clear.cgColor, UIColor.white.withAlphaComponent(0.95).cgColor, UIColor.clear.cgColor]
        band.startPoint = CGPoint(x: 0, y: 0.5); band.endPoint = CGPoint(x: 1, y: 0.5)
        band.opacity = 0
        layer.addSublayer(band)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let c = config, bounds.width > 0, bounds.size != installedFor else { return }
        installedFor = bounds.size
        let w = bounds.width, h = bounds.height, bw = w * 0.25
        band.bounds = CGRect(x: 0, y: 0, width: bw, height: h * 2)
        band.setAffineTransform(CGAffineTransform(rotationAngle: .pi * 18 / 180))
        // 和原来一样：光带左沿从 −0.3w 扫到 w
        let P = c.period, d = c.duration
        band.position = CGPoint(x: -0.3 * w + bw / 2, y: h / 2)
        installKeyframes(band, keyPath: "opacity", period: P,
                         frames: glintKeyframes(starts: c.starts, period: P, duration: d, idle: Float(0)) { _ in Float(1) })
        installKeyframes(band, keyPath: "position.x", period: P,
                         frames: glintKeyframes(starts: c.starts, period: P, duration: d, idle: CGFloat(-0.3 * w + bw / 2)) { CGFloat(-0.3 * w + 1.3 * w * $0 + bw / 2) })
    }
}

/// v11.7：排队的转动次数角标（金色圆牌，×N）
struct SpinQueueBadge: View {
    let count: Int
    var body: some View {
        Text(verbatim: "×\(count)")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(Color(red: 0.3, green: 0.12, blue: 0.0))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(LinearGradient(colors: [ArtPalette.goldLight, ArtPalette.gold], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(Color(red: 0.45, green: 0.2, blue: 0.02), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .accessibilityLabel(Text("\(count) spins left"))
    }
}

/// v11.7 累积奖池数字：目标值变了就在 0.4 秒里分几步滚上去（每秒最多重画约 15 次，只有这块字）
struct RollingJackpotNumber: View {
    @ObservedObject var meter: JackpotMeter
    let size: CGFloat
    var glintStarts: [Double]?
    @State private var shown: Double = GameConstants.jackpotSeed
    @State private var rollTimer: Timer?

    static func format(_ v: Double) -> String { String(format: "%.2f", v) }

    var body: some View {
        GoldText3D(text: RollingJackpotNumber.format(shown), size: size, tracking: 1, glintStarts: glintStarts)
            .onAppear { shown = meter.value }
            .onChange(of: meter.value) { target in roll(to: target) }
            .accessibilityLabel(Text(verbatim: "JACKPOT \(RollingJackpotNumber.format(meter.value))"))
    }

    private func roll(to target: Double) {
        rollTimer?.invalidate()
        // 奖池派出后回到起始值：直接跳过去
        guard target > shown else { shown = target; return }
        let start = shown, steps = 6
        var k = 0
        rollTimer = Timer.scheduledTimer(withTimeInterval: 0.4 / Double(steps), repeats: true) { t in
            k += 1
            shown = k >= steps ? target : start + (target - start) * Double(k) / Double(steps)
            if k >= steps { t.invalidate() }
        }
    }
}
