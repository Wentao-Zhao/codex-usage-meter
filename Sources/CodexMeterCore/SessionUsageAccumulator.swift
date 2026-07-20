import Foundation

public struct SessionUsageAccumulator: Codable, Equatable, Sendable {
  public private(set) var lastUsage: TokenUsage?

  public var lastTotalTokens: Int64? {
    lastUsage?.totalTokens
  }

  public init(lastUsage: TokenUsage? = nil) {
    self.lastUsage = lastUsage
  }

  public init(lastTotalTokens: Int64?) {
    self.lastUsage = lastTotalTokens.map(TokenUsage.init(totalTokens:))
  }

  public mutating func consume(totalTokens: Int64) -> Int64 {
    consume(usage: TokenUsage(totalTokens: totalTokens)).totalTokens
  }

  public mutating func consume(usage: TokenUsage) -> TokenUsage {
    defer { lastUsage = usage }

    guard let previous = lastUsage else {
      return usage
    }
    return usage.delta(from: previous)
  }
}
