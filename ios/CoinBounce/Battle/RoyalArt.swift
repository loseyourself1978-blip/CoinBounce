import SwiftUI

// MARK: - v12.2 国王 / 王后 / 亲吻；v12.4 BOSS
/// 素材在 Assets.xcassets（生成脚本 tools/art/）。国王朝右、王后朝左；1024 高的画布里脚在 y≈975 / 970，
/// 所以按高度缩放、底边对齐；亲吻图是 3:2
enum RoyalAsset: String, CaseIterable {
    case kingIdle = "KingIdle"
    case kingAttack = "KingAttack"
    case kingVictory = "KingVictory"
    case queenCry = "QueenCry"
    case queenHappy = "QueenHappy"
    case kiss = "KingQueenKiss"
    /// v12.4 BOSS（朝左，和国王同一个比例：按同样的高度缩放、底边对齐）。挨打时上半身后仰，K.O. 时坐在地上转圈
    case bossIdle = "BossIdle"
    case bossHurt = "BossHurt"
    case bossKO = "BossKO"

    /// 宽 / 高
    var aspect: CGFloat { self == .kiss ? 1.5 : 1 }
    /// 脚底到画布底边的空白占高度的比例（底边对齐时往下挪这么多）
    var footMargin: CGFloat {
        switch self {
        case .queenCry, .queenHappy: return 54.0 / 1024
        case .bossKO: return 46.0 / 1024
        default: return 49.0 / 1024
        }
    }
}

/// 高度为 height 的一张人物图，脚踩在视图底边
struct RoyalSprite: View {
    let asset: RoyalAsset
    let height: CGFloat
    var body: some View {
        Image(asset.rawValue)
            .resizable()
            .interpolation(.high)
            .frame(width: height * asset.aspect, height: height)
            .offset(y: height * asset.footMargin)
    }
}

/// 亲吻时飘起来的爱心：位置只由时间决定（u = 亲吻这一段走了多少秒），不存状态
struct KissHearts: View {
    let u: Double
    let width: CGFloat
    let height: CGFloat
    static let count = 9

    /// 第 i 颗爱心在 u 秒时的位置（0…1 的归一化坐标）、大小和不透明度；还没出生返回 nil
    static func heart(_ i: Int, at u: Double) -> (x: Double, y: Double, scale: Double, opacity: Double)? {
        let birth = Double(i) * 0.28
        let life = 1.9
        var age = u - birth
        guard age >= 0 else { return nil }
        age = age.truncatingRemainder(dividingBy: life + 0.6)
        guard age <= life else { return nil }
        let k = age / life
        let lane = Double((i * 5) % count) / Double(count - 1)          // 0…1，左右错开
        let x = 0.5 + (lane - 0.5) * 0.9 + 0.04 * sin(age * 3 + Double(i))
        let y = 0.75 - 0.8 * k
        let scale = 0.6 + 0.5 * sin(min(1, k * 3) * .pi / 2) + 0.12 * Double(i % 3)
        let opacity = k < 0.7 ? 1 : max(0, 1 - (k - 0.7) / 0.3)
        return (x, y, scale, opacity)
    }

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { i in
                if let h = Self.heart(i, at: u) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: height * 0.17))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.7), Color(red: 0.95, green: 0.15, blue: 0.35)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .white.opacity(0.8), radius: 1)
                        .scaleEffect(h.scale)
                        .opacity(h.opacity)
                        .position(x: width * h.x, y: height * h.y)
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}
