import AppKit
import Foundation

NSApplication.shared.setActivationPolicy(.prohibited)

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL
  .appendingPathComponent("Resources", isDirectory: true)
let iconURL = resourcesURL.appendingPathComponent("AppIcon.icns", isDirectory: false)

try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

let chunks: [(type: String, pixels: Int)] = [
  ("ic04", 16),
  ("ic11", 32),
  ("ic07", 128),
  ("ic13", 256),
]

let body = try chunks.reduce(into: Data()) { data, chunk in
  let image = drawIcon(size: CGFloat(chunk.pixels))
  guard let png = pngData(from: image) else {
    throw IconGenerationError.pngEncodingFailed(chunk.type)
  }

  data.appendFourCC(chunk.type)
  data.appendUInt32BE(UInt32(png.count + 8))
  data.append(png)
}

var icns = Data()
icns.appendFourCC("icns")
icns.appendUInt32BE(UInt32(body.count + 8))
icns.append(body)
try icns.write(to: iconURL, options: .atomic)

enum IconGenerationError: Error {
  case pngEncodingFailed(String)
}

func drawIcon(size: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  defer { image.unlockFocus() }

  let scale = size / 1024
  func r(_ value: CGFloat) -> CGFloat { value * scale }

  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()

  let tileRect = NSRect(x: r(54), y: r(54), width: r(916), height: r(916))
  let tile = NSBezierPath(roundedRect: tileRect, xRadius: r(210), yRadius: r(210))

  NSGraphicsContext.saveGraphicsState()
  let tileShadow = NSShadow()
  tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
  tileShadow.shadowBlurRadius = r(46)
  tileShadow.shadowOffset = NSSize(width: 0, height: -r(18))
  tileShadow.set()
  NSGradient(colors: [
    NSColor(calibratedRed: 0.055, green: 0.085, blue: 0.125, alpha: 1),
    NSColor(calibratedRed: 0.13, green: 0.205, blue: 0.245, alpha: 1),
    NSColor(calibratedRed: 0.045, green: 0.075, blue: 0.105, alpha: 1),
  ])?.draw(in: tile, angle: 135)
  NSGraphicsContext.restoreGraphicsState()

  drawInnerDepth(tileRect: tileRect, radius: r(210), scale: r)
  drawRingShadow(r: r)
  draw3DQuotaRing(r: r, progress: 0.72)
  drawFloatingSparkline(r: r)
  drawPrompt(x: r(382), y: r(604), scale: r, color: NSColor.white.withAlphaComponent(0.82))

  NSColor.white.withAlphaComponent(0.12).setStroke()
  tile.lineWidth = r(8)
  tile.stroke()

  return image
}

func drawInnerDepth(tileRect: NSRect, radius: CGFloat, scale r: (CGFloat) -> CGFloat) {
  let inset = tileRect.insetBy(dx: r(18), dy: r(18))
  let inner = NSBezierPath(roundedRect: inset, xRadius: radius - r(10), yRadius: radius - r(10))
  NSColor.black.withAlphaComponent(0.10).setStroke()
  inner.lineWidth = r(10)
  inner.stroke()

  let topEdge = NSBezierPath()
  topEdge.move(to: NSPoint(x: inset.minX + r(120), y: inset.maxY - r(64)))
  topEdge.curve(
    to: NSPoint(x: inset.maxX - r(142), y: inset.maxY - r(72)),
    controlPoint1: NSPoint(x: inset.minX + r(300), y: inset.maxY + r(6)),
    controlPoint2: NSPoint(x: inset.maxX - r(300), y: inset.maxY + r(4))
  )
  NSColor.white.withAlphaComponent(0.08).setStroke()
  topEdge.lineWidth = r(18)
  topEdge.lineCapStyle = .round
  topEdge.stroke()
}

func drawRingShadow(r: (CGFloat) -> CGFloat) {
  let shadow = NSBezierPath()
  shadow.appendArc(withCenter: NSPoint(x: r(512), y: r(496)), radius: r(286), startAngle: 0, endAngle: 360, clockwise: false)
  NSColor.black.withAlphaComponent(0.25).setStroke()
  shadow.lineWidth = r(74)
  shadow.lineCapStyle = .round
  shadow.stroke()
}

