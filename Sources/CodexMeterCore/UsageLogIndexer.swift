import Foundation

public final class UsageLogIndexer {
  public struct Configuration: Sendable {
    public let sessionRoots: [URL]
    public let indexURL: URL
    public let timeZoneIdentifier: String

    public init(
      sessionRoots: [URL],
      indexURL: URL,
      timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
      self.sessionRoots = sessionRoots
      self.indexURL = indexURL
      self.timeZoneIdentifier = timeZoneIdentifier
    }
  }

  private struct LogFile {
    let sessionID: String
    let url: URL
    let size: UInt64
    let identity: String
    let modifiedAt: TimeInterval
    var isCompressed: Bool { url.lastPathComponent.hasSuffix(".jsonl.zst") }
    var signature: String { "\(identity):\(size):\(modifiedAt)" }
  }

  private final class ArchiveJob {
    let file: LogFile
    let reader: ZstandardLogReader
    let scanner = JSONLTokenScanner.Stream()
    var session: SessionUsageIndex

    init(file: LogFile, session: SessionUsageIndex) throws {
      self.file = file
      self.session = session
      reader = try ZstandardLogReader(url: file.url)
    }
  }

  public struct ArchiveSliceResult: Sendable {
    public let decodedBytes: Int
    public let completedSession: Bool
    public let hasMoreWork: Bool
  }

  private let configuration: Configuration
  private var index: UsageIndex
  private var discoveredFiles: [String: LogFile] = [:]
  private var pendingArchives: [LogFile] = []
  private var archiveJob: ArchiveJob?
  private var failedArchives: [String: (signature: String, retryAt: Date)] = [:]
  private var dirty = false
  private var lastPersist = -TimeInterval.infinity

  public var hasPendingArchiveWork: Bool { archiveJob != nil || !pendingArchives.isEmpty }

  private var historyScanProgress: HistoryScanProgress? {
    let archives = discoveredFiles.values.filter(\.isCompressed)
    let completed = archives.filter { index.session(id: $0.sessionID)?.compressedFileSignature == $0.signature }.count
    guard completed < archives.count else { return nil }
    let failed = archives.filter { failedArchives[$0.sessionID]?.signature == $0.signature }.count
    let percent = archiveJob.map { Int(min(99, Double($0.reader.compressedBytesRead) / Double(max(1, $0.file.size)) * 100)) }
    return HistoryScanProgress(completed: completed, total: archives.count, failed: failed, currentFilePercent: percent)
  }

  public init(configuration: Configuration) {
    self.configuration = configuration
    self.index = Self.loadIndex(configuration: configuration)
  }

  public func cachedSnapshot(now: Date = Date(), isIndexing: Bool) -> UsageSnapshot {
    index.snapshot(now: now, isIndexing: isIndexing, historyScanProgress: historyScanProgress)
  }

  public func refresh(now: Date = Date(), isIndexing: Bool) throws -> UsageSnapshot {
    let (discovered, discoveryComplete) = discoverLogFiles()
    discoveredFiles = discovered
    let discoveredIDs = Set(discovered.keys)

    if discoveryComplete {
      for existingID in index.sessions.keys where !discoveredIDs.contains(existingID) {
        index.removeSession(id: existingID)
        dirty = true
      }
    }

    if let job = archiveJob, discovered[job.file.sessionID]?.signature != job.file.signature {
      archiveJob = nil
    }
    failedArchives = failedArchives.filter { discovered[$0.key]?.signature == $0.value.signature }
    pendingArchives = discovered.values.filter { file in
      file.isCompressed && archiveJob?.file.sessionID != file.sessionID
        && index.session(id: file.sessionID)?.compressedFileSignature != file.signature
        && !(failedArchives[file.sessionID].map { $0.retryAt > now } ?? false)
    }.sorted {
      if $0.size == $1.size { return $0.sessionID < $1.sessionID }
      return $0.size < $1.size
    }

    for sessionID in discovered.keys.sorted() {
      guard let file = discovered[sessionID] else {
        continue
      }
      guard !file.isCompressed else { continue }

      do {
        try updateSession(from: file)
      } catch {
        continue
      }
    }

    try checkpoint(force: !hasPendingArchiveWork)
    return cachedSnapshot(now: now, isIndexing: isIndexing)
  }

