import AppKit
import Foundation

private final class AppKitWindowPort: NSObject, FixtureWindowPort, NSWindowDelegate {
    weak var coordinator: FixtureCoordinator?
    private var windows: [String: NSWindow] = [:]
    private var nextObject = 1

    func createWindow() throws -> String {
        precondition(Thread.isMainThread)
        let objectID = "fixture-object-\(nextObject)"
        nextObject += 1
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        windows[objectID] = window
        return objectID
    }

    func assignCorrelationToken(_ token: String, objectID: String) throws {
        precondition(Thread.isMainThread)
        windows[objectID]?.setAccessibilityIdentifier(token)
    }

    func clearCorrelationToken(objectID: String) {
        precondition(Thread.isMainThread)
        windows[objectID]?.setAccessibilityIdentifier(nil)
    }

    func abortCreatedWindow(objectID: String) {
        precondition(Thread.isMainThread)
        windows[objectID]?.performClose(nil)
    }

    func orderFront(objectID: String) {
        precondition(Thread.isMainThread)
        windows[objectID]?.orderFrontRegardless()
    }

    func performClose(objectID: String) {
        precondition(Thread.isMainThread)
        windows[objectID]?.performClose(nil)
    }

    // Fixture-local visibility measurement only. The exact registered window
    // must report at least partial visibility; focus/key status is irrelevant.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        precondition(Thread.isMainThread)
        guard let window = notification.object as? NSWindow,
              let objectID = objectID(for: window) else { return }
        _ = coordinator?.didChangeOcclusionState(
            objectID: objectID,
            isVisible: window.occlusionState.contains(.visible)
        )
    }

    func windowWillClose(_ notification: Notification) {
        precondition(Thread.isMainThread)
        guard let window = notification.object as? NSWindow, let objectID = objectID(for: window) else { return }
        _ = coordinator?.windowWillClose(objectID: objectID)
        windows.removeValue(forKey: objectID)
    }

    func closeAllFixtureWindows() {
        precondition(Thread.isMainThread)
        for objectID in Array(windows.keys) { performClose(objectID: objectID) }
    }

    private func objectID(for window: NSWindow) -> String? {
        windows.first(where: { $0.value === window })?.key
    }
}

private final class AppTraceSink: FixtureTraceSink {
    private let writer: TraceWriter
    private let runID: String
    private let clockKind: ClockKind
    private var sequence: UInt64 = 1
    private var starts: [String: UInt64] = [:]

    init(writer: TraceWriter, runID: String, clockKind: ClockKind) {
        self.writer = writer; self.runID = runID; self.clockKind = clockKind
    }

    func record(_ event: FixtureTraceEvent) {
        precondition(Thread.isMainThread, "trace writes must run on the main thread")
        do {
            let clock = try Clock.nowTicks(kind: clockKind)
            let mapped: (String, String, [String: TraceScalar], String?, Bool)
            switch event {
            case let .createRequested(token, correlationAlias, generation, sample): mapped = ("create_requested", sample, ["fixture_token": .string(token), "correlation_alias": .string(correlationAlias)], key(token, generation, "create_visible"), false)
            case let .createVisibleCompleted(token, generation, sample): mapped = ("fixture_create_visible_completed", sample, ["fixture_token": .string(token)], key(token, generation, "create_visible"), true)
            case let .closeRequested(token, generation, sample): mapped = ("close_requested", sample, ["fixture_token": .string(token)], key(token, generation, "close"), false)
            case let .closeCompleted(token, generation, sample, origin): mapped = ("native_close_completed", sample, ["fixture_token": .string(token), "origin": .string(origin == .ipc ? "ipc" : "user")], key(token, generation, "close"), true)
            case let .pendingWorkRequested(token, generation, sample): mapped = ("pending_work_requested", sample, ["fixture_token": .string(token)], key(token, generation, "pending"), false)
            case let .pendingWorkServiced(token, generation, sample): mapped = ("pending_work_serviced", sample, ["fixture_token": .string(token)], key(token, generation, "pending"), true)
            }
            var fields = mapped.2
            if let key = mapped.3 {
                if mapped.4, let start = starts.removeValue(forKey: key) {
                    fields["elapsed_ticks"] = .unsigned(try Clock.elapsedTicks(start: start, end: clock.ticks))
                } else if !mapped.4 {
                    starts[key] = clock.ticks
                }
            }
            try append(event: mapped.0, sampleID: mapped.1, fields: fields, clock: clock)
        } catch {
            fatalError("fixture trace failure")
        }
    }

