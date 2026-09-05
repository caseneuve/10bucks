import Foundation

public enum CloseOrigin: Equatable { case ipc, user }

public enum FixtureTraceEvent: Equatable {
    case createRequested(token: String, generation: UInt64, sampleID: String)
    // Fixture-local AppKit observation only: this reports the first callback
    // for the exact registered NSWindow whose occlusion state contains .visible.
    case createVisibleCompleted(token: String, generation: UInt64, sampleID: String)
    case closeRequested(token: String, generation: UInt64, sampleID: String)
    case closeCompleted(token: String, generation: UInt64, sampleID: String, origin: CloseOrigin)
    case pendingWorkRequested(token: String, generation: UInt64, sampleID: String)
    case pendingWorkServiced(token: String, generation: UInt64, sampleID: String)
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
    case recordedCreateVisibleCompletion
    case ignoredNotVisible
    case completedClose(CloseOrigin)
    case rejectedWrongObject
    case rejectedDuplicate
    case discardedReordered
}

public struct LifecycleActiveGeneration: Equatable {
    public let token: String
    public let generation: UInt64
    public let objectID: String
    public let createSampleID: String
    fileprivate var createVisibleCompleted: Bool
    fileprivate var closeRequested: Bool
    fileprivate var closeSampleID: String?

    public var isCreateVisibleCompleted: Bool { createVisibleCompleted }
}

public struct FixtureLifecycleHooks {
    private let trace: FixtureTraceSink
    private let cancelGeneration: (String, UInt64) -> Void
    public private(set) var active: LifecycleActiveGeneration?
    private var usedGenerations: Set<UInt64> = []

    public init(trace: FixtureTraceSink, cancelGeneration: @escaping (String, UInt64) -> Void = { _, _ in }) {
        self.trace = trace
        self.cancelGeneration = cancelGeneration
    }

    public mutating func register(token: String, generation: UInt64, objectID: String, createSampleID: String) throws {
        guard active == nil else { throw FixtureLifecycleError.activeGenerationExists }
        guard usedGenerations.insert(generation).inserted else { throw FixtureLifecycleError.duplicateGeneration }
        active = LifecycleActiveGeneration(token: token, generation: generation, objectID: objectID, createSampleID: createSampleID, createVisibleCompleted: false, closeRequested: false, closeSampleID: nil)
    }

    // This completion is deliberately narrower than liveness: AppKit has
    // reported that this fixture window is at least partially visible.
    public mutating func didChangeOcclusionState(objectID: String, isVisible: Bool) -> LifecycleHookResult {
        guard var active else { return .rejectedDuplicate }
        guard active.objectID == objectID else { return .rejectedWrongObject }
        guard isVisible else { return .ignoredNotVisible }
        guard !active.createVisibleCompleted else { return .rejectedDuplicate }
        active.createVisibleCompleted = true
        self.active = active
        trace.record(.createVisibleCompleted(token: active.token, generation: active.generation, sampleID: active.createSampleID))
        return .recordedCreateVisibleCompletion
    }

    @discardableResult
    public mutating func requestClose(token: String, generation: UInt64, closeSampleID: String) -> Bool {
        guard var active, active.token == token, active.generation == generation, active.createVisibleCompleted, !active.closeRequested else { return false }
        active.closeRequested = true
        active.closeSampleID = closeSampleID
        self.active = active
        return true
    }

    public mutating func windowWillClose(objectID: String) -> LifecycleHookResult {
        guard let active else { return .rejectedDuplicate }
        guard active.objectID == objectID else { return .rejectedWrongObject }
        self.active = nil
        cancelGeneration(active.token, active.generation)
        guard active.createVisibleCompleted else { return .discardedReordered }
        let origin: CloseOrigin = active.closeRequested ? .ipc : .user
        let sampleID = active.closeSampleID ?? active.createSampleID
        trace.record(.closeCompleted(token: active.token, generation: active.generation, sampleID: sampleID, origin: origin))
        return .completedClose(origin)
    }

    @discardableResult
    public mutating func discardForShutdown() -> LifecycleActiveGeneration? {
        guard let active else { return nil }
        self.active = nil
        cancelGeneration(active.token, active.generation)
        return active
    }
}
