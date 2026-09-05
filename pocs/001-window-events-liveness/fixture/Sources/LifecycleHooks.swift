import Foundation

public enum CloseOrigin: Equatable { case ipc, user }

public enum FixtureTraceEvent: Equatable {
    case createCompleted(token: String, generation: UInt64)
    case closeCompleted(token: String, generation: UInt64, origin: CloseOrigin)
    case pendingWorkRequested(token: String, generation: UInt64)
    case pendingWorkServiced(token: String, generation: UInt64)
}

public protocol FixtureTraceSink: AnyObject {
    func record(_ event: FixtureTraceEvent)
}

final class RecordingTraceSink: FixtureTraceSink {
    private(set) var events: [FixtureTraceEvent] = []
    func record(_ event: FixtureTraceEvent) { events.append(event) }
}

public enum FixtureLifecycleError: Error, Equatable {
    case activeGenerationExists
    case duplicateGeneration
    case noActiveGeneration
}

public enum LifecycleHookResult: Equatable {
    case completedCreate
    case completedClose(CloseOrigin)
    case rejectedWrongObject
    case rejectedDuplicate
    case rejectedReordered
}

public struct LifecycleActiveGeneration: Equatable {
    public let token: String
    public let generation: UInt64
    public let objectID: String
    fileprivate var createCompleted: Bool
    fileprivate var closeRequested: Bool
}

public struct FixtureLifecycleHooks {
    private let trace: FixtureTraceSink
    public private(set) var active: LifecycleActiveGeneration?
    private var usedGenerations: Set<UInt64> = []

    public init(trace: FixtureTraceSink) { self.trace = trace }

    public mutating func register(token: String, generation: UInt64, objectID: String) throws {
        guard active == nil else { throw FixtureLifecycleError.activeGenerationExists }
        guard usedGenerations.insert(generation).inserted else { throw FixtureLifecycleError.duplicateGeneration }
        active = LifecycleActiveGeneration(token: token, generation: generation, objectID: objectID, createCompleted: false, closeRequested: false)
    }

    public mutating func didBecomeVisible(objectID: String) -> LifecycleHookResult {
        guard var active else { return .rejectedDuplicate }
        guard active.objectID == objectID else { return .rejectedWrongObject }
        guard !active.createCompleted else { return .rejectedDuplicate }
        active.createCompleted = true
        self.active = active
        trace.record(.createCompleted(token: active.token, generation: active.generation))
        return .completedCreate
    }

    @discardableResult
    public mutating func requestClose(token: String, generation: UInt64) -> Bool {
        guard var active, active.token == token, active.generation == generation, active.createCompleted, !active.closeRequested else { return false }
        active.closeRequested = true
        self.active = active
        return true
    }

    public mutating func windowWillClose(objectID: String) -> LifecycleHookResult {
        guard let active else { return .rejectedDuplicate }
        guard active.objectID == objectID else { return .rejectedWrongObject }
        guard active.createCompleted else { return .rejectedReordered }
        let origin: CloseOrigin = active.closeRequested ? .ipc : .user
        trace.record(.closeCompleted(token: active.token, generation: active.generation, origin: origin))
        self.active = nil
        return .completedClose(origin)
    }
}
