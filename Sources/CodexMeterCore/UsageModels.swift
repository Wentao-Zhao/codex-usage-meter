import Foundation

public enum UsageStatusColor: String, Codable, Equatable, Sendable {
  case green
  case yellow
  case orange
  case red
  case unknown
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
}
