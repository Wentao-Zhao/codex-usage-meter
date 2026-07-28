import AppKit
import CodexMeterCore

final class TokenCompositionRingView: NSView {
  static let uncachedInputColor = NSColor(
    calibratedRed: 0.83,
    green: 0.60,
    blue: 0.62,
    alpha: 1
  )
  static let cachedInputColor = NSColor(
    calibratedRed: 0.76,
    green: 0.65,
    blue: 0.82,
    alpha: 1
  )
  static let outputColor = NSColor(
    calibratedRed: 0.84,
    green: 0.72,
    blue: 0.49,
    alpha: 1
  )

  var usage: TokenUsage = .zero {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let lineWidth: CGFloat = 8
    let radius = max(0, min(bounds.width, bounds.height) / 2 - lineWidth / 2 - 1)
    guard radius > 0 else {
      return
    }
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    drawArc(
      center: center,
      radius: radius,
      startAngle: 0,
      fraction: 1,
      color: NSColor.separatorColor.withAlphaComponent(0.28),
      lineWidth: lineWidth
    )

    let composition = UsageChartGeometry.composition(usage: usage)
    let segments = [
      (composition.uncachedInput, Self.uncachedInputColor),
      (composition.cachedInput, Self.cachedInputColor),
      (composition.output, Self.outputColor),
    ]
    var startAngle = 90.0
    for (fraction, color) in segments where fraction > 0 {
      drawArc(
        center: center,
        radius: radius,
        startAngle: startAngle,
        fraction: fraction,
        color: color,
        lineWidth: lineWidth
      )
      startAngle -= fraction * 360
    }
  }

  private func drawArc(
    center: NSPoint,
    radius: CGFloat,
    startAngle: Double,
    fraction: Double,
    color: NSColor,
    lineWidth: CGFloat
  ) {
    let path = NSBezierPath()
    path.appendArc(
      withCenter: center,
      radius: radius,
      startAngle: CGFloat(startAngle),
      endAngle: CGFloat(startAngle - fraction * 360),
      clockwise: true
    )
    path.lineWidth = lineWidth
    path.lineCapStyle = .butt
    color.setStroke()
    path.stroke()
  }
}
