import AppKit
import CodexMeterCore

enum StatusDotIcon {
  static func image(for status: UsageStatusColor) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      drawTrafficLight(status: status)
      return true
    }
    image.isTemplate = false
    return image
  }

  private static func drawTrafficLight(status: UsageStatusColor) {
    let metrics = StatusLightLayout.menuBarIconMetrics
    let capsule = NSRect(
      x: CGFloat(metrics.capsuleX),
      y: CGFloat(metrics.capsuleY),
      width: CGFloat(metrics.capsuleWidth),
      height: CGFloat(metrics.capsuleHeight)
    )
    let radius = CGFloat(metrics.capsuleHeight / 2)
    let capsulePath = NSBezierPath(roundedRect: capsule, xRadius: radius, yRadius: radius)
    NSColor.labelColor.withAlphaComponent(0.54).setStroke()
    capsulePath.lineWidth = 1.1
    capsulePath.stroke()

    let activeIndex = StatusLightLayout.activeIndex(for: status)
    let centers = metrics.lampCenterXValues.map {
      NSPoint(x: CGFloat($0), y: CGFloat(metrics.lampCenterY))
    }
    for (index, center) in centers.enumerated() {
      let isActive = activeIndex == index
      let color = isActive ? color(for: status) : inactiveColor
      if isActive {
        drawGlow(center: center, radius: CGFloat(metrics.glowRadius), color: color)
      }
      drawLamp(center: center, radius: CGFloat(metrics.lampRadius), color: color)
    }
  }

  private static func drawLamp(center: NSPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(
      ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
    ).fill()
  }

  private static func drawGlow(center: NSPoint, radius: CGFloat, color: NSColor) {
    color.withAlphaComponent(0.20).setFill()
    NSBezierPath(
      ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
    ).fill()
  }

  static func color(for status: UsageStatusColor) -> NSColor {
    switch status {
    case .green:
      return NSColor(calibratedRed: 0.37, green: 0.72, blue: 0.49, alpha: 1)
    case .yellow:
      return NSColor(calibratedRed: 0.91, green: 0.72, blue: 0.25, alpha: 1)
    case .orange:
      return NSColor(calibratedRed: 0.93, green: 0.46, blue: 0.18, alpha: 1)
    case .red:
      return NSColor(calibratedRed: 0.89, green: 0.25, blue: 0.25, alpha: 1)
    case .unknown:
      return NSColor(calibratedWhite: 0.58, alpha: 1)
    }
  }

  private static var inactiveColor: NSColor {
    NSColor.labelColor.withAlphaComponent(0.30)
  }
}
