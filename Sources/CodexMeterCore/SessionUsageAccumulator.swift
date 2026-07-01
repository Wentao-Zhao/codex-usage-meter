import Foundation

public struct SessionUsageAccumulator: Codable, Equatable, Sendable {
  public private(set) var lastTotalTokens: Int64?

  public init(lastTotalTokens: Int64? = nil) {
    self.lastTotalTokens = lastTotalTokens
  }

  public mutating func consume(totalTokens: Int64) -> Int64 {
    defer { lastTotalTokens = totalTokens }

    guard let previous = lastTotalTokens else {
      return max(0, totalTokens)
    }
    guard totalTokens >= previous else {
      return max(0, totalTokens)
    }
    return totalTokens - previous
  }
}
