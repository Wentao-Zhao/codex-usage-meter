import AppKit
import Sparkle

/// Starts lazily on the first explicit menu action; it never polls in the background.
@MainActor
final class AppUpdater: NSObject, NSMenuItemValidation {
  static let shared = AppUpdater()

  private let bundle: Bundle
  private var userDriver: SPUStandardUserDriver?
  private(set) var updater: SPUUpdater?

  init(bundle: Bundle = .main) {
    self.bundle = bundle
    super.init()
  }

  func makeMenuItem() -> NSMenuItem {
    let item = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
    item.target = self
    return item
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    updater?.canCheckForUpdates ?? true
  }

  func start() throws {
    guard updater == nil else { return }
    guard let rawFeed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
          let feed = URL(string: rawFeed), feed.scheme == "https", feed.host == "github.com",
          let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
          let keyData = Data(base64Encoded: key), keyData.count == 32 else {
      throw NSError(domain: "AppUpdater", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "更新配置不完整，请从 GitHub 下载最新安装包。",
      ])
    }
    let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
    let candidate = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
    // Enforce the product's manual-only policy even if an old Sparkle preference exists.
    candidate.automaticallyChecksForUpdates = false
    candidate.automaticallyDownloadsUpdates = false
    candidate.sendsSystemProfile = false
    try candidate.start()
    userDriver = driver
    updater = candidate
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    do {
      try start()
      updater?.checkForUpdates()
    } catch {
      let alert = NSAlert()
      alert.messageText = "无法检查更新"
      alert.informativeText = error.localizedDescription
      alert.addButton(withTitle: "好")
      alert.runModal()
    }
  }
}
