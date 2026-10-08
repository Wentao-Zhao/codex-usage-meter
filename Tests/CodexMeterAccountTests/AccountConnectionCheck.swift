import AppKit
import CodexMeterCore
import Foundation

@main
enum AccountConnectionCheck {
  static func main() {
    do {
      try checkExecutableDiscovery()
      if CommandLine.arguments.contains("--offline") {
        return
      }
      let client: CodexAppServerClient
      if CommandLine.arguments.count > 1 {
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        client = CodexAppServerClient(executableURLProvider: { executable })
      } else {
        client = CodexAppServerClient()
      }
      let limits = try client.fetchRateLimits()
      guard limits.fiveHour != nil || limits.weekly != nil else {
        fatalError("No supported account quota windows")
      }
      if let window = limits.fiveHour {
        print("5-hour remaining: \(RateLimitPolicy.remainingPercent(for: window))%")
      }
      if let window = limits.weekly {
        print("Weekly remaining: \(RateLimitPolicy.remainingPercent(for: window))%")
      }
      print("PASS: live account quota connection")
    } catch {
      fputs("FAIL: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  private static func checkExecutableDiscovery() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("codex-meter-discovery-\(UUID().uuidString)")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }
    let app = root.appendingPathComponent("Custom Location/ChatGPT.app")
    let legacy = app.appendingPathComponent("Contents/Resources/codex")
    let modern = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
    let nested = app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
    let fallback = root.appendingPathComponent("codex")

    func createExecutable(_ url: URL) throws {
      try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    func locate() -> URL? {
      CodexAppServerClient.locateExecutable(applicationURLs: [app], fallbackURLs: [fallback])
    }

    try createExecutable(fallback)
    precondition(locate() == fallback, "CLI fallback remains available")
    try createExecutable(legacy)
    precondition(locate() == legacy, "Legacy desktop layout remains supported")
    try createExecutable(nested)
    precondition(locate() == nested, "Nested CLI app is discovered")
    try createExecutable(modern)
    precondition(locate() == modern, "Official packaged entrypoint takes precedence")
    try fileManager.removeItem(at: modern)
    try fileManager.createDirectory(at: modern, withIntermediateDirectories: true)
    precondition(locate() == nested, "Executable directories are rejected")
    try fileManager.removeItem(at: modern)
    try createExecutable(modern)
    try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: modern.path)
    precondition(locate() == nested, "Nonexecutable files are rejected")
    precondition(CodexAppServerClient.locateExecutable(applicationURLs: [], fallbackURLs: []) == nil, "Missing installations return nil")
    print("PASS: 7 executable discovery checks")
  }
}
