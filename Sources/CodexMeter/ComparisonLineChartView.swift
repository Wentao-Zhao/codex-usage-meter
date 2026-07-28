import AppKit
import CodexMeterCore

final class ComparisonLineChartView: NSView {
  var currentValues: [Int64] = [] {
    didSet { needsDisplay = true }
  }

  var previousValues: [Int64] = [] {
    didSet { needsDisplay = true }
  }

  var lineColor: NSColor = .systemGreen {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let drawingRect = bounds.insetBy(dx: 2, dy: 3)
    guard drawingRect.width > 0, drawingRect.height > 0 else {
      return
    }

    let geometry = UsageChartGeometry.lines(
      current: currentValues,
      previous: previousValues
    )
    drawBaseline(in: drawingRect)
    drawArea(points: geometry.current, in: drawingRect)
    drawLine(
      points: geometry.previous,
      in: drawingRect,
      color: NSColor.secondaryLabelColor.withAlphaComponent(0.32),
      lineWidth: 1.2,
      dash: [3, 4]
    )
    drawLine(
      points: geometry.current,
      in: drawingRect,
      color: lineColor,
      lineWidth: 2,
      dash: []
    )
    drawEndpoint(points: geometry.current, in: drawingRect)
  }

  private func drawBaseline(in rect: NSRect) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    path.lineWidth = 0.5
    NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
    path.stroke()
  }

  private func drawArea(points: [SparklinePoint], in rect: NSRect) {
    guard points.count > 1 else {
      return
    }
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.minY))
    points.forEach { point in
      path.line(to: map(point, in: rect))
    }
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    path.close()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(
      starting: lineColor.withAlphaComponent(0.22),
      ending: lineColor.withAlphaComponent(0.01)
    )?.draw(in: rect, angle: 90)
    NSGraphicsContext.restoreGraphicsState()
  }

  private func drawLine(
    points: [SparklinePoint],
    in rect: NSRect,
    color: NSColor,
    lineWidth: CGFloat,
    dash: [CGFloat]
  ) {
    guard !points.isEmpty else {
      return
    }
    let path = NSBezierPath()
    for (index, point) in points.enumerated() {
      let mapped = map(point, in: rect)
      index == 0 ? path.move(to: mapped) : path.line(to: mapped)
    }
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    if !dash.isEmpty {
      path.setLineDash(dash, count: dash.count, phase: 0)
    }
    color.setStroke()
    path.stroke()
  }

  private func drawEndpoint(points: [SparklinePoint], in rect: NSRect) {
    guard let last = points.last else {
      return
    }
    let point = map(last, in: rect)
    lineColor.setFill()
    NSBezierPath(
      ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
    ).fill()
  }

  private func map(_ point: SparklinePoint, in rect: NSRect) -> NSPoint {
    NSPoint(
      x: rect.minX + rect.width * point.x,
      y: rect.minY + rect.height * point.y
    )
  }
}
