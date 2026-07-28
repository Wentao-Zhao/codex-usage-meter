import Foundation

public struct MeteredUsage: Codable, Equatable, Sendable {
  public private(set) var usage: TokenUsage
  public private(set) var credits: Double

  public init(usage: TokenUsage = .zero, credits: Double = 0) {
    self.usage = usage
    self.credits = max(0, credits)
  }

  public mutating func add(_ other: MeteredUsage) {
    usage = usage.adding(other.usage)
    credits += other.credits
  }
}

public struct UsageBucketSnapshot: Equatable, Sendable {
  public let todayUsage: TokenUsage
  public let previousDayUsage: TokenUsage
  public let weekUsage: TokenUsage
  public let previousWeekUsage: TokenUsage
  public let allTimeUsage: TokenUsage
  public let allTimeCredits: Double
  public let hourly: [Int64]
  public let previousDayHourly: [Int64]
  public let weekly: [Int64]
  public let previousWeekDaily: [Int64]
  public let monthly: [Int64]
  public let monthKeys: [String]

  public var todayTotal: Int64 {
    todayUsage.totalTokens
  }

  public var weekTotal: Int64 {
    weekUsage.totalTokens
  }

  public var previousDayTotal: Int64 {
    previousDayUsage.totalTokens
  }

  public var previousWeekTotal: Int64 {
    previousWeekUsage.totalTokens
  }

  public var allTimeTotal: Int64 {
    allTimeUsage.totalTokens
  }
}

public struct UsageBuckets: Codable, Equatable, Sendable {
  public private(set) var hourly: [String: MeteredUsage]
  public private(set) var daily: [String: MeteredUsage]
  public private(set) var monthly: [String: MeteredUsage]
  public let timeZoneIdentifier: String

  public init(
    timeZoneIdentifier: String = TimeZone.current.identifier,
    hourly: [String: MeteredUsage] = [:],
    daily: [String: MeteredUsage] = [:],
    monthly: [String: MeteredUsage] = [:]
  ) {
    self.timeZoneIdentifier = timeZoneIdentifier
    self.hourly = hourly
    self.daily = daily
    self.monthly = monthly
  }

  public mutating func add(tokens: Int64, at date: Date) {
    add(usage: TokenUsage(totalTokens: tokens), model: nil, at: date)
  }

  public mutating func add(usage: TokenUsage, model: String?, at date: Date) {
    guard usage.totalTokens > 0 else {
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

    let value = MeteredUsage(
      usage: usage,
      credits: CodexCreditCalculator.credits(for: usage, model: model)
    )
    add(value, to: &hourly, key: Self.hourKey(year: year, month: month, day: day, hour: hour))
    add(value, to: &daily, key: Self.dayKey(year: year, month: month, day: day))
    add(value, to: &monthly, key: Self.monthKey(year: year, month: month))
  }

  public func snapshot(now: Date) -> UsageBucketSnapshot {
    let todayStart = calendar.startOfDay(for: now)
    let currentHour = calendar.component(.hour, from: now)
    let currentHourlyUsage = hourlyUsage(on: todayStart, through: currentHour)
    let previousDayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)
      ?? todayStart
    let previousDayUsage = hourlyUsage(on: previousDayStart, through: currentHour)
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
      ?? todayStart
    let currentWeekdayOffset = max(
      0,
      min(
        6,
        calendar.dateComponents([.day], from: weekStart, to: todayStart).day ?? 0
      )
    )
    let weeklyUsage = dailyUsage(from: weekStart, through: currentWeekdayOffset)
    let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)
      ?? weekStart
    let previousWeekUsage = dailyUsage(
      from: previousWeekStart,
      through: currentWeekdayOffset
    )

    let selectedMonthKeys = Array(monthly.keys.sorted().suffix(12))
    let monthlyUsage = selectedMonthKeys.map { monthly[$0, default: MeteredUsage()] }
    let today = Self.sum(currentHourlyUsage)
    let previousDay = Self.sum(previousDayUsage)
    let week = Self.sum(weeklyUsage)
    let previousWeek = Self.sum(previousWeekUsage)
    let allTime = Self.sum(Array(monthly.values))

    return UsageBucketSnapshot(
      todayUsage: today.usage,
      previousDayUsage: previousDay.usage,
      weekUsage: week.usage,
      previousWeekUsage: previousWeek.usage,
      allTimeUsage: allTime.usage,
      allTimeCredits: allTime.credits,
      hourly: currentHourlyUsage.map(\.usage.totalTokens),
      previousDayHourly: previousDayUsage.map(\.usage.totalTokens),
      weekly: weeklyUsage.map(\.usage.totalTokens),
      previousWeekDaily: previousWeekUsage.map(\.usage.totalTokens),
      monthly: monthlyUsage.map(\.usage.totalTokens),
      monthKeys: selectedMonthKeys
    )
  }

  private func hourlyUsage(on day: Date, through hour: Int) -> [MeteredUsage] {
    let components = calendar.dateComponents([.year, .month, .day], from: day)
    return (0...max(0, min(23, hour))).map {
      hourly[
        Self.hourKey(
          year: components.year ?? 1970,
          month: components.month ?? 1,
          day: components.day ?? 1,
          hour: $0
        ),
        default: MeteredUsage()
      ]
    }
  }

  private func dailyUsage(from start: Date, through offset: Int) -> [MeteredUsage] {
    (0...max(0, min(6, offset))).map { offset -> MeteredUsage in
      guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
        return MeteredUsage()
      }
      let components = calendar.dateComponents([.year, .month, .day], from: date)
      return daily[
        Self.dayKey(
          year: components.year ?? 1970,
          month: components.month ?? 1,
          day: components.day ?? 1
        ),
        default: MeteredUsage()
      ]
    }
  }

  public mutating func merge(_ other: UsageBuckets) {
    merge(other.hourly, into: &hourly)
    merge(other.daily, into: &daily)
    merge(other.monthly, into: &monthly)
  }

  private func add(
    _ value: MeteredUsage,
    to dictionary: inout [String: MeteredUsage],
    key: String
  ) {
    var aggregate = dictionary[key, default: MeteredUsage()]
    aggregate.add(value)
    dictionary[key] = aggregate
  }

  private func merge(
    _ source: [String: MeteredUsage],
    into destination: inout [String: MeteredUsage]
  ) {
    for (key, value) in source {
      add(value, to: &destination, key: key)
    }
  }

  private static func sum(_ values: [MeteredUsage]) -> MeteredUsage {
    values.reduce(into: MeteredUsage()) { result, value in
      result.add(value)
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
    if tokens >= 1_000_000_000 {
      return compact(Double(tokens) / 1_000_000_000, fractionDigits: 2) + "B"
    }
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

public enum CreditCountFormatter {
  public static func string(from credits: Double) -> String {
    if credits >= 1_000_000 {
      return compact(credits / 1_000_000, fractionDigits: 2) + "M"
    }
    if credits >= 1_000 {
      return compact(credits / 1_000, fractionDigits: 2) + "K"
    }
    if credits >= 100 {
      return compact(credits, fractionDigits: 0)
    }
    return compact(credits, fractionDigits: 2)
  }

  private static func compact(_ value: Double, fractionDigits: Int) -> String {
    let format = "%." + String(fractionDigits) + "f"
    var result = String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    while result.last == "0", result.contains(".") {
      result.removeLast()
    }
    if result.last == "." {
      result.removeLast()
    }
    return result
  }
}
