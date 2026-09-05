import Foundation

private final class CoordinatorTrace: FixtureTraceSink {
    var events: [FixtureTraceEvent] = []
    func record(_ event: FixtureTraceEvent) { events.append(event) }
}

private enum CoordinatorInjectedFailure: Error { case afterAssignment }

private final class CoordinatorWindowPort: FixtureWindowPort {
    var operations: [String] = []
    var failAfterAssignment = false
    func createWindow() throws -> String { operations.append("create"); return "window-1" }
    func assignCorrelationToken(_ token: String, objectID: String) throws {
        operations.append("assignAccessibilityIdentifier:\(token):\(objectID)")
        if failAfterAssignment { throw CoordinatorInjectedFailure.afterAssignment }
    }
    func clearCorrelationToken(objectID: String) { operations.append("clearAccessibilityIdentifier:\(objectID)") }
    func abortCreatedWindow(objectID: String) { operations.append("abortCreatedWindow:\(objectID)") }
    func orderFront(objectID: String) { operations.append("orderFront:\(objectID)") }
    func performClose(objectID: String) { operations.append("performClose:\(objectID)") }
}

func testCoordinatorCreateRegistersTracesAndOrdersFrontInFrozenOrder() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    let control = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB"]))
    let coordinator = FixtureCoordinator(control: control, lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: PendingWorkModel(trace: trace, enqueue: { $0() }))

    let response = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    try expect(response.fixtureToken == "fixture-win-AAAA", "create returns frozen fixture token")
    try expect(response.correlationAlias == "poc001-corr-sha256-e7403107d43bc38654e730fa05da93ce573b8b9a4cb1c9ed1adf218e5d868592", "create returns only the correlation alias")
    try expect(window.operations == ["create", "assignAccessibilityIdentifier:corr-BBBB:window-1", "orderFront:window-1"], "assigns the raw token to accessibilityIdentifier before ordering only the fixture window")
    try expect(coordinator.operations == ["create", "assignAccessibilityIdentifier:window-1", "register:window-1", "trace:create_requested", "orderFront:window-1"], "create assigns before trace and order-front in frozen order")
}

func testCoordinatorCloseTracesThenPerformsOnlyMatchingFixtureClose() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    let control = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB"]))
    let coordinator = FixtureCoordinator(control: control, lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: PendingWorkModel(trace: trace, enqueue: { $0() }))
    let created = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    _ = coordinator.didChangeOcclusionState(objectID: "window-1", isVisible: true)
    let beforeClose = coordinator.operations.count

    _ = try coordinator.handle(FixtureRequest(command: "close", fields: ["request_id": "req-002", "sample_id": "close-001", "fixture_token": created.fixtureToken!]))
    try expect(Array(coordinator.operations.dropFirst(beforeClose)) == ["close", "requestClose:window-1", "trace:close_requested", "performClose:window-1"], "close requests, traces, and performs close in frozen order")
    try expect(window.operations.last == "performClose:window-1", "never uses unrelated window APIs")
    _ = coordinator.windowWillClose(objectID: "window-1")
    try expect(window.operations.last == "clearAccessibilityIdentifier:window-1", "matching terminal close clears the exact identifier before registry removal")
}

func testCoordinatorCreateFailureAfterAssignmentClearsAndAbortsExactWindow() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    window.failAfterAssignment = true
    let coordinator = FixtureCoordinator(control: FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB"])), lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: PendingWorkModel(trace: trace, enqueue: { $0() }))

    try expectThrows(CoordinatorInjectedFailure.afterAssignment) {
        _ = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    }
    try expect(window.operations == ["create", "assignAccessibilityIdentifier:corr-BBBB:window-1", "clearAccessibilityIdentifier:window-1", "abortCreatedWindow:window-1"], "a post-assignment failure clears and aborts only the created fixture window")
    try expect(!coordinator.hasActiveGeneration, "post-assignment failure retains no active raw token or lifecycle generation")
}

