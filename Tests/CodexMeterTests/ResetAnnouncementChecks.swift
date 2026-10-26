import CodexMeterCore
import Foundation

func runResetAnnouncementChecks(_ check: (Bool, String) -> Void) {
  let now = ISO8601DateFormatter().date(from: "2026-10-26T08:00:00Z")!
  func decode(_ changes: [String: Any] = [:], checkedAt: String = "2026-10-26T07:59:00Z") throws -> ResetAnnouncementFeed {
    var event: [String: Any] = [
      "id": "event-1", "type": "direct_reset", "status": "announced", "scope": "付费用户",
      "presentation": ["timeInferred": false],
      "schedule": ["from": "2026-10-27T17:00:00Z", "through": "2026-10-27T18:00:00Z", "label": "北京时间预计 10月28日 02:00 前"],
      "posts": [["url": "https://x.com/thsottiaux/status/123", "publishedAt": "2026-10-26T07:00:00Z"]],
    ]
    event.merge(changes) { _, new in new }
    return try ResetAnnouncementFeed.decode(JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "checkedAt": checkedAt, "events": [event]]))
  }
  do {
    let feed = try decode()
    let event = feed.upcoming(at: now)!
    check(feed.isFresh(at: now), "fresh feed accepted")
    check(!feed.isFresh(at: now.addingTimeInterval(1800)), "stale source timestamp rejected")
    check(!feed.isFresh(at: now.addingTimeInterval(-1000)), "future source timestamp rejected")
    check(event.displayTime == "10月28日 02:00 前", "retain deadline qualifier and remove standard prefix")
    check(event.sourceURL?.host == "x.com", "retain safe original post link")
    check(try decode(["status": "confirmed"]).upcoming(at: now) == nil, "confirmation is not an upcoming announcement")
    check(try decode(["status": "retracted"]).upcoming(at: now) == nil, "withdrawn announcements excluded")
    check(try decode(["presentation": ["timeInferred": true]]).upcoming(at: now) == nil, "inferred time excluded")
    check(try decode(["presentation": [:]]).upcoming(at: now) == nil, "missing time provenance excluded")
    check(feed.upcoming(at: now.addingTimeInterval(3 * 86400)) == nil, "expired announcement excluded")
    check(try decode(["schedule": NSNull()]).upcoming(at: now) == nil, "missing schedule excluded")
    check(try decode(["schedule": ["from": "2026-10-28T18:00:00Z", "through": "2026-10-27T18:00:00Z", "label": "invalid"]]).upcoming(at: now) == nil, "reversed schedule excluded")
    check(try decode(["type": "unknown"]).upcoming(at: now) == nil, "unknown event kind excluded")
    let credit = try decode(["type": "reset_credit"]).upcoming(at: now)!
    check(credit.kindLabel == "重置卡发放预告", "credit is distinguished from automatic recovery")
    check(try decode(["scope": "其他用户"]).upcoming(at: now)!.notificationKey != event.notificationKey, "scope changes produce new notification")
    check(try decode(["type": "reset_credit"]).upcoming(at: now)!.notificationKey != event.notificationKey, "event kind changes produce new notification")
    let retimed = try decode(["schedule": ["from": "2026-10-27T18:00:00Z", "through": "2026-10-27T19:00:00Z", "label": "北京时间预计 10月28日 03:00 左右"]]).upcoming(at: now)!
    check(retimed.notificationKey != event.notificationKey && retimed.displayTime.hasSuffix("左右"), "time amendments notify again and retain qualifiers")
    check(try decode(["updatedAt": "2026-10-26T08:00:00Z"]).upcoming(at: now)!.notificationKey == event.notificationKey, "metadata changes do not duplicate notification")
    check(try decode(["posts": [["url": "file:///etc/passwd"]]]).events.first?.sourceURL == nil, "unsafe link rejected")
    check(ResetAnnouncement.safeSourceURL("https://x.com.attacker.example/post") == nil, "lookalike source host rejected")
    let confirmed = try decode(["status": "confirmed", "confirmedAt": "2026-10-25T06:06:00Z"])
    let notice = ResetNoticeState.make(feed: confirmed, fetchedAt: now, now: now)
    check(notice.value.contains("已确认"), "show latest confirmed event when no forecast")
    check(notice.value.contains("10月25日"), "confirmation date uses Beijing time")
    let offline = ResetNoticeState.make(feed: feed, fetchedAt: now, now: now, failed: true)
    check(offline.detail.contains("缓存") && offline.detail.contains("待更新"), "offline cache clearly marked")
    check(ResetNoticeState.make(feed: nil, fetchedAt: nil, now: now, failed: true).value == "暂时无法获取", "empty network failure shown without guessed forecast")
    check(ResetAnnouncementSchedule.isDue(now: now, lastAttempt: nil), "first refresh due")
    check(!ResetAnnouncementSchedule.isDue(now: now, lastAttempt: now), "same half hour not due")
    check(ResetAnnouncementSchedule.isDue(now: now.addingTimeInterval(1800), lastAttempt: now), "next half hour due")
    check(ResetAnnouncementSchedule.isDue(now: now.addingTimeInterval(3 * 86400), lastAttempt: now), "wake catches up with one refresh")
    check(ResetAnnouncementSchedule.isDue(now: now.addingTimeInterval(-3600), lastAttempt: now), "clock rollback does not suppress refresh")
    check(ResetAnnouncementSchedule.retryDate("120", now: now) == now.addingTimeInterval(120), "numeric retry-after respected")
    check(ResetAnnouncementSchedule.retryDate("Mon, 26 Oct 2026 09:00:00 GMT", now: now) == now.addingTimeInterval(3600), "HTTP date retry-after respected")
    check(ResetAnnouncementSchedule.retryDate("invalid", now: now) == nil, "invalid retry-after ignored")
    do {
      _ = try ResetAnnouncementFeed.decode(Data(#"{"schemaVersion":2,"events":[]}"#.utf8))
      check(false, "unsupported feed schema rejected")
    } catch { check(true, "unsupported feed schema rejected") }
  } catch {
    check(false, "reset announcement fixture: \(error)")
  }
}
