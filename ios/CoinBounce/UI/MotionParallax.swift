import Combine
import CoreMotion
import SwiftUI

// MARK: - 设备倾斜视差
// 上半部的背景层随手机倾斜轻微反向移动（最多约 4 点），让机柜有纵深；只移动纯装饰层，不影响物理碰撞位置。
// 模拟器没有陀螺仪，偏移始终为 0。
final class MotionParallax: ObservableObject {
    static let shared = MotionParallax()
    static let maxOffset: CGFloat = 4

    @Published private(set) var offset: CGSize = .zero
    private let manager = CMMotionManager()

    private init() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let g = motion?.gravity else { return }
            let target = CGSize(width: CGFloat(g.x) * MotionParallax.maxOffset,
                                height: CGFloat(g.y + 0.6) * MotionParallax.maxOffset)
            self?.offset = CGSize(width: max(-MotionParallax.maxOffset, min(MotionParallax.maxOffset, target.width)),
                                  height: max(-MotionParallax.maxOffset, min(MotionParallax.maxOffset, target.height)))
        }
    }
}
