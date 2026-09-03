import Foundation

public enum AccountRateLimitResponseParser {
  public static func parse(_ data: Data) -> ResolvedRateLimits? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let root = object as? [String: Any],
      root["error"] == nil,
      let result = root["result"] as? [String: Any],
      let snapshot = preferredSnapshot(in: result)
    else {
      return nil
    }

    let windows = [
      parseWindow(snapshot["primary"]),
      parseWindow(snapshot["secondary"]),
    ].compactMap { $0 }
    guard !windows.isEmpty else {
      return nil
    }
    return ResolvedRateLimits(windows: windows)
  }

  private static func preferredSnapshot(in result: [String: Any]) -> [String: Any]? {
    if
      let snapshots = result["rateLimitsByLimitId"] as? [String: Any],
      let codex = snapshots["codex"] as? [String: Any]
    {
      return codex
    }

    if let legacy = result["rateLimits"] as? [String: Any] {
      return legacy
    }

    return nil
  }

  private static func parseWindow(_ value: Any?) -> RateLimitWindow? {
    guard
      let dictionary = value as? [String: Any],
      let usedPercent = (dictionary["usedPercent"] as? NSNumber)?.doubleValue,
      let windowMinutes = (dictionary["windowDurationMins"] as? NSNumber)?.intValue,
      let resetsAt = (dictionary["resetsAt"] as? NSNumber)?.doubleValue
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
