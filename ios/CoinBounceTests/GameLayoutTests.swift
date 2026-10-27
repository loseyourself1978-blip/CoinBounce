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

    func test_regions_insideSafeArea() {
        for (name, l) in screens {
            for region in l.regions {
                assertInside(region.frame, safeRect(l), "\(name) \(region.name)")
                XCTAssertGreaterThan(region.frame.height, 0, "\(name) \(region.name) 高度")
            }
        }
    }

    func test_regions_doNotOverlap() {
        for (name, l) in screens {
            let regions = l.regions
            for i in 0..<regions.count {
                for j in (i + 1)..<regions.count {
                    XCTAssertLessThan(overlapArea(regions[i].frame, regions[j].frame), 0.01,
                                      "\(name) \(regions[i].name) 与 \(regions[j].name) 重叠")
                }
            }
        }
    }

    func test_slotMachine_reelsAndSpinButton_insideFrameAndSeparate() {
        for (name, l) in screens {
            assertInside(l.slotReels, l.slotMachine, "\(name) 转轴")
            assertInside(l.spinButton, l.slotMachine, "\(name) SPIN")
            XCTAssertEqual(overlapArea(l.slotReels, l.spinButton), 0, "\(name) SPIN 遮挡转轴")
            XCTAssertGreaterThan(l.slotReels.width, l.slotMachine.width * 0.6, "\(name) 转轴宽度")
        }
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

    func test_slotObstacles_insideReels() {
        for (name, l) in screens {
            XCTAssertEqual(l.slotObstacles.count, 15, "5×3 个符号格")
            for p in l.slotObstacles {
                let r = l.slotObstacleRadius
                assertInside(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), l.slotReels, "\(name) 符号格障碍")
            }
            // 相邻障碍之间要能让金币通过
            let gap = l.slotObstacles[1].x - l.slotObstacles[0].x - l.slotObstacleRadius * 2
            XCTAssertGreaterThan(gap, l.coinRadius * 2, "\(name) 金币能从符号之间穿过")
            for p in l.fruitPins {
                XCTAssertTrue(l.fruitBar.contains(p), "\(name) 水果钉在水果栏内")
            }
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
            XCTAssertLessThan(l.pusherFrontRestY + l.pusherStroke, l.bedEntryY, "\(name) 落币点在推板最远处之前")
            XCTAssertLessThan(l.bedEntryY, l.bedDropY)
            XCTAssertTrue(l.pusher.contains(CGPoint(x: l.size.width / 2, y: l.bedDropY)), "\(name) 掉落线在推币台内")
            XCTAssertGreaterThanOrEqual(l.bedMinX - l.coinRadius, 0)
            XCTAssertLessThanOrEqual(l.bedMaxX + l.coinRadius, l.size.width)
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
        state.bedCoins.removeAll()
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

    func test_coinReachingPusher_becomesBedCoin() {
        let l = screens[1].layout
        state.updateLayout(l)
        state.coinReachedPusher(x: l.centerX)
        XCTAssertEqual(state.bedCoins.count, 1)
        XCTAssertTrue(l.pusher.contains(CGPoint(x: state.bedCoins[0].x, y: state.bedCoins[0].y)), "推币台金币在推币台区域内")
    }

    func test_bedCoinPastDropLine_paysReward() {
        let l = screens[1].layout
        state.updateLayout(l)
        let before = state.availableCoins
        state.bedCoins = [PusherCoin(x: l.size.width / 2, y: l.bedDropY + 1)]
        state.step(dt: 1.0 / 60.0)
        XCTAssertTrue(state.bedCoins.isEmpty)
        XCTAssertEqual(state.availableCoins, before + GameConstants.bedDropReward)
    }

    func test_sliderTravel_followsLayout() {
        for (_, l) in screens {
            state.updateLayout(l)
            for _ in 0..<200 {
                state.step(dt: 1.0 / 30.0)
                XCTAssertLessThanOrEqual(abs(state.coinSliderOffset), l.coinSliderTravel + 0.001)
                XCTAssertLessThanOrEqual(abs(state.bonusSliderOffset), l.bonusSliderTravel + 0.001)
                XCTAssertTrue((0...l.pusherStroke + 0.001).contains(state.pusherOffset))
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


// ============================================================
// MARK: - 开局预铺金币
// ============================================================

final class PusherPrefillTests: XCTestCase {

    let layouts: [GameLayout] = [
        GameLayout(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)),
        GameLayout(size: CGSize(width: 393, height: 852), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)),
        GameLayout(size: CGSize(width: 440, height: 956), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
    ]

    var state: GameState!

    override func setUp() {
        super.setUp()
        state = GameState.shared
        state.saveStore = SaveStore(defaults: UserDefaults(suiteName: "PusherPrefillTests")!, key: "PusherPrefillTests.SaveData")
        state.saveStore.clear()
        state.resetForTesting()
        state.availableCoins = 100
        state.pendingDrops.removeAll()
        state.bedCoins.removeAll()
        state.slotSpinState = .spinIdle
    }

    override func tearDown() {
        state.bedCoins.removeAll()
        state.resetForTesting()
        super.tearDown()
    }

    /// 测试里没有 SpriteKit 下落区：排队的金币直接送进推币台（与下落区底部交接一致）
    private func simulate(seconds: Double) {
        for _ in 0..<Int(seconds * 60) {
            let drops = state.pendingDrops
            state.pendingDrops.removeAll()
            drops.forEach { state.coinReachedPusher(x: $0.x) }
            state.advance(by: 1.0 / 60.0)
        }
    }

    func test_prefill_coinsInsideBedWithoutOverlap() {
        for l in layouts {
            let points = GameState.prefillPositions(for: l)
            XCTAssertGreaterThan(points.count, 20, "应预铺一层金币")
            for p in points {
                XCTAssertTrue(p.x >= l.bedMinX - 0.001 && p.x <= l.bedMaxX + 0.001)
                XCTAssertTrue(p.y > l.pusherFrontRestY + l.pusherStroke && p.y < l.bedDropY, "预铺金币在推板最远处之前、掉落线之后")
            }
            for i in 0..<points.count {
                for j in (i + 1)..<points.count {
                    let d = hypot(points[i].x - points[j].x, points[i].y - points[j].y)
                    XCTAssertGreaterThanOrEqual(d, l.coinRadius * 2, "预铺金币不重叠")
                }
            }
        }
    }

    func test_prefill_idlePusherDropsAtMostTwo() {
        for l in layouts {
            state.resetForTesting()
            state.updateLayout(l)
            state.prefillBed()
            let before = state.bedDropCount
            simulate(seconds: 20)
            XCTAssertLessThanOrEqual(state.bedDropCount - before, 2, "\(l.size) 不投币时推板空转不应大量掉落")
        }
    }

    func test_prefill_fewCoinsPushSomeOff() {
        for l in layouts {
            state.resetForTesting()
            state.updateLayout(l)
            state.prefillBed()
            state.availableCoins = 100
            let dropsBefore = state.bedDropCount
            for _ in 0..<5 {
                state.dropCoin()
                simulate(seconds: 1)
            }
            simulate(seconds: 3)
            let drops = state.bedDropCount - dropsBefore
            XCTAssertGreaterThanOrEqual(drops, 1, "\(l.size) 投 5 枚币后应至少推落 1 枚")
        }
    }

    func test_prefill_droppedCoinsPayReward() {
        let l = layouts[1]
        state.updateLayout(l)
        state.prefillBed()
        state.availableCoins = 100
        let won = state.totalCoinsWon
        let dropsBefore = state.bedDropCount
        let fruitsBefore = state.fruitsLit.filter { $0 }.count
        for _ in 0..<5 { state.dropCoin(); simulate(seconds: 1) }
        simulate(seconds: 3)
        let fruitsLit = state.fruitsLit.filter { $0 }.count - fruitsBefore
        XCTAssertEqual(state.totalCoinsWon - won,
                       (state.bedDropCount - dropsBefore) * GameConstants.bedDropReward + fruitsLit * GameConstants.fruitHitReward,
                       "推落的金币按 bedDropReward 计分")
    }

    func test_layoutChange_beforeAnyDrop_refillsForNewScreen() {
        state.updateLayout(layouts[1])
        state.prefillBed()
        state.updateLayout(layouts[0])
        XCTAssertEqual(state.bedCoins.count, GameState.prefillPositions(for: layouts[0]).count)
    }
}