  /// One bounded work unit. Callers must yield before requesting another slice.
  public func scanArchiveSlice(maxBytes: Int = 1_048_576, maxDuration: TimeInterval = 0.008) throws -> ArchiveSliceResult {
    let byteLimit = min(1_048_576, max(1, maxBytes))
    let deadline = ProcessInfo.processInfo.systemUptime + min(0.008, max(0.001, maxDuration))
    var bytes = 0
    var completed = false
    do {
      if archiveJob == nil, !pendingArchives.isEmpty {
        let file = pendingArchives.removeFirst()
        do {
          archiveJob = try ArchiveJob(file: file, session: newSession(for: file))
        } catch {
          failedArchives[file.sessionID] = (file.signature, Date().addingTimeInterval(300))
          throw error
        }
      }
      if let job = archiveJob {
        repeat {
          guard let data = try job.reader.read(upToCount: min(65_536, byteLimit - bytes)) else { break }
          if data.isEmpty {
            // A complete, unchanged frame replaces old totals atomically.
            if let current = discoveredFiles[job.file.sessionID], current.signature == job.file.signature,
               let actual = describeFile(sessionID: current.sessionID, url: current.url), actual.signature == current.signature {
              job.session.path = current.url.path
              job.session.compressedFileSignature = current.signature
              index.upsert(job.session)
              dirty = true
              failedArchives.removeValue(forKey: current.sessionID)
              completed = true
            }
            archiveJob = nil
            break
          }
          bytes += data.count
          let batch = job.scanner.consume(data)
          if batch.historyWasReset { job.session = newSession(for: job.file) }
          apply(batch, to: &job.session)
        } while bytes < byteLimit && ProcessInfo.processInfo.systemUptime < deadline
      }
    } catch {
      if let job = archiveJob {
        failedArchives[job.file.sessionID] = (job.file.signature, Date().addingTimeInterval(300))
      }
      archiveJob = nil
      // Preserve the last valid contribution, then back off this file.
    }
    try checkpoint(force: !hasPendingArchiveWork)
    return ArchiveSliceResult(decodedBytes: bytes, completedSession: completed, hasMoreWork: hasPendingArchiveWork)
  }

  public func cancelArchiveScan() throws {
    archiveJob = nil
    pendingArchives.removeAll()
    try checkpoint(force: true)
  }

  private func checkpoint(force: Bool) throws {
    guard dirty, force || ProcessInfo.processInfo.systemUptime - lastPersist >= 5 else { return }
    try persistIndex()
    dirty = false
    lastPersist = ProcessInfo.processInfo.systemUptime
  }

  private func updateSession(from file: LogFile) throws {
    var session = index.session(id: file.sessionID) ?? newSession(for: file)
    let wasReplaced = session.fileIdentity != file.identity || session.compressedFileSignature != nil
    let wasTruncated = file.size < session.parsedBytes

    if wasReplaced || wasTruncated {
      session = newSession(for: file)
    } else {
      session.path = file.url.path
      session.fileIdentity = file.identity
    }

    let scanResult = try JSONLTokenScanner.scan(
      fileURL: file.url,
      fromOffset: session.parsedBytes,
      context: session.scanContext
    )

    apply(scanResult, to: &session)
    if session != index.session(id: file.sessionID) {
      index.upsert(session)
      dirty = true
    }
  }

  private func apply(_ scanResult: JSONLTokenScanResult, to session: inout SessionUsageIndex) {
    if session.accumulator.lastUsage == nil,
       let initialUsage = scanResult.initialUsage {
      session.accumulator = SessionUsageAccumulator(lastUsage: initialUsage)
    }

    for event in scanResult.events {
      if let usage = event.usage {
        let delta = session.accumulator.consume(usage: usage)
        session.buckets.add(usage: delta, model: event.model, at: event.timestamp)
      }

      if event.primary != nil || event.secondary != nil {
        if session.latestRateLimit == nil
          || event.timestamp > session.latestRateLimit!.timestamp {
          session.latestRateLimit = event
        }
      }
    }

    session.parsedBytes = scanResult.committedOffset
    session.scanContext = scanResult.context
  }

  private func newSession(for file: LogFile) -> SessionUsageIndex {
    SessionUsageIndex(
      sessionID: file.sessionID,
      path: file.url.path,
      fileIdentity: file.identity,
      parsedBytes: 0,
      accumulator: SessionUsageAccumulator(),
      buckets: UsageBuckets(timeZoneIdentifier: configuration.timeZoneIdentifier),
      latestRateLimit: nil
    )
  }

  private func discoverLogFiles() -> ([String: LogFile], Bool) {
    var result: [String: LogFile] = [:]
    var complete = true

    for root in configuration.sessionRoots {
      guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in complete = false; return true }
      ) else {
        complete = false
        continue
      }

      for case let url as URL in enumerator {
        let compressed = url.lastPathComponent.hasSuffix(".jsonl.zst")
        guard url.pathExtension == "jsonl" || compressed else {
          continue
        }

        let plainURL = compressed ? url.deletingPathExtension() : url
        let sessionID = plainURL.deletingPathExtension().lastPathComponent
        guard let file = describeFile(sessionID: sessionID, url: url) else { complete = false; continue }
        if let previous = result[sessionID], !previous.isCompressed || compressed { continue }
        result[sessionID] = file
      }
    }

    return (result, complete)
  }

  private func describeFile(sessionID: String, url: URL) -> LogFile? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          let size = (attributes[.size] as? NSNumber)?.uint64Value else {
      return nil
    }

    let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0
    let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    return LogFile(
      sessionID: sessionID,
      url: url,
      size: size,
      identity: "\(device):\(inode)",
      modifiedAt: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    )
  }

  private func persistIndex() throws {
    let directory = configuration.indexURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(index)
    try data.write(to: configuration.indexURL, options: .atomic)
  }

  private static func loadIndex(configuration: Configuration) -> UsageIndex {
    guard
      let data = try? Data(contentsOf: configuration.indexURL),
      let loaded = try? JSONDecoder().decode(UsageIndex.self, from: data),
      loaded.version == UsageIndex.currentVersion,
      loaded.timeZoneIdentifier == configuration.timeZoneIdentifier
    else {
      return UsageIndex(timeZoneIdentifier: configuration.timeZoneIdentifier)
    }
    return loaded
  }
}
