import AppKit
import CodexMeterCore
import Foundation

final class CodexAppServerClient {
  enum ClientError: LocalizedError {
    case executableNotFound
    case launchFailed
    case timedOut
    case invalidResponse

    var errorDescription: String? {
      switch self {
      case .executableNotFound:
        return "未找到 Codex 本地服务"
      case .launchFailed:
        return "无法启动 Codex 本地服务"
      case .timedOut:
        return "读取 Codex 额度超时"
      case .invalidResponse:
        return "Codex 返回了无法识别的额度数据"
      }
    }
  }

  private let executableURLProvider: () -> URL?

  init(
    executableURLProvider: @escaping () -> URL? = CodexAppServerClient.locateExecutable
  ) {
    self.executableURLProvider = executableURLProvider
  }

  func fetchRateLimits(timeout: TimeInterval = 12) throws -> ResolvedRateLimits {
    guard let executableURL = executableURLProvider() else {
      throw ClientError.executableNotFound
    }

    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = executableURL
    process.arguments = ["app-server", "--stdio"]
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let lock = NSLock()
    let completion = DispatchSemaphore(value: 0)
    var collector = JSONRPCLineCollector(expectedResponseIDs: [2])

    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        return
      }
      lock.lock()
      collector.consume(data)
      let isComplete = collector.isComplete
      lock.unlock()
      if isComplete {
        completion.signal()
      }
    }
    process.terminationHandler = { _ in
      completion.signal()
    }

    do {
      try process.run()
      try inputPipe.fileHandleForWriting.write(contentsOf: requestData)
    } catch {
      cleanup(
        process: process,
        inputPipe: inputPipe,
        outputPipe: outputPipe,
        errorPipe: errorPipe
      )
      throw ClientError.launchFailed
    }

    let waitResult = completion.wait(timeout: .now() + timeout)
    lock.lock()
    let response = collector.response(for: 2)
    lock.unlock()
    cleanup(
      process: process,
      inputPipe: inputPipe,
      outputPipe: outputPipe,
      errorPipe: errorPipe
    )

    guard waitResult == .success else {
      throw ClientError.timedOut
    }
    guard
      let response,
      let rateLimits = AccountRateLimitResponseParser.parse(response)
    else {
      throw ClientError.invalidResponse
    }
    return rateLimits
  }

  private var requestData: Data {
    let messages = [
      #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-meter","title":"CodexMeter","version":"1"},"capabilities":null}}"#,
      #"{"method":"initialized"}"#,
      #"{"id":2,"method":"account/rateLimits/read"}"#,
    ]
    return Data((messages.joined(separator: "\n") + "\n").utf8)
  }

  private func cleanup(
    process: Process,
    inputPipe: Pipe,
    outputPipe: Pipe,
    errorPipe: Pipe
  ) {
    outputPipe.fileHandleForReading.readabilityHandler = nil
    process.terminationHandler = nil
    try? inputPipe.fileHandleForWriting.close()
    try? outputPipe.fileHandleForReading.close()
    try? errorPipe.fileHandleForReading.close()
    if process.isRunning {
      process.terminate()
    }
  }

  private static func locateExecutable() -> URL? {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    var candidates: [URL] = []

    if let appURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.openai.codex"
    ) {
      candidates.append(
        appURL.appendingPathComponent("Contents/Resources/codex")
      )
    }

    candidates.append(contentsOf: [
      URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
      URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
      home.appendingPathComponent(".codex/plugins/.plugin-appserver/codex"),
      URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
      URL(fileURLWithPath: "/usr/local/bin/codex"),
    ])

    return candidates.first {
      fileManager.isExecutableFile(atPath: $0.path)
    }
  }
}
