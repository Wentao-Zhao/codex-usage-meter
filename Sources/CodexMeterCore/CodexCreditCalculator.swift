import Foundation

public struct CodexCreditRate: Equatable, Sendable {
  public let inputPerMillion: Double
  public let cachedInputPerMillion: Double
  public let outputPerMillion: Double

  public init(
    inputPerMillion: Double,
    cachedInputPerMillion: Double,
    outputPerMillion: Double
  ) {
    self.inputPerMillion = inputPerMillion
    self.cachedInputPerMillion = cachedInputPerMillion
    self.outputPerMillion = outputPerMillion
  }
}

public enum CodexCreditCalculator {
  public static func credits(for usage: TokenUsage, model: String?) -> Double {
    let rate = rate(for: model)
    let uncachedInput = usage.uncachedInputTokens + usage.unclassifiedTokens
    let weighted = Double(uncachedInput) * rate.inputPerMillion
      + Double(usage.cachedInputTokens) * rate.cachedInputPerMillion
      + Double(usage.outputTokens) * rate.outputPerMillion
    return weighted / 1_000_000
  }

  public static func rate(for model: String?) -> CodexCreditRate {
    let normalized = model?.lowercased() ?? ""

    if normalized.contains("gpt-5.6-sol") {
      return CodexCreditRate(
        inputPerMillion: 125,
        cachedInputPerMillion: 12.5,
        outputPerMillion: 750
      )
    }
    if normalized.contains("gpt-5.6-terra") {
      return CodexCreditRate(
        inputPerMillion: 62.5,
        cachedInputPerMillion: 6.25,
        outputPerMillion: 375
      )
    }
    if normalized.contains("gpt-5.6-luna") {
      return CodexCreditRate(
        inputPerMillion: 25,
        cachedInputPerMillion: 2.5,
        outputPerMillion: 150
      )
    }
    if normalized.contains("gpt-5.5-cyber") {
      return CodexCreditRate(
        inputPerMillion: 500,
        cachedInputPerMillion: 50,
        outputPerMillion: 3_000
      )
    }
    if normalized.contains("gpt-5.5") {
      return CodexCreditRate(
        inputPerMillion: 125,
        cachedInputPerMillion: 12.5,
        outputPerMillion: 750
      )
    }
    if normalized.contains("gpt-5.4-mini") {
      return CodexCreditRate(
        inputPerMillion: 18.75,
        cachedInputPerMillion: 1.875,
        outputPerMillion: 113
      )
    }
    if normalized.contains("gpt-5.3-codex")
      || normalized.contains("gpt-5.2")
      || normalized == "codex-auto-review" {
      return CodexCreditRate(
        inputPerMillion: 43.75,
        cachedInputPerMillion: 4.375,
        outputPerMillion: 350
      )
    }

    // Current general Codex default. Known model aliases above retain their exact rate.
    return CodexCreditRate(
      inputPerMillion: 62.5,
      cachedInputPerMillion: 6.25,
      outputPerMillion: 375
    )
  }
}
