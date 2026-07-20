import Foundation

public struct JSONLTokenScanContext: Codable, Equatable, Sendable {
  public let sawInitialSessionMetadata: Bool
  public let forkSessionStartedAt: TimeInterval?
  public let forkSessionID: String?
  public let isSkippingForkHistory: Bool
  public let forkBaselineUsage: TokenUsage?
  public let currentModel: String?

  public init(
    sawInitialSessionMetadata: Bool = false,
    forkSessionStartedAt: TimeInterval? = nil,
    forkSessionID: String? = nil,
    isSkippingForkHistory: Bool = false,
    forkBaselineUsage: TokenUsage? = nil,
    currentModel: String? = nil
  ) {
    self.sawInitialSessionMetadata = sawInitialSessionMetadata
    self.forkSessionStartedAt = forkSessionStartedAt
    self.forkSessionID = forkSessionID
    self.isSkippingForkHistory = isSkippingForkHistory
    self.forkBaselineUsage = forkBaselineUsage
    self.currentModel = currentModel
  }
}

public struct JSONLTokenScanResult: Equatable, Sendable {
  public let events: [TokenUsageEvent]
  public let committedOffset: UInt64
  public let initialUsage: TokenUsage?
  public let context: JSONLTokenScanContext
}

public enum JSONLTokenScanner {
  private static let tokenMarker = Data(#""type":"token_count""#.utf8)
  private static let sessionMarker = Data(#""type":"session_meta""#.utf8)
  private static let taskStartedMarker = Data(#""type":"task_started""#.utf8)
  private static let turnContextMarker = Data(#""type":"turn_context""#.utf8)
  private static let markers = [tokenMarker, sessionMarker, taskStartedMarker, turnContextMarker]
  private static let prefixLimit = 4 * 1_024
  private static let candidateLineLimit = 256 * 1_024
  private static let readChunkSize = 64 * 1_024

  public static func scan(
    data: Data,
    startingOffset: UInt64 = 0,
    context: JSONLTokenScanContext = JSONLTokenScanContext()
  ) -> JSONLTokenScanResult {
    var state = ScanState(startingOffset: startingOffset, context: context)
    state.consume(data)
    return state.result
  }

  public static func scan(
    fileURL: URL,
    fromOffset: UInt64,
    context: JSONLTokenScanContext = JSONLTokenScanContext()
  ) throws -> JSONLTokenScanResult {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    try handle.seek(toOffset: fromOffset)

    var state = ScanState(startingOffset: fromOffset, context: context)
    while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
      state.consume(chunk)
    }
    return state.result
  }

  private struct ScanState {
    private(set) var events: [TokenUsageEvent] = []
    private(set) var committedOffset: UInt64
    private(set) var forkBaselineUsage: TokenUsage?
    private var absoluteOffset: UInt64
    private var lineBuffer = Data()
    private var isSkippingLine = false
    private var isCandidate = false
    private var sawInitialSessionMetadata = false
    private var forkSessionStartedAt: TimeInterval?
    private var forkSessionID: String?
    private var isSkippingForkHistory = false
    private var currentModel: String?

    init(startingOffset: UInt64, context: JSONLTokenScanContext) {
      committedOffset = startingOffset
      absoluteOffset = startingOffset
      sawInitialSessionMetadata = context.sawInitialSessionMetadata
      forkSessionStartedAt = context.forkSessionStartedAt
      forkSessionID = context.forkSessionID
      isSkippingForkHistory = context.isSkippingForkHistory
      forkBaselineUsage = context.forkBaselineUsage
      currentModel = context.currentModel
    }

    var result: JSONLTokenScanResult {
      JSONLTokenScanResult(
        events: events,
        committedOffset: committedOffset,
        initialUsage: isSkippingForkHistory ? nil : forkBaselineUsage,
        context: JSONLTokenScanContext(
          sawInitialSessionMetadata: sawInitialSessionMetadata,
          forkSessionStartedAt: forkSessionStartedAt,
          forkSessionID: forkSessionID,
          isSkippingForkHistory: isSkippingForkHistory,
          forkBaselineUsage: forkBaselineUsage,
          currentModel: currentModel
        )
      )
    }

    mutating func consume(_ data: Data) {
      var cursor = data.startIndex

      while cursor < data.endIndex {
        let remaining = data[cursor..<data.endIndex]
        if let newline = remaining.firstIndex(of: 0x0A) {
          appendSegment(data[cursor..<newline])
          absoluteOffset += UInt64(data.distance(from: cursor, to: newline)) + 1
          finishLine()
          cursor = data.index(after: newline)
        } else {
          appendSegment(remaining)
          absoluteOffset += UInt64(remaining.count)
          break
        }
      }
    }

    private mutating func appendSegment(_ segment: Data.SubSequence) {
      guard !isSkippingLine else {
        return
      }

      lineBuffer.append(contentsOf: segment)
      if !isCandidate, JSONLTokenScanner.markers.contains(where: {
        lineBuffer.range(of: $0) != nil
      }) {
        isCandidate = true
      }

      if isCandidate {
        if lineBuffer.count > JSONLTokenScanner.candidateLineLimit {
          lineBuffer.removeAll(keepingCapacity: false)
          isSkippingLine = true
        }
      } else if lineBuffer.count >= JSONLTokenScanner.prefixLimit {
        lineBuffer.removeAll(keepingCapacity: false)
        isSkippingLine = true
      }
    }

    private mutating func finishLine() {
      if !isSkippingLine, isCandidate {
        if lineBuffer.range(of: JSONLTokenScanner.sessionMarker) != nil {
          consumeSessionMetadata(lineBuffer)
        } else if lineBuffer.range(of: JSONLTokenScanner.taskStartedMarker) != nil {
          consumeTaskStarted(lineBuffer)
        } else if lineBuffer.range(of: JSONLTokenScanner.turnContextMarker) != nil {
          consumeTurnContext(lineBuffer)
        } else if lineBuffer.range(of: JSONLTokenScanner.tokenMarker) != nil,
                  let event = TokenEventParser.parse(line: lineBuffer, model: currentModel) {
          if isSkippingForkHistory {
            if let usage = event.usage {
              forkBaselineUsage = usage
            }
          } else {
            events.append(event)
          }
        }
      }

      lineBuffer.removeAll(keepingCapacity: true)
      isSkippingLine = false
      isCandidate = false
      committedOffset = absoluteOffset
    }

    private mutating func consumeSessionMetadata(_ line: Data) {
      guard
        let object = try? JSONSerialization.jsonObject(with: line),
        let root = object as? [String: Any],
        root["type"] as? String == "session_meta",
        let payload = root["payload"] as? [String: Any]
      else {
        return
      }

      if !sawInitialSessionMetadata {
        sawInitialSessionMetadata = true
        let isFork = payload["forked_from_id"] as? String != nil
          || payload["thread_source"] as? String == "subagent"
          || (payload["source"] as? [String: Any])?["subagent"] != nil
        if isFork, let timestamp = Self.parseTimestamp(root["timestamp"] as? String) {
          forkSessionStartedAt = timestamp.timeIntervalSince1970
          forkSessionID = payload["id"] as? String
        }
        return
      }

      guard forkSessionStartedAt != nil else {
        return
      }
      isSkippingForkHistory = true
      forkBaselineUsage = nil
      currentModel = nil
      events.removeAll(keepingCapacity: true)
    }

    private mutating func consumeTaskStarted(_ line: Data) {
      guard
        isSkippingForkHistory,
        let sessionStartedAt = forkSessionStartedAt,
        let object = try? JSONSerialization.jsonObject(with: line),
        let root = object as? [String: Any],
        let payload = root["payload"] as? [String: Any],
        payload["type"] as? String == "task_started",
        Self.isCurrentForkTask(
          turnID: payload["turn_id"] as? String,
          sessionID: forkSessionID,
          taskStartedAt: (payload["started_at"] as? NSNumber)?.doubleValue,
          sessionStartedAt: sessionStartedAt
        )
      else {
        return
      }

      isSkippingForkHistory = false
      currentModel = nil
    }

    private mutating func consumeTurnContext(_ line: Data) {
      guard
        !isSkippingForkHistory,
        let object = try? JSONSerialization.jsonObject(with: line),
        let root = object as? [String: Any],
        root["type"] as? String == "turn_context",
        let payload = root["payload"] as? [String: Any]
      else {
        return
      }
      currentModel = payload["model"] as? String
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
      guard let value else {
        return nil
      }
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func isCurrentForkTask(
      turnID: String?,
      sessionID: String?,
      taskStartedAt: TimeInterval?,
      sessionStartedAt: TimeInterval
    ) -> Bool {
      if let turnTimestamp = uuidV7Timestamp(turnID),
         let sessionTimestamp = uuidV7Timestamp(sessionID) {
        return turnTimestamp >= sessionTimestamp
      }
      return taskStartedAt.map { $0 >= floor(sessionStartedAt) } ?? false
    }

    private static func uuidV7Timestamp(_ value: String?) -> UInt64? {
      guard let value else {
        return nil
      }
      let compact = value.replacingOccurrences(of: "-", with: "")
      guard compact.count >= 12 else {
        return nil
      }
      return UInt64(compact.prefix(12), radix: 16)
    }
  }
}
