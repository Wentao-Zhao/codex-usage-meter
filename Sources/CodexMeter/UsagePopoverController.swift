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
  private let todayCard = ComparisonMetricCardView(
    title: "今日消耗",
    accentColor: StatusDotIcon.color(for: .green),
    style: .line
  )
  private let weekCard = ComparisonMetricCardView(
    title: "本周消耗",
    accentColor: NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.80, alpha: 1),
    style: .bars
  )
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
      total: snapshot.todayTotal,
      currentValues: snapshot.hourly,
      previousValues: snapshot.previousDayHourly,
      comparison: UsageComparison.resolve(
        current: snapshot.todayTotal,
        previous: snapshot.previousDayTotal
      ),
      comparisonPeriod: "昨日",
      currentPeriod: "今日",
      startLabel: "00 时",
      endLabel: "现在"
    )
    weekCard.update(
      total: snapshot.weekTotal,
      currentValues: snapshot.weekly,
      previousValues: snapshot.previousWeekDaily,
      comparison: UsageComparison.resolve(
        current: snapshot.weekTotal,
        previous: snapshot.previousWeekTotal
      ),
      comparisonPeriod: "上周",
      currentPeriod: "本周",
      startLabel: "周一",
      endLabel: "今天"
    )
    totalCard.update(
      total: snapshot.allTimeTotal,
      usage: snapshot.allTimeUsage,
      credits: snapshot.allTimeCredits
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
      rootView.heightAnchor.constraint(equalToConstant: 450),

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
      todayCard.heightAnchor.constraint(equalToConstant: 82),
      weekCard.topAnchor.constraint(equalTo: todayCard.bottomAnchor, constant: 8),
      weekCard.leadingAnchor.constraint(equalTo: todayCard.leadingAnchor),
      weekCard.trailingAnchor.constraint(equalTo: todayCard.trailingAnchor),
      weekCard.heightAnchor.constraint(equalToConstant: 82),
      totalCard.topAnchor.constraint(equalTo: weekCard.bottomAnchor, constant: 8),
      totalCard.leadingAnchor.constraint(equalTo: todayCard.leadingAnchor),
      totalCard.trailingAnchor.constraint(equalTo: todayCard.trailingAnchor),
      totalCard.heightAnchor.constraint(equalToConstant: 110),
      totalCard.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16),
    ])

    let viewController = NSViewController()
    viewController.view = rootView
    viewController.preferredContentSize = NSSize(width: 320, height: 450)
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

private final class SectionLabelView: NSView {
  private let accent = NSView()
  private let label = NSTextField(labelWithString: "")

  var title: String {
    get { label.stringValue }
    set {
      label.stringValue = newValue
      invalidateIntrinsicContentSize()
    }
  }

  override var intrinsicContentSize: NSSize {
    NSSize(
      width: label.intrinsicContentSize.width + 9,
      height: max(11, label.intrinsicContentSize.height)
    )
  }

  init(title: String, accentColor: NSColor) {
    super.init(frame: .zero)

    label.stringValue = title
    label.font = .systemFont(ofSize: 9, weight: .medium)
    label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.78)

    accent.wantsLayer = true
    accent.layer?.cornerRadius = 1.5
    accent.layer?.backgroundColor = accentColor.withAlphaComponent(0.82).cgColor

    [accent, label].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      accent.leadingAnchor.constraint(equalTo: leadingAnchor),
      accent.centerYAnchor.constraint(equalTo: centerYAnchor),
      accent.widthAnchor.constraint(equalToConstant: 3),
      accent.heightAnchor.constraint(equalToConstant: 9),
      label.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 6),
      label.trailingAnchor.constraint(equalTo: trailingAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func setAccentColor(_ color: NSColor) {
    accent.layer?.backgroundColor = color.withAlphaComponent(0.82).cgColor
  }
}

private final class ComparisonBadgeView: NSView {
  private let label = NSTextField(labelWithString: "")

