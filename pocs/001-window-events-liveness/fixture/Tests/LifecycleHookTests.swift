import Foundation

func testLifecycleHooksCompleteCreateOnlyOnceForTheRegisteredObjectAndGeneration() throws {
    let trace = RecordingTraceSink()
    var model = FixtureLifecycleHooks(trace: trace)
    try model.register(token: "fixture-win-AAAA", generation: 1, objectID: "object-1")

    try expect(model.didBecomeVisible(objectID: "other") == .rejectedWrongObject, "wrong visible notification is rejected")
    try expect(model.didBecomeVisible(objectID: "object-1") == .completedCreate, "registered visible hook completes create")
    try expect(model.didBecomeVisible(objectID: "object-1") == .rejectedDuplicate, "duplicate visible notification is rejected")
    try expect(trace.events == [.createCompleted(token: "fixture-win-AAAA", generation: 1)], "only one create completion is traced")
}

func testLifecycleHooksRejectReorderedCloseAndRetainRegistryUntilWillClose() throws {
    let trace = RecordingTraceSink()
    var model = FixtureLifecycleHooks(trace: trace)
    try model.register(token: "fixture-win-AAAA", generation: 7, objectID: "object-1")

    try expect(model.windowWillClose(objectID: "object-1") == .rejectedReordered, "close before create completion is rejected")
    try expect(model.active != nil, "reordered hook cannot remove registry")
    _ = model.didBecomeVisible(objectID: "object-1")
    try expect(model.requestClose(token: "fixture-win-AAAA", generation: 7), "IPC close records expected attribution but retains registry")
    try expect(model.active != nil, "requesting close does not remove registry")
    try expect(model.windowWillClose(objectID: "wrong") == .rejectedWrongObject, "wrong close object is rejected")
    try expect(model.active != nil, "wrong close object cannot remove registry")
    try expect(model.windowWillClose(objectID: "object-1") == .completedClose(.ipc), "matching will-close completes IPC close")
    try expect(model.active == nil, "only matching will-close removes registry")
    try expect(trace.events.suffix(1).first == .closeCompleted(token: "fixture-win-AAAA", generation: 7, origin: .ipc), "traces IPC close attribution")
}

func testLifecycleHooksAttributeUnrequestedUserCloseAndRejectDuplicateGeneration() throws {
    let trace = RecordingTraceSink()
    var model = FixtureLifecycleHooks(trace: trace)
    try model.register(token: "fixture-win-AAAA", generation: 2, objectID: "object-1")
    _ = model.didBecomeVisible(objectID: "object-1")
    try expect(model.windowWillClose(objectID: "object-1") == .completedClose(.user), "unrequested close is attributed to user")
    try expect(trace.events.last == .closeCompleted(token: "fixture-win-AAAA", generation: 2, origin: .user), "user attribution is traced")
    try expectThrows(FixtureLifecycleError.duplicateGeneration) {
        try model.register(token: "fixture-win-BBBB", generation: 2, objectID: "object-2")
    }
}

let lifecycleHookTests: [(String, () throws -> Void)] = [
    ("lifecycle hooks complete one create for registered object and generation", testLifecycleHooksCompleteCreateOnlyOnceForTheRegisteredObjectAndGeneration),
    ("lifecycle hooks reject reordering and remove only at will-close", testLifecycleHooksRejectReorderedCloseAndRetainRegistryUntilWillClose),
    ("lifecycle hooks attribute user close and reject duplicate generation", testLifecycleHooksAttributeUnrequestedUserCloseAndRejectDuplicateGeneration),
]
