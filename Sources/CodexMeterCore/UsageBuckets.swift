import Foundation

public struct UsageBucketSnapshot: Equatable, Sendable {
  public let todayTotal: Int64
  public let weekTotal: Int64
  public let allTimeTotal: Int64
  public let hourly: [Int64]
  public let weekly: [Int64]
  public let monthly: [Int64]
  public let monthKeys: [String]
}

public struct UsageBuckets: Codable, Equatable, Sendable {
  public private(set) var hourly: [String: Int64]
  public private(set) var daily: [String: Int64]
  public private(set) var monthly: [String: Int64]
  public let timeZoneIdentifier: String

  public init(
    timeZoneIdentifier: String = TimeZone.current.identifier,
    hourly: [String: Int64] = [:],
    daily: [String: Int64] = [:],
    monthly: [String: Int64] = [:]
  ) {
    self.timeZoneIdentifier = timeZoneIdentifier
    self.hourly = hourly
    self.daily = daily
    self.monthly = monthly
  }

  public mutating func add(tokens: Int64, at date: Date) {
    guard tokens > 0 else {
      return
    }

    let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
    guard
      let year = components.year,
      let month = components.month,
      let day = components.day,
      let hour = components.hour
    else {
      return
    }

    hourly[Self.hourKey(year: year, month: month, day: day, hour: hour), default: 0] += tokens
    daily[Self.dayKey(year: year, month: month, day: day), default: 0] += tokens
    monthly[Self.monthKey(year: year, month: month), default: 0] += tokens
  }

  public func snapshot(now: Date) -> UsageBucketSnapshot {
    let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
    let currentYear = nowComponents.year ?? 1970
    let currentMonth = nowComponents.month ?? 1
    let currentDay = nowComponents.day ?? 1

    let hourlySeries = (0..<24).map {
      hourly[Self.hourKey(year: currentYear, month: currentMonth, day: currentDay, hour: $0), default: 0]
    }

    let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
      ?? calendar.startOfDay(for: now)
    let weeklySeries = (0..<7).map { offset -> Int64 in
      guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
        return 0
      }
      let components = calendar.dateComponents([.year, .month, .day], from: date)
      return daily[
        Self.dayKey(
          year: components.year ?? 1970,
          month: components.month ?? 1,
          day: components.day ?? 1
        ),
        default: 0
      ]
    }

    let selectedMonthKeys = Array(monthly.keys.sorted().suffix(12))
    let monthlySeries = selectedMonthKeys.map { monthly[$0, default: 0] }

    return UsageBucketSnapshot(
      todayTotal: hourlySeries.reduce(0, +),
      weekTotal: weeklySeries.reduce(0, +),
      allTimeTotal: monthly.values.reduce(0, +),
      hourly: hourlySeries,
      weekly: weeklySeries,
      monthly: monthlySeries,
      monthKeys: selectedMonthKeys
    )
  }

  public mutating func merge(_ other: UsageBuckets) {
    for (key, value) in other.hourly {
      hourly[key, default: 0] += value
    }
    for (key, value) in other.daily {
      daily[key, default: 0] += value
    }
    for (key, value) in other.monthly {
      monthly[key, default: 0] += value
    }
  }

  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.locale = Locale(identifier: "en_US_POSIX")
    value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    value.firstWeekday = 2
    value.minimumDaysInFirstWeek = 4
    return value
  }

  private static func hourKey(year: Int, month: Int, day: Int, hour: Int) -> String {
    String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
  }

  private static func dayKey(year: Int, month: Int, day: Int) -> String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  private static func monthKey(year: Int, month: Int) -> String {
    String(format: "%04d-%02d", year, month)
  }
}

public enum TokenCountFormatter {
  public static func string(from tokens: Int64) -> String {
    if tokens >= 1_000_000 {
      return compact(Double(tokens) / 1_000_000, fractionDigits: 2) + "M"
    }
    if tokens >= 1_000 {
      return compact(Double(tokens) / 1_000, fractionDigits: 1) + "K"
    }
    return String(tokens)
  }

  private static func compact(_ value: Double, fractionDigits: Int) -> String {
    let format = "%." + String(fractionDigits) + "f"
    var result = String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    while result.last == "0" {
      result.removeLast()
    }
    if result.last == "." {
      result.removeLast()
    }
    return result
  }
}
