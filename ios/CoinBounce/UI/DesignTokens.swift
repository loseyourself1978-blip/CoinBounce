import SwiftUI
import CoreGraphics

// 设计系统简易常量（用于视觉对齐和快速迭代）
struct DS {
    // 颜色
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let deepGold = Color(red: 0.82, green: 0.66, blue: 0.31)
    static let burnRed = Color(red: 0.6, green: 0.12, blue: 0.12)
    // 圆角与阴影
    static let cornerRadius: CGFloat = 8.0
    static let shadowSoft = Color.black.opacity(0.25)
    // SPIN 按钮横向定位百分比（相对屏幕宽度）
    static let spinButtonXPercent: CGFloat = 0.75
}
