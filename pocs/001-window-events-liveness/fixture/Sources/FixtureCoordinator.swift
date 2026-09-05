import Foundation

// The coordinator is the single main-thread owner of FixtureControl and
// FixtureLifecycleHooks. AppKit and socket implementations are ports so this
// ordering remains pure-testable without a run loop or a real window.
public protocol FixtureWindowPort: AnyObject {
    func createWindow() throws -> String
    func orderFront(objectID: String)
    func performClose(objectID: String)
}

public final class FixtureCoordinator {
    private var control: FixtureControl
    private var lifecycle: FixtureLifecycleHooks
    private let windows: FixtureWindowPort
    private let trace: FixtureTraceSink
    private let pending: PendingWorkModel
    public private(set) var operations: [String] = []

    public init(control: FixtureControl, lifecycle: FixtureLifecycleHooks, windows: FixtureWindowPort, trace: FixtureTraceSink, pending: PendingWorkModel) {
        self.control = control
        self.lifecycle = lifecycle
        self.windows = windows
        self.trace = trace
        self.pending = pending
    }

    public func handle(_ request: FixtureRequest) throws -> FixtureResponse {
        precondition(Thread.isMainThread, "FixtureCoordinator must run on the main thread")
        switch request.command {
        case "create": return try create(request)
        case "probe_pending_work": return try probe(request)
        case "close": return try close(request)
        case "shutdown":
            operations.append("shutdown")
            return try control.handle(request)
        default:
            throw FixtureControlError.invalidRequest
        }
    }

    public func didBecomeVisible(objectID: String) -> LifecycleHookResult {
        precondition(Thread.isMainThread, "FixtureCoordinator must run on the main thread")
        return lifecycle.didBecomeVisible(objectID: objectID)
    }

    public func windowWillClose(objectID: String) -> LifecycleHookResult {
        precondition(Thread.isMainThread, "FixtureCoordinator must run on the main thread")
        let result = lifecycle.windowWillClose(objectID: objectID)
        if case .completedClose = result, let active = control.activeGeneration {
            _ = control.completeClose(token: active.token, generation: active.generation)
        }
        return result
    }

    public func shutdown() {
        precondition(Thread.isMainThread, "FixtureCoordinator must run on the main thread")
        pending.shutdown()
        guard let active = lifecycle.active else { return }
        // A shutdown is allowed to close the sole fixture window even when the
        // operator did not issue close. It never enumerates or touches another window.
        windows.performClose(objectID: active.objectID)
    }

    private func create(_ request: FixtureRequest) throws -> FixtureResponse {
        let response = try control.handle(request)
        guard let active = control.activeGeneration else { throw FixtureControlError.invalidRequest }
        operations.append("create")
        let objectID = try windows.createWindow()
        try lifecycle.register(token: active.token, generation: active.generation, objectID: objectID, createSampleID: active.createSampleID)
        operations.append("register:\(objectID)")
        trace.record(.createRequested(token: active.token, generation: active.generation, sampleID: active.createSampleID))
        operations.append("trace:create_requested")
        windows.orderFront(objectID: objectID)
        operations.append("orderFront:\(objectID)")
        return response
    }

    private func probe(_ request: FixtureRequest) throws -> FixtureResponse {
        guard let active = lifecycle.active, active.isCreateCompleted else {
            throw FixtureControlError.commandRejected(.unknownFixtureToken)
        }
        let response = try control.handle(request)
        guard pending.request(token: active.token, generation: active.generation, sampleID: request.fields["sample_id"]!) else {
            throw FixtureControlError.commandRejected(.unknownFixtureToken)
        }
        return response
    }

    private func close(_ request: FixtureRequest) throws -> FixtureResponse {
        guard let active = lifecycle.active, active.isCreateCompleted,
              request.fields["fixture_token"] == active.token else {
            throw FixtureControlError.commandRejected(.unknownFixtureToken)
        }
        let response = try control.handle(request)
        guard lifecycle.requestClose(token: active.token, generation: active.generation, closeSampleID: request.fields["sample_id"]!) else {
            throw FixtureControlError.commandRejected(.unknownFixtureToken)
        }
        operations.append("close")
        operations.append("requestClose:\(active.objectID)")
        trace.record(.closeRequested(token: active.token, generation: active.generation, sampleID: request.fields["sample_id"]!))
        operations.append("trace:close_requested")
        windows.performClose(objectID: active.objectID)
        operations.append("performClose:\(active.objectID)")
        return response
    }
}
