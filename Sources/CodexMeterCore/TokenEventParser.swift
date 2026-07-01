import Foundation

public enum TokenEventParser {
  private static let fractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let dateFormatter = ISO8601DateFormatter()

  public static func parse(line: Data) -> TokenUsageEvent? {
    guard
      let object = try? JSONSerialization.jsonObject(with: line),
      let root = object as? [String: Any],
      root["type"] as? String == "event_msg",
      let timestampString = root["timestamp"] as? String,
      let timestamp = fractionalDateFormatter.date(from: timestampString)
        ?? dateFormatter.date(from: timestampString),
      let payload = root["payload"] as? [String: Any],
      payload["type"] as? String == "token_count"
    else {
      return nil
    }

    let info = payload["info"] as? [String: Any]
    let totalUsage = info?["total_token_usage"] as? [String: Any]
    let totalTokens = (totalUsage?["total_tokens"] as? NSNumber)?.int64Value
    let rateLimits = payload["rate_limits"] as? [String: Any]

    return TokenUsageEvent(
      timestamp: timestamp,
      totalTokens: totalTokens,
      primary: parseWindow(rateLimits?["primary"]),
      secondary: parseWindow(rateLimits?["secondary"])
    )
  }

  private static func parseWindow(_ value: Any?) -> RateLimitWindow? {
    guard
      let dictionary = value as? [String: Any],
      let usedPercent = (dictionary["used_percent"] as? NSNumber)?.doubleValue,
      let windowMinutes = (dictionary["window_minutes"] as? NSNumber)?.intValue,
      let resetsAt = (dictionary["resets_at"] as? NSNumber)?.doubleValue
    else {
      return nil
    }

    return RateLimitWindow(
      usedPercent: usedPercent,
      windowMinutes: windowMinutes,
      resetsAt: Date(timeIntervalSince1970: resetsAt)
    )
  }
}
