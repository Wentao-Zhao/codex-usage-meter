import AppKit
import CodexMeterCore

@MainActor
final class ResetAnnouncementService {
  var onUpdate: ((ResetNoticeState) -> Void)?
  private(set) var notice: ResetNoticeState
  var notificationsEnabled: Bool { defaults.bool(forKey: "resetAnnouncements.notificationsEnabled") }

  private struct Cache: Codable {
    let feed: ResetAnnouncementFeed
    let fetchedAt: Date
    let etag: String?
  }

  private let session: URLSession
  private let defaults: UserDefaults
  private let notifier: ResetNotificationDelivering
  private let now: () -> Date
  private var cache: Cache?
  private var lastAttempt: Date?
  private var retryAt: Date?
  private var failed = false
  private var validated = false
  private var stopped = false
  private var activeRequest: UUID?
  private var permissionRequest = UUID()
  private var notifying = Set<String>()
  private var refreshTask: Task<Void, Never>?
  private var refreshTaskID: UUID?
  private var wakeObserver: NSObjectProtocol?
  private let cacheKey = "resetAnnouncements.cache.v1"
  private let deliveryKey = "resetAnnouncements.delivered.v1"

  init(
    session: URLSession? = nil, defaults: UserDefaults = .standard,
    notifier: ResetNotificationDelivering? = nil, now: @escaping () -> Date = Date.init
  ) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = 25
    self.session = session ?? URLSession(configuration: configuration)
    self.defaults = defaults
    self.notifier = notifier ?? ResetNotificationSender()
    self.now = now
    if let data = defaults.data(forKey: cacheKey), data.count <= 512_000 {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      cache = try? decoder.decode(Cache.self, from: data)
    }
    lastAttempt = cache?.fetchedAt
    notice = ResetNoticeState.make(feed: cache?.feed, fetchedAt: cache?.fetchedAt, now: now())
  }

  func start() {
    stopped = false
    if wakeObserver == nil {
      wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    tick()
  }

  func stop() {
    stopped = true
    activeRequest = nil
    permissionRequest = UUID()
    refreshTask?.cancel()
    refreshTask = nil
    refreshTaskID = nil
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    wakeObserver = nil
  }

  // Called by the existing usage countdown: no second polling timer is needed.
  func tick() {
    guard !stopped else { return }
    publish()
    if ResetAnnouncementSchedule.isDue(now: now(), lastAttempt: lastAttempt) { requestRefresh() }
  }

  func requestRefresh() {
    guard refreshTask == nil, !stopped else { return }
    let id = UUID()
    refreshTaskID = id
    refreshTask = Task { [weak self] in
      guard let self else { return }
      await self.refresh()
      if self.refreshTaskID == id {
        self.refreshTask = nil
        self.refreshTaskID = nil
      }
    }
  }

  func refresh() async {
    guard !stopped, activeRequest == nil, retryAt.map({ now() >= $0 }) ?? true else { return }
    let id = UUID()
    activeRequest = id
    lastAttempt = now()
    publish()
    defer {
      if activeRequest == id {
        activeRequest = nil
        publish()
      }
    }
    do {
      var request = URLRequest(url: URL(string: "https://aihot.news/api/v1/codex-resets")!)
      request.timeoutInterval = 20
      request.cachePolicy = .reloadIgnoringLocalCacheData
      request.setValue("CodexMeter/1.3", forHTTPHeaderField: "User-Agent")
      if let etag = cache?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
      let (data, response) = try await session.data(for: request)
      guard !stopped, !Task.isCancelled, activeRequest == id,
        let http = response as? HTTPURLResponse else { return }
      let feed: ResetAnnouncementFeed
      let etag: String?
      switch http.statusCode {
      case 200:
        feed = try await Task.detached(priority: .utility) { try ResetAnnouncementFeed.decode(data) }.value
        etag = http.value(forHTTPHeaderField: "ETag")
      case 304:
        guard let cached = cache else { throw URLError(.badServerResponse) }
        feed = cached.feed
        etag = cached.etag
      default:
        retryAt = ResetAnnouncementSchedule.retryDate(http.value(forHTTPHeaderField: "Retry-After"), now: now())
        if http.statusCode == 429 && retryAt == nil { retryAt = now().addingTimeInterval(1800) }
        throw URLError(.badServerResponse)
      }
      guard !stopped, !Task.isCancelled, activeRequest == id else { return }
      cache = Cache(feed: feed, fetchedAt: now(), etag: etag)
      failed = false
      validated = true
      retryAt = nil
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      if let data = try? encoder.encode(cache), data.count <= 512_000 { defaults.set(data, forKey: cacheKey) }
      await notifyIfNeeded()
    } catch {
      if !stopped, !Task.isCancelled, activeRequest == id { failed = true }
    }
  }

  func setNotificationsEnabled(_ enabled: Bool) async -> Bool {
    let id = UUID()
    permissionRequest = id
    if !enabled {
      defaults.set(false, forKey: "resetAnnouncements.notificationsEnabled")
      return false
    }
    let allowed = await notifier.requestPermission()
    guard !stopped, permissionRequest == id else { return notificationsEnabled }
    defaults.set(allowed, forKey: "resetAnnouncements.notificationsEnabled")
    if allowed { await notifyIfNeeded() }
    return allowed
  }

  private func notifyIfNeeded() async {
    guard !stopped, notificationsEnabled, validated, !failed, !Task.isCancelled,
      let cache, cache.feed.isFresh(at: now()), now().timeIntervalSince(cache.fetchedAt) < 1800,
      let event = cache.feed.upcoming(at: now()) else { return }
    let key = event.notificationKey
    let delivered = defaults.stringArray(forKey: deliveryKey) ?? []
    guard !delivered.contains(key), notifying.insert(key).inserted else { return }
    defer { notifying.remove(key) }
    do {
      if try await notifier.deliver(event) {
        var keys = defaults.stringArray(forKey: deliveryKey) ?? []
        keys.append(key)
        defaults.set(Array(keys.suffix(200)), forKey: deliveryKey)
      }
    } catch { /* A failed delivery remains eligible on the next successful refresh. */ }
  }

  private func publish() {
    notice = ResetNoticeState.make(
      feed: cache?.feed, fetchedAt: cache?.fetchedAt, now: now(),
      isLoading: activeRequest != nil, failed: failed, retryAt: retryAt
    )
    onUpdate?(notice)
  }
}
