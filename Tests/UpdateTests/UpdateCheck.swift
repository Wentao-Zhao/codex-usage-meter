import AppKit
import Sparkle

@MainActor
final class CheckDelegate: NSObject, SPUUpdaterDelegate {
  var completed = false
  var failures = 0
  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    print("PASS: remote signed appcast reports no newer version")
    completed = true
  }
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    print("PASS: remote appcast offers version \(item.displayVersionString)")
    completed = true
  }
  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    let reported = error as NSError
    // Sparkle also ends a successful no-update check via SUNoUpdateError.
    if completed && reported.domain == SUSparkleErrorDomain,
       reported.code == SUError.noUpdateError.rawValue { return }
    fputs("FAIL: feed check: \(error.localizedDescription)\n", stderr)
    failures += 1
    completed = true
  }
}

@main
@MainActor
enum UpdateCheck {
  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    guard CommandLine.arguments.count >= 2, let bundle = Bundle(path: CommandLine.arguments[1]) else { exit(2) }
    let wrapper = AppUpdater(bundle: bundle)
    guard wrapper.updater == nil else { fatalError("Updater must remain lazy before menu use") }
    let menu = wrapper.makeMenuItem()
    guard menu.title == "检查更新…", menu.target === wrapper, wrapper.updater == nil else { exit(1) }
    do {
      try wrapper.start()
      let updater = wrapper.updater!
      guard !updater.automaticallyChecksForUpdates, !updater.automaticallyDownloadsUpdates,
            !updater.sendsSystemProfile, updater.canCheckForUpdates else { exit(1) }
      print("PASS: \(bundle.bundleIdentifier!) Sparkle loads, starts, and remains manual-only")
      // An unpackaged executable must refuse a missing update key/feed before opening a dialog.
      do {
        try AppUpdater(bundle: .main).start()
        fputs("FAIL: missing update configuration was accepted\n", stderr)
        exit(1)
      } catch { print("PASS: missing update configuration is rejected") }
      if CommandLine.arguments.contains("--network") {
        let delegate = CheckDelegate()
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let checker = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: delegate)
        checker.automaticallyChecksForUpdates = false
        checker.automaticallyDownloadsUpdates = false
        checker.sendsSystemProfile = false
        try checker.start()
        checker.checkForUpdateInformation()
        let deadline = Date(timeIntervalSinceNow: 40)
        while !delegate.completed && Date() < deadline {
          RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        guard delegate.completed && delegate.failures == 0 else { exit(1) }
      }
    } catch {
      fputs("FAIL: updater start: \(error)\n", stderr)
      exit(1)
    }
  }
}