    func append(event: String, sampleID: String, fields: [String: TraceScalar] = [:]) {
        precondition(Thread.isMainThread, "trace writes must run on the main thread")
        do { try append(event: event, sampleID: sampleID, fields: fields, clock: Clock.nowTicks(kind: clockKind)) }
        catch { fatalError("fixture trace failure") }
    }

    private func append(event: String, sampleID: String, fields: [String: TraceScalar], clock: ClockReading) throws {
        try writer.append(TraceRecord(runID: runID, sampleID: sampleID, sequence: sequence, event: event, clock: clock, approvedFields: fields))
        sequence += 1
    }

    private func key(_ token: String, _ generation: UInt64, _ kind: String) -> String { "\(token).\(generation).\(kind)" }

    func close() throws { precondition(Thread.isMainThread); try writer.close() }
}

@main
final class POC001FixtureApp: NSObject, NSApplicationDelegate {
    private var server: FixtureSocketServer?
    private var coordinator: FixtureCoordinator?
    private var windows: AppKitWindowPort?
    private var trace: AppTraceSink?
    private var stopping = false

    static func main() {
        let app = NSApplication.shared
        let delegate = POC001FixtureApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        precondition(Thread.isMainThread)
        do {
            let runDirectory = try requiredRunDirectory()
            // Validate the mode before creating any trace/socket artifact.
            let clockKind = try Clock.kind(environment: ProcessInfo.processInfo.environment)
            let writer = try TraceWriter(createAt: runDirectory.appendingPathComponent("trace.ndjson"))
            let runID = "run-" + String(try SecureTokenGenerator().fixtureToken().dropFirst(12))
            let sink = AppTraceSink(writer: writer, runID: runID, clockKind: clockKind)
            // Each trace record contains the selected clock kind and timebase;
            // this startup record makes the choice explicit before any action.
            sink.append(event: "run_started", sampleID: "startup")
            let port = AppKitWindowPort()
            let pending = PendingWorkModel(trace: sink, enqueue: { work in DispatchQueue.main.async(execute: work) })
            let lifecycle = FixtureLifecycleHooks(trace: sink, cancelGeneration: { [weak pending] token, generation in pending?.cancel(token: token, generation: generation) })
            let coordinator = FixtureCoordinator(control: FixtureControl(tokenGenerator: SecureTokenGenerator()), lifecycle: lifecycle, windows: port, trace: sink, pending: pending)
            port.coordinator = coordinator
            self.trace = sink; self.windows = port; self.coordinator = coordinator
            let socket = runDirectory.appendingPathComponent("poc001-fixture.sock")
            server = try FixtureSocketServer(socketPath: socket, dispatch: { [weak self] request in
                guard let self, let coordinator = self.coordinator else { throw FixtureControlError.invalidRequest }
                return try coordinator.handle(request)
            }, afterResponse: { [weak self] request in
                guard request.command == "shutdown" else { return }
                self?.finishShutdown()
            })
            sink.append(event: "socket_ready", sampleID: "startup")
            serveInBackground()
        } catch {
            NSApp.terminate(nil)
        }
    }

    private func serveInBackground() {
        guard let server else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self, server] in
            while true {
                do { try server.serveOne() } catch { return }
                let shouldStop = DispatchQueue.main.sync { self?.stopping ?? true }
                if shouldStop { return }
            }
        }
    }

    private func finishShutdown() {
        precondition(Thread.isMainThread)
        guard !stopping else { return }
        stopping = true
        coordinator?.shutdown()
        windows?.closeAllFixtureWindows()
        try? server?.shutdown()
        try? trace?.close()
        NSApp.terminate(nil)
    }

    private func requiredRunDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["POC001_FIXTURE_RUN_DIR"], !path.isEmpty else { throw IPCError.unsafeRunDirectory }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FixtureSocketServer.validateRunDirectory(directory)
        return directory
    }
}
