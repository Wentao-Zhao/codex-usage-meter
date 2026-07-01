import CodexMeterCore
import Foundation

private var checks = 0

private func check(
  _ condition: @autoclosure () -> Bool,
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  checks += 1
  guard condition() else {
    fputs("FAIL: \(message) (\(file):\(line))\n", stderr)
    exit(1)
  }
}

private func isoDate(_ value: String) -> Date {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  guard let date = formatter.date(from: value) else {
    fatalError("Invalid fixture date: \(value)")
  }
  return date
}

check(RateLimitPolicy.color(remainingPercent: 70, isStale: false) == .green, "70% green")
check(RateLimitPolicy.color(remainingPercent: 30, isStale: false) == .yellow, "30% yellow")
check(RateLimitPolicy.color(remainingPercent: 10, isStale: false) == .orange, "10% orange")
check(RateLimitPolicy.color(remainingPercent: 9.99, isStale: false) == .red, "below 10% red")
check(RateLimitPolicy.color(remainingPercent: 90, isStale: true) == .unknown, "stale gray")
check(RateLimitPolicy.color(remainingPercent: nil, isStale: false) == .unknown, "missing gray")
check(StatusLightLayout.activeIndex(for: .red) == 0, "red lights left status lamp")
check(StatusLightLayout.activeIndex(for: .yellow) == 1, "yellow lights middle status lamp")
check(StatusLightLayout.activeIndex(for: .orange) == 1, "orange lights middle status lamp")
check(StatusLightLayout.activeIndex(for: .green) == 2, "green lights right status lamp")
check(StatusLightLayout.activeIndex(for: .unknown) == nil, "unknown does not light status lamp")
let iconMetrics = StatusLightLayout.menuBarIconMetrics
check(iconMetrics.canvasSize == 18, "status icon keeps standard menu bar canvas")
check(iconMetrics.capsuleX == 1.2, "status icon capsule expands horizontally")
check(iconMetrics.capsuleWidth == 15.6, "status icon capsule width is larger")
check(iconMetrics.capsuleHeight == 8.2, "status icon capsule height is larger")
check(iconMetrics.lampRadius == 1.7, "status icon lamps are larger")
check(iconMetrics.lampCenterXValues == [4.95, 9, 13.05], "status icon lamp centers stay balanced")

