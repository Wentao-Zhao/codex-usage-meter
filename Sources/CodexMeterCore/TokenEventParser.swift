import Foundation

public enum TokenEventParser {
  private static let fractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let dateFormatter = ISO8601DateFormatter()

  public static func parse(line: Data, model: String? = nil) -> TokenUsageEvent? {
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
    let usage = parseUsage(totalUsage)
    let rateLimits = payload["rate_limits"] as? [String: Any]

    return TokenUsageEvent(
      timestamp: timestamp,
      usage: usage,
      model: model,
      primary: parseWindow(rateLimits?["primary"]),
      secondary: parseWindow(rateLimits?["secondary"])
    )
  }

  private static func parseUsage(_ value: [String: Any]?) -> TokenUsage? {
    guard let value else {
      return nil
    }

    let totalTokens = (value["total_tokens"] as? NSNumber)?.int64Value
    let inputTokens = (value["input_tokens"] as? NSNumber)?.int64Value
    let cachedInputTokens = (value["cached_input_tokens"] as? NSNumber)?.int64Value
    let outputTokens = (value["output_tokens"] as? NSNumber)?.int64Value

    if inputTokens == nil, cachedInputTokens == nil, outputTokens == nil {
      return totalTokens.map(TokenUsage.init(totalTokens:))
    }

    let input = inputTokens ?? cachedInputTokens ?? 0
    let output = outputTokens ?? 0
    return TokenUsage(
      inputTokens: input,
      cachedInputTokens: cachedInputTokens ?? 0,
      outputTokens: output,
      totalTokens: totalTokens ?? input + output
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
