import AppKit
import CodexMeterCore

@MainActor
@main
enum CodexMeterMain {
  private static let appDelegate = AppDelegate()

  static func main() {
    let application = NSApplication.shared
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)
    application.run()
  }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
  private var controller: CodexMeterApplicationController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller = CodexMeterApplicationController()
    controller?.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller?.stop()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

@MainActor
private final class CodexMeterApplicationController {
  private let usageService = UsageService.makeDefault()
  private let resetService = ResetAnnouncementService()
  private var changingNotifications = false
  private lazy var statusItemController = StatusItemController(
    onRefresh: { [weak self] in
      self?.usageService.refreshNow()
      self?.resetService.requestRefresh()
    },
    onQuit: { NSApp.terminate(nil) }
  )

  func start() {
    _ = statusItemController
    usageService.onSnapshot = { [weak self] snapshot in
      self?.statusItemController.update(snapshot: snapshot)
    }
    statusItemController.notificationsEnabled = { [weak self] in self?.resetService.notificationsEnabled ?? false }
    statusItemController.onToggleNotifications = { [weak self] in self?.toggleResetNotifications() }
    resetService.onUpdate = { [weak self] notice in self?.statusItemController.update(resetNotice: notice) }
    usageService.onMinuteTick = { [weak self] in self?.resetService.tick() }
    usageService.start()
    resetService.start()
  }

  func stop() {
    usageService.stop()
    resetService.stop()
  }

  private func toggleResetNotifications() {
    guard !changingNotifications else { return }
    changingNotifications = true
    let desired = !resetService.notificationsEnabled
    Task { [weak self] in
      guard let self else { return }
      defer { self.changingNotifications = false }
      let enabled = await self.resetService.setNotificationsEnabled(desired)
      if desired && !enabled {
        let alert = NSAlert()
        alert.messageText = "未开启重置动态通知"
        alert.informativeText = "请在系统设置 → 通知 → CodexMeter 中允许通知，再重新开启。动态页脚仍可正常使用。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
      }
    }
  }
}
