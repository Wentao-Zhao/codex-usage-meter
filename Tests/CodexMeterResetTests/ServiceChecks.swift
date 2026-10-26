import CodexMeterCore
import Foundation

private final class FeedProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var storedResponse = (200, [String: String](), Data())
  private static var recordedRequests: [URLRequest] = []
  private static var held: FeedProtocol?
  private static var shouldHold = false
  static var response: (Int, [String: String], Data) {
    get { lock.withLock { storedResponse } }
    set { lock.withLock { storedResponse = newValue } }
  }
  static var requests: [URLRequest] { lock.withLock { recordedRequests } }
  static var holdResponse: Bool {
    get { lock.withLock { shouldHold } }
    set { lock.withLock { shouldHold = newValue } }
  }
  static var hasHeldRequest: Bool { lock.withLock { held != nil } }
  static func releaseResponse() {
    let pending = lock.withLock { let value = held; held = nil; return value }
    pending?.respond()
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let hold = Self.lock.withLock {
      Self.recordedRequests.append(request)
      if Self.shouldHold { Self.held = self }
      return Self.shouldHold
    }
    if !hold { respond() }
  }
  private func respond() {
    let (code, headers, data) = Self.response
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@MainActor
private final class NotificationRecorder: ResetNotificationDelivering {
  var permission = true
  var deliverySucceeds = true
  var keys: [String] = []
  func requestPermission() async -> Bool { permission }
  func deliver(_ event: ResetAnnouncement) async throws -> Bool {
    if !deliverySucceeds { throw URLError(.unknown) }
    keys.append(event.notificationKey)
    return true
  }
}

@main
enum ResetServiceChecks {
  @MainActor
  static func main() async throws {
    var checks = 0
    func check(_ condition: Bool, _ message: String) {
      checks += 1
      if !condition { print("FAIL: \(message)"); exit(1) }
    }
    let suite = "CodexMeter.ResetTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FeedProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let notifier = NotificationRecorder()
    var now = ISO8601DateFormatter().date(from: "2026-10-26T08:00:00Z")!
    func body(scope: String = "付费用户", checkedAt: String = "2026-10-26T07:59:00Z") -> Data {
      Data("""
      {"schemaVersion":1,"checkedAt":"\(checkedAt)","events":[{"id":"test-reset","type":"direct_reset","status":"announced","scope":"\(scope)","presentation":{"timeInferred":false},"schedule":{"from":"2026-10-27T17:00:00Z","through":"2026-10-27T18:00:00Z","label":"北京时间预计 10月28日 02:00 前"},"posts":[{"url":"https://x.com/thsottiaux/status/123"}]}]}
      """.utf8)
    }
    let service = ResetAnnouncementService(session: session, defaults: defaults, notifier: notifier, now: { now })
    check(!service.notificationsEnabled, "notifications opt in by default")
    FeedProtocol.response = (200, ["ETag": "test-etag"], body())
    await service.refresh()
    check(service.notice.value == "10月28日 02:00 前", "valid response updates footer")
    check(notifier.keys.isEmpty, "disabled notifications never deliver")
    check(FeedProtocol.requests.last?.httpMethod == "GET", "feed is read-only GET")
    check(FeedProtocol.requests.last?.httpBody == nil, "no personal usage sent in request body")
    let accepted = await service.setNotificationsEnabled(true)
    check(accepted && notifier.keys.count == 1, "opt in sends current validated announcement")
    FeedProtocol.response = (304, [:], Data())
    await service.refresh()
    check(FeedProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "test-etag", "conditional request reuses ETag")
    check(notifier.keys.count == 1, "304 does not duplicate notification")
    let restored = ResetAnnouncementService(session: session, defaults: defaults, notifier: notifier, now: { now })
    check(restored.notice.value == service.notice.value, "compact cache restored across restart")
    check(notifier.keys.count == 1, "cached data alone never notifies")
    await restored.refresh()
    check(notifier.keys.count == 1, "delivered keys survive restart")
    FeedProtocol.response = (200, [:], body(scope: "Pro 用户"))
    await service.refresh()
    check(notifier.keys.count == 2, "changed scope notifies again")
    await service.refresh()
    check(notifier.keys.count == 2, "unchanged event stays deduplicated")
    let beforeConcurrent = FeedProtocol.requests.count
    async let firstRefresh: Void = service.refresh()
    async let secondRefresh: Void = service.refresh()
    _ = await (firstRefresh, secondRefresh)
    check(FeedProtocol.requests.count == beforeConcurrent + 1, "concurrent refreshes share a single request")
    FeedProtocol.response = (500, [:], Data())
    await service.refresh()
    check(service.notice.detail.contains("缓存"), "network failure preserves marked cache")
    check(notifier.keys.count == 2, "network failure does not notify cached event")
    FeedProtocol.response = (429, ["Retry-After": "120"], Data())
    await service.refresh()
    let requestCount = FeedProtocol.requests.count
    await service.refresh()
    check(FeedProtocol.requests.count == requestCount, "retry-after cannot be bypassed manually")
    check(service.notice.detail.contains("限流"), "rate limit visible in footer")
    now = now.addingTimeInterval(121)
    FeedProtocol.response = (200, [:], body(scope: "其他用户"))
    notifier.deliverySucceeds = false
    await service.refresh()
    check(notifier.keys.count == 2, "failed notification not marked delivered")
    notifier.deliverySucceeds = true
    await service.refresh()
    check(notifier.keys.count == 3, "failed delivery can retry")
    _ = await service.setNotificationsEnabled(false)
    notifier.permission = false
    let denied = await service.setNotificationsEnabled(true)
    check(!denied && !service.notificationsEnabled, "permission denial keeps preference off")
    notifier.permission = true
    _ = await service.setNotificationsEnabled(true)
    now = now.addingTimeInterval(3600)
    FeedProtocol.response = (200, [:], body(scope: "过期数据"))
    await service.refresh()
    check(notifier.keys.count == 3, "stale upstream checkedAt suppresses notification")
    FeedProtocol.response = (200, [:], Data("malformed".utf8))
    await service.refresh()
    check(service.notice.detail.contains("待更新"), "bad payload preserves stale state")
    let cancelling = ResetAnnouncementService(session: session, defaults: defaults, notifier: notifier, now: { now })
    let previousValue = cancelling.notice.value
    FeedProtocol.holdResponse = true
    FeedProtocol.response = (200, [:], body(scope: "取消后不可发送", checkedAt: "2026-10-26T09:02:00Z"))
    let pendingRequest = Task { await cancelling.refresh() }
    let deadline = Date().addingTimeInterval(3)
    while !FeedProtocol.hasHeldRequest && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
    check(FeedProtocol.hasHeldRequest, "request paused to test stop during flight")
    cancelling.stop()
    FeedProtocol.releaseResponse()
    await pendingRequest.value
    FeedProtocol.holdResponse = false
    check(cancelling.notice.value == previousValue && notifier.keys.count == 3, "late response after stop cannot change UI or notify")
    service.stop()
    let beforeStopRefresh = FeedProtocol.requests.count
    await service.refresh()
    check(FeedProtocol.requests.count == beforeStopRefresh, "stopped service cannot request or notify")
    restored.stop()
    print("PASS: \(checks) reset service checks; no real network or system notifications")
    if CommandLine.arguments.contains("--live") {
      let liveSuite = "CodexMeter.ResetLiveCheck.\(UUID().uuidString)"
      let liveDefaults = UserDefaults(suiteName: liveSuite)!
      defer { liveDefaults.removePersistentDomain(forName: liveSuite) }
      let live = ResetAnnouncementService(defaults: liveDefaults, notifier: NotificationRecorder())
      await live.refresh()
      check(live.notice.value != "暂时无法获取", "live public feed can be decoded")
      print("Live feed: \(live.notice.value) · \(live.notice.detail)")
      live.stop()
    }
  }
}
