import CodexMeterCore
import Foundation

// Valid single-segment Zstandard frames with raw blocks; tests need no compressor.
func rawZstandardFrame(_ data: Data) -> Data {
  var result = Data([0x28, 0xb5, 0x2f, 0xfd, 0xa0])
  let size = UInt32(data.count)
  for shift in stride(from: 0, to: 32, by: 8) { result.append(UInt8(truncatingIfNeeded: size >> shift)) }
  var offset = 0
  repeat {
    let length = min(128 * 1024, data.count - offset)
    let last = offset + length == data.count
    let header = UInt32(length << 3) | (last ? 1 : 0)
    for shift in stride(from: 0, to: 24, by: 8) { result.append(UInt8(truncatingIfNeeded: header >> shift)) }
    result.append(data[offset..<(offset + length)])
    offset += length
  } while offset < data.count
  return result
}

func runCompressedHistoryChecks(_ check: (Bool, String) -> Void) throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompressedHistory-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let logs = root.appendingPathComponent("sessions")
  try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
  let file = logs.appendingPathComponent("rollout-history.jsonl.zst")
  let line = Data(#"{"timestamp":"2026-07-01T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":800,"output_tokens":100,"total_tokens":1000}}}}"#.utf8) + Data([10])
  try rawZstandardFrame(line).write(to: file)
  let indexer = UsageLogIndexer(configuration: .init(sessionRoots: [logs], indexURL: root.appendingPathComponent("index.json"), timeZoneIdentifier: "Asia/Shanghai"))
  _ = try indexer.refresh(isIndexing: false)
  check(indexer.hasPendingArchiveWork, "compressed history must not disappear from discovery")
  func drain(_ target: UsageLogIndexer, chunk: Int = 65_536) throws {
    var slices = 0
    while target.hasPendingArchiveWork && slices < 100_000 {
      let result = try target.scanArchiveSlice(maxBytes: chunk)
      check(result.decodedBytes <= min(chunk, 1_048_576), "archive slice respects byte budget")
      slices += 1
    }
    check(!target.hasPendingArchiveWork, "archive work eventually finishes")
  }
  try drain(indexer, chunk: 17)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "compressed token usage recovered across partial lines")
  check(indexer.cachedSnapshot(isIndexing: false).allTimeUsage.cachedInputTokens == 800, "compressed cached input recovered")
  _ = try indexer.refresh(isIndexing: false)
  check(!indexer.hasPendingArchiveWork, "unchanged archives are not decoded again")
  let reload = UsageLogIndexer(configuration: .init(sessionRoots: [logs], indexURL: root.appendingPathComponent("index.json"), timeZoneIdentifier: "Asia/Shanghai"))
  _ = try reload.refresh(isIndexing: false)
  check(!reload.hasPendingArchiveWork && reload.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "compressed signature persists across app restart")

  let plain = logs.appendingPathComponent("rollout-history.jsonl")
  try line.write(to: plain)
  _ = try indexer.refresh(isIndexing: false)
  check(!indexer.hasPendingArchiveWork && indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "plain copy is preferred and not double counted")
  try FileManager.default.removeItem(at: plain)
  _ = try indexer.refresh(isIndexing: false)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "migration retains previous statistics while scanning")
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "migration replaces rather than adds old totals")

  let larger = Data(String(data: line, encoding: .utf8)!.replacingOccurrences(of: "900", with: "1900").replacingOccurrences(of: "1000", with: "2000").utf8)
  try rawZstandardFrame(larger).write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  check(indexer.hasPendingArchiveWork, "replaced compressed file is rescanned")
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 2000, "changed archive updates contribution once")

  try rawZstandardFrame(line).dropLast(8).write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 2000, "truncated archive preserves last valid totals")
  check(indexer.cachedSnapshot(isIndexing: false).historyScanProgress?.failed == 1, "unreadable archive remains visible for retry")
  _ = try indexer.refresh(isIndexing: false)
  check(!indexer.hasPendingArchiveWork, "failed archive backs off instead of spinning")
  try rawZstandardFrame(line).write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "corrected archive is eligible immediately")

  let padded = Data((String(repeating: "{\"type\":\"response_item\",\"payload\":\"ignored\"}\n", count: 40_000)).utf8) + line
  try rawZstandardFrame(padded).write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  let firstSlice = try indexer.scanArchiveSlice(maxBytes: 65_536)
  check(firstSlice.decodedBytes <= 65_536 && firstSlice.hasMoreWork, "large archive yields before completing")
  try indexer.cancelArchiveScan()
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "cancelled scan cannot expose partial totals")
  _ = try indexer.refresh(isIndexing: false)
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 1000, "large bounded streaming archive recovers full totals")

  let second = logs.appendingPathComponent("second.jsonl.zst")
  try (rawZstandardFrame(line) + rawZstandardFrame(larger)).write(to: second)
  _ = try indexer.refresh(isIndexing: false)
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 3000, "concatenated Zstandard frames are decoded")

  let genuine = Data(base64Encoded: "KLUv/QRYTQQAcogbHXC11QFmoF6j0trKjx8F+w2kKgzBWG4D81L6cRcHgRhj/I/SDy1shHRoYqnl8xfSb6FjiZu0IurBpKhtDcESHy+DbSWmAG2b9KGawijnY+QtaZkGqNPqmPXx4c8/0Q3oxeCFwLjhtFvUPl2SdRMJAFkwAMG9yQOsq6escWL1czSgbhACoaIxUjGY")!
  try genuine.write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 3000, "real compressed blocks and frame checksum decode without an external executable")

  var damaged = genuine
  damaged[damaged.count - 1] ^= 1
  try damaged.write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 3000, "checksum error does not commit partial output")

  // Single-segment frames advertise a window equal to their content size.
  var excessiveWindow = Data([0x28, 0xb5, 0x2f, 0xfd, 0xa0])
  for shift in stride(from: 0, to: 32, by: 8) { excessiveWindow.append(UInt8(truncatingIfNeeded: UInt32(16 * 1024 * 1024) >> shift)) }
  for block in 0..<128 {
    let header = UInt32((128 * 1024) << 3) | 2 | (block == 127 ? 1 : 0)
    for shift in stride(from: 0, to: 24, by: 8) { excessiveWindow.append(UInt8(truncatingIfNeeded: header >> shift)) }
    excessiveWindow.append(0) // RLE block: valid 16 MiB output without a large fixture.
  }
  try excessiveWindow.write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 3000, "excessive decoder window fails safely within memory limit")

  var skippable = Data([0x50, 0x2a, 0x4d, 0x18])
  let skippedLength = UInt32(512 * 1024)
  for shift in stride(from: 0, to: 32, by: 8) { skippable.append(UInt8(truncatingIfNeeded: skippedLength >> shift)) }
  skippable.append(Data(count: Int(skippedLength)))
  skippable.append(genuine)
  try skippable.write(to: file, options: .atomic)
  _ = try indexer.refresh(isIndexing: false)
  let skipSlice = try indexer.scanArchiveSlice()
  check(skipSlice.decodedBytes == 0 && skipSlice.hasMoreWork, "non-output compressed frames yield after bounded input I/O")
  try drain(indexer)
  check(indexer.cachedSnapshot(isIndexing: false).allTimeTotal == 3000, "streaming skips metadata frames without changing usage")
}

