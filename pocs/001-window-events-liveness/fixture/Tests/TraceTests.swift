import Foundation

func validTraceRecord(sequence: UInt64 = 1) -> TraceRecord {
    TraceRecord(
        runID: "run-001",
        sampleID: "fixture-create-warm-001",
        sequence: sequence,
        event: "create_requested",
        clock: ClockReading(kind: .machContinuous, ticks: 7, timebase: MachTimebase(numer: 1, denom: 1)),
        approvedFields: [
            "fixture_token": .string("fixture-win-ABC234"),
            "timebase_numer": .unsigned(1),
            "timebase_denom": .unsigned(1),
        ]
    )
}

func testTraceEncodesOnlyRequiredAndApprovedFields() throws {
    let line = try Trace.encode(validTraceRecord())
    let object = try JSONSerialization.jsonObject(with: line) as! [String: Any]
    try expect(Set(object.keys) == ["schema", "run_id", "sample_id", "sequence", "event", "clock_kind", "ticks", "monotonic_ms", "fixture_token", "timebase_numer", "timebase_denom"], "emits exactly required plus approved fields")
    try expect(object["schema"] as? String == Trace.schema, "uses frozen schema")
    try expect(object["monotonic_ms"] as? UInt64 == 0, "derives floor milliseconds from clock")
    try expect(object["timebase_numer"] as? UInt64 == 1, "preserves approved numeric scalar fields")
    try expect(line.last == 0x0A, "writes one NDJSON line")
}

func testTraceRejectsUnsafeValuesAndUnknownFields() throws {
    try expectThrows(TraceError.invalidToken("run_id")) {
        _ = try Trace.encode(TraceRecord(
            runID: "run 001", sampleID: "sample-001", sequence: 1, event: "create_requested",
            clock: ClockReading(kind: .machContinuous, ticks: 1, timebase: MachTimebase(numer: 1, denom: 1))
        ))
    }
    for unsafe in ["native_window_id", "title", "document_path", "url", "app_name"] {
        try expectThrows(TraceError.unapprovedField(unsafe)) {
            _ = try Trace.encode(TraceRecord(
                runID: "run-001", sampleID: "sample-001", sequence: 1, event: "create_requested",
                clock: ClockReading(kind: .machContinuous, ticks: 1, timebase: MachTimebase(numer: 1, denom: 1)),
                approvedFields: [unsafe: "safe"]
            ))
        }
    }
    try expectThrows(TraceError.unsafeScalar("fixture_token")) {
        _ = try Trace.encode(TraceRecord(
            runID: "run-001", sampleID: "sample-001", sequence: 1, event: "create_requested",
            clock: ClockReading(kind: .machContinuous, ticks: 1, timebase: MachTimebase(numer: 1, denom: 1)),
            approvedFields: ["fixture_token": "fixture-win-contains space"]
        ))
    }
}

func testTraceEnforcesSequenceOrdering() throws {
    var trace = TraceBuffer()
    try trace.append(validTraceRecord(sequence: 1))
    try expectThrows(TraceError.invalidSequence(expected: 2, received: 1)) {
        try trace.append(validTraceRecord(sequence: 1))
    }
    try expectThrows(TraceError.invalidSequence(expected: 2, received: 3)) {
        try trace.append(validTraceRecord(sequence: 3))
    }
}

func testTraceOutputIsExactlyOwnerPrivate() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("trace.ndjson")
    let writer = try TraceWriter(createAt: output)
    try writer.append(validTraceRecord())
    try writer.close()
    try expect(fileMode(output) == 0o600, "creates trace output with exact 0600 mode")

    let unsafeOutput = directory.appendingPathComponent("unsafe.ndjson")
    FileManager.default.createFile(atPath: unsafeOutput.path, contents: Data())
    try setFileMode(unsafeOutput, mode: 0o644)
    try expectThrows(TraceError.unsafeOutputPermissions) {
        _ = try TraceWriter(createAt: unsafeOutput)
    }
}

let traceTests: [(String, () throws -> Void)] = [
    ("trace emits strict NDJSON required and approved fields", testTraceEncodesOnlyRequiredAndApprovedFields),
    ("trace rejects unsafe fields and values", testTraceRejectsUnsafeValuesAndUnknownFields),
    ("trace enforces sequence ordering", testTraceEnforcesSequenceOrdering),
    ("trace creates only 0600 output", testTraceOutputIsExactlyOwnerPrivate),
]
