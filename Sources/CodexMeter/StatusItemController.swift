import AppKit
import CodexMeterCore

@MainActor
final class StatusItemController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let popoverController = UsagePopoverController()
  private let onRefresh: () -> Void
  private let onQuit: () -> Void
  private var localEventMonitor: Any?
  private var globalEventMonitor: Any?

  init(onRefresh: @escaping () -> Void, onQuit: @escaping () -> Void) {
    self.onRefresh = onRefresh
    self.onQuit = onQuit
    super.init()
    configure()
  }

  func update(snapshot: UsageSnapshot) {
    statusItem.button?.image = StatusDotIcon.image(for: snapshot.statusColor)
    statusItem.button?.toolTip = tooltip(for: snapshot)
    popoverController.update(snapshot: snapshot)
  }

  private func configure() {
    guard let button = statusItem.button else {
      return
    }
    button.image = StatusDotIcon.image(for: .unknown)
    button.imagePosition = .imageOnly
    button.target = self
    button.action = #selector(handleStatusItem(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    popoverController.onClose = { [weak self] in self?.stopOutsideClickMonitoring() }
  }

  @objc private func handleStatusItem(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu(relativeTo: sender)
      return
    }

    if popoverController.isShown {
      popoverController.close()
    } else {
      popoverController.show(relativeTo: sender)
      startOutsideClickMonitoring()
    }
  }

  private func showContextMenu(relativeTo sender: NSStatusBarButton) {
    popoverController.close()

    let menu = NSMenu()
    let refreshItem = NSMenuItem(
      title: "立即刷新",
      action: #selector(refreshNow),
      keyEquivalent: ""
    )
    refreshItem.target = self
    menu.addItem(refreshItem)

    let launchItem = NSMenuItem(
      title: "开机自启",
      action: #selector(toggleLaunchAtLogin),
      keyEquivalent: ""
    )
    launchItem.target = self
    launchItem.state = LaunchAtLoginController.isEnabled ? .on : .off
    menu.addItem(launchItem)

    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "退出 CodexMeter",
      action: #selector(quit),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
  }

  private func startOutsideClickMonitoring() {
    stopOutsideClickMonitoring()

    localEventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      guard let self else {
        return event
      }
      if self.shouldKeepPopoverOpen(for: event) {
        return event
      }
      self.popoverController.close()
      return event
    }

    globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      DispatchQueue.main.async {
        self?.popoverController.close()
      }
    }
  }

  private func stopOutsideClickMonitoring() {
    if let localEventMonitor {
      NSEvent.removeMonitor(localEventMonitor)
      self.localEventMonitor = nil
    }
    if let globalEventMonitor {
      NSEvent.removeMonitor(globalEventMonitor)
      self.globalEventMonitor = nil
    }
  }

  private func shouldKeepPopoverOpen(for event: NSEvent) -> Bool {
    if let popoverWindow = popoverController.popover.contentViewController?.view.window,
       event.window === popoverWindow {
      return true
    }

    guard let button = statusItem.button, event.window === button.window else {
      return false
    }
    let location = button.convert(event.locationInWindow, from: nil)
    return button.bounds.contains(location)
  }

  @objc private func refreshNow() {
    onRefresh()
  }

  @objc private func toggleLaunchAtLogin() {
    let desiredState = !LaunchAtLoginController.isEnabled
    do {
      try LaunchAtLoginController.setEnabled(desiredState)
    } catch {
      let alert = NSAlert()
      alert.messageText = "无法修改开机自启"
      alert.informativeText = error.localizedDescription
      alert.alertStyle = .warning
      alert.runModal()
    }
  }

  @objc private func quit() {
    onQuit()
  }

  private func tooltip(for snapshot: UsageSnapshot) -> String {
    if snapshot.isIndexing {
      return "CodexMeter：正在建立索引"
    }
    guard let primary = snapshot.primary else {
      return "CodexMeter：暂无额度数据"
    }
    let remaining = Int(RateLimitPolicy.remainingPercent(for: primary).rounded())
    return "Codex 五小时剩余 \(remaining)%"
  }
}
