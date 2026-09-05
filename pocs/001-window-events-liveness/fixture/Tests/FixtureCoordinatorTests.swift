import Foundation

private final class CoordinatorTrace: FixtureTraceSink {
    var events: [FixtureTraceEvent] = []
    func record(_ event: FixtureTraceEvent) { events.append(event) }
}

private final class CoordinatorWindowPort: FixtureWindowPort {
    var operations: [String] = []
    func createWindow() throws -> String { operations.append("create"); return "window-1" }
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
    try expect(window.operations == ["create", "orderFront:window-1"], "creates then orders only the fixture window")
    try expect(coordinator.operations == ["create", "register:window-1", "trace:create_requested", "orderFront:window-1"], "create has exact register/trace/order-front ordering")
}

func testCoordinatorCloseTracesThenPerformsOnlyMatchingFixtureClose() throws {
    let trace = CoordinatorTrace()
    let window = CoordinatorWindowPort()
    let control = FixtureControl(tokenGenerator: DeterministicTokenGenerator(values: ["AAAA", "BBBB"]))
    let coordinator = FixtureCoordinator(control: control, lifecycle: FixtureLifecycleHooks(trace: trace), windows: window, trace: trace, pending: PendingWorkModel(trace: trace, enqueue: { $0() }))
    let created = try coordinator.handle(FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "create-001"]))
    _ = coordinator.didBecomeVisible(objectID: "window-1")
    let beforeClose = coordinator.operations.count

    _ = try coordinator.handle(FixtureRequest(command: "close", fields: ["request_id": "req-002", "sample_id": "close-001", "fixture_token": created.fixtureToken!]))
    try expect(Array(coordinator.operations.dropFirst(beforeClose)) == ["close", "requestClose:window-1", "trace:close_requested", "performClose:window-1"], "close requests, traces, and performs close in frozen order")
    try expect(window.operations.last == "performClose:window-1", "never uses unrelated window APIs")
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
    _ = coordinator.didBecomeVisible(objectID: "window-1")
    _ = try coordinator.handle(FixtureRequest(command: "close", fields: ["request_id": "req-003", "sample_id": "close-002", "fixture_token": created.fixtureToken!]))
    try expect(window.operations.last == "performClose:window-1", "rejected premature close leaves the completed generation closable")
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
    _ = coordinator.didBecomeVisible(objectID: "window-1")
    _ = try coordinator.handle(FixtureRequest(command: "probe_pending_work", fields: ["request_id": "req-003", "sample_id": "probe-002"]))
    try expect(queued.count == 1, "probe queues exactly one pending main-work closure")
}

let fixtureCoordinatorTests: [(String, () throws -> Void)] = [
    ("coordinator creates, registers, traces, and orders front in frozen order", testCoordinatorCreateRegistersTracesAndOrdersFrontInFrozenOrder),
    ("coordinator closes only the matching fixture in frozen order", testCoordinatorCloseTracesThenPerformsOnlyMatchingFixtureClose),
    ("coordinator rejects premature close without poisoning its generation", testCoordinatorRejectsCloseBeforeCompletionWithoutPoisoningGeneration),
    ("coordinator queues pending work only for a completed fixture generation", testCoordinatorRejectsPendingProbeWithoutCompletedMatchingGeneration),
]
