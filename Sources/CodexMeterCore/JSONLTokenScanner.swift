import Foundation

public struct JSONLTokenScanResult: Equatable, Sendable {
  public let events: [TokenUsageEvent]
  public let committedOffset: UInt64
}

public enum JSONLTokenScanner {
  private static let marker = Data(#""type":"token_count""#.utf8)
  private static let prefixLimit = 4 * 1_024
  private static let candidateLineLimit = 64 * 1_024
  private static let readChunkSize = 64 * 1_024

  public static func scan(data: Data, startingOffset: UInt64 = 0) -> JSONLTokenScanResult {
    var state = ScanState(startingOffset: startingOffset)
    state.consume(data)
    return state.result
  }

  public static func scan(fileURL: URL, fromOffset: UInt64) throws -> JSONLTokenScanResult {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    try handle.seek(toOffset: fromOffset)

    var state = ScanState(startingOffset: fromOffset)
    while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
      state.consume(chunk)
    }
    return state.result
  }

  private struct ScanState {
    private(set) var events: [TokenUsageEvent] = []
    private(set) var committedOffset: UInt64
    private var absoluteOffset: UInt64
    private var lineBuffer = Data()
    private var isSkippingLine = false
    private var isCandidate = false

    init(startingOffset: UInt64) {
      committedOffset = startingOffset
      absoluteOffset = startingOffset
    }

    var result: JSONLTokenScanResult {
      JSONLTokenScanResult(events: events, committedOffset: committedOffset)
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
      if !isCandidate, lineBuffer.range(of: JSONLTokenScanner.marker) != nil {
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
      if !isSkippingLine, isCandidate, let event = TokenEventParser.parse(line: lineBuffer) {
        events.append(event)
      }

      lineBuffer.removeAll(keepingCapacity: true)
      isSkippingLine = false
      isCandidate = false
      committedOffset = absoluteOffset
    }
  }
}
