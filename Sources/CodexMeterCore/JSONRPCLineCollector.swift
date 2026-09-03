import Foundation

public struct JSONRPCLineCollector: Sendable {
  private let expectedResponseIDs: Set<Int>
  private var buffer = Data()
  private var responses: [Int: Data] = [:]

  public init(expectedResponseIDs: Set<Int>) {
    self.expectedResponseIDs = expectedResponseIDs
  }

  public var isComplete: Bool {
    expectedResponseIDs.allSatisfy { responses[$0] != nil }
  }

  public mutating func consume(_ data: Data) {
    buffer.append(data)

    while let newline = buffer.firstIndex(of: 0x0A) {
      var line = Data(buffer[..<newline])
      buffer.removeSubrange(...newline)
      if line.last == 0x0D {
        line.removeLast()
      }
      consumeLine(line)
    }
  }

  public func response(for id: Int) -> Data? {
    responses[id]
  }

  private mutating func consumeLine(_ line: Data) {
    guard
      !line.isEmpty,
      let object = try? JSONSerialization.jsonObject(with: line),
      let dictionary = object as? [String: Any],
      let id = (dictionary["id"] as? NSNumber)?.intValue,
      expectedResponseIDs.contains(id)
    else {
      return
    }
    responses[id] = line
  }
}
