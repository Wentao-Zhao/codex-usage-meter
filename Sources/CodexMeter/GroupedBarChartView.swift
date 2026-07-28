import AppKit
import CodexMeterCore

final class GroupedBarChartView: NSView {
  var currentValues: [Int64] = [] {
    didSet { needsDisplay = true }
  }

  var previousValues: [Int64] = [] {
    didSet { needsDisplay = true }
  }

  var barColor = NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.80, alpha: 1) {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let drawingRect = bounds.insetBy(dx: 2, dy: 2)
    let fractions = UsageChartGeometry.bars(
      current: currentValues,
      previous: previousValues
    )
    guard !fractions.isEmpty, drawingRect.width > 0, drawingRect.height > 0 else {
      return
    }

    drawBaseline(in: drawingRect)
    let groupWidth = drawingRect.width / CGFloat(fractions.count)
    let barWidth = min(7, max(3, groupWidth * 0.24))
    let gap = min(3, max(1.5, groupWidth * 0.08))

    for (index, pair) in fractions.enumerated() {
      let centerX = drawingRect.minX + groupWidth * (CGFloat(index) + 0.5)
      drawBar(
        fraction: pair.previous,
        x: centerX - gap / 2 - barWidth,
        width: barWidth,
        in: drawingRect,
        color: NSColor.secondaryLabelColor.withAlphaComponent(0.24)
      )
      drawBar(
        fraction: pair.current,
        x: centerX + gap / 2,
        width: barWidth,
        in: drawingRect,
        color: barColor
      )
    }
  }

  private func drawBaseline(in rect: NSRect) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    path.lineWidth = 0.5
    NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
    path.stroke()
  }

  private func drawBar(
    fraction: Double,
    x: CGFloat,
    width: CGFloat,
    in rect: NSRect,
    color: NSColor
  ) {
    guard fraction > 0 else {
      return
    }
    let height = max(2, rect.height * CGFloat(fraction))
    let barRect = NSRect(x: x, y: rect.minY, width: width, height: height)
    color.setFill()
    NSBezierPath(
      roundedRect: barRect,
      xRadius: min(2.5, width / 2),
      yRadius: min(2.5, width / 2)
    ).fill()
  }
}
