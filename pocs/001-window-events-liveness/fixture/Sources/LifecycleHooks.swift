import Foundation

public enum CloseOrigin: Equatable { case ipc, user }

public enum FixtureTraceEvent: Equatable {
    case createRequested(token: String, generation: UInt64, sampleID: String)
    case createKeyCandidate(token: String, generation: UInt64, sampleID: String)
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
    case recordedCreateCandidate
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
    fileprivate var keyCandidateRecorded: Bool
    fileprivate var closeRequested: Bool
    fileprivate var closeSampleID: String?

    public var isKeyCandidateRecorded: Bool { keyCandidateRecorded }
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
        active = LifecycleActiveGeneration(token: token, generation: generation, objectID: objectID, createSampleID: createSampleID, keyCandidateRecorded: false, closeRequested: false, closeSampleID: nil)
    }

    public mutating func didBecomeKeyCandidate(objectID: String) -> LifecycleHookResult {
        guard var active else { return .rejectedDuplicate }
        guard active.objectID == objectID else { return .rejectedWrongObject }
        guard !active.keyCandidateRecorded else { return .rejectedDuplicate }
        active.keyCandidateRecorded = true
        self.active = active
        trace.record(.createKeyCandidate(token: active.token, generation: active.generation, sampleID: active.createSampleID))
        return .recordedCreateCandidate
    }

    @discardableResult
    public mutating func requestClose(token: String, generation: UInt64, closeSampleID: String) -> Bool {
        guard var active, active.token == token, active.generation == generation, active.keyCandidateRecorded, !active.closeRequested else { return false }
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
        guard active.keyCandidateRecorded else { return .discardedReordered }
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
