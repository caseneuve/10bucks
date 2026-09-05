import Foundation

func testPendingWorkQueuesExactlyOneClosureAndEmitsOneServiceRecord() throws {
    let trace = RecordingTraceSink()
    var queued: [() -> Void] = []
    let model = PendingWorkModel(trace: trace, enqueue: { queued.append($0) })

    try expect(model.request(token: "fixture-win-AAAA", generation: 1), "first request queues one closure")
    try expect(!model.request(token: "fixture-win-AAAA", generation: 1), "duplicate request is rejected while one is queued")
    try expect(queued.count == 1, "only one closure is queued")
    queued.removeFirst()()
    try expect(model.state == .idle, "servicing clears pending state")
    try expect(trace.events == [
        .pendingWorkRequested(token: "fixture-win-AAAA", generation: 1),
        .pendingWorkServiced(token: "fixture-win-AAAA", generation: 1),
    ], "emits one requested and one serviced trace record")
    queued.forEach { $0() }
    try expect(trace.events.count == 2, "a stale invocation cannot emit another service record")
}

func testPendingWorkCancelsOnCloseAndRejectsAfterShutdown() throws {
    let trace = RecordingTraceSink()
    var queued: [() -> Void] = []
    let model = PendingWorkModel(trace: trace, enqueue: { queued.append($0) })
    try expect(model.request(token: "fixture-win-AAAA", generation: 1), "queues pending work")
    model.cancel(token: "fixture-win-AAAA", generation: 1)
    queued.removeFirst()()
    try expect(model.state == .idle, "close cancellation clears work")
    try expect(!trace.events.contains(.pendingWorkServiced(token: "fixture-win-AAAA", generation: 1)), "cancelled closure cannot service")
    try expect(model.request(token: "fixture-win-AAAA", generation: 2), "new generation can queue after cancellation")
    model.shutdown()
    try expect(!model.request(token: "fixture-win-AAAA", generation: 2), "shutdown rejects new pending work")
    queued.removeFirst()()
    try expect(!trace.events.contains(.pendingWorkServiced(token: "fixture-win-AAAA", generation: 2)), "shutdown cancels queued work")
}

let pendingWorkTests: [(String, () throws -> Void)] = [
    ("pending work queues one closure and records one service", testPendingWorkQueuesExactlyOneClosureAndEmitsOneServiceRecord),
    ("pending work cancels on close and rejects after shutdown", testPendingWorkCancelsOnCloseAndRejectsAfterShutdown),
]
