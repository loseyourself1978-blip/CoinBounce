import SwiftUI

// MARK: - 推币台底图（代码绘制）
// 按 GameLayout 绘制：后挡板、左右侧栏、台面、前沿掉落口。推板和引导斜坡在 CoinPusherView 里叠加。
// 不画任何金币，台面上的金币全部来自物理。
struct PusherBedBackground: View {
    let layout: GameLayout

    static let railGradient = LinearGradient(colors: [
        Color(red: 0.55, green: 0.38, blue: 0.12),
        Color(red: 0.85, green: 0.66, blue: 0.28),
        Color(red: 0.45, green: 0.30, blue: 0.08)
    ], startPoint: .leading, endPoint: .trailing)

    static let rampGradient = LinearGradient(stops: [
        .init(color: Color(red: 0.42, green: 0.28, blue: 0.10), location: 0.0),
        .init(color: Color(red: 0.28, green: 0.18, blue: 0.06), location: 1.0)
    ], startPoint: .top, endPoint: .bottom)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let top = layout.pusher.minY
            // 台面左右边缘 = 金币可到达的范围
            let deckLeft = layout.bedMinX - layout.coinRadius
            let deckRight = layout.bedMaxX + layout.coinRadius
            let backWallH = layout.pusherFrontRestY - top
            // 掉落口：金币中心越过 bedDropY 即掉落，口子从这里开始
            let mouthTop = layout.bedDropY - top

            ZStack(alignment: .topLeading) {
                // 机身底色
                Color(red: 0.10, green: 0.07, blue: 0.04)

                // 台面（绿色绒面，越靠前越亮）
                Rectangle()
                    .fill(LinearGradient(colors: [
                        Color(red: 0.05, green: 0.20, blue: 0.14),
                        Color(red: 0.09, green: 0.32, blue: 0.22)
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(width: deckRight - deckLeft, height: mouthTop)
                    .offset(x: deckLeft)

                // 台面细纹，表现纵深
                Path { p in
                    var y = backWallH
                    var step: CGFloat = 10
                    while y < mouthTop {
                        p.move(to: CGPoint(x: deckLeft, y: y))
                        p.addLine(to: CGPoint(x: deckRight, y: y))
                        y += step
                        step *= 1.12
                    }
                }
                .stroke(Color.white.opacity(0.05), lineWidth: 1)

                // 后挡板（被推板遮住大部分，推板后退时露出）
                Rectangle()
                    .fill(LinearGradient(colors: [
                        Color(red: 0.20, green: 0.12, blue: 0.05),
                        Color(red: 0.08, green: 0.05, blue: 0.02)
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(width: deckRight - deckLeft, height: backWallH)
                    .offset(x: deckLeft)

                // 前沿掉落口
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Color.black, Color(red: 0.12, green: 0.08, blue: 0.03)],
                                   startPoint: .top, endPoint: .bottom)
                    Rectangle()
                        .fill(Color(red: 0.95, green: 0.78, blue: 0.30))
                        .frame(height: 2)
                }
                .frame(width: deckRight - deckLeft, height: max(0, h - mouthTop))
                .offset(x: deckLeft, y: mouthTop)

                // 左右侧栏
                rail(width: deckLeft, height: h)
                rail(width: w - deckRight, height: h)
                    .offset(x: deckRight)
            }
        }
    }

    private func rail(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(PusherBedBackground.railGradient)
            // 侧栏灯
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    Spacer(minLength: 0)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.92, blue: 0.6))
                        .frame(width: width * 0.4, height: width * 0.4)
                        .shadow(color: .yellow.opacity(0.8), radius: 3)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: width, height: height)
    }
}
