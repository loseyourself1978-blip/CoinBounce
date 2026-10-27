// CoinBounce App 图标生成脚本（原创，纯代码绘制）
// 用法：swift tools/icon/make_icon.swift [输出路径]
// 默认输出：ios/CoinBounce/Assets.xcassets/AppIcon.appiconset/AppIcon.png（1024×1024，无透明通道）
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let S = CGFloat(size)
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ios/CoinBounce/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
// noneSkipLast：不带透明通道
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("context") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }

let gold = rgb(1.00, 0.80, 0.20)
let goldDeep = rgb(0.80, 0.50, 0.05)
let goldLight = rgb(1.00, 0.95, 0.65)
let magenta = rgb(0.88, 0.18, 0.55)
let magentaDeep = rgb(0.40, 0.05, 0.28)
let teal = rgb(0.10, 0.78, 0.72)
let outline = rgb(0.18, 0.08, 0.10)

// CoreGraphics 原点在左下角
func radial(_ colors: [CGColor], center: CGPoint, radius: CGFloat, clipTo path: CGPath? = nil) {
    ctx.saveGState()
    if let path { ctx.addPath(path); ctx.clip() }
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

func star(center: CGPoint, radius: CGFloat, inner: CGFloat = 0.45, points: Int = 5) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<(points * 2) {
        let angle = Double(i) * .pi / Double(points) + .pi / 2
        let r = i.isMultiple(of: 2) ? radius : radius * inner
        let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

// 1. 背景：紫红径向渐变 + 放射光芒
radial([magenta, magentaDeep], center: CGPoint(x: S * 0.5, y: S * 0.58), radius: S * 0.75)
ctx.saveGState()
ctx.setFillColor(rgb(1, 1, 1, 0.07))
for i in 0..<16 where i.isMultiple(of: 2) {
    let a0 = Double(i) * .pi / 8, a1 = a0 + .pi / 8
    let c = CGPoint(x: S * 0.5, y: S * 0.56)
    let p = CGMutablePath()
    p.move(to: c)
    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a0)) * S, y: c.y + CGFloat(sin(a0)) * S))
    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a1)) * S, y: c.y + CGFloat(sin(a1)) * S))
    p.closeSubpath()
    ctx.addPath(p)
}
ctx.fillPath()
ctx.restoreGState()

// 2. 弹跳轨迹：青绿弧线 + 落点小金币
ctx.saveGState()
ctx.setLineCap(.round)
ctx.setStrokeColor(teal)
ctx.setLineWidth(S * 0.035)
for (i, offset) in [CGFloat(0), 0.07].enumerated() {
    ctx.setAlpha(i == 0 ? 0.9 : 0.5)
    ctx.move(to: CGPoint(x: S * (0.12 + offset), y: S * 0.2))
    ctx.addQuadCurve(to: CGPoint(x: S * (0.3 + offset), y: S * 0.2), control: CGPoint(x: S * (0.21 + offset), y: S * 0.42))
    ctx.strokePath()
}
ctx.restoreGState()

func coin(center c: CGPoint, radius r: CGFloat, tilt: CGFloat = 1) {
    // 侧边厚度
    let edge = CGRect(x: c.x - r, y: c.y - r * tilt - r * 0.12, width: r * 2, height: r * 2 * tilt)
    ctx.setFillColor(goldDeep)
    ctx.fillEllipse(in: edge)
    let face = CGRect(x: c.x - r, y: c.y - r * tilt, width: r * 2, height: r * 2 * tilt)
    let facePath = CGPath(ellipseIn: face, transform: nil)
    radial([goldLight, gold, goldDeep], center: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.35 * tilt), radius: r * 1.4, clipTo: facePath)
    // 内圈
    ctx.setStrokeColor(goldDeep)
    ctx.setLineWidth(r * 0.07)
    ctx.strokeEllipse(in: face.insetBy(dx: r * 0.15, dy: r * 0.15 * tilt))
    // 星形压印
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.scaleBy(x: 1, y: tilt)
    let s = star(center: .zero, radius: r * 0.5)
    ctx.addPath(s); ctx.setFillColor(goldLight); ctx.fillPath()
    ctx.addPath(s); ctx.setStrokeColor(goldDeep); ctx.setLineWidth(r * 0.04); ctx.strokePath()
    ctx.restoreGState()
    // 外轮廓与高光
    ctx.setStrokeColor(outline)
    ctx.setLineWidth(r * 0.05)
    ctx.strokeEllipse(in: face)
    ctx.saveGState()
    ctx.addPath(facePath); ctx.clip()
    ctx.setFillColor(rgb(1, 1, 1, 0.35))
    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.75, y: c.y + r * 0.25 * tilt, width: r * 0.7, height: r * 0.4 * tilt))
    ctx.restoreGState()
}

// 3. 小金币在弹跳落点，大金币在中央（略微倾斜，表现弹起）
coin(center: CGPoint(x: S * 0.3, y: S * 0.2), radius: S * 0.07, tilt: 0.55)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.03), blur: S * 0.04, color: rgb(0, 0, 0, 0.45))
ctx.translateBy(x: S * 0.56, y: S * 0.56)
ctx.rotate(by: -0.18)
ctx.translateBy(x: -S * 0.56, y: -S * 0.56)
coin(center: CGPoint(x: S * 0.56, y: S * 0.56), radius: S * 0.3, tilt: 0.92)
ctx.restoreGState()

// 4. 闪光
for (pt, r) in [(CGPoint(x: S * 0.83, y: S * 0.82), S * 0.06), (CGPoint(x: S * 0.22, y: S * 0.78), S * 0.04), (CGPoint(x: S * 0.86, y: S * 0.32), S * 0.035)] {
    ctx.addPath(star(center: pt, radius: r, inner: 0.25, points: 4))
    ctx.setFillColor(goldLight)
    ctx.fillPath()
}

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("image") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("wrote \(output) (\(size)x\(size), no alpha)")
