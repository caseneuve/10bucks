import Security

public enum TokenGenerationError: Error, Equatable {
    case randomSourceFailure
    case invalidRandomByteCount
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
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw TokenGenerationError.randomSourceFailure
        }
        return bytes
    }

    private static func base32(_ bytes: [UInt8]) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var result = ""
        var buffer = 0
        var bitCount = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                result.append(alphabet[(buffer >> bitCount) & 31])
            }
        }
        if bitCount > 0 { result.append(alphabet[(buffer << (5 - bitCount)) & 31]) }
        return result
    }
}
