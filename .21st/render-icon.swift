import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Exports Nanashi's native orbital N mark. The concentric composition adapts
// 21st Orbit Rotation (18010); geometry matches StrandDesign/BrandMark.swift.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let design = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".21st/design.json"))) as! [String: Any]
let dark = (design["palette"] as! [String: Any])["dark"] as! [String: String]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// Read the exact native geometry instead of keeping a second set of drawing constants.
let markSource = try String(contentsOf: root.appendingPathComponent("Packages/StrandDesign/Sources/StrandDesign/BrandMark.swift"), encoding: .utf8)
func identity(_ key: String) -> CGFloat {
    let regex = try! NSRegularExpression(pattern: "public static let " + key + ": CGFloat = ([0-9.]+)")
    let range = NSRange(markSource.startIndex..., in: markSource)
    guard let match = regex.firstMatch(in: markSource, range: range),
          let valueRange = Range(match.range(at: 1), in: markSource),
          let value = Double(markSource[valueRange]) else { fatalError("Missing identity token: " + key) }
    return CGFloat(value)
}
func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let n = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(colorSpace: space, components: [CGFloat((n >> 16) & 255) / 255,
                     CGFloat((n >> 8) & 255) / 255, CGFloat(n & 255) / 255, alpha])!
}
func glyph(size: CGFloat, background: String) -> CGImage {
    let c = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.setFillColor(color(background)); c.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let center = CGPoint(x: size/2, y: size/2)
    let light = CGGradient(colorsSpace: space, colors: [color(dark["accent"]!, alpha: identity("lightOpacity")), color(dark["accent"]!, alpha: 0)] as CFArray, locations: [0,1])!
    c.drawRadialGradient(light, startCenter: CGPoint(x: size, y: size), startRadius: 0,
                         endCenter: CGPoint(x: size, y: size), endRadius: size * identity("lightRadius"), options: [])
    c.saveGState()
    c.setLineWidth(size * identity("orbitStroke")); c.setLineCap(.round)
    c.addArc(center: center, radius: size * (0.5 - identity("orbitInset")),
             startAngle: .pi/2 - 2 * .pi * identity("arcStart"),
             endAngle: .pi/2 - 2 * .pi * identity("arcEnd"), clockwise: true)
    c.replacePathWithStrokedPath(); c.clip()
    let rim = CGGradient(colorsSpace: space, colors: [color(dark["text"]!), color(dark["accent"]!, alpha: 0.66)] as CFArray, locations: [0,1])!
    c.drawLinearGradient(rim, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
    let left = size * (0.5 - identity("letterWidth") / 2)
    let right = size * (0.5 + identity("letterWidth") / 2)
    let bottom = size * (0.5 - identity("letterHeight") / 2)
    let top = size * (0.5 + identity("letterHeight") / 2)
    c.setStrokeColor(color(dark["text"]!)); c.setLineWidth(size * identity("letterStroke"))
    c.setLineJoin(.round); c.setLineCap(.round)
    c.move(to: CGPoint(x: left, y: bottom))
    c.addLine(to: CGPoint(x: left, y: top))
    c.addLine(to: CGPoint(x: right, y: bottom))
    c.addLine(to: CGPoint(x: right, y: top)); c.strokePath()
    return c.makeImage()!
}
for target in CommandLine.arguments.dropFirst() {
    let size: CGFloat = target.contains("@2x") ? 120 : target.contains("@3x") ? 180 : 1024
    let alternate = target.contains("AppIcon-Navy") || target.contains("NavyTitanium")
    let image = glyph(size: size, background: dark[alternate ? "canvas" : "surface"]!)
    let writer = CGImageDestinationCreateWithURL(root.appendingPathComponent(target) as CFURL,
                        UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil); precondition(CGImageDestinationFinalize(writer))
    print("Exported \(target)")
}
