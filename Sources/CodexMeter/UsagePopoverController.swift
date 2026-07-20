import AppKit
import CodexMeterCore

final class UsagePopoverController: NSObject, NSPopoverDelegate {
  let popover = NSPopover()
  var onClose: (() -> Void)?

  private let rootView = NSVisualEffectView()
  private let updatedLabel = NSTextField(labelWithString: "正在读取")
  private let primaryCard = QuotaCardView()
  private let secondaryCard = QuotaCardView()
  private lazy var quotaStack = NSStackView(views: [primaryCard, secondaryCard])
  private let todayCard = TrendCardView()
  private let weekCard = TrendCardView()
  private let totalCard = UsageSummaryCardView()

  override init() {
    super.init()
    configure()
  }

  var isShown: Bool {
    popover.isShown
  }

  func show(relativeTo button: NSStatusBarButton) {
    guard !popover.isShown else {
      return
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  func close() {
    popover.performClose(nil)
  }

  func popoverDidClose(_ notification: Notification) {
    onClose?()
  }

  func update(snapshot: UsageSnapshot) {
    let now = snapshot.generatedAt
    primaryCard.isHidden = snapshot.fiveHourLimit == nil
    primaryCard.update(window: snapshot.fiveHourLimit, now: now, kind: .fiveHour)
    secondaryCard.update(window: snapshot.weeklyLimit, now: now, kind: .weekly)

    todayCard.update(
      title: "今日消耗",
      total: snapshot.todayTotal,
      values: snapshot.hourly,
      startLabel: "00 时",
      endLabel: "现在",
      color: StatusDotIcon.color(for: .green)
    )
    weekCard.update(
      title: "本周消耗",
      total: snapshot.weekTotal,
      values: snapshot.weekly,
      startLabel: "周一",
      endLabel: "今天",
      color: NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.80, alpha: 1)
    )
    totalCard.update(
      title: "本机总量",
      total: snapshot.allTimeTotal,
      usage: snapshot.allTimeUsage,
      credits: snapshot.allTimeCredits,
      values: snapshot.monthly,
      startLabel: Self.monthStartLabel(snapshot.monthKeys.first),
      endLabel: "本月",
      color: NSColor(calibratedRed: 0.68, green: 0.57, blue: 0.75, alpha: 1)
    )

    updatedLabel.stringValue = Self.updateText(for: snapshot, now: now)
  }

  private func configure() {
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self

    rootView.material = .popover
    rootView.blendingMode = .behindWindow
    rootView.state = .active
    rootView.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: "Codex 用量")
    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    updatedLabel.font = .systemFont(ofSize: 10)
    updatedLabel.textColor = .secondaryLabelColor
    updatedLabel.alignment = .right

    quotaStack.orientation = .horizontal
    quotaStack.distribution = .fillEqually
    quotaStack.spacing = 8
    quotaStack.detachesHiddenViews = true
    primaryCard.isHidden = true

    [titleLabel, updatedLabel, quotaStack, todayCard, weekCard, totalCard].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      rootView.addSubview($0)
    }

    NSLayoutConstraint.activate([
      rootView.widthAnchor.constraint(equalToConstant: 320),
      rootView.heightAnchor.constraint(equalToConstant: 382),

      titleLabel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 16),
      titleLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
      updatedLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      updatedLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: updatedLabel.leadingAnchor, constant: -8),

      quotaStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 13),
      quotaStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
      quotaStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
      quotaStack.heightAnchor.constraint(equalToConstant: 88),

      todayCard.topAnchor.constraint(equalTo: quotaStack.bottomAnchor, constant: 10),
      todayCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
      todayCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
      todayCard.heightAnchor.constraint(equalToConstant: 62),
      weekCard.topAnchor.constraint(equalTo: todayCard.bottomAnchor, constant: 8),
      weekCard.leadingAnchor.constraint(equalTo: todayCard.leadingAnchor),
      weekCard.trailingAnchor.constraint(equalTo: todayCard.trailingAnchor),
      weekCard.heightAnchor.constraint(equalToConstant: 62),
      totalCard.topAnchor.constraint(equalTo: weekCard.bottomAnchor, constant: 8),
      totalCard.leadingAnchor.constraint(equalTo: todayCard.leadingAnchor),
      totalCard.trailingAnchor.constraint(equalTo: todayCard.trailingAnchor),
      totalCard.heightAnchor.constraint(equalToConstant: 82),
      totalCard.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16),
    ])

    let viewController = NSViewController()
    viewController.view = rootView
    viewController.preferredContentSize = NSSize(width: 320, height: 382)
    popover.contentViewController = viewController
  }

  private static func updateText(for snapshot: UsageSnapshot, now: Date) -> String {
    if snapshot.isIndexing {
      return "正在建立索引"
    }
    guard let updatedAt = snapshot.latestRateLimitAt else {
      return snapshot.hasUsage ? "暂无额度数据" : "暂无本机记录"
    }
    let minutes = max(0, Int(now.timeIntervalSince(updatedAt) / 60))
    if minutes < 1 {
      return "刚刚更新"
    }
    if minutes < 60 {
      return "\(minutes) 分钟前更新"
    }
    return "额度数据待更新"
  }

  private static func monthStartLabel(_ key: String?) -> String {
    guard let key, let month = key.split(separator: "-").last else {
      return "首月"
    }
    return "\(month) 月"
  }
}

