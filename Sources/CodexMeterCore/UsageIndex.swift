import Foundation

public struct SessionUsageIndex: Codable, Equatable, Sendable {
  public var sessionID: String
  public var path: String
  public var fileIdentity: String
  public var parsedBytes: UInt64
  public var accumulator: SessionUsageAccumulator
  public var buckets: UsageBuckets
  public var latestRateLimit: TokenUsageEvent?
  public var scanContext: JSONLTokenScanContext

  public init(
    sessionID: String,
    path: String,
    fileIdentity: String,
    parsedBytes: UInt64,
    accumulator: SessionUsageAccumulator,
    buckets: UsageBuckets,
    latestRateLimit: TokenUsageEvent?,
    scanContext: JSONLTokenScanContext = JSONLTokenScanContext()
  ) {
    self.sessionID = sessionID
    self.path = path
    self.fileIdentity = fileIdentity
    self.parsedBytes = parsedBytes
    self.accumulator = accumulator
    self.buckets = buckets
    self.latestRateLimit = latestRateLimit
    self.scanContext = scanContext
  }
}

public struct UsageSnapshot: Equatable, Sendable {
  public let generatedAt: Date
  public let isIndexing: Bool
  public let todayTotal: Int64
  public let weekTotal: Int64
  public let allTimeTotal: Int64
  public let allTimeUsage: TokenUsage
  public let allTimeCredits: Double
  public let hourly: [Int64]
  public let weekly: [Int64]
  public let monthly: [Int64]
  public let monthKeys: [String]
  public let fiveHourLimit: RateLimitWindow?
  public let weeklyLimit: RateLimitWindow?
  public let statusLimitKind: RateLimitKind?
  public let latestRateLimitAt: Date?
  public let statusColor: UsageStatusColor

  public var hasUsage: Bool {
    allTimeTotal > 0
  }
}

public struct UsageIndex: Codable, Equatable, Sendable {
  public static let currentVersion = 4

  public var version: Int
  public var timeZoneIdentifier: String
  public private(set) var sessions: [String: SessionUsageIndex]

  public init(
    timeZoneIdentifier: String = TimeZone.current.identifier,
    sessions: [String: SessionUsageIndex] = [:]
  ) {
    self.version = Self.currentVersion
    self.timeZoneIdentifier = timeZoneIdentifier
    self.sessions = sessions
  }

  public mutating func upsert(_ session: SessionUsageIndex) {
    sessions[session.sessionID] = session
  }

  public mutating func removeSession(id: String) {
    sessions.removeValue(forKey: id)
  }

  public func session(id: String) -> SessionUsageIndex? {
    sessions[id]
  }

  public func snapshot(now: Date, isIndexing: Bool) -> UsageSnapshot {
    var merged = UsageBuckets(timeZoneIdentifier: timeZoneIdentifier)
    var latestEvent: TokenUsageEvent?

    for session in sessions.values {
      merged.merge(session.buckets)
      if let candidate = session.latestRateLimit,
         latestEvent == nil || candidate.timestamp > latestEvent!.timestamp {
        latestEvent = candidate
      }
    }

    let bucketSnapshot = merged.snapshot(now: now)
    let resolvedRateLimits = latestEvent?.resolvedRateLimits
    let statusWindow = resolvedRateLimits?.statusWindow
    let stale = statusWindow.map { RateLimitPolicy.isStale($0, now: now) } ?? true
    let remaining = statusWindow.map(RateLimitPolicy.remainingPercent(for:))

    return UsageSnapshot(
      generatedAt: now,
      isIndexing: isIndexing,
      todayTotal: bucketSnapshot.todayTotal,
      weekTotal: bucketSnapshot.weekTotal,
      allTimeTotal: bucketSnapshot.allTimeTotal,
      allTimeUsage: bucketSnapshot.allTimeUsage,
      allTimeCredits: bucketSnapshot.allTimeCredits,
      hourly: bucketSnapshot.hourly,
      weekly: bucketSnapshot.weekly,
      monthly: bucketSnapshot.monthly,
      monthKeys: bucketSnapshot.monthKeys,
      fiveHourLimit: resolvedRateLimits?.fiveHour,
      weeklyLimit: resolvedRateLimits?.weekly,
      statusLimitKind: resolvedRateLimits?.statusKind,
      latestRateLimitAt: latestEvent?.timestamp,
      statusColor: RateLimitPolicy.color(remainingPercent: remaining, isStale: stale)
    )
  }
}
