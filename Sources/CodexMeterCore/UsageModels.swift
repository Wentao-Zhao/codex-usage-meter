import Foundation

public enum UsageStatusColor: String, Codable, Equatable, Sendable {
  case green
  case yellow
  case orange
  case red
  case unknown
}

public enum RateLimitKind: String, Codable, Equatable, Sendable {
  case fiveHour
  case weekly
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
  public let usedPercent: Double
  public let windowMinutes: Int
  public let resetsAt: Date

  public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date) {
    self.usedPercent = usedPercent
    self.windowMinutes = windowMinutes
    self.resetsAt = resetsAt
  }
}

public struct TokenUsageEvent: Codable, Equatable, Sendable {
  public let timestamp: Date
  public let totalTokens: Int64?
  public let primary: RateLimitWindow?
  public let secondary: RateLimitWindow?

  public init(
    timestamp: Date,
    totalTokens: Int64?,
    primary: RateLimitWindow?,
    secondary: RateLimitWindow?
  ) {
    self.timestamp = timestamp
    self.totalTokens = totalTokens
    self.primary = primary
    self.secondary = secondary
  }

  public var resolvedRateLimits: ResolvedRateLimits {
    ResolvedRateLimits(windows: [primary, secondary].compactMap { $0 })
  }
}

public struct ResolvedRateLimits: Equatable, Sendable {
  public let fiveHour: RateLimitWindow?
  public let weekly: RateLimitWindow?

  public init(windows: [RateLimitWindow]) {
    fiveHour = windows.first { $0.windowMinutes == 5 * 60 }
    weekly = windows.first { $0.windowMinutes == 7 * 24 * 60 }
  }

  public var statusKind: RateLimitKind? {
    if fiveHour != nil {
      return .fiveHour
    }
    if weekly != nil {
      return .weekly
    }
    return nil
  }

  public var statusWindow: RateLimitWindow? {
    fiveHour ?? weekly
  }
}
