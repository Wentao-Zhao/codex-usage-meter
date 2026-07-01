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
  private lazy var statusItemController = StatusItemController(
    onRefresh: { [weak self] in self?.usageService.refreshNow() },
    onQuit: { NSApp.terminate(nil) }
  )

  func start() {
    _ = statusItemController
    usageService.onSnapshot = { [weak self] snapshot in
      self?.statusItemController.update(snapshot: snapshot)
    }
    usageService.start()
  }

  func stop() {
    usageService.stop()
  }
}
