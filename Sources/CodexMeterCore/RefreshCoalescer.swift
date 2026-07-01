import Foundation

public final class RefreshCoalescer: @unchecked Sendable {
  private let queue: DispatchQueue
  private let delay: TimeInterval
  private let action: () -> Void
  private let lock = NSLock()
  private var pendingWorkItem: DispatchWorkItem?

  public init(
    queue: DispatchQueue,
    delay: TimeInterval,
    action: @escaping () -> Void
  ) {
    self.queue = queue
    self.delay = delay
    self.action = action
  }

  deinit {
    cancel()
  }

  public func schedule() {
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else {
        return
      }
      self.lock.lock()
      self.pendingWorkItem = nil
      self.lock.unlock()
      self.action()
    }

    lock.lock()
    pendingWorkItem?.cancel()
    pendingWorkItem = workItem
    lock.unlock()

    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  public func cancel() {
    lock.lock()
    pendingWorkItem?.cancel()
    pendingWorkItem = nil
    lock.unlock()
  }
}
