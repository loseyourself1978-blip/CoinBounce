import SwiftUI
import UIKit

// MARK: - v12.3 画面升级（SwiftUI 这一层）：暗角、静态颗粒、光斑、光柱、金字高光
// 全部是静态图层或由 Core Animation 驱动的位移动画，不拦触摸、不按帧重算。-fxOff 时都不画（前后对比用）。

/// 一小块随机颗粒，平铺到全屏。只生成一次
enum FilmGrain {
    static let tile: UIImage = {
        let side = 128
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            // 一半亮点一半暗点，透明度随机：普通混合就有颗粒感，不需要 overlay 混合（那样要把下面的 3D 层整个再合成一次）
            let light = Bool.random(using: &generator)
            let alpha = UInt8.random(in: 0...255, using: &generator)
            let value: UInt8 = light ? alpha : 0          // 预乘
            bytes[i * 4] = value; bytes[i * 4 + 1] = value; bytes[i * 4 + 2] = value; bytes[i * 4 + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()
}

/// 暗角 + 颗粒，盖在整个画面最上面
struct FilmOverlay: View {
    /// 四角最暗处的不透明度
    var vignette: Double = 0.36
    /// 颗粒的不透明度
    var grain: Double = 0.07

    var body: some View {
        if VisualFX.enabled {
            ZStack {
                EllipticalGradient(stops: [.init(color: .clear, location: 0.0),
                                           .init(color: .clear, location: 0.62),
                                           .init(color: .black.opacity(vignette * 0.45), location: 0.86),
                                           .init(color: .black.opacity(vignette), location: 1.0)],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.72)
                Image(uiImage: FilmGrain.tile)
                    .resizable(resizingMode: .tile)
                    .opacity(grain)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 一圈暖色的光（灯下面的光斑、JACKPOT 数字后面的光晕）
struct LightPool: View {
    var color: Color = Color(red: 1, green: 0.8, blue: 0.45)
    var strength: Double = 0.3

    var body: some View {
        if VisualFX.enabled {
            EllipticalGradient(stops: [.init(color: color.opacity(strength), location: 0),
                                       .init(color: color.opacity(strength * 0.35), location: 0.5),
                                       .init(color: color.opacity(0), location: 1)],
                               center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// 从顶上斜着照下来的几道光柱（叠加混合的渐变）。只用在纯 SwiftUI 的画面（大厅、轮盘）
struct LightShafts: View {
    var color: Color = Color(red: 1, green: 0.86, blue: 0.6)
    var strength: Double = 0.09
    /// 每道光：顶端中心的横向位置（0…1）、倾斜角度、顶端宽度（占画面宽度）
    var beams: [(x: CGFloat, degrees: Double, width: CGFloat)] = [(0.18, 14, 0.10), (0.5, 0, 0.13), (0.82, -14, 0.10)]

    var body: some View {
        if VisualFX.enabled {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    ForEach(0..<beams.count, id: \.self) { i in
                        let beam = beams[i]
                        ShaftShape()
                            .fill(LinearGradient(colors: [color.opacity(strength), color.opacity(strength * 0.4), color.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: w * beam.width * 2.4, height: h * 0.72)
                            .rotationEffect(.degrees(beam.degrees), anchor: .top)
                            .position(x: w * beam.x, y: h * 0.36)
                    }
                }
                .blur(radius: w * 0.025)
                .blendMode(.plusLighter)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 上窄下宽的梯形
struct ShaftShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - r.width * 0.16, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.16, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 金字上扫过的一道高光：每隔几秒从左到右扫一次。位移动画交给 Core Animation，不按帧重算
struct SpecularSweep: ViewModifier {
    var period: Double = 4.2
    var sweep: Double = 1.1
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if VisualFX.enabled && !reduceMotion {
            content.overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(18, w * 0.22))
                        .rotationEffect(.degrees(18))
                        .offset(x: moved ? w * 1.15 : -w * 0.45)
                        .frame(width: w, height: geo.size.height, alignment: .leading)
                        .clipped()
                }
                .mask(content)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: sweep).delay(period - sweep).repeatForever(autoreverses: false)) { moved = true }
            }
        } else {
            content
        }
    }
}

extension View {
    /// 金色标题用：每隔几秒扫过一道高光
    func specularSweep(period: Double = 4.2) -> some View { modifier(SpecularSweep(period: period)) }
}