  override var intrinsicContentSize: NSSize {
    NSSize(
      width: label.intrinsicContentSize.width + 12,
      height: label.intrinsicContentSize.height + 4
    )
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.cornerRadius = 8
    label.font = .systemFont(ofSize: 8, weight: .semibold)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(text: String, tint: NSColor) {
    label.stringValue = text
    label.textColor = tint
    layer?.backgroundColor = tint.withAlphaComponent(0.10).cgColor
    invalidateIntrinsicContentSize()
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
  private let titleView = SectionLabelView(
    title: "--",
    accentColor: NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.80, alpha: 1)
  )
  private let percentLabel = NSTextField(labelWithString: "--")
  private let countdownLabel = NSTextField(labelWithString: "暂无额度数据")
  private let progress = ProgressBarView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    percentLabel.font = .systemFont(ofSize: 20, weight: .semibold)
    countdownLabel.font = .systemFont(ofSize: 9)
    countdownLabel.textColor = .secondaryLabelColor
    countdownLabel.lineBreakMode = .byTruncatingTail

    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)

    [titleView, percentLabel, countdownLabel, progress].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview($0)
    }

    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
      contentView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 3),

      percentLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
      titleView.centerYAnchor.constraint(equalTo: percentLabel.centerYAnchor),
      titleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      percentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      titleView.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -8),

      countdownLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 6),
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
    let color = kind == .weekly
      ? NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.80, alpha: 1)
      : StatusDotIcon.color(for: .green)
    titleView.title = kind == .weekly ? "本周剩余" : "5 小时剩余"
    titleView.setAccentColor(color)
    progress.fillColor = color
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

private final class ComparisonMetricCardView: CardView {
  enum Style {
    case line
    case bars
  }

  private let style: Style
  private let accentColor: NSColor
  private let titleView: SectionLabelView
  private let badgeView = ComparisonBadgeView()
  private let totalLabel = NSTextField(labelWithString: "0")
  private let periodLabel = NSTextField(labelWithString: "--")
  private let lineChart = ComparisonLineChartView()
  private let barChart = GroupedBarChartView()
  private let startLabel = NSTextField(labelWithString: "--")
  private let endLabel = NSTextField(labelWithString: "--")

  private var chartView: NSView {
    style == .line ? lineChart : barChart
  }

  init(title: String, accentColor: NSColor, style: Style) {
    self.style = style
    self.accentColor = accentColor
    self.titleView = SectionLabelView(title: title, accentColor: accentColor)
    super.init(frame: .zero)

    totalLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
    periodLabel.font = .systemFont(ofSize: 8)
    periodLabel.textColor = .tertiaryLabelColor
    startLabel.font = .systemFont(ofSize: 8)
    endLabel.font = .systemFont(ofSize: 8)
    startLabel.textColor = .tertiaryLabelColor
    endLabel.textColor = .tertiaryLabelColor
    endLabel.alignment = .right

    lineChart.lineColor = accentColor
    barChart.barColor = accentColor

    [titleView, badgeView, totalLabel, periodLabel, chartView, startLabel, endLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      titleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      titleView.topAnchor.constraint(equalTo: topAnchor, constant: 9),
      badgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      badgeView.centerYAnchor.constraint(equalTo: titleView.centerYAnchor),
      titleView.trailingAnchor.constraint(lessThanOrEqualTo: badgeView.leadingAnchor, constant: -6),

      totalLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      totalLabel.topAnchor.constraint(equalTo: titleView.bottomAnchor, constant: 7),
      periodLabel.leadingAnchor.constraint(equalTo: totalLabel.leadingAnchor),
      periodLabel.topAnchor.constraint(equalTo: totalLabel.bottomAnchor, constant: 2),

      chartView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 104),
      chartView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      chartView.topAnchor.constraint(equalTo: topAnchor, constant: 29),
      chartView.heightAnchor.constraint(equalToConstant: style == .bars ? 32 : 34),
      startLabel.leadingAnchor.constraint(equalTo: chartView.leadingAnchor),
      startLabel.topAnchor.constraint(equalTo: chartView.bottomAnchor, constant: 4),
      endLabel.trailingAnchor.constraint(equalTo: chartView.trailingAnchor),
      endLabel.centerYAnchor.constraint(equalTo: startLabel.centerYAnchor),
      startLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -5),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(
    total: Int64,
    currentValues: [Int64],
    previousValues: [Int64],
    comparison: UsageComparisonState,
    comparisonPeriod: String,
    currentPeriod: String,
    startLabel: String,
    endLabel: String
  ) {
    totalLabel.stringValue = TokenCountFormatter.string(from: total)
    periodLabel.stringValue = style == .line ? "当前累计" : "周一至今"
    self.startLabel.stringValue = startLabel
    self.endLabel.stringValue = endLabel
    badgeView.update(
      text: Self.comparisonText(
        comparison,
        comparisonPeriod: comparisonPeriod,
        currentPeriod: currentPeriod
      ),
      tint: Self.comparisonTint(comparison, accentColor: accentColor)
    )

    lineChart.currentValues = currentValues
    lineChart.previousValues = previousValues
    barChart.currentValues = currentValues
    barChart.previousValues = previousValues
  }

