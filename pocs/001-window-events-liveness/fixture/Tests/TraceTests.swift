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

func testTraceEmitsOnlyFullCorrelationAliasNeverRawToken() throws {
    let record = TraceRecord(
        runID: "run-001", sampleID: "sample-001", sequence: 1, event: "create_requested",
        clock: ClockReading(kind: .machContinuous, ticks: 1, timebase: MachTimebase(numer: 1, denom: 1)),
        approvedFields: ["correlation_alias": .string("poc001-corr-sha256-e7403107d43bc38654e730fa05da93ce573b8b9a4cb1c9ed1adf218e5d868592")]
    )
    let object = try JSONSerialization.jsonObject(with: Trace.encode(record)) as! [String: Any]
    try expect(object["correlation_alias"] as? String == "poc001-corr-sha256-e7403107d43bc38654e730fa05da93ce573b8b9a4cb1c9ed1adf218e5d868592", "emits the full frozen lowercase alias")
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

func testTraceWriterRetriesInterruptedAndPartialWrites() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("partial.ndjson")
    let expected = try Trace.encode(validTraceRecord())
    var results: [TraceWriter.WriteResult] = [.written(3), .interrupted, .written(Int.max)]
    var written = Data()
    let writer = try TraceWriter(createAt: output, writeChunk: { _, bytes, count in
        let result = results.removeFirst()
        if case let .written(requested) = result {
            let accepted = min(requested, count)
            written.append(bytes!.assumingMemoryBound(to: UInt8.self), count: accepted)
            return .written(accepted)
        }
        return result
    })
    try writer.append(validTraceRecord())
    try writer.close()
    try expect(written == expected, "retries EINTR and writes every byte after a partial write")
}

func testTraceWriterUnlinksOutputWhenPermissionValidationFails() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("rejected.ndjson")
    try expectThrows(TraceError.unsafeOutputPermissions) {
        _ = try TraceWriter(createAt: output, writeChunk: { _, _, _ in .failed }, permissionValidator: { _ in false })
    }
    try expect(!FileManager.default.fileExists(atPath: output.path), "removes a newly created output after permission validation fails")
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
    ("trace emits only full correlation aliases", testTraceEmitsOnlyFullCorrelationAliasNeverRawToken),
    ("trace rejects unsafe fields and values", testTraceRejectsUnsafeValuesAndUnknownFields),
    ("trace enforces sequence ordering", testTraceEnforcesSequenceOrdering),
    ("trace retries interrupted and partial writes", testTraceWriterRetriesInterruptedAndPartialWrites),
    ("trace removes output after failed permission validation", testTraceWriterUnlinksOutputWhenPermissionValidationFails),
    ("trace creates only 0600 output", testTraceOutputIsExactlyOwnerPrivate),
]
