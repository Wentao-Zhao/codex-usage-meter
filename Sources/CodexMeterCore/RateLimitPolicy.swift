import Foundation

public enum RateLimitPolicy {
  public static func remainingPercent(for window: RateLimitWindow) -> Double {
    min(100, max(0, 100 - window.usedPercent))
  }

  public static func isStale(_ window: RateLimitWindow, now: Date) -> Bool {
    now >= window.resetsAt
  }

  public static func minutesUntilReset(_ window: RateLimitWindow, now: Date) -> Int {
    max(0, Int(ceil(window.resetsAt.timeIntervalSince(now) / 60)))
  }

  public static func daysUntilReset(_ window: RateLimitWindow, now: Date) -> Int {
    max(0, Int(ceil(window.resetsAt.timeIntervalSince(now) / 86_400)))
  }

  public static func color(
    remainingPercent: Double?,
    isStale: Bool
  ) -> UsageStatusColor {
    guard let remainingPercent, !isStale else {
      return .unknown
    }

    if remainingPercent >= 70 {
      return .green
    }
    if remainingPercent >= 30 {
      return .yellow
    }
    if remainingPercent >= 10 {
      return .orange
    }
    return .red
  }
}