func runStreamingScannerChecks(data: Data, _ check: (Bool, String) -> Void) {
  func apply(_ scan: JSONLTokenScanResult, accumulator: inout SessionUsageAccumulator, buckets: inout UsageBuckets) {
    if scan.historyWasReset { accumulator = SessionUsageAccumulator(); buckets = UsageBuckets() }
    if accumulator.lastUsage == nil, let initial = scan.initialUsage { accumulator = SessionUsageAccumulator(lastUsage: initial) }
    for event in scan.events {
      if let usage = event.usage { buckets.add(usage: accumulator.consume(usage: usage), model: event.model, at: event.timestamp) }
    }
  }
  var expectedAccumulator = SessionUsageAccumulator()
  var expectedBuckets = UsageBuckets()
  apply(JSONLTokenScanner.scan(data: data), accumulator: &expectedAccumulator, buckets: &expectedBuckets)
  for chunkSize in [1, 13, 4096, 65536] {
    let stream = JSONLTokenScanner.Stream()
    var accumulator = SessionUsageAccumulator()
    var buckets = UsageBuckets()
    for offset in stride(from: 0, to: data.count, by: chunkSize) {
      apply(stream.consume(data[offset..<min(data.count, offset + chunkSize)]), accumulator: &accumulator, buckets: &buckets)
    }
    check(buckets == expectedBuckets, "streaming scanner preserves fork, model and incomplete line semantics at chunk size \(chunkSize)")
  }
}
