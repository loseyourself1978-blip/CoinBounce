import XCTest
@testable import CoinBounce

final class SlotMachineViewTests: XCTestCase {
    func testSpinButtonPercent() {
        // 验证设计系统常量中 Spin Button 百分比是否在合理范围内
        let v = DS.spinButtonXPercent
        XCTAssertGreaterThanOrEqual(v, 0.5)
        XCTAssertLessThanOrEqual(v, 0.9)
    }
}
