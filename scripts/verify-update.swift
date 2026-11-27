import Foundation
import CryptoKit

// Public-key verifier. Never reads or exports a private signing key.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]), key.count == 32,
      let signature = Data(base64Encoded: CommandLine.arguments[2]), signature.count == 64 else {
  fputs("Usage: verify-update PUBLIC_KEY SIGNATURE FILE\n", stderr)
  exit(2)
}
do {
  let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
  let contents = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
  guard publicKey.isValidSignature(signature, for: contents) else {
    fputs("Update signature does not match the application's public key\n", stderr)
    exit(1)
  }
  print("PASS: Ed25519 signature matches embedded application public key")
} catch {
  fputs("Cannot verify update: \(error.localizedDescription)\n", stderr)
  exit(1)
}
