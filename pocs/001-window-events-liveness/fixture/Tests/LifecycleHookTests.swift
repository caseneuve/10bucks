import Foundation

func testLifecycleHooksRecordOneExplicitKeyCandidateForTheRegisteredObjectAndGeneration() throws {
    let trace = RecordingTraceSink()
    var model = FixtureLifecycleHooks(trace: trace)
    try model.register(token: "fixture-win-AAAA", generation: 1, objectID: "object-1", createSampleID: "fixture-create-warm-001")

    try expect(model.didBecomeKeyCandidate(objectID: "other") == .rejectedWrongObject, "wrong key candidate is rejected")
    try expect(model.didBecomeKeyCandidate(objectID: "object-1") == .recordedCreateCandidate, "registered key hook records a candidate, not completion")
    try expect(model.didBecomeKeyCandidate(objectID: "object-1") == .rejectedDuplicate, "duplicate key candidate is rejected")
    try expect(trace.events == [.createKeyCandidate(token: "fixture-win-AAAA", generation: 1, sampleID: "fixture-create-warm-001")], "only one explicit candidate carries its create sample")
}

func testLifecycleHooksDiscardReorderedCloseAtItsRemovalBoundary() throws {
    let trace = RecordingTraceSink()
    var cancelled: [(String, UInt64)] = []
    var model = FixtureLifecycleHooks(trace: trace, cancelGeneration: { token, generation in cancelled.append((token, generation)) })
    try model.register(token: "fixture-win-AAAA", generation: 7, objectID: "object-1", createSampleID: "fixture-create-warm-007")

    try expect(model.windowWillClose(objectID: "object-1") == .discardedReordered, "close before create completion is discarded")
    try expect(model.active == nil, "the actual will-close hook removes an anomalous generation for cleanup")
    try expect(cancelled.count == 1 && cancelled[0].0 == "fixture-win-AAAA" && cancelled[0].1 == 7, "will-close cancels the anomalous generation's pending work")
    try expect(trace.events.isEmpty, "reordered close emits no false native close completion")
}

func testLifecycleHooksAttributeCloseSamplesAndRetainRegistryUntilWillClose() throws {
    let trace = RecordingTraceSink()
    var model = FixtureLifecycleHooks(trace: trace)
    try model.register(token: "fixture-win-AAAA", generation: 7, objectID: "object-1", createSampleID: "fixture-create-warm-007")
    _ = model.didBecomeKeyCandidate(objectID: "object-1")
    try expect(model.requestClose(token: "fixture-win-AAAA", generation: 7, closeSampleID: "fixture-close-warm-007"), "IPC close records expected attribution and sample")
    try expect(model.active != nil, "requesting close does not remove registry")
    try expect(model.windowWillClose(objectID: "wrong") == .rejectedWrongObject, "wrong close object is rejected")
    try expect(model.active != nil, "wrong close object cannot remove registry")
    try expect(model.windowWillClose(objectID: "object-1") == .completedClose(.ipc), "matching will-close completes IPC close")
    try expect(model.active == nil, "only matching will-close removes registry")
    try expect(trace.events.suffix(1).first == .closeCompleted(token: "fixture-win-AAAA", generation: 7, sampleID: "fixture-close-warm-007", origin: .ipc), "traces IPC close sample attribution")
}

func testLifecycleHooksAttributeUnrequestedUserCloseAndRejectDuplicateGeneration() throws {
    let trace = RecordingTraceSink()
    var model = FixtureLifecycleHooks(trace: trace)
    try model.register(token: "fixture-win-AAAA", generation: 2, objectID: "object-1", createSampleID: "fixture-create-warm-002")
    _ = model.didBecomeKeyCandidate(objectID: "object-1")
    try expect(model.windowWillClose(objectID: "object-1") == .completedClose(.user), "unrequested close is attributed to user")
    try expect(trace.events.last == .closeCompleted(token: "fixture-win-AAAA", generation: 2, sampleID: "fixture-create-warm-002", origin: .user), "user close retains the create sample when no close request exists")
    try expectThrows(FixtureLifecycleError.duplicateGeneration) {
        try model.register(token: "fixture-win-BBBB", generation: 2, objectID: "object-2", createSampleID: "fixture-create-warm-003")
    }
}

let lifecycleHookTests: [(String, () throws -> Void)] = [
    ("lifecycle hooks record one explicit key candidate with its sample", testLifecycleHooksRecordOneExplicitKeyCandidateForTheRegisteredObjectAndGeneration),
    ("lifecycle hooks discard reordered close at will-close removal boundary", testLifecycleHooksDiscardReorderedCloseAtItsRemovalBoundary),
    ("lifecycle hooks attribute close samples and remove only at will-close", testLifecycleHooksAttributeCloseSamplesAndRetainRegistryUntilWillClose),
    ("lifecycle hooks attribute user close and reject duplicate generation", testLifecycleHooksAttributeUnrequestedUserCloseAndRejectDuplicateGeneration),
]
