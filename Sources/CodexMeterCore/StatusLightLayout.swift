public enum StatusLightLayout {
  public struct IconMetrics: Equatable, Sendable {
    public let canvasSize: Double
    public let capsuleX: Double
    public let capsuleY: Double
    public let capsuleWidth: Double
    public let capsuleHeight: Double
    public let lampCenterY: Double
    public let lampCenterXValues: [Double]
    public let lampRadius: Double
    public let glowRadius: Double
  }

  public static let menuBarIconMetrics = IconMetrics(
    canvasSize: 18,
    capsuleX: 1.2,
    capsuleY: 4.9,
    capsuleWidth: 15.6,
    capsuleHeight: 8.2,
    lampCenterY: 9,
    lampCenterXValues: [4.95, 9, 13.05],
    lampRadius: 1.7,
    glowRadius: 2.85
  )

  public static func activeIndex(for status: UsageStatusColor) -> Int? {
    switch status {
    case .red:
      return 0
    case .yellow, .orange:
      return 1
    case .green:
      return 2
    case .unknown:
      return nil
    }
  }
}
