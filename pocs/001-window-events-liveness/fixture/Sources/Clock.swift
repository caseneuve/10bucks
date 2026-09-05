import Darwin

public enum ClockKind: String, Equatable {
    case machContinuous = "mach_continuous"
    case machAbsolute = "mach_absolute"
}

public struct MachTimebase: Equatable {
    public let numer: UInt64
    public let denom: UInt64

    public init(numer: UInt64, denom: UInt64) {
        self.numer = numer
        self.denom = denom
    }
}

public struct ClockReading: Equatable {
    public let kind: ClockKind
    public let ticks: UInt64
    public let timebase: MachTimebase

    public init(kind: ClockKind, ticks: UInt64, timebase: MachTimebase) {
        self.kind = kind
        self.ticks = ticks
        self.timebase = timebase
    }
}

public enum ClockError: Error, Equatable {
    case timebaseUnavailable
    case tickUnderflow
    case invalidTimebase
    case conversionOverflow
}

public enum Clock {
    public static func nowTicks() throws -> ClockReading {
        var nativeTimebase = mach_timebase_info_data_t()
        let status = mach_timebase_info(&nativeTimebase)
        let timebase = MachTimebase(numer: UInt64(nativeTimebase.numer), denom: UInt64(nativeTimebase.denom))

        if #available(macOS 10.12, *) {
            return try makeReading(
                timebaseStatus: status,
                continuousAvailable: true,
                continuousTicks: mach_continuous_time(),
                absoluteTicks: 0,
                timebase: timebase
            )
        }
        return try makeReading(
            timebaseStatus: status,
            continuousAvailable: false,
            continuousTicks: 0,
            absoluteTicks: mach_absolute_time(),
            timebase: timebase
        )
    }

    // Keeps the raw system result and clock selection testable without mocking Darwin.
    static func makeReading(
        timebaseStatus: kern_return_t,
        continuousAvailable: Bool,
        continuousTicks: UInt64,
        absoluteTicks: UInt64,
        timebase: MachTimebase
    ) throws -> ClockReading {
        guard timebaseStatus == KERN_SUCCESS, timebase.numer != 0, timebase.denom != 0 else {
            throw ClockError.timebaseUnavailable
        }
        return ClockReading(
            kind: continuousAvailable ? .machContinuous : .machAbsolute,
            ticks: continuousAvailable ? continuousTicks : absoluteTicks,
            timebase: timebase
        )
    }

    public static func elapsedTicks(start: UInt64, end: UInt64) throws -> UInt64 {
        guard end >= start else { throw ClockError.tickUnderflow }
        return end - start
    }

    public static func nanoseconds(ticks: UInt64, timebase: MachTimebase) throws -> UInt64 {
        guard timebase.denom != 0 else { throw ClockError.invalidTimebase }
        let quotient = ticks / timebase.denom
        let remainder = ticks % timebase.denom
        let (wholeNanoseconds, wholeOverflow) = quotient.multipliedReportingOverflow(by: timebase.numer)
        let (remainderProduct, remainderOverflow) = remainder.multipliedReportingOverflow(by: timebase.numer)
        guard !wholeOverflow, !remainderOverflow else { throw ClockError.conversionOverflow }
        let fractionalNanoseconds = remainderProduct / timebase.denom
        let (result, additionOverflow) = wholeNanoseconds.addingReportingOverflow(fractionalNanoseconds)
        guard !additionOverflow else { throw ClockError.conversionOverflow }
        return result
    }

    public static func monotonicMilliseconds(nanoseconds: UInt64) -> UInt64 {
        nanoseconds / 1_000_000
    }
}
