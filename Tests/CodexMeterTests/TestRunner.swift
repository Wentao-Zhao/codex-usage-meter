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

let fixtureLine = Data(#"{"timestamp":"2026-07-01T01:02:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1100,"cached_input_tokens":800,"output_tokens":150,"total_tokens":1250}},"rate_limits":{"primary":{"used_percent":24.0,"window_minutes":300,"resets_at":1782879000},"secondary":{"used_percent":36.0,"window_minutes":10080,"resets_at":1783300000}}}}"#.utf8)
let parsedEvent = TokenEventParser.parse(line: fixtureLine, model: "gpt-5.4")
check(parsedEvent?.totalTokens == 1_250, "parse total tokens")
check(parsedEvent?.usage?.inputTokens == 1_100, "parse input tokens")
check(parsedEvent?.usage?.cachedInputTokens == 800, "parse cached input tokens")
check(parsedEvent?.usage?.uncachedInputTokens == 300, "derive uncached input tokens")
check(parsedEvent?.usage?.outputTokens == 150, "parse output tokens")
check(parsedEvent?.model == "gpt-5.4", "attach active model to token event")
let fixtureCredits = CodexCreditCalculator.credits(
  for: parsedEvent!.usage!,
  model: parsedEvent!.model
)
check(abs(fixtureCredits - 0.08) < 0.000_001, "calculate official gpt-5.4 credit weighting")
check(parsedEvent?.primary?.windowMinutes == 300, "parse five-hour window")
check(parsedEvent?.primary?.usedPercent == 24, "parse primary usage")
check(parsedEvent?.secondary?.windowMinutes == 10_080, "parse weekly window")
check(parsedEvent?.resolvedRateLimits.fiveHour == parsedEvent?.primary, "resolve five-hour window by duration")
check(parsedEvent?.resolvedRateLimits.weekly == parsedEvent?.secondary, "resolve weekly window by duration")
check(TokenEventParser.parse(line: Data("not json".utf8)) == nil, "skip malformed JSON")
check(TokenEventParser.parse(line: Data(#"{"type":"event_msg","payload":{"type":"other"}}"#.utf8)) == nil, "skip other events")

let weeklyOnlyFixtureLine = Data(#"{"timestamp":"2026-07-13T06:09:48.277Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":261660508}},"rate_limits":{"primary":{"used_percent":16.0,"window_minutes":10080,"resets_at":1784509654},"secondary":null}}}"#.utf8)
let weeklyOnlyEvent = TokenEventParser.parse(line: weeklyOnlyFixtureLine)
check(weeklyOnlyEvent?.resolvedRateLimits.fiveHour == nil, "weekly-only payload has no five-hour limit")
check(weeklyOnlyEvent?.resolvedRateLimits.weekly?.usedPercent == 16, "resolve weekly limit when it moves to primary")
check(weeklyOnlyEvent?.resolvedRateLimits.statusKind == .weekly, "weekly limit drives status when five-hour limit is absent")

var accumulator = SessionUsageAccumulator()
check(accumulator.consume(totalTokens: 100) == 100, "first counter")
check(accumulator.consume(totalTokens: 140) == 40, "counter delta")
check(accumulator.consume(totalTokens: 140) == 0, "duplicate counter")
check(accumulator.consume(totalTokens: 20) == 20, "counter reset")

var detailedAccumulator = SessionUsageAccumulator()
let firstUsageDelta = detailedAccumulator.consume(
  usage: TokenUsage(inputTokens: 1_100, cachedInputTokens: 800, outputTokens: 150, totalTokens: 1_250)
)
check(firstUsageDelta.totalTokens == 1_250, "first detailed counter")
let secondUsageDelta = detailedAccumulator.consume(
  usage: TokenUsage(inputTokens: 1_300, cachedInputTokens: 920, outputTokens: 190, totalTokens: 1_490)
)
check(secondUsageDelta.inputTokens == 200, "input counter delta")
check(secondUsageDelta.cachedInputTokens == 120, "cached input counter delta")
check(secondUsageDelta.outputTokens == 40, "output counter delta")
check(secondUsageDelta.totalTokens == 240, "total counter delta")

var evolvingAccumulator = SessionUsageAccumulator()
_ = evolvingAccumulator.consume(totalTokens: 100)
let newlyDetailedDelta = evolvingAccumulator.consume(
  usage: TokenUsage(inputTokens: 90, cachedInputTokens: 50, outputTokens: 10, totalTokens: 100)
)
check(newlyDetailedDelta == .zero, "new breakdown fields do not create usage without total delta")

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

var detailedBuckets = UsageBuckets(timeZoneIdentifier: "Asia/Shanghai")
detailedBuckets.add(
  usage: TokenUsage(inputTokens: 1_100, cachedInputTokens: 800, outputTokens: 150, totalTokens: 1_250),
  model: "gpt-5.4",
  at: isoDate("2026-07-01T01:10:00.000Z")
)
let detailedBucketSnapshot = detailedBuckets.snapshot(now: isoDate("2026-07-01T03:00:00.000Z"))
check(detailedBucketSnapshot.allTimeUsage.uncachedInputTokens == 300, "bucket uncached input")
check(detailedBucketSnapshot.allTimeUsage.cachedInputTokens == 800, "bucket cached input")
check(detailedBucketSnapshot.allTimeUsage.outputTokens == 150, "bucket output")
check(abs(detailedBucketSnapshot.allTimeCredits - 0.08) < 0.000_001, "bucket official credits")

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
check(mergedSnapshot.fiveHourLimit?.usedPercent == 40, "select newest five-hour limit")
check(mergedSnapshot.weeklyLimit == weekWindow, "select weekly limit")
check(mergedSnapshot.statusLimitKind == .fiveHour, "five-hour limit keeps status priority")
check(mergedSnapshot.statusColor == .yellow, "snapshot derives current status color")

let weeklyOnlySession = SessionUsageIndex(
  sessionID: "weekly-only",
  path: "/tmp/weekly-only.jsonl",
  fileIdentity: "inode-3",
  parsedBytes: 90,
  accumulator: SessionUsageAccumulator(lastTotalTokens: 90),
  buckets: UsageBuckets(timeZoneIdentifier: "Asia/Shanghai"),
  latestRateLimit: TokenUsageEvent(
    timestamp: countdownNow.addingTimeInterval(120),
    totalTokens: 90,
    primary: RateLimitWindow(
      usedPercent: 75,
      windowMinutes: 10_080,
      resetsAt: countdownNow.addingTimeInterval(3 * 86_400)
    ),
    secondary: nil
  )
)
var weeklyOnlyIndex = UsageIndex(timeZoneIdentifier: "Asia/Shanghai")
weeklyOnlyIndex.upsert(weeklyOnlySession)
let weeklyOnlySnapshot = weeklyOnlyIndex.snapshot(now: countdownNow, isIndexing: false)
check(weeklyOnlySnapshot.fiveHourLimit == nil, "snapshot omits unavailable five-hour limit")
check(weeklyOnlySnapshot.weeklyLimit?.usedPercent == 75, "snapshot exposes weekly-only limit")
check(weeklyOnlySnapshot.statusLimitKind == .weekly, "snapshot uses weekly status fallback")
check(weeklyOnlySnapshot.statusColor == .orange, "weekly remaining percentage drives status color")

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

let forkRoot = integrationRoot.appendingPathComponent("forked-sessions", isDirectory: true)
let forkIndexURL = integrationRoot.appendingPathComponent("forked-usage-index.json")
try FileManager.default.createDirectory(at: forkRoot, withIntermediateDirectories: true)
let forkSessionURL = forkRoot.appendingPathComponent(
  "rollout-2026-07-01T11-00-00-019f0000-1000-7000-8000-000000000001.jsonl"
)
let forkLines = [
  #"{"timestamp":"2026-07-01T03:00:00.000Z","type":"session_meta","payload":{"id":"019f0000-1000-7000-8000-000000000001","session_id":"019e0000-1000-7000-8000-000000000001","forked_from_id":"019e0000-1000-7000-8000-000000000001","thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"019e0000-1000-7000-8000-000000000001"}}}}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.001Z","type":"session_meta","payload":{"id":"019e0000-1000-7000-8000-000000000001","session_id":"019e0000-1000-7000-8000-000000000001","source":"vscode"}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.002Z","type":"event_msg","payload":{"type":"task_started","turn_id":"019e0000-2000-7000-8000-000000000001","started_at":1782870000}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.003Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.004Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":800,"output_tokens":100,"total_tokens":1000}}}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.005Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1050,"cached_input_tokens":900,"output_tokens":150,"total_tokens":1200}}}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.005Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":20.0,"window_minutes":300,"resets_at":1782879000}}}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.005Z","type":"event_msg","payload":{"type":"task_started","turn_id":"019f0000-2000-7000-8000-000000000001","started_at":1782874800}}"#,
  #"{"timestamp":"2026-07-01T03:00:00.006Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
  #"{"timestamp":"2026-07-01T03:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1050,"cached_input_tokens":900,"output_tokens":150,"total_tokens":1200}}}}"#,
  #"{"timestamp":"2026-07-01T03:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1130,"cached_input_tokens":940,"output_tokens":170,"total_tokens":1300}}}}"#,
]
try Data((forkLines.joined(separator: "\n") + "\n").utf8).write(to: forkSessionURL)
let forkIndexer = UsageLogIndexer(
  configuration: .init(
    sessionRoots: [forkRoot],
    indexURL: forkIndexURL,
    timeZoneIdentifier: "Asia/Shanghai"
  )
)
let forkSnapshot = try forkIndexer.refresh(now: integrationNow, isIndexing: false)
check(forkSnapshot.todayTotal == 100, "forked session excludes copied parent history")
check(forkSnapshot.allTimeUsage.uncachedInputTokens == 40, "forked session input delta")
check(forkSnapshot.allTimeUsage.cachedInputTokens == 40, "forked session cached input delta")
check(forkSnapshot.allTimeUsage.outputTokens == 20, "forked session output delta")
check(abs(forkSnapshot.allTimeCredits - 0.01025) < 0.000_001, "forked session credit delta")

let incrementalModelRoot = integrationRoot.appendingPathComponent(
  "incremental-model-sessions",
  isDirectory: true
)
try FileManager.default.createDirectory(
  at: incrementalModelRoot,
  withIntermediateDirectories: true
)
let incrementalModelURL = incrementalModelRoot.appendingPathComponent(
  "rollout-2026-07-01T12-00-00-model-session.jsonl"
)
let modelContextLine = Data(
  #"{"timestamp":"2026-07-01T04:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}"#.utf8
)
func detailedTokenLine(
  input: Int64,
  cached: Int64,
  output: Int64,
  total: Int64,
  timestamp: String
) -> Data {
  Data(#"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"total_tokens":\#(total)}}}}"#.utf8)
}
var incrementalModelData = completeLine(modelContextLine)
incrementalModelData.append(
  completeLine(
    detailedTokenLine(
      input: 80,
      cached: 40,
      output: 20,
      total: 100,
      timestamp: "2026-07-01T04:00:01.000Z"
    )
  )
)
try incrementalModelData.write(to: incrementalModelURL)
let incrementalModelConfiguration = UsageLogIndexer.Configuration(
  sessionRoots: [incrementalModelRoot],
  indexURL: integrationRoot.appendingPathComponent("incremental-model-index.json"),
  timeZoneIdentifier: "Asia/Shanghai"
)
let incrementalModelIndexer = UsageLogIndexer(configuration: incrementalModelConfiguration)
_ = try incrementalModelIndexer.refresh(now: integrationNow, isIndexing: false)
let incrementalModelHandle = try FileHandle(forWritingTo: incrementalModelURL)
try incrementalModelHandle.seekToEnd()
try incrementalModelHandle.write(
  contentsOf: completeLine(
    detailedTokenLine(
      input: 160,
      cached: 80,
      output: 40,
      total: 200,
      timestamp: "2026-07-01T04:00:02.000Z"
    )
  )
)
try incrementalModelHandle.close()
let reloadedIncrementalModelIndexer = UsageLogIndexer(
  configuration: incrementalModelConfiguration
)
let incrementalModelSnapshot = try reloadedIncrementalModelIndexer.refresh(
  now: integrationNow,
  isIndexing: false
)
check(
  abs(incrementalModelSnapshot.allTimeCredits - 0.0082) < 0.000_001,
  "incremental scan retains active model rate"
)

let stagedForkRoot = integrationRoot.appendingPathComponent("staged-fork-sessions", isDirectory: true)
try FileManager.default.createDirectory(at: stagedForkRoot, withIntermediateDirectories: true)
let stagedForkURL = stagedForkRoot.appendingPathComponent(
  "rollout-2026-07-01T13-00-00-019f0000-3000-7000-8000-000000000001.jsonl"
)
let stagedForkHead = forkLines[0] + "\n"
try Data(stagedForkHead.utf8).write(to: stagedForkURL)
let stagedForkConfiguration = UsageLogIndexer.Configuration(
  sessionRoots: [stagedForkRoot],
  indexURL: integrationRoot.appendingPathComponent("staged-fork-index.json"),
  timeZoneIdentifier: "Asia/Shanghai"
)
let stagedForkIndexer = UsageLogIndexer(configuration: stagedForkConfiguration)
_ = try stagedForkIndexer.refresh(now: integrationNow, isIndexing: false)
let stagedForkHandle = try FileHandle(forWritingTo: stagedForkURL)
try stagedForkHandle.seekToEnd()
try stagedForkHandle.write(
  contentsOf: Data((forkLines.dropFirst().joined(separator: "\n") + "\n").utf8)
)
try stagedForkHandle.close()
let reloadedStagedForkIndexer = UsageLogIndexer(configuration: stagedForkConfiguration)
let stagedForkSnapshot = try reloadedStagedForkIndexer.refresh(
  now: integrationNow,
  isIndexing: false
)
check(stagedForkSnapshot.todayTotal == 100, "staged fork scan excludes copied parent history")

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
