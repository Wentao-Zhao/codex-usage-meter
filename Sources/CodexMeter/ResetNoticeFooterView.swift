import AppKit
import CodexMeterCore

final class ResetNoticeFooterView: NSButton {
  private let symbol = NSImageView()
  private let label = NSTextField(labelWithString: "重置动态")
  private let valueLabel = NSTextField(labelWithString: "正在检查预告…")
  private let detailLabel = NSTextField(labelWithString: "AIHOT 非官方整理 · 每 30 分钟检查")
  private let chevron = NSImageView()
  private var sourceURL = URL(string: "https://aihot.news/codex-reset")!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    title = ""
    isBordered = false
    setButtonType(.momentaryChange)
    target = self
    action = #selector(openSource)
    symbol.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    [symbol, chevron].forEach { $0.contentTintColor = .secondaryLabelColor; $0.imageScaling = .scaleProportionallyDown }
    label.font = .systemFont(ofSize: 8)
    label.textColor = .secondaryLabelColor
    valueLabel.font = .systemFont(ofSize: 10, weight: .medium)
    valueLabel.textColor = .secondaryLabelColor
    valueLabel.alignment = .right
    valueLabel.lineBreakMode = .byTruncatingTail
    valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    detailLabel.font = .systemFont(ofSize: 8)
    detailLabel.textColor = .tertiaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingTail
    [label, valueLabel, detailLabel].forEach { $0.maximumNumberOfLines = 1; $0.cell?.wraps = false }
    [symbol, label, valueLabel, chevron, detailLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    NSLayoutConstraint.activate([
      symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
      symbol.centerYAnchor.constraint(equalTo: valueLabel.centerYAnchor),
      symbol.widthAnchor.constraint(equalToConstant: 9),
      symbol.heightAnchor.constraint(equalToConstant: 9),
      label.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 5),
      label.centerYAnchor.constraint(equalTo: valueLabel.centerYAnchor),
      valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
      valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
      valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -5),
      chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
      chevron.centerYAnchor.constraint(equalTo: valueLabel.centerYAnchor),
      chevron.widthAnchor.constraint(equalToConstant: 6),
      chevron.heightAnchor.constraint(equalToConstant: 8),
      detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      detailLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 3),
      detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
    ])
    setAccessibilityLabel("重置动态")
  }

  required init?(coder: NSCoder) { nil }

  func update(_ notice: ResetNoticeState) {
    valueLabel.stringValue = notice.value
    detailLabel.stringValue = notice.detail
    sourceURL = notice.sourceURL
    toolTip = notice.tooltip
    setAccessibilityValue(notice.tooltip)
  }

  @objc private func openSource() { NSWorkspace.shared.open(sourceURL) }
}
