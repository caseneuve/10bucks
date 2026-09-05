import Darwin
import Foundation

public enum TraceError: Error, Equatable {
    case invalidToken(String)
    case unapprovedField(String)
    case unsafeScalar(String)
    case invalidSequence(expected: UInt64, received: UInt64)
    case conversionOverflow
    case unsafeOutputPermissions
    case outputAlreadyExists
    case outputOpenFailed
    case outputWriteFailed
    case outputClosed
}

public enum TraceScalar: Equatable {
    case string(String)
    case unsigned(UInt64)
}

public struct TraceRecord {
    public let runID: String
    public let sampleID: String
    public let sequence: UInt64
    public let event: String
    public let clock: ClockReading
    public let approvedFields: [String: TraceScalar]

    public init(
        runID: String,
        sampleID: String,
        sequence: UInt64,
        event: String,
        clock: ClockReading,
        approvedFields: [String: TraceScalar] = [:]
    ) {
        self.runID = runID
        self.sampleID = sampleID
        self.sequence = sequence
        self.event = event
        self.clock = clock
        self.approvedFields = approvedFields
    }

    public init(
        runID: String,
        sampleID: String,
        sequence: UInt64,
        event: String,
        clock: ClockReading,
        approvedFields: [String: String]
    ) {
        self.init(
            runID: runID,
            sampleID: sampleID,
            sequence: sequence,
            event: event,
            clock: clock,
            approvedFields: approvedFields.mapValues(TraceScalar.string)
        )
    }
}

public enum Trace {
    public static let schema = "poc001-fixture-v1"

    // This is deliberately a small, explicit vocabulary. New trace data must be
    // reviewed here rather than allowing fixture or host identifiers by default.
    private static let approvedStringFieldNames: Set<String> = [
        "fixture_token", "correlation_token", "request_id", "origin", "status", "reason"
    ]
    private static let approvedUnsignedFieldNames: Set<String> = [
        "timebase_numer", "timebase_denom", "elapsed_ticks"
    ]

    public static func encode(_ record: TraceRecord) throws -> Data {
        try validateToken(record.runID, field: "run_id")
        try validateToken(record.sampleID, field: "sample_id")
        try validateToken(record.event, field: "event")
        for (name, value) in record.approvedFields {
            switch value {
            case let .string(string) where approvedStringFieldNames.contains(name):
                try validateApprovedScalar(string, field: name)
            case .unsigned where approvedUnsignedFieldNames.contains(name):
                break
            default:
                throw TraceError.unapprovedField(name)
            }
        }

        let nanoseconds: UInt64
        do {
            nanoseconds = try Clock.nanoseconds(ticks: record.clock.ticks, timebase: record.clock.timebase)
        } catch ClockError.conversionOverflow {
            throw TraceError.conversionOverflow
        }

        var object: [String: Any] = [
            "schema": schema,
            "run_id": record.runID,
            "sample_id": record.sampleID,
            "sequence": record.sequence,
            "event": record.event,
            "clock_kind": record.clock.kind.rawValue,
            "ticks": record.clock.ticks,
            "monotonic_ms": Clock.monotonicMilliseconds(nanoseconds: nanoseconds),
        ]
        for (name, value) in record.approvedFields {
            switch value {
            case let .string(string): object[name] = string
            case let .unsigned(unsigned): object[name] = unsigned
            }
        }
        guard var line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            throw TraceError.outputWriteFailed
        }
        line.append(0x0A)
        return line
    }

    private static func validateToken(_ value: String, field: String) throws {
        guard !value.isEmpty, value.unicodeScalars.allSatisfy(isSafeTokenScalar) else {
            throw TraceError.invalidToken(field)
        }
    }

    private static func validateApprovedScalar(_ value: String, field: String) throws {
        guard !value.isEmpty, value.unicodeScalars.allSatisfy(isSafeTokenScalar) else {
            throw TraceError.unsafeScalar(field)
        }
        if field == "fixture_token", !value.hasPrefix("fixture-win-") {
            throw TraceError.unsafeScalar(field)
        }
        if field == "correlation_token", !value.hasPrefix("corr-") {
            throw TraceError.unsafeScalar(field)
        }
    }

    private static func isSafeTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 46, 48...57, 65...90, 95, 97...122: return true // - . 0-9 A-Z _ a-z
        default: return false
        }
    }
}

public struct TraceBuffer {
    private var nextSequence: UInt64 = 1
    public private(set) var lines: [Data] = []

    public init() {}

    public mutating func append(_ record: TraceRecord) throws {
        guard record.sequence == nextSequence else {
            throw TraceError.invalidSequence(expected: nextSequence, received: record.sequence)
        }
        lines.append(try Trace.encode(record))
        nextSequence += 1
    }
}

public final class TraceWriter {
    private let descriptor: Int32
    private var nextSequence: UInt64 = 1
    private var closed = false

    public init(createAt url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            if errno == EEXIST {
                var existing = stat()
                if stat(url.path, &existing) == 0, (existing.st_mode & 0o777) != 0o600 {
                    throw TraceError.unsafeOutputPermissions
                }
                throw TraceError.outputAlreadyExists
            }
            throw TraceError.outputOpenFailed
        }
        guard fchmod(descriptor, 0o600) == 0 else {
            Darwin.close(descriptor)
            throw TraceError.unsafeOutputPermissions
        }
        var created = stat()
        guard fstat(descriptor, &created) == 0, (created.st_mode & 0o777) == 0o600 else {
            Darwin.close(descriptor)
            throw TraceError.unsafeOutputPermissions
        }
        self.descriptor = descriptor
    }

    deinit { if !closed { Darwin.close(descriptor) } }

    public func append(_ record: TraceRecord) throws {
        guard !closed else { throw TraceError.outputClosed }
        guard record.sequence == nextSequence else {
            throw TraceError.invalidSequence(expected: nextSequence, received: record.sequence)
        }
        let line = try Trace.encode(record)
        let result = line.withUnsafeBytes { write(descriptor, $0.baseAddress, line.count) }
        guard result == line.count else { throw TraceError.outputWriteFailed }
        nextSequence += 1
    }

    public func close() throws {
        guard !closed else { return }
        guard Darwin.close(descriptor) == 0 else { throw TraceError.outputWriteFailed }
        closed = true
    }
}
