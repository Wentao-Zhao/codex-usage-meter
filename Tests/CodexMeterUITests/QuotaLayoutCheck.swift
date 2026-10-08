import AppKit
import CodexMeterCore

@main
enum QuotaLayoutCheck {
  @MainActor
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.accessory)
    let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    if let output {
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }
    var checks = 0
    for appearanceName in [NSAppearance.Name.darkAqua, .aqua] {
      for (name, primary, secondary) in [("normal", Optional(13.0), 4.0), ("full", Optional(0.0), 0.0), ("empty", Optional(100.0), 100.0), ("weekly-only", nil, 4.0)] {
        let appearance = NSAppearance(named: appearanceName)!
        var controller: UsagePopoverController!
        appearance.performAsCurrentDrawingAppearance { controller = UsagePopoverController() }
        controller.update(snapshot: fixture(primary: primary, secondary: secondary))
        let root = controller.popover.contentViewController!.view
        root.appearance = appearance
        root.frame = NSRect(x: 0, y: 0, width: 320, height: 450)
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = root
        root.layoutSubtreeIfNeeded()

        let cards = descendants(root).filter { String(describing: type(of: $0)) == "QuotaCardView" && !$0.isHidden }
        guard cards.count == (primary == nil ? 1 : 2) else {
          throw LayoutError.invalid("Unexpected visible quota count")
        }
        for card in cards {
          // NSTextField has horizontal alignment insets; check the quota rows,
          // not the section title's internal alignment rectangle.
          for view in card.subviews.flatMap({ [$0] + $0.subviews }) {
            guard let parent = view.superview else { continue }
            let frame = view.convert(view.bounds, to: parent)
            let horizontalInset: CGFloat = view is NSTextField ? 2.5 : 0.5
            guard parent.bounds.insetBy(dx: -horizontalInset, dy: -0.5).contains(frame) else {
              let text = (view as? NSTextField)?.stringValue ?? String(describing: type(of: view))
              throw LayoutError.invalid("\(appearanceName.rawValue)/\(name): \(text) exceeds parent: \(frame), bounds: \(parent.bounds)")
            }
            if let label = view as? NSTextField {
              guard label.intrinsicContentSize.width <= label.frame.width + 1,
                    label.intrinsicContentSize.height <= label.frame.height + 1 else {
                throw LayoutError.invalid("Clipped label: \(label.stringValue)")
              }
            }
            checks += 1
          }
        }
        if let output {
          let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
          root.cacheDisplay(in: root.bounds, to: bitmap)
          try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(appearanceName.rawValue)-\(name).png"))
        }
        window.close()
      }
    }
    print("PASS: \(checks) quota layout bounds checks (light/dark, 0/87/96/100%, weekly-only)")
  }

  @MainActor
  private static func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }

  private static func fixture(primary: Double?, secondary: Double) -> UsageSnapshot {
    let now = Date()
    let event = TokenUsageEvent(
      timestamp: now, usage: nil, model: nil,
      primary: primary.map { RateLimitWindow(usedPercent: $0, windowMinutes: 300, resetsAt: now.addingTimeInterval(291 * 60)) },
      secondary: RateLimitWindow(usedPercent: secondary, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(7 * 86400))
    )
    let session = SessionUsageIndex(sessionID: "layout", path: "/layout", fileIdentity: "layout", parsedBytes: 0, accumulator: SessionUsageAccumulator(), buckets: UsageBuckets(timeZoneIdentifier: "Asia/Shanghai"), latestRateLimit: event)
    return UsageIndex(timeZoneIdentifier: "Asia/Shanghai", sessions: ["layout": session]).snapshot(now: now, isIndexing: false)
  }

  private enum LayoutError: Error {
    case invalid(String)
  }
}