private class CardView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 11
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.58).cgColor
    layer?.borderWidth = 0.5
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
  }

  required init?(coder: NSCoder) {
    nil
  }
}

private final class ProgressBarView: NSView {
  var fraction: Double = 0 {
    didSet { needsDisplay = true }
  }
  var fillColor: NSColor = .systemGreen {
    didSet { needsDisplay = true }
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: 100, height: 4)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let track = bounds
    NSColor.separatorColor.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()

    let clamped = min(1, max(0, fraction))
    guard clamped > 0 else {
      return
    }
    let fillRect = NSRect(x: track.minX, y: track.minY, width: track.width * clamped, height: track.height)
    fillColor.setFill()
    NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()
  }
}

private final class QuotaCardView: CardView {
  private let contentView = NSView()
  private let titleLabel = NSTextField(labelWithString: "--")
  private let percentLabel = NSTextField(labelWithString: "--")
  private let countdownLabel = NSTextField(labelWithString: "暂无额度数据")
  private let progress = ProgressBarView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    titleLabel.font = .systemFont(ofSize: 10)
    titleLabel.textColor = .secondaryLabelColor
    percentLabel.font = .systemFont(ofSize: 20, weight: .semibold)
    countdownLabel.font = .systemFont(ofSize: 9)
    countdownLabel.textColor = .secondaryLabelColor
    countdownLabel.lineBreakMode = .byTruncatingTail

    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)

    [titleLabel, percentLabel, countdownLabel, progress].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview($0)
    }

    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
      contentView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 3),

      titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      percentLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
      percentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -8),

      countdownLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      countdownLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      countdownLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

      progress.topAnchor.constraint(equalTo: countdownLabel.bottomAnchor, constant: 9),
      progress.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      progress.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      progress.heightAnchor.constraint(equalToConstant: 4),
      progress.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(window: RateLimitWindow?, now: Date, kind: RateLimitKind) {
    titleLabel.stringValue = kind == .weekly ? "本周剩余" : "5 小时剩余"
    progress.fillColor = kind == .weekly
      ? NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.80, alpha: 1)
      : StatusDotIcon.color(for: .green)
    guard let window else {
      percentLabel.stringValue = "--"
      countdownLabel.stringValue = "暂无额度数据"
      progress.fraction = 0
      return
    }

    let remaining = RateLimitPolicy.remainingPercent(for: window)
    percentLabel.stringValue = "\(Int(remaining.rounded()))%"
    progress.fraction = remaining / 100

    if RateLimitPolicy.isStale(window, now: now) {
      countdownLabel.stringValue = "等待 Codex 更新"
    } else if kind == .weekly {
      countdownLabel.stringValue = "\(RateLimitPolicy.daysUntilReset(window, now: now)) 天后刷新"
    } else {
      countdownLabel.stringValue = "\(RateLimitPolicy.minutesUntilReset(window, now: now)) 分钟后刷新"
    }
  }
}

private final class TrendCardView: CardView {
  private let titleLabel = NSTextField(labelWithString: "--")
  private let totalLabel = NSTextField(labelWithString: "0")
  private let sparkline = SparklineView()
  private let startLabel = NSTextField(labelWithString: "--")
  private let endLabel = NSTextField(labelWithString: "--")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    titleLabel.font = .systemFont(ofSize: 9)
    titleLabel.textColor = .secondaryLabelColor
    totalLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    startLabel.font = .systemFont(ofSize: 8)
    endLabel.font = .systemFont(ofSize: 8)
    startLabel.textColor = .tertiaryLabelColor
    endLabel.textColor = .tertiaryLabelColor
    endLabel.alignment = .right

    let metrics = NSStackView(views: [titleLabel, totalLabel])
    metrics.orientation = .vertical
    metrics.alignment = .leading
    metrics.spacing = 2
    metrics.translatesAutoresizingMaskIntoConstraints = false

    let axis = NSStackView(views: [startLabel, endLabel])
    axis.orientation = .horizontal
    axis.distribution = .fill
    axis.translatesAutoresizingMaskIntoConstraints = false

