import AppKit
import CodexMeterCore

final class SparklineView: NSView {
  var values: [Int64] = [] {
    didSet { needsDisplay = true }
  }

  var lineColor: NSColor = .systemGreen {
    didSet { needsDisplay = true }
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: 150, height: 36)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let drawingRect = bounds.insetBy(dx: 2, dy: 4)
    let baseline = NSBezierPath()
    baseline.move(to: NSPoint(x: drawingRect.minX, y: drawingRect.minY + 1))
    baseline.line(to: NSPoint(x: drawingRect.maxX, y: drawingRect.minY + 1))
    baseline.lineWidth = 1
    baseline.setLineDash([2, 4], count: 2, phase: 0)
    NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
    baseline.stroke()

    let points = SparklineGeometry.points(values: values)
    guard !points.isEmpty else {
      return
    }

    let path = NSBezierPath()
    for (index, point) in points.enumerated() {
      let mapped = NSPoint(
        x: drawingRect.minX + (drawingRect.width * point.x),
        y: drawingRect.minY + (drawingRect.height * point.y)
      )
      if index == 0 {
        path.move(to: mapped)
      } else {
        path.line(to: mapped)
      }
    }
    path.lineWidth = 2
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    lineColor.setStroke()
    path.stroke()
  }
}
