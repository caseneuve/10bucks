import Foundation

private func request(_ command: String, _ fields: [String: String]) -> FixtureRequest {
    FixtureRequest(command: command, fields: fields)
}

func testFixtureControlAcceptsOnlyTheFourExactCommandGrammars() throws {
    let generator = DeterministicTokenGenerator(values: ["AAAA", "BBBB"])
    var control = FixtureControl(tokenGenerator: generator)

    let created = try control.handle(request("create", [
        "request_id": "req-001", "sample_id": "fixture-create-warm-001",
    ]))
    try expect(created.status == .accepted, "accepts create with exactly request and sample IDs")
    try expect(created.fixtureToken == "fixture-win-AAAA", "returns the generated fixture token")
    try expect(created.correlationToken == "corr-BBBB", "returns the generated correlation token")

    for invalid in [
        request("CREATE", ["request_id": "req-002", "sample_id": "sample-002"]),
        request("create", ["request_id": "req-002"]),
        request("create", ["request_id": "req-002", "sample_id": "sample-002", "fixture_token": "fixture-win-AAAA"]),
        request("probe_pending_work", ["request_id": "req-003", "sample_id": "sample-003", "fixture_token": "fixture-win-AAAA"]),
        request("close", ["request_id": "req-004", "sample_id": "sample-004"]),
        request("shutdown", ["request_id": "req-005", "sample_id": "sample 005"]),
    ] {
        try expectThrows(FixtureControlError.invalidRequest) { _ = try control.handle(invalid) }
    }
}

func testFixtureControlSerializesStateAndRejectsDuplicateOrWrongTokens() throws {
    let generator = DeterministicTokenGenerator(values: ["AAAA", "BBBB", "CCCC", "DDDD"])
    var control = FixtureControl(tokenGenerator: generator)
    let first = try control.handle(request("create", ["request_id": "req-001", "sample_id": "sample-001"]))

    try expectThrows(FixtureControlError.commandRejected(.createAlreadyActive)) {
        _ = try control.handle(request("create", ["request_id": "req-002", "sample_id": "sample-002"]))
    }
    try expectThrows(FixtureControlError.commandRejected(.unknownFixtureToken)) {
        _ = try control.handle(request("close", ["request_id": "req-003", "sample_id": "sample-003", "fixture_token": "fixture-win-CCCC"]))
    }
    _ = try control.handle(request("close", ["request_id": "req-004", "sample_id": "sample-004", "fixture_token": first.fixtureToken!]))
    try expectThrows(FixtureControlError.commandRejected(.closeAlreadyRequested)) {
        _ = try control.handle(request("close", ["request_id": "req-005", "sample_id": "sample-005", "fixture_token": first.fixtureToken!]))
    }
    try expect(control.activeGeneration?.token == first.fixtureToken, "close request retains registry ownership until will-close")
}

func testFixtureControlRemovesOnlyAfterMatchingWillCloseAndRejectsAfterShutdown() throws {
    let generator = DeterministicTokenGenerator(values: ["AAAA", "BBBB"])
    var control = FixtureControl(tokenGenerator: generator)
    let created = try control.handle(request("create", ["request_id": "req-001", "sample_id": "sample-001"]))
    _ = try control.handle(request("close", ["request_id": "req-002", "sample_id": "sample-002", "fixture_token": created.fixtureToken!]))

    try expect(!control.completeClose(token: "fixture-win-wrong", generation: 1), "wrong close hook cannot remove the active registry entry")
    try expect(control.activeGeneration != nil, "wrong completion retains active registry")
    try expect(control.completeClose(token: created.fixtureToken!, generation: 1), "matching will-close removes registry")
    try expect(control.activeGeneration == nil, "registry is empty only after matching will-close")
    try expectThrows(FixtureControlError.commandRejected(.unknownFixtureToken)) {
        _ = try control.handle(request("close", ["request_id": "req-003", "sample_id": "sample-003", "fixture_token": created.fixtureToken!]))
    }

    _ = try control.handle(request("shutdown", ["request_id": "req-004", "sample_id": "sample-004"]))
    try expect(control.activeGeneration == nil, "this completed generation remains removed after shutdown")
    try expectThrows(FixtureControlError.commandRejected(.shutDown)) {
        _ = try control.handle(request("create", ["request_id": "req-005", "sample_id": "sample-005"]))
    }

    var shuttingDown = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["CCCC", "DDDD"]))
    _ = try shuttingDown.handle(request("create", ["request_id": "req-006", "sample_id": "sample-006"]))
    _ = try shuttingDown.handle(request("shutdown", ["request_id": "req-007", "sample_id": "sample-007"]))
    try expect(shuttingDown.activeGeneration != nil, "shutdown rejects work but does not remove a live registry entry outside will-close")
}

let fixtureControlTests: [(String, () throws -> Void)] = [
    ("fixture control accepts only the exact four-command grammar", testFixtureControlAcceptsOnlyTheFourExactCommandGrammars),
    ("fixture control serializes active-token command state", testFixtureControlSerializesStateAndRejectsDuplicateOrWrongTokens),
    ("fixture control removes only at matching will-close and rejects after shutdown", testFixtureControlRemovesOnlyAfterMatchingWillCloseAndRejectsAfterShutdown),
]
