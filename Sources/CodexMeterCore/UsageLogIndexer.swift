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
  }

  private let configuration: Configuration
  private var index: UsageIndex

  public init(configuration: Configuration) {
    self.configuration = configuration
    self.index = Self.loadIndex(configuration: configuration)
  }

  public func cachedSnapshot(now: Date = Date(), isIndexing: Bool) -> UsageSnapshot {
    index.snapshot(now: now, isIndexing: isIndexing)
  }

  public func refresh(now: Date = Date(), isIndexing: Bool) throws -> UsageSnapshot {
    let discovered = discoverLogFiles()
    let discoveredIDs = Set(discovered.keys)

    for existingID in index.sessions.keys where !discoveredIDs.contains(existingID) {
      index.removeSession(id: existingID)
    }

    for sessionID in discovered.keys.sorted() {
      guard let file = discovered[sessionID] else {
        continue
      }

      do {
        try updateSession(from: file)
      } catch {
        continue
      }
    }

    try persistIndex()
    return index.snapshot(now: now, isIndexing: isIndexing)
  }

  private func updateSession(from file: LogFile) throws {
    var session = index.session(id: file.sessionID) ?? newSession(for: file)
    let samePath = session.path == file.url.path
    let wasReplaced = samePath && session.fileIdentity != file.identity
    let wasTruncated = file.size < session.parsedBytes

    if wasReplaced || wasTruncated {
      session = newSession(for: file)
    } else {
      session.path = file.url.path
      session.fileIdentity = file.identity
    }

    let scanResult = try JSONLTokenScanner.scan(
      fileURL: file.url,
      fromOffset: session.parsedBytes
    )

    for event in scanResult.events {
      if let totalTokens = event.totalTokens {
        let delta = session.accumulator.consume(totalTokens: totalTokens)
        session.buckets.add(tokens: delta, at: event.timestamp)
      }

      if event.primary != nil || event.secondary != nil {
        if session.latestRateLimit == nil
          || event.timestamp > session.latestRateLimit!.timestamp {
          session.latestRateLimit = event
        }
      }
    }

    session.parsedBytes = scanResult.committedOffset
    index.upsert(session)
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

  private func discoverLogFiles() -> [String: LogFile] {
    var result: [String: LogFile] = [:]

    for root in configuration.sessionRoots {
      guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else {
        continue
      }

      for case let url as URL in enumerator {
        guard url.pathExtension == "jsonl" else {
          continue
        }

        let sessionID = url.deletingPathExtension().lastPathComponent
        guard result[sessionID] == nil,
              let file = describeFile(sessionID: sessionID, url: url) else {
          continue
        }
        result[sessionID] = file
      }
    }

    return result
  }

  private func describeFile(sessionID: String, url: URL) -> LogFile? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = (attributes[.size] as? NSNumber)?.uint64Value else {
      return nil
    }

    let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0
    let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    return LogFile(
      sessionID: sessionID,
      url: url,
      size: size,
      identity: "\(device):\(inode)"
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