  private static func comparisonText(
    _ comparison: UsageComparisonState,
    comparisonPeriod: String,
    currentPeriod: String
  ) -> String {
    switch comparison {
    case .empty:
      return "暂无消耗"
    case .added:
      return "\(currentPeriod)新增"
    case .unchanged:
      return "与\(comparisonPeriod)持平"
    case .increased(let percent):
      return "↑ \(percent)% 较\(comparisonPeriod)"
    case .decreased(let percent):
      return "↓ \(percent)% 较\(comparisonPeriod)"
    }
  }

  private static func comparisonTint(
    _ comparison: UsageComparisonState,
    accentColor: NSColor
  ) -> NSColor {
    switch comparison {
    case .empty, .unchanged:
      return .secondaryLabelColor
    case .added, .increased:
      return accentColor
    case .decreased:
      return NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.80, alpha: 1)
    }
  }
}

private final class CompositionColumnView: NSView {
  private static let percentFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = 1
    return formatter
  }()

  private let swatch = NSView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let valueLabel = NSTextField(labelWithString: "0")
  private let percentLabel = NSTextField(labelWithString: "0%")

  init(name: String, color: NSColor) {
    super.init(frame: .zero)

    swatch.wantsLayer = true
    swatch.layer?.cornerRadius = 2
    swatch.layer?.backgroundColor = color.cgColor
    nameLabel.stringValue = name
    nameLabel.font = .systemFont(ofSize: 8)
    nameLabel.textColor = .secondaryLabelColor
    valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    valueLabel.lineBreakMode = .byTruncatingTail
    percentLabel.font = .monospacedDigitSystemFont(ofSize: 8, weight: .regular)
    percentLabel.textColor = .tertiaryLabelColor
    percentLabel.alignment = .right
    nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    [swatch, nameLabel, valueLabel, percentLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      swatch.leadingAnchor.constraint(equalTo: leadingAnchor),
      swatch.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
      swatch.widthAnchor.constraint(equalToConstant: 5),
      swatch.heightAnchor.constraint(equalToConstant: 5),
      nameLabel.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 4),
      nameLabel.topAnchor.constraint(equalTo: topAnchor),
      percentLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 4),
      percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      percentLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
      valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      valueLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
      valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(value: Int64, fraction: Double) {
    valueLabel.stringValue = TokenCountFormatter.string(from: value)
    valueLabel.toolTip = value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))) + " Tokens"
    percentLabel.stringValue = fraction > 0 && fraction < 0.01
      ? "<1%"
      : Self.percentFormatter.string(from: NSNumber(value: fraction)) ?? "0%"
  }
}

