import CommonCrypto
import Foundation
import Security

public enum TokenGenerationError: Error, Equatable {
    case randomSourceFailure
    case invalidRandomByteCount
}

// This public CommonCrypto implementation intentionally hashes the exact UTF-8
// bytes of the raw fixture token. The alias is the only correlation value that
// may cross the fixture's IPC or trace boundary.
public enum CorrelationAlias {
    public static let prefix = "poc001-corr-sha256-"

    public static func alias(for rawToken: String) -> String {
        let digest = rawToken.data(using: .utf8)!.withUnsafeBytes { bytes -> [UInt8] in
            var output = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(bytes.baseAddress, CC_LONG(bytes.count), &output)
            return output
        }
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func isValidAlias(_ alias: String) -> Bool {
        guard alias.hasPrefix(prefix), alias.utf8.count == prefix.utf8.count + 64 else { return false }
        return alias.dropFirst(prefix.count).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

}

public protocol TokenGenerating {
    func fixtureToken() throws -> String
    func correlationToken() throws -> String
}

public final class SecureTokenGenerator: TokenGenerating {
    private static let byteCount = 10
    private let randomBytes: (Int) throws -> [UInt8]

    public init(randomBytes: ((Int) throws -> [UInt8])? = nil) {
        self.randomBytes = randomBytes ?? Self.systemRandomBytes
    }

    public func fixtureToken() throws -> String {
        "fixture-win-" + (try randomSuffix())
    }

    public func correlationToken() throws -> String {
        "corr-" + (try randomSuffix())
    }

    private func randomSuffix() throws -> String {
        let bytes = try randomBytes(Self.byteCount)
        guard bytes.count == Self.byteCount else { throw TokenGenerationError.invalidRandomByteCount }
        return Self.base32(bytes)
    }

    private static func systemRandomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else { throw TokenGenerationError.randomSourceFailure }
        return bytes
    }

    private static func base32(_ bytes: [UInt8]) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var result = ""
        var remainingBits: UInt16 = 0
        var remainingCount = 0
        for byte in bytes {
            remainingBits = (remainingBits << 8) | UInt16(byte)
            remainingCount += 8
            while remainingCount >= 5 {
                remainingCount -= 5
                result.append(alphabet[Int((remainingBits >> remainingCount) & 31)])
                let mask: UInt16 = remainingCount == 0 ? 0 : (1 << remainingCount) - 1
                remainingBits &= mask
            }
        }
        if remainingCount > 0 {
            result.append(alphabet[Int((remainingBits << (5 - remainingCount)) & 31)])
        }
        return result
    }
}