func testCoordinatorRejectsCloseBeforeCompletionWithoutPoisoningGeneration() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    let control = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB"]))
    let coordinator = FixtureCoordinator(control: control, lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: PendingWorkModel(trace: trace, enqueue: { $0() }))
    let created = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    try expectThrows(FixtureControlError.commandRejected(.unknownFixtureToken)) {
        _ = try coordinator.handle(FixtureRequest(command: "close", fields: ["request_id": "req-002", "sample_id": "close-001", "fixture_token": created.fixtureToken!]))
    }
    _ = coordinator.didChangeOcclusionState(objectID: "window-1", isVisible: true)
    _ = try coordinator.handle(FixtureRequest(command: "close", fields: ["request_id": "req-003", "sample_id": "close-002", "fixture_token": created.fixtureToken!]))
    try expect(window.operations.last == "performClose:window-1", "rejected premature close leaves the completed generation closable")
}

func testCoordinatorClearsControlForReorderedWillCloseWithoutFalseCloseRecord() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    let control = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB", "CCCC", "DDDD"]))
    let coordinator = FixtureCoordinator(control: control, lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: PendingWorkModel(trace: trace, enqueue: { $0() }))
    _ = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    try expect(coordinator.windowWillClose(objectID: "window-1") == .discardedReordered, "reordered will-close remains a discarded lifecycle result")
    try expect(!coordinator.hasActiveGeneration, "every matching terminal will-close clears control and lifecycle state")
    try expect(!trace.events.contains(where: { if case .closeCompleted = $0 { return true }; return false }), "discarded ordering emits no false close-completed record")
    let next = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-002", "sample_id": "create-002"]))
    try expect(next.fixtureToken == "fixture-win-CCCC", "cleared control accepts the next generation")
}

func testCoordinatorShutdownClearsActiveGenerationAndPendingWorkBeforeClosingFixture() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    var queued: [() -> Void] = []
    let pending = PendingWorkModel(trace: trace, enqueue: { queued.append($0) })
    let control = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB"]))
    let coordinator = FixtureCoordinator(control: control, lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: pending)
    _ = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    _ = coordinator.didChangeOcclusionState(objectID: "window-1", isVisible: true)
    _ = try coordinator.handle(FixtureRequest(command: "probe_pending_work", fields: ["request_id": "req-002", "sample_id": "probe-001"]))
    coordinator.shutdown()
    try expect(!coordinator.hasActiveGeneration && pending.state == .shutDown, "shutdown leaves no active generation or pending work")
    try expect(Array(window.operations.suffix(2)) == ["clearAccessibilityIdentifier:window-1", "performClose:window-1"], "shutdown clears the exact fixture identifier before closing it")
}

func testCoordinatorRejectsPendingProbeWithoutCompletedMatchingGeneration() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    let control = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB"]))
    var queued: [() -> Void] = []
    let pending = PendingWorkModel(trace: trace, enqueue: { queued.append($0) })
    let coordinator = FixtureCoordinator(control: control, lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: pending)
    _ = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    try expectThrows(FixtureControlError.commandRejected(.unknownFixtureToken)) {
        _ = try coordinator.handle(FixtureRequest(command: "probe_pending_work", fields: ["request_id": "req-002", "sample_id": "probe-001"]))
    }
    _ = coordinator.didChangeOcclusionState(objectID: "window-1", isVisible: true)
    _ = try coordinator.handle(FixtureRequest(command: "probe_pending_work", fields: ["request_id": "req-003", "sample_id": "probe-002"]))
    try expect(queued.count == 1, "probe queues exactly one pending main-work closure")
}

let fixtureCoordinatorTests: [(String, () throws -> Void)] = [
    ("coordinator creates, registers, traces, and orders front in frozen order", testCoordinatorCreateRegistersTracesAndOrdersFrontInFrozenOrder),
    ("coordinator closes only the matching fixture in frozen order", testCoordinatorCloseTracesThenPerformsOnlyMatchingFixtureClose),
    ("coordinator aborts a post-assignment create failure transactionally", testCoordinatorCreateFailureAfterAssignmentClearsAndAbortsExactWindow),
    ("coordinator rejects premature close without poisoning its generation", testCoordinatorRejectsCloseBeforeCompletionWithoutPoisoningGeneration),
    ("coordinator clears control for reordered will-close without a false completion", testCoordinatorClearsControlForReorderedWillCloseWithoutFalseCloseRecord),
    ("coordinator shutdown clears state before closing the fixture", testCoordinatorShutdownClearsActiveGenerationAndPendingWorkBeforeClosingFixture),
    ("coordinator queues pending work only for a recorded visible completion", testCoordinatorRejectsPendingProbeWithoutCompletedMatchingGeneration),
]
