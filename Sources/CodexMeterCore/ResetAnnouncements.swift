import Foundation

public struct ResetAnnouncementFeed: Codable, Sendable {
  public let checkedAt: Date
  public let events: [ResetAnnouncement]

  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 2_000_000,
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      root["schemaVersion"] as? Int == 1,
      let checkedAt = parseDate(root["checkedAt"]),
      let rows = root["events"] as? [[String: Any]], rows.count <= 1000
    else { throw CocoaError(.coderReadCorrupt) }
    return Self(checkedAt: checkedAt, events: rows.compactMap(ResetAnnouncement.init))
  }

  public func isFresh(at now: Date) -> Bool {
    (-300..<1800).contains(now.timeIntervalSince(checkedAt))
  }

  public func upcoming(at now: Date) -> ResetAnnouncement? {
    events.filter { $0.isUpcoming(at: now) }.sorted {
      if $0.schedule!.through == $1.schedule!.through { return $0.id < $1.id }
      return $0.schedule!.through < $1.schedule!.through
    }.first
  }

  public func latestConfirmed(at now: Date) -> ResetAnnouncement? {
    events.filter { $0.status == "confirmed" && $0.confirmationDate.map { $0 <= now } == true }
      .max { $0.confirmationDate! < $1.confirmationDate! }
  }
}

public struct ResetAnnouncement: Codable, Sendable {
  public struct Schedule: Codable, Sendable {
    public let from: Date
    public let through: Date
    public let label: String
  }

  public let id: String
  public let type: String
  public let status: String
  public let scope: String
  public let timeInferred: Bool?
  public let schedule: Schedule?
  public let confirmedAt: Date?
  public let occurredOn: String?
  private let source: String?

  fileprivate init?(_ row: [String: Any]) {
    guard let id = row["id"] as? String, !id.isEmpty,
      let type = row["type"] as? String, ["direct_reset", "reset_credit"].contains(type),
      let status = row["status"] as? String
    else { return nil }
    self.id = id
    self.type = type
    self.status = status
    scope = (row["scope"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    timeInferred = (row["presentation"] as? [String: Any])?["timeInferred"] as? Bool
    confirmedAt = parseDate(row["confirmedAt"])
    occurredOn = row["occurredOn"] as? String
    if let raw = row["schedule"] as? [String: Any],
      let from = parseDate(raw["from"]), let through = parseDate(raw["through"]), from <= through,
      let label = raw["label"] as? String, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      schedule = Schedule(from: from, through: through, label: label)
    } else { schedule = nil }
    let posts = row["posts"] as? [[String: Any]] ?? []
    let confirmations = posts.filter { $0["stage"] as? String == "确认完成" }
    let candidates = status == "confirmed" && !confirmations.isEmpty ? confirmations : posts
    source = candidates.sorted {
      (parseDate($0["publishedAt"]) ?? .distantPast) > (parseDate($1["publishedAt"]) ?? .distantPast)
    }.compactMap { $0["url"] as? String }.first { Self.safeSourceURL($0) != nil }
  }

  public func isUpcoming(at now: Date) -> Bool {
    status == "announced" && timeInferred == false && (schedule?.through ?? .distantPast) > now
  }

  public var kindLabel: String { type == "reset_credit" ? "重置卡发放预告" : "额外额度重置预告" }

  public var displayTime: String {
    var value = schedule?.label ?? "暂无明确时间"
    for prefix in ["北京时间预计 ", "北京时间预计", "北京时间 ", "北京时间"] where value.hasPrefix(prefix) {
      value.removeFirst(prefix.count)
      break
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var notificationKey: String {
    let parts = [id, type, scope, schedule?.label ?? "", String(schedule?.from.timeIntervalSince1970 ?? 0), String(schedule?.through.timeIntervalSince1970 ?? 0)]
    return (try? JSONEncoder().encode(parts).base64EncodedString()) ?? id
  }

  public var sourceURL: URL? { source.flatMap(Self.safeSourceURL) }

  public static func safeSourceURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme?.lowercased() == "https",
      let host = url.host?.lowercased(), ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "aihot.news"].contains(host),
      url.user == nil, url.password == nil
    else { return nil }
    return url
  }

  fileprivate var confirmationDate: Date? {
    if let confirmedAt { return confirmedAt }
    guard let occurredOn else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: occurredOn)
  }
}

public struct ResetNoticeState: Sendable {
  public let value: String
  public let detail: String
  public let tooltip: String
  public let sourceURL: URL

  public static func make(
    feed: ResetAnnouncementFeed?, fetchedAt: Date?, now: Date,
    isLoading: Bool = false, failed: Bool = false, retryAt: Date? = nil
  ) -> Self {
    let upcoming = feed?.upcoming(at: now)
    let confirmed = feed?.latestConfirmed(at: now)
    let stale = feed != nil && (failed || !feed!.isFresh(at: now) || fetchedAt.map { now.timeIntervalSince($0) >= 1800 || $0 > now.addingTimeInterval(300) } != false)
    let value: String
    if let upcoming { value = upcoming.displayTime }
    else if let confirmed, let date = confirmed.confirmationDate {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "zh_CN")
      formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
      formatter.dateFormat = "M月d日"
      value = formatter.string(from: date) + (confirmed.type == "reset_credit" ? "发卡已确认" : "重置已确认")
    } else if feed != nil { value = "暂无明确预告" }
    else { value = failed ? "暂时无法获取" : "正在检查预告…" }
    var detail = upcoming == nil ? "AIHOT 非官方整理 · 每 30 分钟检查" : "北京时间 · AIHOT 非官方整理"
    if stale { detail = "缓存 · 数据待更新 · AIHOT 非官方整理" }
    if let retryAt, retryAt > now { detail = "限流等待 · AIHOT 非官方整理" }
    else if isLoading { detail = "正在更新 · AIHOT 非官方整理" }
    let selected = upcoming ?? confirmed
    let scope = selected?.scope.isEmpty == false ? selected!.scope : "原帖未明确适用范围"
    let kind = selected?.status == "confirmed"
      ? (selected?.type == "reset_credit" ? "重置卡发放已确认" : "额外额度重置已确认")
      : selected?.kindLabel ?? "重置动态"
    let tooltip = [kind, value, scope, detail, "公开动态不代表个人额度已恢复；点击查看来源"].joined(separator: "\n")
    return Self(value: value, detail: detail, tooltip: tooltip, sourceURL: selected?.sourceURL ?? URL(string: "https://aihot.news/codex-reset")!)
  }
}

public enum ResetAnnouncementSchedule {
  public static func isDue(now: Date, lastAttempt: Date?) -> Bool {
    guard let lastAttempt else { return true }
    let slot = floor(now.timeIntervalSince1970 / 1800) * 1800
    return lastAttempt > now || lastAttempt.timeIntervalSince1970 < slot
  }

  public static func retryDate(_ value: String?, now: Date) -> Date? {
    guard let value else { return nil }
    if let seconds = Double(value), seconds.isFinite { return now.addingTimeInterval(max(0, seconds)) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
    return formatter.date(from: value)
  }
}

private func parseDate(_ value: Any?) -> Date? {
  guard let string = value as? String else { return nil }
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: string) { return date }
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: string)
}
