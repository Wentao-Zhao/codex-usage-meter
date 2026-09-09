import AppKit
import CodexMeterCore

final class TokenCompositionBarView: NSView {
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

    guard bounds.width > 0, bounds.height > 0 else {
      return
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let outline = NSBezierPath(
      roundedRect: bounds,
      xRadius: bounds.height / 2,
      yRadius: bounds.height / 2
    )
    outline.addClip()
    NSColor.separatorColor.withAlphaComponent(0.28).setFill()
    outline.fill()

    let composition = UsageChartGeometry.composition(usage: usage)
    let segments = [
      (composition.uncachedInput, Self.uncachedInputColor),
      (composition.cachedInput, Self.cachedInputColor),
      (composition.output, Self.outputColor),
    ]
    var x = bounds.minX
    for (fraction, color) in segments where fraction > 0 {
      let width = min(bounds.width * CGFloat(fraction), bounds.maxX - x)
      color.withAlphaComponent(0.85).setFill()
      NSBezierPath(rect: NSRect(x: x, y: bounds.minY, width: width, height: bounds.height)).fill()
      x += width
    }
  }
}
