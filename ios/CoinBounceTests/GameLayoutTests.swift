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

    func test_coinReachingPusher_handsOffToPusherWithFraction() {
        let l = screens[1].layout
        state.updateLayout(l)
        var received: [CGFloat] = []
        state.onCoinToPusher = { received.append($0) }
        defer { state.onCoinToPusher = nil }
        state.coinReachedPusher(x: l.centerX)
        state.coinReachedPusher(x: l.fieldMinX)
        state.coinReachedPusher(x: l.fieldMaxX + 100)
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(received[0], 0, accuracy: 0.001, "中间投下落在台面中间")
        XCTAssertEqual(received[1], -1, accuracy: 0.001, "最左")
        XCTAssertEqual(received[2], 1, accuracy: 0.001, "超出范围夹到最右")
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


