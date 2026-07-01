import Foundation

public struct SparklinePoint: Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public enum SparklineGeometry {
  public static func points(values: [Int64]) -> [SparklinePoint] {
    guard !values.isEmpty else {
      return []
    }
    guard values.count > 1 else {
      return [SparklinePoint(x: 0.5, y: 0.5)]
    }

    let minimum = values.min() ?? 0
    let maximum = values.max() ?? 0
    let range = maximum - minimum
    let divisor = Double(values.count - 1)

    return values.enumerated().map { index, value in
      let y = range == 0 ? 0.5 : Double(value - minimum) / Double(range)
      return SparklinePoint(x: Double(index) / divisor, y: y)
    }
  }
}
