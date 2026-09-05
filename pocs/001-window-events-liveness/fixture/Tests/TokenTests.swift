import Foundation

func testSecureTokenGeneratorUsesInjectedRandomBoundaryAndFrozenPrefixes() throws {
    var bytes: [UInt8] = Array(repeating: 0, count: 10)
    let generator = SecureTokenGenerator(randomBytes: { count in
        try expect(count == 10, "uses the fixed token byte length")
        return bytes
    })
    let fixtureToken = try generator.fixtureToken()
    try expect(fixtureToken == "fixture-win-AAAAAAAAAAAAAAAA", "encodes random bytes as base32")
    bytes = Array(repeating: 0xff, count: 10)
    let correlationToken = try generator.correlationToken()
    try expect(correlationToken == "corr-7777777777777777", "encodes all 80 random bits without overflowing its accumulator")
}

func testCorrelationAliasUsesPublicSHA256WithFrozenCrossLanguageVectors() throws {
    try expect(
        CorrelationAlias.alias(for: "corr-AAAAAAAAAAAAAAAA") == "poc001-corr-sha256-83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac",
        "the all-A token has the frozen full lowercase SHA-256 alias"
    )
    try expect(
        CorrelationAlias.alias(for: "corr-7777777777777777") == "poc001-corr-sha256-5e5f2182c2728604b072539a13264b2ed227582defd4deaa220f8ed8cb7e178b",
        "the all-7 token has the frozen full lowercase SHA-256 alias"
    )
}

func testSecureTokenGeneratorRejectsBoundaryFailuresAndWrongLengths() throws {
    let failed = SecureTokenGenerator(randomBytes: { _ in throw TokenGenerationError.randomSourceFailure })
    try expectThrows(TokenGenerationError.randomSourceFailure) { _ = try failed.fixtureToken() }
    let short = SecureTokenGenerator(randomBytes: { _ in [0] })
    try expectThrows(TokenGenerationError.invalidRandomByteCount) { _ = try short.correlationToken() }
}

let tokenTests: [(String, () throws -> Void)] = [
    ("secure token generation has a testable random boundary and frozen prefixes", testSecureTokenGeneratorUsesInjectedRandomBoundaryAndFrozenPrefixes),
    ("correlation aliases use frozen public SHA-256 vectors", testCorrelationAliasUsesPublicSHA256WithFrozenCrossLanguageVectors),
    ("secure token generation fails closed at its random boundary", testSecureTokenGeneratorRejectsBoundaryFailuresAndWrongLengths),
]
