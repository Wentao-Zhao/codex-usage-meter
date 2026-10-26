import AppKit
import CodexMeterCore
import UserNotifications

@MainActor
protocol ResetNotificationDelivering: AnyObject {
  func requestPermission() async -> Bool
  func deliver(_ event: ResetAnnouncement) async throws -> Bool
}

@MainActor
final class ResetNotificationSender: NSObject, ResetNotificationDelivering, UNUserNotificationCenterDelegate {
  override init() {
    super.init()
    center?.delegate = self
  }

  private var center: UNUserNotificationCenter? {
    Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
  }

  func requestPermission() async -> Bool {
    guard let center else { return false }
    center.delegate = self
    let settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
      return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
    }
    return settings.authorizationStatus == .authorized
  }

  func deliver(_ event: ResetAnnouncement) async throws -> Bool {
    guard let center else { return false }
    center.delegate = self
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized, !Task.isCancelled else { return false }
    let content = UNMutableNotificationContent()
    content.title = "Codex \(event.kindLabel)"
    let scope = event.scope.isEmpty ? "原帖未明确适用范围" : event.scope
    content.body = "\(event.displayTime)（北京时间）\n\(scope)\nAIHOT 非官方整理，以个人额度为准"
    content.sound = .default
    if let url = event.sourceURL { content.userInfo["sourceURL"] = url.absoluteString }
    try await center.add(UNNotificationRequest(identifier: "codex-reset-announcement", content: content, trigger: nil))
    return true
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let value = response.notification.request.content.userInfo["sourceURL"] as? String,
      let url = ResetAnnouncement.safeSourceURL(value) {
      Task { @MainActor in NSWorkspace.shared.open(url) }
    }
    completionHandler()
  }
}
