@_implementationOnly import CZstdDecoder
import Foundation

final class ZstandardLogReader {
  private let reader: OpaquePointer

  init(url: URL) throws {
    var error = [CChar](repeating: 0, count: 160)
    let opened = url.withUnsafeFileSystemRepresentation { path in
      CMZstdOpen(path, &error, error.count)
    }
    guard let opened else { throw Self.error(String(cString: error)) }
    reader = opened
  }

  deinit { CMZstdClose(reader) }

  var compressedBytesRead: UInt64 { CMZstdCompressedBytesRead(reader) }

  func read(upToCount count: Int) throws -> Data? {
    var data = Data(count: min(65_536, max(1, count)))
    let size = data.withUnsafeMutableBytes { CMZstdRead(reader, $0.baseAddress, $0.count) }
    if size == -2 { return nil }
    guard size >= 0 else { throw Self.error(String(cString: CMZstdError(reader))) }
    data.count = size
    return data
  }

  private static func error(_ message: String) -> NSError {
    NSError(domain: "CodexMeter.Zstandard", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
