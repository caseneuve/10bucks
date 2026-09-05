import Foundation

public enum PendingWorkState: Equatable { case idle, queued, shutDown }

public final class PendingWorkModel {
    private let trace: FixtureTraceSink
    private let enqueue: (@escaping () -> Void) -> Void
    private var pending: (token: String, generation: UInt64)?
    public private(set) var state: PendingWorkState = .idle

    public init(trace: FixtureTraceSink, enqueue: @escaping (@escaping () -> Void) -> Void) {
        self.trace = trace
        self.enqueue = enqueue
    }

    @discardableResult
    public func request(token: String, generation: UInt64) -> Bool {
        guard state == .idle, pending == nil else { return false }
        pending = (token, generation)
        state = .queued
        trace.record(.pendingWorkRequested(token: token, generation: generation))
        enqueue { [weak self] in self?.service(token: token, generation: generation) }
        return true
    }

    public func cancel(token: String, generation: UInt64) {
        guard let pending, pending.token == token, pending.generation == generation else { return }
        self.pending = nil
        if state != .shutDown { state = .idle }
    }

    public func shutdown() {
        pending = nil
        state = .shutDown
    }

    private func service(token: String, generation: UInt64) {
        guard state == .queued, let pending, pending.token == token, pending.generation == generation else { return }
        self.pending = nil
        state = .idle
        trace.record(.pendingWorkServiced(token: token, generation: generation))
    }
}
