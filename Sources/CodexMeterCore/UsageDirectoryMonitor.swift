import Darwin
import Foundation

public final class UsageDirectoryMonitor {
  private struct Watch {
    let source: DispatchSourceFileSystemObject
  }

  private let paths: [URL]
  private let eventQueue = DispatchQueue(
    label: "com.local.CodexMeter.file-events",
    qos: .utility
  )
  private let onChange: () -> Void
  private var coalescer: RefreshCoalescer!
  private var watches: [String: Watch] = [:]
  private var rebuildWorkItem: DispatchWorkItem?
  private var isRunning = false

  public init(
    paths: [URL],
    debounceDelay: TimeInterval = 1,
    onChange: @escaping () -> Void
  ) {
    self.paths = paths
    self.onChange = onChange
    self.coalescer = RefreshCoalescer(queue: eventQueue, delay: debounceDelay) { [weak self] in
      self?.onChange()
    }
    eventQueue.setSpecific(key: Self.queueKey, value: Self.queueValue)
  }

  deinit {
    stop()
  }

  public func start() {
    eventQueue.async { [weak self] in
      guard let self, !self.isRunning else {
        return
      }
      self.isRunning = true
      self.rebuildWatches()
    }
  }

  public func stop() {
    let cleanup = { [self] in
      isRunning = false
      rebuildWorkItem?.cancel()
      rebuildWorkItem = nil
      coalescer.cancel()
      let oldWatches = watches
      watches.removeAll()
      for watch in oldWatches.values {
        watch.source.cancel()
      }
    }

    if DispatchQueue.getSpecific(key: Self.queueKey) == Self.queueValue {
      cleanup()
    } else {
      eventQueue.sync(execute: cleanup)
    }
  }

  private func rebuildWatches() {
    guard isRunning else {
      return
    }

    let desiredURLs = monitoredURLs()
    let desiredPaths = Set(desiredURLs.map(\.path))

    for path in watches.keys where !desiredPaths.contains(path) {
      watches.removeValue(forKey: path)?.source.cancel()
    }

    for url in desiredURLs where watches[url.path] == nil {
      addWatch(for: url)
    }
  }

  private func monitoredURLs() -> [URL] {
    var urls: [URL] = []
    for root in paths where FileManager.default.fileExists(atPath: root.path) {
      urls.append(root)
      guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else {
        continue
      }

      for case let url as URL in enumerator {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values?.isDirectory == true || (values?.isRegularFile == true && url.pathExtension == "jsonl") {
          urls.append(url)
        }
      }
    }
    return urls
  }

  private func addWatch(for url: URL) {
    let descriptor = open(url.path, O_EVTONLY)
    guard descriptor >= 0 else {
      return
    }

    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
    let isDirectory = values?.isDirectory == true
    let mask: DispatchSource.FileSystemEvent = isDirectory
      ? [.write, .rename, .delete]
      : [.write, .extend, .attrib, .rename, .delete]
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: mask,
      queue: eventQueue
    )
    source.setEventHandler { [weak self] in
      guard let self, self.isRunning else {
        return
      }
      self.coalescer.schedule()
      if isDirectory || !FileManager.default.fileExists(atPath: url.path) {
        self.scheduleRebuild()
      }
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
    watches[url.path] = Watch(source: source)
  }

  private func scheduleRebuild() {
    rebuildWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.rebuildWatches()
    }
    rebuildWorkItem = item
    eventQueue.asyncAfter(deadline: .now() + 0.1, execute: item)
  }

  private static let queueKey = DispatchSpecificKey<UInt8>()
  private static let queueValue: UInt8 = 1

}
