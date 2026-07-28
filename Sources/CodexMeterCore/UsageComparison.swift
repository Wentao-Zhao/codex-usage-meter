public enum UsageComparisonState: Equatable, Sendable {
  case empty
  case added
  case unchanged
  case increased(percent: Int)
  case decreased(percent: Int)
}

public enum UsageComparison {
  public static func resolve(current: Int64, previous: Int64) -> UsageComparisonState {
    let current = max(0, current)
    let previous = max(0, previous)
    guard previous > 0 else {
      return current > 0 ? .added : .empty
    }
    guard current != previous else {
      return .unchanged
    }

    let change = abs(Double(current - previous)) / Double(previous)
    let percent = max(1, Int((change * 100).rounded()))
    return current > previous
      ? .increased(percent: percent)
      : .decreased(percent: percent)
  }
}
