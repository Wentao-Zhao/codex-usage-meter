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
        root.frame = NSRect(origin: .zero, size: controller.popover.contentViewController!.preferredContentSize)
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = root
        root.layoutSubtreeIfNeeded()

        guard root.bounds.size == NSSize(width: 320, height: 492),
          let footer = descendants(root).first(where: { String(describing: type(of: $0)) == "ResetNoticeFooterView" }),
          let total = descendants(root).first(where: { String(describing: type(of: $0)) == "UsageSummaryCardView" }),
          total.bounds.height == 110, footer.bounds.height == 32 else {
          throw LayoutError.invalid("Missing borderless footer or changed metric sizes")
        }
        checks += 1

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
        for (stateName, notice) in try noticeFixtures() {
          controller.update(resetNotice: notice)
          root.layoutSubtreeIfNeeded()
          for view in footer.subviews {
            guard footer.bounds.insetBy(dx: -2.5, dy: -0.5).contains(view.frame) else {
              throw LayoutError.invalid("Footer child out of bounds: \(stateName), \(type(of: view)), \(view.frame), alignment: \(view.alignmentRect(forFrame: view.frame)), parent: \(footer.bounds)")
            }
            checks += 1
          }
          let labels = footer.subviews.compactMap { $0 as? NSTextField }
          for (index, label) in labels.enumerated() {
            for other in labels.dropFirst(index + 1) where label.frame.intersects(other.frame) {
              throw LayoutError.invalid("Footer overlap: \(stateName), \(label.stringValue) / \(other.stringValue)")
            }
          }
          if let output, name == "normal" {
            let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(appearanceName.rawValue)-footer-\(stateName).png"))
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
    print("PASS: \(checks) native quota/footer checks (light/dark, long text, offline, weekly-only)")
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

  private static func noticeFixtures() throws -> [(String, ResetNoticeState)] {
    let now = ISO8601DateFormatter().date(from: "2026-10-26T08:00:00Z")!
    func feed(label: String) throws -> ResetAnnouncementFeed {
      try ResetAnnouncementFeed.decode(JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1, "checkedAt": "2026-10-26T07:59:00Z",
        "events": [["id": "ui", "type": "direct_reset", "status": "announced", "presentation": ["timeInferred": false],
                    "schedule": ["from": "2026-10-27T17:00:00Z", "through": "2026-10-27T18:00:00Z", "label": label]]],
      ]))
    }
    let normal = try feed(label: "北京时间预计 10月28日 02:00 前")
    let long = try feed(label: "北京时间预计 10月28日 02:00 至 10月29日 08:00 左右，部分用户分批生效")
    return [
      ("upcoming", .make(feed: normal, fetchedAt: now, now: now)),
      ("long", .make(feed: long, fetchedAt: now, now: now)),
      ("offline", .make(feed: normal, fetchedAt: now, now: now, failed: true)),
      ("unavailable", .make(feed: nil, fetchedAt: nil, now: now, failed: true)),
    ]
  }

  private enum LayoutError: Error {
    case invalid(String)
  }
}
