import Foundation

public enum UsageStatusColor: String, Codable, Equatable, Sendable {
  case green
  case yellow
  case orange
  case red
  case unknown
}

public enum RateLimitKind: String, Codable, Equatable, Sendable {
  case fiveHour
  case weekly
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
  public let usedPercent: Double
  public let windowMinutes: Int
  public let resetsAt: Date

  public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date) {
    self.usedPercent = usedPercent
    self.windowMinutes = windowMinutes
    self.resetsAt = resetsAt
  }
}

public struct TokenUsage: Codable, Equatable, Sendable {
  public static let zero = TokenUsage(
    inputTokens: 0,
    cachedInputTokens: 0,
    outputTokens: 0,
    totalTokens: 0
  )

  public let inputTokens: Int64
  public let cachedInputTokens: Int64
  public let outputTokens: Int64
  public let totalTokens: Int64

  public init(
    inputTokens: Int64,
    cachedInputTokens: Int64,
    outputTokens: Int64,
    totalTokens: Int64
  ) {
    let normalizedCached = max(0, cachedInputTokens)
    let normalizedInput = max(max(0, inputTokens), normalizedCached)
    let normalizedOutput = max(0, outputTokens)
    self.inputTokens = normalizedInput
    self.cachedInputTokens = min(normalizedCached, normalizedInput)
    self.outputTokens = normalizedOutput
    self.totalTokens = max(max(0, totalTokens), normalizedInput + normalizedOutput)
  }

  public init(totalTokens: Int64) {
    self.init(
      inputTokens: max(0, totalTokens),
      cachedInputTokens: 0,
      outputTokens: 0,
      totalTokens: totalTokens
    )
  }

  public var uncachedInputTokens: Int64 {
    max(0, inputTokens - cachedInputTokens)
  }

  public var unclassifiedTokens: Int64 {
    max(0, totalTokens - inputTokens - outputTokens)
  }

  public func adding(_ other: TokenUsage) -> TokenUsage {
    return TokenUsage(
      inputTokens: inputTokens + other.inputTokens,
      cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
      outputTokens: outputTokens + other.outputTokens,
      totalTokens: totalTokens + other.totalTokens
    )
  }

  public func delta(from previous: TokenUsage) -> TokenUsage {
    let totalDelta = Self.counterDelta(current: totalTokens, previous: previous.totalTokens)
    guard totalDelta > 0 else {
      return .zero
    }

    var inputDelta = Self.counterDelta(current: inputTokens, previous: previous.inputTokens)
    var outputDelta = Self.counterDelta(current: outputTokens, previous: previous.outputTokens)
    let classifiedDelta = inputDelta + outputDelta
    if classifiedDelta > totalDelta {
      let inputShare = Double(inputDelta) / Double(classifiedDelta)
      inputDelta = Int64((Double(totalDelta) * inputShare).rounded())
      outputDelta = max(0, totalDelta - inputDelta)
    }

    return TokenUsage(
      inputTokens: inputDelta,
      cachedInputTokens: min(
        inputDelta,
        Self.counterDelta(current: cachedInputTokens, previous: previous.cachedInputTokens)
      ),
      outputTokens: outputDelta,
      totalTokens: totalDelta
    )
  }

  private static func counterDelta(current: Int64, previous: Int64) -> Int64 {
    current >= previous ? current - previous : current
  }
}

public struct TokenUsageEvent: Codable, Equatable, Sendable {
  public let timestamp: Date
  public let usage: TokenUsage?
  public let model: String?
  public let primary: RateLimitWindow?
  public let secondary: RateLimitWindow?

  public var totalTokens: Int64? {
    usage?.totalTokens
  }

  public init(
    timestamp: Date,
    usage: TokenUsage?,
    model: String?,
    primary: RateLimitWindow?,
    secondary: RateLimitWindow?
  ) {
    self.timestamp = timestamp
    self.usage = usage
    self.model = model
    self.primary = primary
    self.secondary = secondary
  }

  public init(
    timestamp: Date,
    totalTokens: Int64?,
    primary: RateLimitWindow?,
    secondary: RateLimitWindow?
  ) {
    self.init(
      timestamp: timestamp,
      usage: totalTokens.map(TokenUsage.init(totalTokens:)),
      model: nil,
      primary: primary,
      secondary: secondary
    )
  }

  public var resolvedRateLimits: ResolvedRateLimits {
    ResolvedRateLimits(windows: [primary, secondary].compactMap { $0 })
  }
}

public struct ResolvedRateLimits: Equatable, Sendable {
  public let fiveHour: RateLimitWindow?
  public let weekly: RateLimitWindow?

  public init(windows: [RateLimitWindow]) {
    fiveHour = windows.first { $0.windowMinutes == 5 * 60 }
    weekly = windows.first { $0.windowMinutes == 7 * 24 * 60 }
  }

  public var statusKind: RateLimitKind? {
    if fiveHour != nil {
      return .fiveHour
    }
    if weekly != nil {
      return .weekly
    }
    return nil
  }

  public var statusWindow: RateLimitWindow? {
    fiveHour ?? weekly
  }
}
