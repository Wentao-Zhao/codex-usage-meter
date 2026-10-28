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
  public var compressedFileSignature: String?

  public init(
    sessionID: String,
    path: String,
    fileIdentity: String,
    parsedBytes: UInt64,
    accumulator: SessionUsageAccumulator,
    buckets: UsageBuckets,
    latestRateLimit: TokenUsageEvent?,
    scanContext: JSONLTokenScanContext = JSONLTokenScanContext(),
    compressedFileSignature: String? = nil
  ) {
    self.sessionID = sessionID
    self.path = path
    self.fileIdentity = fileIdentity
    self.parsedBytes = parsedBytes
    self.accumulator = accumulator
    self.buckets = buckets
    self.latestRateLimit = latestRateLimit
    self.scanContext = scanContext
    self.compressedFileSignature = compressedFileSignature
  }
}

public struct UsageSnapshot: Equatable, Sendable {
  public let generatedAt: Date
  public let isIndexing: Bool
  public let todayTotal: Int64
  public let previousDayTotal: Int64
  public let weekTotal: Int64
  public let previousWeekTotal: Int64
  public let allTimeTotal: Int64
  public let allTimeUsage: TokenUsage
  public let allTimeCredits: Double
  public let hourly: [Int64]
  public let previousDayHourly: [Int64]
  public let weekly: [Int64]
  public let previousWeekDaily: [Int64]
  public let monthly: [Int64]
  public let monthKeys: [String]
  public let fiveHourLimit: RateLimitWindow?
  public let weeklyLimit: RateLimitWindow?
  public let statusLimitKind: RateLimitKind?
  public let latestRateLimitAt: Date?
  public let statusColor: UsageStatusColor
  public let historyScanProgress: HistoryScanProgress?

  public var hasUsage: Bool {
    allTimeTotal > 0
  }

  public func replacingRateLimits(
    _ rateLimits: ResolvedRateLimits,
    updatedAt: Date
  ) -> UsageSnapshot {
    let statusWindow = rateLimits.statusWindow
    let isStale = statusWindow.map {
      RateLimitPolicy.isStale($0, now: generatedAt)
    } ?? true
    let remaining = statusWindow.map(RateLimitPolicy.remainingPercent(for:))

    return UsageSnapshot(
      generatedAt: generatedAt,
      isIndexing: isIndexing,
      todayTotal: todayTotal,
      previousDayTotal: previousDayTotal,
      weekTotal: weekTotal,
      previousWeekTotal: previousWeekTotal,
      allTimeTotal: allTimeTotal,
      allTimeUsage: allTimeUsage,
      allTimeCredits: allTimeCredits,
      hourly: hourly,
      previousDayHourly: previousDayHourly,
      weekly: weekly,
      previousWeekDaily: previousWeekDaily,
      monthly: monthly,
      monthKeys: monthKeys,
      fiveHourLimit: rateLimits.fiveHour,
      weeklyLimit: rateLimits.weekly,
      statusLimitKind: rateLimits.statusKind,
      latestRateLimitAt: updatedAt,
      statusColor: RateLimitPolicy.color(
        remainingPercent: remaining,
        isStale: isStale
      ),
      historyScanProgress: historyScanProgress
    )
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

  public func snapshot(now: Date, isIndexing: Bool, historyScanProgress: HistoryScanProgress? = nil) -> UsageSnapshot {
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
      previousDayTotal: bucketSnapshot.previousDayTotal,
      weekTotal: bucketSnapshot.weekTotal,
      previousWeekTotal: bucketSnapshot.previousWeekTotal,
      allTimeTotal: bucketSnapshot.allTimeTotal,
      allTimeUsage: bucketSnapshot.allTimeUsage,
      allTimeCredits: bucketSnapshot.allTimeCredits,
      hourly: bucketSnapshot.hourly,
      previousDayHourly: bucketSnapshot.previousDayHourly,
      weekly: bucketSnapshot.weekly,
      previousWeekDaily: bucketSnapshot.previousWeekDaily,
      monthly: bucketSnapshot.monthly,
      monthKeys: bucketSnapshot.monthKeys,
      fiveHourLimit: resolvedRateLimits?.fiveHour,
      weeklyLimit: resolvedRateLimits?.weekly,
      statusLimitKind: resolvedRateLimits?.statusKind,
      latestRateLimitAt: latestEvent?.timestamp,
      statusColor: RateLimitPolicy.color(remainingPercent: remaining, isStale: stale),
      historyScanProgress: historyScanProgress
    )
  }
}

public struct HistoryScanProgress: Equatable, Sendable {
  public let completed: Int
  public let total: Int
  public let failed: Int
  public let currentFilePercent: Int?

  public init(completed: Int, total: Int, failed: Int = 0, currentFilePercent: Int? = nil) {
    self.completed = completed
    self.total = total
    self.failed = failed
    self.currentFilePercent = currentFilePercent
  }
}
