import XCTest
import SwiftUI
@testable import CoinBounce

// ============================================================
// MARK: - GameLayout：三种屏幕尺寸下的布局与物理位置
// ============================================================

final class GameLayoutTests: XCTestCase {

    /// iPhone SE（375×667）、iPhone 16/17（393×852）、Pro Max（440×956）
    let screens: [(name: String, layout: GameLayout)] = [
        ("SE", GameLayout(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))),
        ("16/17", GameLayout(size: CGSize(width: 393, height: 852), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))),
        ("ProMax", GameLayout(size: CGSize(width: 440, height: 956), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)))
    ]

    private func safeRect(_ l: GameLayout) -> CGRect {
        CGRect(x: 0, y: l.safeArea.top, width: l.size.width,
               height: l.size.height - l.safeArea.top - l.safeArea.bottom)
    }

    private func assertInside(_ inner: CGRect, _ outer: CGRect, _ message: String, file: StaticString = #file, line: UInt = #line) {
        let eps: CGFloat = 0.001
        XCTAssertTrue(inner.minX >= outer.minX - eps && inner.maxX <= outer.maxX + eps
                      && inner.minY >= outer.minY - eps && inner.maxY <= outer.maxY + eps,
                      "\(message): \(inner) 不在 \(outer) 内", file: file, line: line)
    }

    private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// v11.4：参考隐藏状态栏、画面从屏幕最顶端开始（JACKPOT 牌在灵动岛后面）。所有区域在屏幕内；
    /// 可点的金币 / 帮助 / 设置一行及以下的区域在安全区上沿以下
    func test_regions_insideScreen_controlsBelowSafeTop() {
        for (name, l) in screens {
            let screen = CGRect(origin: .zero, size: l.size)
            for region in l.regions {
                assertInside(region.frame, screen, "\(name) \(region.name)")
                XCTAssertGreaterThan(region.frame.height, 0, "\(name) \(region.name) 高度")
                if region.name != "jackpot" { XCTAssertGreaterThanOrEqual(region.frame.minY, l.safeArea.top, "\(name) \(region.name) 在安全区上沿以下") }
            }
        }
    }

    func test_regions_doNotOverlap() {
        for (name, l) in screens {
            let regions = l.regions
            for i in 0..<regions.count {
                for j in (i + 1)..<regions.count {
                    // v11.6：金币 / 按钮一行叠在投币口区域上方两侧（用户允许），另外检查它不挡 COIN 牌
                    let pair = Set([regions[i].name, regions[j].name])
                    if pair == ["topRow", "sliderTrack"] { continue }
                    XCTAssertLessThan(overlapArea(regions[i].frame, regions[j].frame), 0.01,
                                      "\(name) \(regions[i].name) 与 \(regions[j].name) 重叠")
                }
            }
            // COIN 牌往复的整个范围
            let plateH = ReferenceBoxes.y(ReferenceBoxes.coinPlate.height, l.size)
            let plate = CGRect(x: l.centerX - l.coinSliderTravel - l.coinSliderWidth / 2, y: l.coinPlateY - plateH / 2,
                               width: l.coinSliderTravel * 2 + l.coinSliderWidth, height: plateH)
            XCTAssertFalse(l.topRow.intersects(plate), "\(name) 金币 / 按钮一行不挡 COIN 牌")
        }
    }

    func test_slotReels_fillSlotFrameWidth() {
        for (name, l) in screens {
            assertInside(l.slotReels, l.slotMachine, "\(name) 转轴")
            XCTAssertGreaterThan(l.slotReels.width, l.slotMachine.width * 0.9, "\(name) 没有 SPIN 按钮，转轴铺满宽度")
        }
    }

    /// v11.1：铆钉只做装饰（不参与碰撞），只检查位置在转轴区内
    /// v11.6：转轴间的装饰铆钉不再单独画（格挡钉由 PegsLayer 统一画，和碰撞钉同一组位置）
    func test_slotPins_replacedByPegs() {
        for (_, l) in screens { XCTAssertTrue(l.slotPins.isEmpty) }
    }

    func test_layout_matchesReferenceProportions() {
        let l = screens[1].layout
        XCTAssertEqual(l.slotMachine.height / l.size.height, (1280 - 570) / 2622, accuracy: 0.001, "v11.6 老虎机向上加高：570–1280 像素（原 787–1280）")
        XCTAssertGreaterThan(l.slotMachine.height, l.dropField.height * 1.8, "老虎机明显高于战斗区")
        XCTAssertEqual(l.pusherView.maxY, l.size.height, "推币台延伸到屏幕底部，投币按钮叠在上面")
        // v11.1：各区域在 iPhone 17 整屏上的位置与参考 App 实测一致（误差 1% 屏高以内）
        do {
            let l = GameLayout(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
            let H = l.size.height
            XCTAssertEqual(l.jackpot.minY, 0, "JACKPOT 从屏幕最顶端开始")
            XCTAssertEqual(l.jackpot.maxY / H, 320 / 2622, accuracy: 0.002, "JACKPOT 两行，底部 320 像素")
            XCTAssertEqual(l.topRow.midY / H, 363 / 2622, accuracy: 0.005, "金币 / 按钮一行 326–400 像素")
            XCTAssertEqual(l.slotMachine.minY / H, 570 / 2622, accuracy: 0.005, "老虎机顶部 570 像素")
            XCTAssertEqual(l.slotMachine.maxY / H, 0.488, accuracy: 0.005, "老虎机底部 ≈ 48.8%")
            XCTAssertEqual(l.fruitBar.minY / H, 0.588, accuracy: 0.005, "水果排顶部 ≈ 58.8%")
            XCTAssertEqual(l.bonusLane.maxY / H, 0.69, accuracy: 0.01, "BONUS 底部 ≈ 69%")
            XCTAssertEqual(l.dropButton.minY / H, 0.905, accuracy: 0.01, "底部面板 ≈ 90.5%")
            XCTAssertEqual(l.pusherFrontY / H, 0.855, accuracy: 0.01, "台面前沿 ≈ 85.5%（参考 85–86%）")
            XCTAssertEqual(l.sideMargin / l.size.width, 0.10, accuracy: 0.005, "两侧立柱各 10% 屏宽")
        }
        XCTAssertTrue(l.pusherView.contains(CGPoint(x: l.dropButton.midX, y: l.dropButton.midY)))
    }

    func test_sliderTravel_matchesReference() {
        for (name, l) in screens {
            XCTAssertLessThanOrEqual(l.coinSliderTravel, l.size.width * GameConstants.coinSliderTravelFraction + 0.001, name)
            XCTAssertLessThanOrEqual(l.bonusSliderTravel, l.size.width * GameConstants.bonusSliderTravelFraction + 0.001, name)
        }
    }

    func test_coinSlider_periodFromConstants() {
        state.resetForTesting()
        state.advance(by: 0.05)
        let start = state.coinSliderOffset
        // 推进一个完整周期（真实时间）后回到相同位置
        var t = 0.0
        while t < GameConstants.coinSliderPeriod - 0.0001 { state.advance(by: 1.0 / 60); t += 1.0 / 60 }
        XCTAssertEqual(state.coinSliderOffset, start, accuracy: 1.5, "COIN 滑块周期为 \(GameConstants.coinSliderPeriod) 秒")
    }

    func test_dropFallTime_constantsInReferenceRange() {
        XCTAssertTrue((0.5...1.0).contains(GameConstants.dropFallSeconds), "自由落体时长在参考范围内，弹跳后总时长约 1.4～2 秒")
    }

    func test_fruits_insideFruitBar() {
        for (name, l) in screens {
            XCTAssertEqual(l.fruitCenters.count, 7)
            for (i, c) in l.fruitCenters.enumerated() {
                let lamp = CGRect(x: c.x - l.fruitLampWidth / 2, y: c.y - 1, width: l.fruitLampWidth, height: 2)
                assertInside(lamp, l.fruitBar, "\(name) 水果 \(i)")
            }
            for x in l.fruitBaffleXs {
                XCTAssertTrue(x > l.fruitBar.minX && x < l.fruitBar.maxX, "\(name) 水果格挡 \(x)")
            }
        }
    }

    /// v11.6 格挡钉：A 排 3、B 排 4、C 排 3、D 排 4、水果排 6；同一排相邻两钉、钉和下落区侧墙之间都能让金币通过；
    /// 排与排交错（下一排的钉不在上一排钉的正下方）
    func test_pegs_staggeredAndPassable() {
        for (name, l) in screens {
            XCTAssertEqual(l.slotObstacles.count, 14, name)
            XCTAssertEqual(l.fruitPins.count, 6, name)
            let all: [CGPoint] = l.slotObstacles + l.fruitPins
            let grouped: [Int: [CGPoint]] = Dictionary(grouping: all, by: { (p: CGPoint) -> Int in Int(p.y.rounded()) })
            var rows: [[CGPoint]] = grouped.values.map { (row: [CGPoint]) -> [CGPoint] in row.sorted { $0.x < $1.x } }
            rows.sort { $0[0].y < $1[0].y }
            XCTAssertEqual(rows.count, 5, "\(name) 5 排")
            let r = l.slotObstacleRadius
            for row in rows {
                for (a, b) in zip(row, row.dropFirst()) { XCTAssertGreaterThan(b.x - a.x - r * 2, l.coinRadius * 2, "\(name) 相邻两钉之间过得去") }
                XCTAssertGreaterThan(row.first!.x - r - (l.fieldMinX - l.coinRadius), l.coinRadius * 2, "\(name) 左墙和钉之间过得去")
                XCTAssertGreaterThan((l.fieldMaxX + l.coinRadius) - row.last!.x - r, l.coinRadius * 2, "\(name) 右墙和钉之间过得去")
            }
            for (upper, lower) in zip(rows, rows.dropFirst()) where upper.count != lower.count {
                for p in lower { XCTAssertFalse(upper.contains { abs($0.x - p.x) < r }, "\(name) 交错排列") }
            }
            for p in l.fruitPins { XCTAssertTrue(l.fruitBar.contains(p), "\(name) 水果钉在水果栏内") }
        }
    }

    func test_sliders_stayOnScreenAtFullTravel() {
        for (name, l) in screens {
            for sign: CGFloat in [-1, 1] {
                let coin = l.coinSliderCenter(offset: sign * l.coinSliderTravel)
                assertInside(CGRect(x: coin.x - l.coinSliderWidth / 2, y: coin.y, width: l.coinSliderWidth, height: 0),
                             l.sliderTrack.insetBy(dx: GameLayout.margin - 0.001, dy: 0), "\(name) COIN 滑块")
                let bonus = l.bonusSliderCenter(offset: sign * l.bonusSliderTravel)
                assertInside(CGRect(x: bonus.x - l.bonusSliderWidth / 2, y: bonus.y, width: l.bonusSliderWidth, height: 0),
                             l.bonusLane.insetBy(dx: GameLayout.margin - 0.001, dy: 0), "\(name) BONUS 滑块")
            }
        }
    }

    func test_coinPath_isOrderedTopToBottom() {
        for (name, l) in screens {
            XCTAssertTrue(l.sliderTrack.contains(CGPoint(x: l.centerX, y: l.coinSpawnY)), "\(name) 出币点")
            // 投币口在最顶端：金币依次经过老虎机、战斗区、水果、BONUS
            XCTAssertLessThan(l.sliderTrack.maxY, l.slotMachine.minY + 0.001, "\(name) 投币口在老虎机上方")
            XCTAssertLessThanOrEqual(l.slotMachine.maxY, l.dropField.minY + 0.001)
            XCTAssertLessThan(l.coinSpawnY, l.slotMachine.minY)
            XCTAssertLessThanOrEqual(l.dropField.maxY, l.fruitBar.minY + 0.001)
            XCTAssertLessThanOrEqual(l.fruitBar.maxY, l.bonusLane.minY + 0.001)
            XCTAssertLessThanOrEqual(l.bonusLane.maxY, l.bedEntryY)
            XCTAssertTrue(l.pusher.contains(CGPoint(x: l.centerX, y: l.bedEntryY)), "\(name) 交接线在推币台区域顶部")
            XCTAssertLessThan(l.bedEntryY - l.pusher.minY, l.pusher.height * 0.2)
            XCTAssertGreaterThanOrEqual(l.fieldMinX - l.coinRadius, 0)
            XCTAssertLessThanOrEqual(l.fieldMaxX + l.coinRadius, l.size.width)
        }
    }

    // MARK: - GameState 与布局一致

    var state: GameState!

    override func setUp() {
        super.setUp()
        state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "GameLayoutTests")!, key: "GameLayoutTests.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.availableCoins = 100
        state.pendingDrops.removeAll()
        state.fruitsLit = Array(repeating: false, count: 7)
        state.showCardSelection = false
        state.slotSpinState = .spinIdle
    }

    override func tearDown() {
        state.resetForTesting()
        super.tearDown()
    }

    func test_dropCoin_queuesCoinUnderSlider() {
        for (_, l) in screens {
            state.updateLayout(l)
            state.pendingDrops.removeAll()
            state.dropCoin()
            let coin = state.pendingDrops.last!
            let slider = l.coinSliderCenter(offset: state.coinSliderOffset)
            XCTAssertEqual(coin.y, l.coinSpawnY)
            XCTAssertLessThanOrEqual(abs(coin.x - slider.x), 26.001, "金币从 COIN 滑块位置落下")
            XCTAssertGreaterThan(coin.vy, 0, "初速度向下")
        }
    }

    func test_fruitColumn_matchesLamps() {
        for (name, l) in screens {
            for (i, c) in l.fruitCenters.enumerated() {
                XCTAssertEqual(l.fruitColumn(forX: c.x), i, "\(name) 水果 \(i) 中心")
                XCTAssertEqual(l.fruitColumn(forX: c.x - l.fruitLampWidth * 0.49), i)
                XCTAssertEqual(l.fruitColumn(forX: c.x + l.fruitLampWidth * 0.49), i)
            }
            XCTAssertNil(l.fruitColumn(forX: l.fruitCenters[0].x - l.fruitLampWidth))
            XCTAssertNil(l.fruitColumn(forX: l.fruitCenters[6].x + l.fruitLampWidth))
        }
    }

    func test_coinCrossingFruitRow_lightsThatFruit() {
        let original = state.randomUnit
        state.randomUnit = { 0 }   // 必定点亮
        defer { state.randomUnit = original }
        for (name, l) in screens {
            state.updateLayout(l)
            for index in [0, 3, 6] {
                state.fruitsLit = Array(repeating: false, count: 7)
                state.coinCrossedFruitRow(x: l.fruitCenters[index].x)
                XCTAssertTrue(state.fruitsLit[index], "\(name) 经过水果 \(index) 应点亮它")
                XCTAssertEqual(state.fruitsLit.filter { $0 }.count, 1, "\(name) 只点亮一个")
            }
        }
    }

    func test_coinThroughBonusSlider_startsSlot() {
        let l = screens[0].layout
        state.updateLayout(l)
        state.step(dt: 1.0 / 60.0)
        let bonus = l.bonusSliderCenter(offset: state.bonusSliderOffset)
        XCTAssertFalse(state.coinCrossedBonusLane(x: bonus.x + l.bonusSliderWidth), "偏离 BONUS 不触发")
        XCTAssertFalse(state.isSpinning)
        XCTAssertTrue(state.coinCrossedBonusLane(x: bonus.x), "从 BONUS 中间穿过")
        XCTAssertTrue(state.isSpinning, "穿过 BONUS 应启动老虎机")
    }

    func test_coinReachingPusher_handsOffAtSameScreenPoint() {
        let l = screens[1].layout
        state.updateLayout(l)
        var received: [CGPoint] = []
        state.onCoinToPusher = { point, _, _ in received.append(point) }
        defer { state.onCoinToPusher = nil }
        state.coinReachedPusher(x: l.centerX)
        state.coinReachedPusher(x: l.fieldMaxX + 100)
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0].x, l.centerX - l.pusher.minX, accuracy: 0.001, "推币台视图内的横坐标与屏幕一致")
        XCTAssertEqual(received[0].y, l.bedEntryY - l.pusher.minY, accuracy: 0.001, "纵坐标为交接线")
        XCTAssertEqual(received[1].x, l.fieldMaxX - l.pusher.minX, accuracy: 0.001, "超出范围夹到边界")
    }

    func test_coinFellOffPusher_paysReward() {
        let before = state.availableCoins
        let drops = state.bedDropCount
        state.coinFellOffPusher()
        XCTAssertEqual(state.availableCoins, before + GameConstants.bedDropReward)
        XCTAssertEqual(state.bedDropCount, drops + 1)
    }

    func test_sliderTravel_followsLayout() {
        for (_, l) in screens {
            state.updateLayout(l)
            for _ in 0..<200 {
                state.step(dt: 1.0 / 30.0)
                XCTAssertLessThanOrEqual(abs(state.coinSliderOffset), l.coinSliderTravel + 0.001)
                XCTAssertLessThanOrEqual(abs(state.bonusSliderOffset), l.bonusSliderTravel + 0.001)
            }
        }
    }

    func test_advance_appliesSimulationSpeedInSubsteps() {
        state.advance(by: 1.0 / 60.0)
        let advanced = state.coinSliderOffset

        state.resetForTesting()
        let steps = Int((GameConstants.simulationSpeed).rounded())
        for _ in 0..<steps { state.step(dt: 1.0 / 60.0) }
        XCTAssertEqual(advanced, state.coinSliderOffset, accuracy: 0.0001, "一帧 = simulationSpeed 个 1/60s 子步")
    }
}


