import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
    let publicKey = Data(base64Encoded: CommandLine.arguments[1]),
    let signature = Data(base64Encoded: CommandLine.arguments[2])
else {
    fatalError("Usage: swift scripts/VerifyUpdate.swift base64-public-key base64-signature archive")
}
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
exit(key.isValidSignature(signature, for: archive) ? 0 : 1)
