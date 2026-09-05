import Darwin
import Foundation

func testClockSelectionAndMetadata() throws {
    let continuous = try Clock.makeReading(
        timebaseStatus: KERN_SUCCESS,
        continuousAvailable: true,
        continuousTicks: 101,
        absoluteTicks: 202,
        timebase: MachTimebase(numer: 125, denom: 3)
    )
    try expect(continuous.kind == .machContinuous, "uses continuous clock when available")
    try expect(continuous.ticks == 101, "retains continuous ticks")
    try expect(continuous.timebase == MachTimebase(numer: 125, denom: 3), "retains timebase metadata")

    let fallback = try Clock.makeReading(
        timebaseStatus: KERN_SUCCESS,
        continuousAvailable: false,
        continuousTicks: 101,
        absoluteTicks: 202,
        timebase: MachTimebase(numer: 1, denom: 1)
    )
    try expect(fallback.kind == .machAbsolute, "falls back to absolute clock")
    try expect(fallback.ticks == 202, "retains absolute fallback ticks")
}

func testCorrelationClockModeSelectsAbsoluteAndRejectsInvalidConfiguration() throws {
    let defaultKind = try Clock.kind(environment: [:])
    let correlationKind = try Clock.kind(environment: ["POC001_FIXTURE_CLOCK_KIND": "mach_absolute"])
    try expect(defaultKind == .machContinuous, "defaults standalone fixture runs to continuous time")
    try expect(correlationKind == .machAbsolute, "selects absolute time explicitly for correlation")
    try expectThrows(ClockError.invalidClockKind) {
        _ = try Clock.kind(environment: ["POC001_FIXTURE_CLOCK_KIND": "continuous-ish"])
    }
}

func testClockRejectsFailedOrZeroTimebase() throws {
    try expectThrows(ClockError.timebaseUnavailable) {
        _ = try Clock.makeReading(
            timebaseStatus: KERN_FAILURE,
            continuousAvailable: true,
            continuousTicks: 1,
            absoluteTicks: 2,
            timebase: MachTimebase(numer: 1, denom: 1)
        )
    }
    for timebase in [MachTimebase(numer: 0, denom: 1), MachTimebase(numer: 1, denom: 0)] {
        try expectThrows(ClockError.timebaseUnavailable) {
            _ = try Clock.makeReading(
                timebaseStatus: KERN_SUCCESS,
                continuousAvailable: true,
                continuousTicks: 1,
                absoluteTicks: 2,
                timebase: timebase
            )
        }
    }
}

func testElapsedTicksIsChecked() throws {
    let elapsed = try Clock.elapsedTicks(start: 40, end: 41)
    try expect(elapsed == 1, "calculates elapsed ticks")
    try expectThrows(ClockError.tickUnderflow) {
        _ = try Clock.elapsedTicks(start: 41, end: 40)
    }
}

func testNanosecondConversionUsesQuotientAndRemainder() throws {
    let converted = try Clock.nanoseconds(ticks: 17, timebase: MachTimebase(numer: 10, denom: 3))
    try expect(converted == 56, "uses q * numer + (r * numer) / denom")
    try expect(Clock.monotonicMilliseconds(nanoseconds: 2_999_999) == 2, "floors display milliseconds")
}

func testNanosecondConversionRejectsInvalidAndOverflowingValues() throws {
    try expectThrows(ClockError.invalidTimebase) {
        _ = try Clock.nanoseconds(ticks: 1, timebase: MachTimebase(numer: 1, denom: 0))
    }
    try expectThrows(ClockError.conversionOverflow) {
        _ = try Clock.nanoseconds(ticks: UInt64.max, timebase: MachTimebase(numer: UInt64.max, denom: 1))
    }
    try expectThrows(ClockError.conversionOverflow) {
        _ = try Clock.nanoseconds(ticks: UInt64.max - 1, timebase: MachTimebase(numer: 2, denom: UInt64.max))
    }
}

let clockTests: [(String, () throws -> Void)] = [
    ("clock selects continuous and fallback metadata", testClockSelectionAndMetadata),
    ("correlation clock mode selects absolute and fails closed", testCorrelationClockModeSelectsAbsoluteAndRejectsInvalidConfiguration),
    ("clock rejects failed and zero timebase metadata", testClockRejectsFailedOrZeroTimebase),
    ("clock checks elapsed tick subtraction", testElapsedTicksIsChecked),
    ("clock converts ticks with quotient and remainder", testNanosecondConversionUsesQuotientAndRemainder),
    ("clock rejects invalid and overflowing conversion", testNanosecondConversionRejectsInvalidAndOverflowingValues),
]
