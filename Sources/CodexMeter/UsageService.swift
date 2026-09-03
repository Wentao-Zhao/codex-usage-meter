import CodexMeterCore
import Foundation

final class UsageService {
  var onSnapshot: ((UsageSnapshot) -> Void)?

  private let indexer: UsageLogIndexer
  private let accountClient: CodexAppServerClient
  private let sessionRoots: [URL]
  private let queue = DispatchQueue(
    label: "com.local.CodexMeter.usage",
    qos: .utility
  )
  private lazy var monitor = UsageDirectoryMonitor(paths: sessionRoots) { [weak self] in
    self?.refreshUsageLogs()
  }
  private var reconcileTimer: DispatchSourceTimer?
  private var countdownTimer: DispatchSourceTimer?
  private var isRunning = false
  private var latestAccountRateLimits: ResolvedRateLimits?
  private var latestAccountRateLimitsAt: Date?

  init(
    configuration: UsageLogIndexer.Configuration,
    accountClient: CodexAppServerClient = CodexAppServerClient()
  ) {
    self.indexer = UsageLogIndexer(configuration: configuration)
    self.accountClient = accountClient
    self.sessionRoots = configuration.sessionRoots
  }

  static func makeDefault() -> UsageService {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let roots = [
      home.appendingPathComponent(".codex/sessions", isDirectory: true),
      home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
    ]
    let supportRoot = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
    let configuration = UsageLogIndexer.Configuration(
      sessionRoots: roots,
      indexURL: supportRoot
        .appendingPathComponent("CodexMeter", isDirectory: true)
        .appendingPathComponent("usage-index.json"),
      timeZoneIdentifier: TimeZone.current.identifier
    )
    return UsageService(configuration: configuration)
  }

  func start() {
    guard !isRunning else {
      return
    }
    isRunning = true

    publish(indexer.cachedSnapshot(isIndexing: true))
    configureMonitor()
    configureTimers()
    refreshNow()
  }

  func stop() {
    guard isRunning else {
      return
    }
    isRunning = false
    monitor.stop()
    reconcileTimer?.cancel()
    countdownTimer?.cancel()
    reconcileTimer = nil
    countdownTimer = nil
  }

  func refreshNow() {
    queue.async { [weak self] in
      guard let self, self.isRunning else {
        return
      }
      self.refreshUsageLogsOnQueue()
      self.refreshAccountRateLimitsOnQueue()
    }
  }

  private func refreshUsageLogs() {
    queue.async { [weak self] in
      guard let self, self.isRunning else {
        return
      }
      self.refreshUsageLogsOnQueue()
    }
  }

  private func refreshUsageLogsOnQueue() {
    do {
      publish(applyingAccountRateLimits(to: try indexer.refresh(isIndexing: false)))
    } catch {
      publish(applyingAccountRateLimits(to: indexer.cachedSnapshot(isIndexing: false)))
    }
  }

  private func refreshAccountRateLimitsOnQueue() {
    do {
      latestAccountRateLimits = try accountClient.fetchRateLimits()
      latestAccountRateLimitsAt = Date()
    } catch {
      // Keep the last successful account snapshot and continue using JSONL as fallback.
    }
    publish(applyingAccountRateLimits(to: indexer.cachedSnapshot(isIndexing: false)))
  }

  private func applyingAccountRateLimits(to snapshot: UsageSnapshot) -> UsageSnapshot {
    guard let latestAccountRateLimits, let latestAccountRateLimitsAt else {
      return snapshot
    }
    return snapshot.replacingRateLimits(
      latestAccountRateLimits,
      updatedAt: latestAccountRateLimitsAt
    )
  }

  private func configureMonitor() {
    monitor.start()
  }

  private func configureTimers() {
    let reconcile = DispatchSource.makeTimerSource(queue: queue)
    reconcile.schedule(deadline: .now() + 300, repeating: 300, leeway: .seconds(15))
    reconcile.setEventHandler { [weak self] in
      guard let self, self.isRunning else {
        return
      }
      self.refreshUsageLogsOnQueue()
      self.refreshAccountRateLimitsOnQueue()
    }
    reconcile.resume()
    reconcileTimer = reconcile

    let countdown = DispatchSource.makeTimerSource(queue: queue)
    countdown.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
    countdown.setEventHandler { [weak self] in
      guard let self, self.isRunning else {
        return
      }
      self.publish(
        self.applyingAccountRateLimits(
          to: self.indexer.cachedSnapshot(isIndexing: false)
        )
      )
    }
    countdown.resume()
    countdownTimer = countdown
  }

  private func publish(_ snapshot: UsageSnapshot) {
    DispatchQueue.main.async { [weak self] in
      self?.onSnapshot?(snapshot)
    }
  }
}
