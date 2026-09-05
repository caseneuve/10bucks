import Foundation

func testSecureTokenGeneratorUsesInjectedRandomBoundaryAndFrozenPrefixes() throws {
    var bytes: [UInt8] = Array(repeating: 0, count: 10)
    let generator = SecureTokenGenerator(randomBytes: { count in
        try expect(count == 10, "uses the fixed token byte length")
        return bytes
    })
    let fixtureToken = try generator.fixtureToken()
    try expect(fixtureToken == "fixture-win-AAAAAAAAAAAAAAAA", "encodes random bytes as base32")
    bytes[0] = 0xff
    let correlationToken = try generator.correlationToken()
    try expect(correlationToken == "corr-74AAAAAAAAAAAAAA", "uses only base32 alphabet with correlation prefix")
}

func testSecureTokenGeneratorRejectsBoundaryFailuresAndWrongLengths() throws {
    let failed = SecureTokenGenerator(randomBytes: { _ in throw TokenGenerationError.randomSourceFailure })
    try expectThrows(TokenGenerationError.randomSourceFailure) { _ = try failed.fixtureToken() }
    let short = SecureTokenGenerator(randomBytes: { _ in [0] })
    try expectThrows(TokenGenerationError.invalidRandomByteCount) { _ = try short.correlationToken() }
}

let tokenTests: [(String, () throws -> Void)] = [
    ("secure token generation has a testable random boundary and frozen prefixes", testSecureTokenGeneratorUsesInjectedRandomBoundaryAndFrozenPrefixes),
    ("secure token generation fails closed at its random boundary", testSecureTokenGeneratorRejectsBoundaryFailuresAndWrongLengths),
]