private final class UsageSummaryCardView: CardView {
  private let titleView = SectionLabelView(
    title: "本机总量",
    accentColor: NSColor(calibratedRed: 0.68, green: 0.57, blue: 0.75, alpha: 1)
  )
  private let totalLabel = NSTextField(labelWithString: "0")
  private let totalCaptionLabel = NSTextField(labelWithString: "Tokens")
  private let creditLabel = NSTextField(labelWithString: "≈ 0 credits")
  private let compositionBar = TokenCompositionBarView()
  private let inputColumn = CompositionColumnView(
    name: "普通输入",
    color: TokenCompositionBarView.uncachedInputColor
  )
  private let cacheColumn = CompositionColumnView(
    name: "缓存输入",
    color: TokenCompositionBarView.cachedInputColor
  )
  private let outputColumn = CompositionColumnView(
    name: "输出",
    color: TokenCompositionBarView.outputColor
  )

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    totalLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
    totalLabel.lineBreakMode = .byTruncatingTail
    totalCaptionLabel.font = .systemFont(ofSize: 8)
    totalCaptionLabel.textColor = .tertiaryLabelColor
    totalCaptionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    creditLabel.font = .monospacedDigitSystemFont(ofSize: 8, weight: .regular)
    creditLabel.textColor = .secondaryLabelColor

    let columns = NSStackView(views: [inputColumn, cacheColumn, outputColumn])
    columns.orientation = .horizontal
    columns.alignment = .height
    columns.distribution = .fillEqually
    columns.spacing = 12

    let divider = makeDivider()
    let columnDividers = [makeDivider(), makeDivider()]

    ([titleView, creditLabel, compositionBar, totalLabel, totalCaptionLabel, columns, divider]
      + columnDividers).forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      titleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      titleView.topAnchor.constraint(equalTo: topAnchor, constant: 9),
      creditLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      creditLabel.centerYAnchor.constraint(equalTo: titleView.centerYAnchor),
      titleView.trailingAnchor.constraint(lessThanOrEqualTo: creditLabel.leadingAnchor, constant: -6),

      totalLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      totalLabel.topAnchor.constraint(equalTo: titleView.bottomAnchor, constant: 7),
      totalCaptionLabel.leadingAnchor.constraint(equalTo: totalLabel.trailingAnchor, constant: 5),
      totalCaptionLabel.firstBaselineAnchor.constraint(equalTo: totalLabel.firstBaselineAnchor),
      totalCaptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: compositionBar.leadingAnchor, constant: -16),
      compositionBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      compositionBar.centerYAnchor.constraint(equalTo: totalLabel.centerYAnchor),
      compositionBar.widthAnchor.constraint(equalToConstant: 114),
      compositionBar.heightAnchor.constraint(equalToConstant: 4),

      divider.topAnchor.constraint(equalTo: totalLabel.bottomAnchor, constant: 10),
      divider.leadingAnchor.constraint(equalTo: totalLabel.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: compositionBar.trailingAnchor),
      divider.heightAnchor.constraint(equalToConstant: 0.5),
      columns.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
      columns.leadingAnchor.constraint(equalTo: divider.leadingAnchor),
      columns.trailingAnchor.constraint(equalTo: divider.trailingAnchor),
      columns.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
    ])

    for (column, separator) in zip([inputColumn, cacheColumn], columnDividers) {
      NSLayoutConstraint.activate([
        separator.leadingAnchor.constraint(equalTo: column.trailingAnchor, constant: 6),
        separator.widthAnchor.constraint(equalToConstant: 0.5),
        separator.topAnchor.constraint(equalTo: columns.topAnchor),
        separator.bottomAnchor.constraint(equalTo: columns.bottomAnchor),
      ])
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(
    total: Int64,
    usage: TokenUsage,
    credits: Double
  ) {
    totalLabel.stringValue = TokenCountFormatter.string(from: total)
    totalLabel.toolTip = total.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))) + " Tokens"
    creditLabel.stringValue = "≈ \(CreditCountFormatter.string(from: credits)) credits"
    let inputTokens = usage.uncachedInputTokens + usage.unclassifiedTokens
    let composition = UsageChartGeometry.composition(usage: usage)
    compositionBar.usage = usage
    inputColumn.update(value: inputTokens, fraction: composition.uncachedInput)
    cacheColumn.update(value: usage.cachedInputTokens, fraction: composition.cachedInput)
    outputColumn.update(value: usage.outputTokens, fraction: composition.output)
  }

  private func makeDivider() -> NSView {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
    return view
  }
}
