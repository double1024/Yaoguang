import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "YaoguangApp/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func strokeCircle(_ center: CGPoint, radius: CGFloat, color: CGColor, width: CGFloat) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

func drawStar(center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int, color: CGColor, rotation: CGFloat = 0) {
    let path = CGMutablePath()
    for index in 0..<(points * 2) {
        let radius = index.isMultiple(of: 2) ? outer : inner
        let angle = rotation + CGFloat(index) * .pi / CGFloat(points)
        let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    context.setFillColor(color)
    context.addPath(path)
    context.fillPath()
}

// Square, full-bleed source; macOS applies the rounded-rectangle mask.
let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgba(0.025, 0.075, 0.17), rgba(0.055, 0.20, 0.34), rgba(0.035, 0.105, 0.23)] as CFArray,
    locations: [0, 0.52, 1]
)!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])

let halo = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgba(0.17, 0.88, 0.92, 0.24), rgba(0.10, 0.54, 0.75, 0.09), rgba(0.10, 0.54, 0.75, 0)] as CFArray,
    locations: [0, 0.42, 1]
)!
context.drawRadialGradient(halo, startCenter: CGPoint(x: 530, y: 540), startRadius: 10, endCenter: CGPoint(x: 530, y: 540), endRadius: 540, options: [])

// Quiet radar rings and a north-oriented sweep establish the local aircraft-tracking theme.
let radarCenter = CGPoint(x: 512, y: 480)
strokeCircle(radarCenter, radius: 152, color: rgba(0.33, 0.91, 0.91, 0.28), width: 3)
strokeCircle(radarCenter, radius: 260, color: rgba(0.33, 0.91, 0.91, 0.20), width: 3)
strokeCircle(radarCenter, radius: 370, color: rgba(0.33, 0.91, 0.91, 0.12), width: 3)
context.setStrokeColor(rgba(0.50, 0.96, 0.94, 0.22))
context.setLineWidth(2)
context.move(to: CGPoint(x: 512, y: 160))
context.addLine(to: CGPoint(x: 512, y: 820))
context.move(to: CGPoint(x: 180, y: 480))
context.addLine(to: CGPoint(x: 844, y: 480))
context.strokePath()

// Sparse signal marks add depth without turning into a map or dashboard.
drawStar(center: CGPoint(x: 240, y: 778), outer: 8, inner: 3, points: 4, color: rgba(0.76, 0.96, 1, 0.85), rotation: .pi / 4)
drawStar(center: CGPoint(x: 790, y: 715), outer: 6, inner: 2.5, points: 4, color: rgba(0.76, 0.96, 1, 0.68), rotation: .pi / 4)
drawStar(center: CGPoint(x: 772, y: 302), outer: 7, inner: 2.5, points: 4, color: rgba(0.76, 0.96, 1, 0.62), rotation: .pi / 4)

// A clean top-down aircraft silhouette stays legible at small Dock sizes.
let plane = CGMutablePath()
plane.move(to: CGPoint(x: 512, y: 820))
plane.addCurve(to: CGPoint(x: 470, y: 626), control1: CGPoint(x: 500, y: 770), control2: CGPoint(x: 478, y: 700))
plane.addLine(to: CGPoint(x: 300, y: 560))
plane.addLine(to: CGPoint(x: 286, y: 524))
plane.addLine(to: CGPoint(x: 471, y: 566))
plane.addLine(to: CGPoint(x: 468, y: 468))
plane.addLine(to: CGPoint(x: 428, y: 422))
plane.addLine(to: CGPoint(x: 428, y: 390))
plane.addLine(to: CGPoint(x: 498, y: 426))
plane.addLine(to: CGPoint(x: 512, y: 310))
plane.addLine(to: CGPoint(x: 526, y: 426))
plane.addLine(to: CGPoint(x: 596, y: 390))
plane.addLine(to: CGPoint(x: 596, y: 422))
plane.addLine(to: CGPoint(x: 556, y: 468))
plane.addLine(to: CGPoint(x: 553, y: 566))
plane.addLine(to: CGPoint(x: 738, y: 524))
plane.addLine(to: CGPoint(x: 724, y: 560))
plane.addLine(to: CGPoint(x: 554, y: 626))
plane.addCurve(to: CGPoint(x: 512, y: 820), control1: CGPoint(x: 546, y: 700), control2: CGPoint(x: 524, y: 770))
plane.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgba(0.01, 0.05, 0.12, 0.6))
context.addPath(plane)
context.setFillColor(rgba(0.82, 0.97, 1))
context.fillPath()
context.restoreGState()

// The project name means a star; this warm four-point beacon is the single accent.
drawStar(center: CGPoint(x: 512, y: 878), outer: 34, inner: 12, points: 4, color: rgba(1.0, 0.79, 0.40), rotation: .pi / 4)

func writePNG(_ image: CGImage, to url: URL) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

let image = context.makeImage()!
let destinationURL = URL(fileURLWithPath: output)
let iconFolder = destinationURL.deletingLastPathComponent()
try FileManager.default.createDirectory(at: iconFolder, withIntermediateDirectories: true)
try writePNG(image, to: iconFolder.appendingPathComponent("icon_1024.png"))

for side in [16, 32, 64, 128, 256, 512] {
    let scaled = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    scaled.interpolationQuality = .high
    scaled.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    try writePNG(scaled.makeImage()!, to: iconFolder.appendingPathComponent("icon_\(side).png"))
}
