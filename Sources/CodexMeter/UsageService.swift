import CodexMeterCore
import Foundation

final class UsageService {
  var onSnapshot: ((UsageSnapshot) -> Void)?
  var onMinuteTick: (() -> Void)?

  private let indexer: UsageLogIndexer
  private let accountClient: CodexAppServerClient
  private let sessionRoots: [URL]
  private let queue = DispatchQueue(
    label: "com.local.CodexMeter.usage",
    qos: .background
  )
  private lazy var monitor = UsageDirectoryMonitor(paths: sessionRoots) { [weak self] in
    self?.refreshUsageLogs()
  }
  private var reconcileTimer: DispatchSourceTimer?
  private var countdownTimer: DispatchSourceTimer?
  private var archiveContinuation: DispatchWorkItem?
  private var lastArchivePublish = -TimeInterval.infinity
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
    queue.async { [weak self] in
      self?.archiveContinuation?.cancel()
      self?.archiveContinuation = nil
      try? self?.indexer.cancelArchiveScan()
    }
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
      scheduleArchiveSlice()
    } catch {
      publish(applyingAccountRateLimits(to: indexer.cachedSnapshot(isIndexing: false)))
    }
  }

  private func scheduleArchiveSlice() {
    guard isRunning, archiveContinuation == nil, indexer.hasPendingArchiveWork else { return }
    let process = ProcessInfo.processInfo
    let thermalPause = process.thermalState == .serious || process.thermalState == .critical
    let delay: TimeInterval = thermalPause ? 30 : (process.isLowPowerModeEnabled ? 1 : 0.2)
    let work = DispatchWorkItem(qos: .background) { [weak self] in
      guard let self else { return }
      self.archiveContinuation = nil
      guard self.isRunning else { return }
      let thermal = ProcessInfo.processInfo.thermalState
      if thermal != .serious && thermal != .critical {
        do {
          _ = try self.indexer.scanArchiveSlice()
          let uptime = ProcessInfo.processInfo.systemUptime
          if !self.indexer.hasPendingArchiveWork || uptime - self.lastArchivePublish >= 1 {
            self.publish(self.applyingAccountRateLimits(to: self.indexer.cachedSnapshot(isIndexing: false)))
            self.lastArchivePublish = uptime
          }
        } catch {
          // Retain valid data; a later normal reconciliation can retry persistence.
        }
      }
      self.scheduleArchiveSlice()
    }
    archiveContinuation = work
    queue.asyncAfter(deadline: .now() + delay, execute: work)
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
      DispatchQueue.main.async { [weak self] in self?.onMinuteTick?() }
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
