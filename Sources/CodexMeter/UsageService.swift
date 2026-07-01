import CodexMeterCore
import Foundation

final class UsageService {
  var onSnapshot: ((UsageSnapshot) -> Void)?

  private let indexer: UsageLogIndexer
  private let sessionRoots: [URL]
  private let queue = DispatchQueue(
    label: "com.local.CodexMeter.usage",
    qos: .utility
  )
  private lazy var monitor = UsageDirectoryMonitor(paths: sessionRoots) { [weak self] in
    self?.refreshNow()
  }
  private var reconcileTimer: DispatchSourceTimer?
  private var countdownTimer: DispatchSourceTimer?
  private var isRunning = false

  init(configuration: UsageLogIndexer.Configuration) {
    self.indexer = UsageLogIndexer(configuration: configuration)
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
      do {
        let snapshot = try self.indexer.refresh(isIndexing: false)
        self.publish(snapshot)
      } catch {
        self.publish(self.indexer.cachedSnapshot(isIndexing: false))
      }
    }
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
      do {
        self.publish(try self.indexer.refresh(isIndexing: false))
      } catch {
        self.publish(self.indexer.cachedSnapshot(isIndexing: false))
      }
    }
    reconcile.resume()
    reconcileTimer = reconcile

    let countdown = DispatchSource.makeTimerSource(queue: queue)
    countdown.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
    countdown.setEventHandler { [weak self] in
      guard let self, self.isRunning else {
        return
      }
      self.publish(self.indexer.cachedSnapshot(isIndexing: false))
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
