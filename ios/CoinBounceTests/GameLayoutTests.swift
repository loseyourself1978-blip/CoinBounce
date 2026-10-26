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

    func test_pegs_insideDropField() {
        for (name, l) in screens {
            XCTAssertEqual(l.pegRows.map(\.count), [3, 4, 3])
            for peg in l.pegRows.joined() {
                let r = l.pegRadius
                assertInside(CGRect(x: peg.x - r, y: peg.y - r, width: r * 2, height: r * 2), l.dropField, "\(name) 格挡")
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
            XCTAssertLessThan(l.coinSpawnY, l.dropField.minY)
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
        state.active2DCoins.removeAll()
        state.bedCoins.removeAll()
        state.fruitsLit = Array(repeating: false, count: 7)
        state.showCardSelection = false
        state.slotSpinState = .spinIdle
    }

    override func tearDown() {
        state.resetForTesting()
        super.tearDown()
    }

    func test_dropCoin_spawnsUnderCoinSlider() {
        for (_, l) in screens {
            state.updateLayout(l)
            state.active2DCoins.removeAll()
            state.dropCoin()
            let coin = state.active2DCoins.last!
            let slider = l.coinSliderCenter(offset: state.coinSliderOffset)
            XCTAssertEqual(coin.y, l.coinSpawnY)
            XCTAssertLessThanOrEqual(abs(coin.x - slider.x), 26.001, "金币从 COIN 滑块位置落下")
        }
    }

    func test_coinFallingOnFruit_lightsThatFruit() {
        for (name, l) in screens {
            state.updateLayout(l)
            for index in [0, 3, 6] {
                state.fruitsLit = Array(repeating: false, count: 7)
                let c = l.fruitCenters[index]
                state.active2DCoins = [Active2DCoin(x: c.x, y: l.fruitBar.minY - 2, vx: 0, vy: 300)]
                for _ in 0..<5 { state.step(dt: 1.0 / 60.0) }
                XCTAssertTrue(state.fruitsLit[index], "\(name) 落在水果 \(index) 上应点亮它")
                XCTAssertEqual(state.fruitsLit.filter { $0 }.count, 1, "\(name) 只点亮一个")
            }
        }
    }

    func test_coinFallingOnBonusSlider_startsSlot() {
        let l = screens[0].layout
        state.updateLayout(l)
        state.step(dt: 1.0 / 60.0)
        let bonus = l.bonusSliderCenter(offset: state.bonusSliderOffset)
        state.active2DCoins = [Active2DCoin(x: bonus.x, y: l.bonusLane.minY + 1, vx: 0, vy: 0)]
        state.step(dt: 1.0 / 240.0)
        XCTAssertTrue(state.isSpinning, "落在 BONUS 滑块上应启动老虎机")
    }

    func test_coinReachingBedEntry_becomesBedCoin() {
        let l = screens[1].layout
        state.updateLayout(l)
        state.active2DCoins = [Active2DCoin(x: l.centerX, y: l.bedEntryY - 1, vx: 0, vy: 300)]
        state.step(dt: 1.0 / 60.0)
        XCTAssertTrue(state.active2DCoins.isEmpty)
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

    func test_fallingCoin_staysInsideField() {
        let l = screens[0].layout
        state.updateLayout(l)
        state.active2DCoins = [Active2DCoin(x: l.fieldMaxX, y: l.dropField.minY, vx: 2000, vy: 0)]
        state.step(dt: 1.0 / 60.0)
        XCTAssertLessThanOrEqual(state.active2DCoins[0].x, l.fieldMaxX)
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
        let start = Active2DCoin(x: 200, y: 300, vx: 0, vy: 0)
        state.active2DCoins = [start]
        state.advance(by: 1.0 / 60.0)
        let advanced = state.active2DCoins[0].y

        state.resetForTesting()
        state.active2DCoins = [start]
        let steps = Int((GameConstants.simulationSpeed).rounded())
        for _ in 0..<steps { state.step(dt: 1.0 / 60.0) }
        XCTAssertEqual(advanced, state.active2DCoins[0].y, accuracy: 0.0001, "一帧 = simulationSpeed 个 1/60s 子步")
    }
}