func draw3DQuotaRing(r: (CGFloat) -> CGFloat, progress: CGFloat) {
  let center = NSPoint(x: r(512), y: r(522))
  let radius = r(282)
  let lineWidth = r(66)

  let base = NSBezierPath()
  base.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
  NSColor.white.withAlphaComponent(0.12).setStroke()
  base.lineWidth = lineWidth
  base.lineCapStyle = .round
  base.stroke()

  let under = NSBezierPath()
  under.appendArc(withCenter: NSPoint(x: center.x, y: center.y - r(8)), radius: radius, startAngle: 118, endAngle: 118 - 302 * progress, clockwise: true)
  NSColor(calibratedRed: 0.15, green: 0.34, blue: 0.27, alpha: 0.72).setStroke()
  under.lineWidth = lineWidth
  under.lineCapStyle = .round
  under.stroke()

  let progressPath = NSBezierPath()
  progressPath.appendArc(withCenter: center, radius: radius, startAngle: 118, endAngle: 118 - 302 * progress, clockwise: true)
  NSColor(calibratedRed: 0.48, green: 0.84, blue: 0.63, alpha: 1).setStroke()
  progressPath.lineWidth = lineWidth
  progressPath.lineCapStyle = .round
  progressPath.stroke()

  let highlight = NSBezierPath()
  highlight.appendArc(withCenter: NSPoint(x: center.x - r(2), y: center.y + r(7)), radius: radius, startAngle: 92, endAngle: -38, clockwise: true)
  NSColor.white.withAlphaComponent(0.22).setStroke()
  highlight.lineWidth = r(16)
  highlight.lineCapStyle = .round
  highlight.stroke()

  let warmCap = NSBezierPath()
  warmCap.appendArc(withCenter: center, radius: radius, startAngle: -95, endAngle: -138, clockwise: true)
  NSColor(calibratedRed: 0.94, green: 0.70, blue: 0.31, alpha: 1).setStroke()
  warmCap.lineWidth = lineWidth
  warmCap.lineCapStyle = .round
  warmCap.stroke()
}

func drawFloatingSparkline(r: (CGFloat) -> CGFloat) {
  let points = [
    NSPoint(x: r(316), y: r(422)),
    NSPoint(x: r(392), y: r(462)),
    NSPoint(x: r(456), y: r(438)),
    NSPoint(x: r(526), y: r(514)),
    NSPoint(x: r(592), y: r(382)),
    NSPoint(x: r(674), y: r(446)),
    NSPoint(x: r(726), y: r(426)),
  ]

  let softShadow = path(points: points.map { NSPoint(x: $0.x, y: $0.y - r(13)) })
  NSColor.black.withAlphaComponent(0.34).setStroke()
  softShadow.lineWidth = r(52)
  softShadow.lineCapStyle = .round
  softShadow.lineJoinStyle = .round
  softShadow.stroke()

  let base = path(points: points)
  NSColor(calibratedRed: 0.18, green: 0.39, blue: 0.30, alpha: 0.78).setStroke()
  base.lineWidth = r(42)
  base.lineCapStyle = .round
  base.lineJoinStyle = .round
  base.stroke()

  let line = path(points: points.map { NSPoint(x: $0.x, y: $0.y + r(3)) })
  NSColor(calibratedRed: 0.55, green: 0.88, blue: 0.68, alpha: 1).setStroke()
  line.lineWidth = r(28)
  line.lineCapStyle = .round
  line.lineJoinStyle = .round
  line.stroke()

  let shine = path(points: points.map { NSPoint(x: $0.x, y: $0.y + r(14)) })
  NSColor.white.withAlphaComponent(0.22).setStroke()
  shine.lineWidth = r(8)
  shine.lineCapStyle = .round
  shine.lineJoinStyle = .round
  shine.stroke()
}

func path(points: [NSPoint]) -> NSBezierPath {
  let path = NSBezierPath()
  guard let first = points.first else { return path }
  path.move(to: first)
  for point in points.dropFirst() {
    path.line(to: point)
  }
  return path
}

func drawPrompt(x: CGFloat, y: CGFloat, scale r: (CGFloat) -> CGFloat, color: NSColor) {
  let shadow = NSBezierPath()
  shadow.move(to: NSPoint(x: x, y: y + r(45) - r(8)))
  shadow.line(to: NSPoint(x: x + r(70), y: y - r(8)))
  shadow.line(to: NSPoint(x: x, y: y - r(45) - r(8)))
  NSColor.black.withAlphaComponent(0.24).setStroke()
  shadow.lineWidth = r(30)
  shadow.lineCapStyle = .round
  shadow.lineJoinStyle = .round
  shadow.stroke()

  color.setStroke()
  let chevron = NSBezierPath()
  chevron.move(to: NSPoint(x: x, y: y + r(45)))
  chevron.line(to: NSPoint(x: x + r(70), y: y))
  chevron.line(to: NSPoint(x: x, y: y - r(45)))
  chevron.lineWidth = r(24)
  chevron.lineCapStyle = .round
  chevron.lineJoinStyle = .round
  chevron.stroke()

  let cursor = NSBezierPath()
  cursor.move(to: NSPoint(x: x + r(116), y: y - r(50)))
  cursor.line(to: NSPoint(x: x + r(238), y: y - r(50)))
  cursor.lineWidth = r(23)
  cursor.lineCapStyle = .round
  cursor.stroke()
}

func pngData(from image: NSImage) -> Data? {
  guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff)
  else {
    return nil
  }
  return bitmap.representation(using: .png, properties: [:])
}

extension Data {
  mutating func appendFourCC(_ value: String) {
    let bytes = Array(value.utf8)
    precondition(bytes.count == 4)
    append(contentsOf: bytes)
  }

  mutating func appendUInt32BE(_ value: UInt32) {
    append(UInt8((value >> 24) & 0xff))
    append(UInt8((value >> 16) & 0xff))
    append(UInt8((value >> 8) & 0xff))
    append(UInt8(value & 0xff))
  }
}
