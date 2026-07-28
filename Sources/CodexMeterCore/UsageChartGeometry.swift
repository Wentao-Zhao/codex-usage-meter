public struct ComparisonLineGeometry: Equatable, Sendable {
  public let current: [SparklinePoint]
  public let previous: [SparklinePoint]

  public init(current: [SparklinePoint], previous: [SparklinePoint]) {
    self.current = current
    self.previous = previous
  }
}

public struct GroupedBarFraction: Equatable, Sendable {
  public let current: Double
  public let previous: Double

  public init(current: Double, previous: Double) {
    self.current = current
    self.previous = previous
  }
}

public struct TokenComposition: Equatable, Sendable {
  public static let zero = TokenComposition(
    uncachedInput: 0,
    cachedInput: 0,
    output: 0
  )

  public let uncachedInput: Double
  public let cachedInput: Double
  public let output: Double

  public init(uncachedInput: Double, cachedInput: Double, output: Double) {
    self.uncachedInput = uncachedInput
    self.cachedInput = cachedInput
    self.output = output
  }
}

public enum UsageChartGeometry {
  public static func lines(
    current: [Int64],
    previous: [Int64]
  ) -> ComparisonLineGeometry {
    let maximum = max(current.max() ?? 0, previous.max() ?? 0)
    return ComparisonLineGeometry(
      current: points(values: current, maximum: maximum),
      previous: points(values: previous, maximum: maximum)
    )
  }

  public static func bars(
    current: [Int64],
    previous: [Int64]
  ) -> [GroupedBarFraction] {
    let count = max(current.count, previous.count)
    guard count > 0 else {
      return []
    }
    let maximum = max(current.max() ?? 0, previous.max() ?? 0)
    return (0..<count).map { index in
      GroupedBarFraction(
        current: fraction(value: value(at: index, in: current), maximum: maximum),
        previous: fraction(value: value(at: index, in: previous), maximum: maximum)
      )
    }
  }

  public static func composition(usage: TokenUsage) -> TokenComposition {
    guard usage.totalTokens > 0 else {
      return .zero
    }
    let total = Double(usage.totalTokens)
    return TokenComposition(
      uncachedInput: Double(usage.uncachedInputTokens + usage.unclassifiedTokens) / total,
      cachedInput: Double(usage.cachedInputTokens) / total,
      output: Double(usage.outputTokens) / total
    )
  }

  private static func points(values: [Int64], maximum: Int64) -> [SparklinePoint] {
    guard !values.isEmpty else {
      return []
    }
    let divisor = max(1, values.count - 1)
    return values.enumerated().map { index, value in
      SparklinePoint(
        x: values.count == 1 ? 0.5 : Double(index) / Double(divisor),
        y: fraction(value: value, maximum: maximum)
      )
    }
  }

  private static func value(at index: Int, in values: [Int64]) -> Int64 {
    values.indices.contains(index) ? values[index] : 0
  }

  private static func fraction(value: Int64, maximum: Int64) -> Double {
    guard maximum > 0 else {
      return 0
    }
    return min(1, max(0, Double(value) / Double(maximum)))
  }
}