    sparkline.translatesAutoresizingMaskIntoConstraints = false
    addSubview(metrics)
    addSubview(sparkline)
    addSubview(axis)

    NSLayoutConstraint.activate([
      metrics.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      metrics.centerYAnchor.constraint(equalTo: centerYAnchor),
      metrics.widthAnchor.constraint(equalToConstant: 96),
      sparkline.leadingAnchor.constraint(equalTo: metrics.trailingAnchor, constant: 4),
      sparkline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      sparkline.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      sparkline.heightAnchor.constraint(equalToConstant: 38),
      axis.leadingAnchor.constraint(equalTo: sparkline.leadingAnchor),
      axis.trailingAnchor.constraint(equalTo: sparkline.trailingAnchor),
      axis.topAnchor.constraint(equalTo: sparkline.bottomAnchor, constant: -2),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(
    title: String,
    total: Int64,
    values: [Int64],
    startLabel: String,
    endLabel: String,
    color: NSColor
  ) {
    titleLabel.stringValue = title
    totalLabel.stringValue = TokenCountFormatter.string(from: total)
    self.startLabel.stringValue = startLabel
    self.endLabel.stringValue = endLabel
    sparkline.values = values
    sparkline.lineColor = color
  }
}

private final class UsageSummaryCardView: CardView {
  private let titleLabel = NSTextField(labelWithString: "--")
  private let totalLabel = NSTextField(labelWithString: "0")
  private let creditLabel = NSTextField(labelWithString: "等效 0 credits")
  private let breakdownLabel = NSTextField(labelWithString: "普通输入 0 · 缓存 0 · 输出 0")
  private let sparkline = SparklineView()
  private let startLabel = NSTextField(labelWithString: "--")
  private let endLabel = NSTextField(labelWithString: "--")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    titleLabel.font = .systemFont(ofSize: 9)
    titleLabel.textColor = .secondaryLabelColor
    totalLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    creditLabel.font = .monospacedDigitSystemFont(ofSize: 8, weight: .medium)
    creditLabel.textColor = .secondaryLabelColor
    breakdownLabel.font = .systemFont(ofSize: 8)
    breakdownLabel.textColor = .secondaryLabelColor
    breakdownLabel.lineBreakMode = .byTruncatingTail
    startLabel.font = .systemFont(ofSize: 8)
    endLabel.font = .systemFont(ofSize: 8)
    startLabel.textColor = .tertiaryLabelColor
    endLabel.textColor = .tertiaryLabelColor
    endLabel.alignment = .right

    let metrics = NSStackView(views: [titleLabel, totalLabel, creditLabel])
    metrics.orientation = .vertical
    metrics.alignment = .leading
    metrics.spacing = 1
    metrics.translatesAutoresizingMaskIntoConstraints = false

    let axis = NSStackView(views: [startLabel, endLabel])
    axis.orientation = .horizontal
    axis.distribution = .fill
    axis.translatesAutoresizingMaskIntoConstraints = false

    sparkline.translatesAutoresizingMaskIntoConstraints = false
    breakdownLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(metrics)
    addSubview(sparkline)
    addSubview(axis)
    addSubview(breakdownLabel)

    NSLayoutConstraint.activate([
      metrics.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      metrics.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      metrics.widthAnchor.constraint(equalToConstant: 96),
      sparkline.leadingAnchor.constraint(equalTo: metrics.trailingAnchor, constant: 4),
      sparkline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      sparkline.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      sparkline.heightAnchor.constraint(equalToConstant: 38),
      axis.leadingAnchor.constraint(equalTo: sparkline.leadingAnchor),
      axis.trailingAnchor.constraint(equalTo: sparkline.trailingAnchor),
      axis.topAnchor.constraint(equalTo: sparkline.bottomAnchor, constant: -2),
      breakdownLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      breakdownLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      breakdownLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(
    title: String,
    total: Int64,
    usage: TokenUsage,
    credits: Double,
    values: [Int64],
    startLabel: String,
    endLabel: String,
    color: NSColor
  ) {
    titleLabel.stringValue = title
    totalLabel.stringValue = TokenCountFormatter.string(from: total)
    creditLabel.stringValue = "等效 \(CreditCountFormatter.string(from: credits)) credits"
    let inputTokens = usage.uncachedInputTokens + usage.unclassifiedTokens
    breakdownLabel.stringValue = [
      "普通输入 \(TokenCountFormatter.string(from: inputTokens))",
      "缓存 \(TokenCountFormatter.string(from: usage.cachedInputTokens))",
      "输出 \(TokenCountFormatter.string(from: usage.outputTokens))",
    ].joined(separator: " · ")
    self.startLabel.stringValue = startLabel
    self.endLabel.stringValue = endLabel
    sparkline.values = values
    sparkline.lineColor = color
  }
}