let fixtureLine = Data(#"{"timestamp":"2026-07-01T01:02:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1250}},"rate_limits":{"primary":{"used_percent":24.0,"window_minutes":300,"resets_at":1782879000},"secondary":{"used_percent":36.0,"window_minutes":10080,"resets_at":1783300000}}}}"#.utf8)
let parsedEvent = TokenEventParser.parse(line: fixtureLine)
check(parsedEvent?.totalTokens == 1_250, "parse total tokens")
check(parsedEvent?.primary?.windowMinutes == 300, "parse five-hour window")
check(parsedEvent?.primary?.usedPercent == 24, "parse primary usage")
check(parsedEvent?.secondary?.windowMinutes == 10_080, "parse weekly window")
check(TokenEventParser.parse(line: Data("not json".utf8)) == nil, "skip malformed JSON")
check(TokenEventParser.parse(line: Data(#"{"type":"event_msg","payload":{"type":"other"}}"#.utf8)) == nil, "skip other events")

var accumulator = SessionUsageAccumulator()
check(accumulator.consume(totalTokens: 100) == 100, "first counter")
check(accumulator.consume(totalTokens: 140) == 40, "counter delta")
check(accumulator.consume(totalTokens: 140) == 0, "duplicate counter")
check(accumulator.consume(totalTokens: 20) == 20, "counter reset")

var buckets = UsageBuckets(timeZoneIdentifier: "Asia/Shanghai")
buckets.add(tokens: 120, at: isoDate("2026-07-01T01:10:00.000Z"))
buckets.add(tokens: 80, at: isoDate("2026-07-01T02:10:00.000Z"))
buckets.add(tokens: 50, at: isoDate("2026-06-30T01:10:00.000Z"))
let bucketSnapshot = buckets.snapshot(now: isoDate("2026-07-01T03:00:00.000Z"))
check(bucketSnapshot.todayTotal == 200, "today total")
check(bucketSnapshot.weekTotal == 250, "week total starts Monday")
check(bucketSnapshot.allTimeTotal == 250, "all-time total")
check(bucketSnapshot.hourly.count == 24, "24 hour series")
check(bucketSnapshot.hourly[9] == 120 && bucketSnapshot.hourly[10] == 80, "local hourly buckets")
check(bucketSnapshot.weekly.count == 7, "seven day series")
check(bucketSnapshot.monthly.reduce(0, +) == 250, "monthly series")

let countdownNow = isoDate("2026-07-01T03:00:00.000Z")
let fiveHourWindow = RateLimitWindow(
  usedPercent: 24,
  windowMinutes: 300,
  resetsAt: countdownNow.addingTimeInterval(128 * 60)
)
let weekWindow = RateLimitWindow(
  usedPercent: 36,
  windowMinutes: 10_080,
  resetsAt: countdownNow.addingTimeInterval((2 * 86_400) + 3_600)
)
check(RateLimitPolicy.remainingPercent(for: fiveHourWindow) == 76, "remaining percentage")
check(RateLimitPolicy.minutesUntilReset(fiveHourWindow, now: countdownNow) == 128, "minute countdown")
check(RateLimitPolicy.daysUntilReset(weekWindow, now: countdownNow) == 3, "day countdown rounds up")
check(RateLimitPolicy.isStale(fiveHourWindow, now: fiveHourWindow.resetsAt) == true, "window stale at reset")
let plainCount = TokenCountFormatter.string(from: 999)
let thousandCount = TokenCountFormatter.string(from: 1_200)
let millionCount = TokenCountFormatter.string(from: 2_840_000)
check(plainCount == "999", "plain token count: \(plainCount)")
check(thousandCount == "1.2K", "thousand token count: \(thousandCount)")
check(millionCount == "2.84M", "million token count: \(millionCount)")

var firstSessionBuckets = UsageBuckets(timeZoneIdentifier: "Asia/Shanghai")
firstSessionBuckets.add(tokens: 120, at: countdownNow)
var secondSessionBuckets = UsageBuckets(timeZoneIdentifier: "Asia/Shanghai")
secondSessionBuckets.add(tokens: 80, at: countdownNow)

let olderRateEvent = TokenUsageEvent(
  timestamp: countdownNow,
  totalTokens: 120,
  primary: fiveHourWindow,
  secondary: weekWindow
)
let newerRateEvent = TokenUsageEvent(
  timestamp: countdownNow.addingTimeInterval(60),
  totalTokens: 80,
  primary: RateLimitWindow(
    usedPercent: 40,
    windowMinutes: 300,
    resetsAt: countdownNow.addingTimeInterval(180 * 60)
  ),
  secondary: weekWindow
)

let firstSession = SessionUsageIndex(
  sessionID: "first",
  path: "/tmp/first.jsonl",
  fileIdentity: "inode-1",
  parsedBytes: 100,
  accumulator: SessionUsageAccumulator(lastTotalTokens: 120),
  buckets: firstSessionBuckets,
  latestRateLimit: olderRateEvent
)
let secondSession = SessionUsageIndex(
  sessionID: "second",
  path: "/tmp/second.jsonl",
  fileIdentity: "inode-2",
  parsedBytes: 80,
  accumulator: SessionUsageAccumulator(lastTotalTokens: 80),
  buckets: secondSessionBuckets,
  latestRateLimit: newerRateEvent
)

var usageIndex = UsageIndex(timeZoneIdentifier: "Asia/Shanghai")
usageIndex.upsert(firstSession)
usageIndex.upsert(secondSession)
let mergedSnapshot = usageIndex.snapshot(now: countdownNow, isIndexing: false)
check(mergedSnapshot.todayTotal == 200, "merge session contributions")
check(mergedSnapshot.primary?.usedPercent == 40, "select newest rate limit")
check(mergedSnapshot.statusColor == .yellow, "snapshot derives current status color")

let encodedIndex = try JSONEncoder().encode(usageIndex)
let decodedIndex = try JSONDecoder().decode(UsageIndex.self, from: encodedIndex)
check(decodedIndex == usageIndex, "index JSON round trip")

usageIndex.removeSession(id: "second")
check(usageIndex.snapshot(now: countdownNow, isIndexing: false).todayTotal == 120, "remove session contribution")

let secondFixtureLine = Data(
  String(data: fixtureLine, encoding: .utf8)!
    .replacingOccurrences(of: "\"total_tokens\":1250", with: "\"total_tokens\":1300")
    .utf8
)
let longNonTokenLine = Data(
  ("{\"type\":\"response_item\",\"payload\":\"" + String(repeating: "x", count: 10_000) + "\"}\n").utf8
)
var completeScanData = Data()
completeScanData.append(fixtureLine)
completeScanData.append(0x0A)
completeScanData.append(longNonTokenLine)
completeScanData.append(secondFixtureLine)
completeScanData.append(0x0A)
var scanFixture = completeScanData
scanFixture.append(Data("{\"timestamp\":\"2026-07-01T03:00:00.000Z\",\"type\":\"event_msg\"".utf8))

let scanResult = JSONLTokenScanner.scan(data: scanFixture, startingOffset: 42)
check(scanResult.events.count == 2, "scan token events only")
check(scanResult.events.last?.totalTokens == 1_300, "scan second token event")
check(scanResult.committedOffset == UInt64(42 + completeScanData.count), "retain incomplete tail")

func tokenLine(total: Int64, timestamp: String) -> Data {
  Data(#"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\#(total)}},"rate_limits":{"primary":{"used_percent":20.0,"window_minutes":300,"resets_at":1782879000},"secondary":{"used_percent":30.0,"window_minutes":10080,"resets_at":1783300000}}}}"#.utf8)
}

func completeLine(_ data: Data) -> Data {
  var value = data
  value.append(0x0A)
  return value
}

let integrationRoot = FileManager.default.temporaryDirectory
  .appendingPathComponent("CodexMeterTests-\(UUID().uuidString)", isDirectory: true)
let activeRoot = integrationRoot.appendingPathComponent("sessions", isDirectory: true)
let archiveRoot = integrationRoot.appendingPathComponent("archived_sessions", isDirectory: true)
let indexURL = integrationRoot.appendingPathComponent("usage-index.json")
try FileManager.default.createDirectory(at: activeRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: integrationRoot) }

let sessionFileName = "rollout-2026-07-01T09-00-00-session-a.jsonl"
let activeSessionURL = activeRoot.appendingPathComponent(sessionFileName)
var initialSessionData = completeLine(tokenLine(total: 1_250, timestamp: "2026-07-01T01:02:03.000Z"))
initialSessionData.append(completeLine(tokenLine(total: 1_300, timestamp: "2026-07-01T01:03:03.000Z")))
try initialSessionData.write(to: activeSessionURL)

let indexerConfiguration = UsageLogIndexer.Configuration(
  sessionRoots: [activeRoot, archiveRoot],
  indexURL: indexURL,
  timeZoneIdentifier: "Asia/Shanghai"
)
let integrationNow = isoDate("2026-07-01T03:00:00.000Z")
let usageLogIndexer = UsageLogIndexer(configuration: indexerConfiguration)
let initialIndexedSnapshot = try usageLogIndexer.refresh(now: integrationNow, isIndexing: false)
check(initialIndexedSnapshot.todayTotal == 1_300, "initial file indexing")

let archivedSessionURL = archiveRoot.appendingPathComponent(sessionFileName)
try FileManager.default.moveItem(at: activeSessionURL, to: archivedSessionURL)
let movedSnapshot = try usageLogIndexer.refresh(now: integrationNow, isIndexing: false)
check(movedSnapshot.todayTotal == 1_300, "moving to archive does not duplicate")

let appendHandle = try FileHandle(forWritingTo: archivedSessionURL)
try appendHandle.seekToEnd()
try appendHandle.write(contentsOf: completeLine(tokenLine(total: 1_400, timestamp: "2026-07-01T01:04:03.000Z")))
try appendHandle.close()
let appendedSnapshot = try usageLogIndexer.refresh(now: integrationNow, isIndexing: false)
check(appendedSnapshot.todayTotal == 1_400, "append reads only new delta")

try completeLine(tokenLine(total: 200, timestamp: "2026-07-01T01:05:03.000Z")).write(to: archivedSessionURL)
let rebuiltSnapshot = try usageLogIndexer.refresh(now: integrationNow, isIndexing: false)
check(rebuiltSnapshot.todayTotal == 200, "truncation rebuilds session contribution")

let reloadedIndexer = UsageLogIndexer(configuration: indexerConfiguration)
let reloadedSnapshot = try reloadedIndexer.refresh(now: integrationNow, isIndexing: false)
check(reloadedSnapshot.todayTotal == 200, "reload persisted index")

let debounceQueue = DispatchQueue(label: "CodexMeterTests.debounce")
let debounceSignal = DispatchSemaphore(value: 0)
let debounceLock = NSLock()
var debounceFireCount = 0
let refreshCoalescer = RefreshCoalescer(queue: debounceQueue, delay: 0.05) {
  debounceLock.lock()
  debounceFireCount += 1
  debounceLock.unlock()
  debounceSignal.signal()
}
refreshCoalescer.schedule()
refreshCoalescer.schedule()
refreshCoalescer.schedule()
check(debounceSignal.wait(timeout: .now() + 1) == .success, "debounced refresh fires")
Thread.sleep(forTimeInterval: 0.1)
debounceLock.lock()
let finalDebounceCount = debounceFireCount
debounceLock.unlock()
check(finalDebounceCount == 1, "directory events coalesce into one refresh")

check(SparklineGeometry.points(values: []).isEmpty, "empty sparkline")
let singleSparklinePoint = SparklineGeometry.points(values: [8])
check(singleSparklinePoint == [SparklinePoint(x: 0.5, y: 0.5)], "single sparkline point centered")
let twoSparklinePoints = SparklineGeometry.points(values: [0, 10])
check(twoSparklinePoints == [
  SparklinePoint(x: 0, y: 0),
  SparklinePoint(x: 1, y: 1),
], "sparkline normalized range")

let eventMonitorRoot = integrationRoot.appendingPathComponent("event-monitor", isDirectory: true)
try FileManager.default.createDirectory(at: eventMonitorRoot, withIntermediateDirectories: true)
let eventMonitorSignal = DispatchSemaphore(value: 0)
let directoryMonitor = UsageDirectoryMonitor(
  paths: [eventMonitorRoot],
  debounceDelay: 0.05
) {
  eventMonitorSignal.signal()
}
directoryMonitor.start()
Thread.sleep(forTimeInterval: 0.2)
try Data("event".utf8).write(to: eventMonitorRoot.appendingPathComponent("change.jsonl"))
check(eventMonitorSignal.wait(timeout: .now() + 3) == .success, "FSEvents observes directory change")
directoryMonitor.stop()

print("PASS: \(checks) checks")
