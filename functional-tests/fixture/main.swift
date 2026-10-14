import AppKit
import Darwin

// One main-thread mailbox; this is a test fixture, not a manager or native oracle.
final class Fixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let run: String
    let directory: URL
    var sequence = 0
    var windows: [String: NSWindow] = [:]
    var numbers: [String: Int] = [:] // reuse requires an explicit closed-alias acknowledgement
    var timer: Timer?
    var creationFrames: [String: [String: Double]] = [:]
    var observationSequence = 0
    var observeNative = false
    var closedAliases = Set<String>()

    func publishObservation() {
        observationSequence += 1
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let acquired = Double(mach_absolute_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        let top = NSScreen.screens[0].frame.maxY
        var rows: [String: Any] = [:]
        for (alias, window) in windows {
            let frame = window.frame
            rows[alias] = ["windowNumber": window.windowNumber, "key": window.isKeyWindow,
                "frame": ["x": frame.minX, "y": top - frame.maxY, "w": frame.width, "h": frame.height],
                "minimized": window.isMiniaturized, "hidden": NSApp.isHidden,
                "fullscreen": window.styleMask.contains(.fullScreen), "title": window.title]
        }
        let value: [String: Any] = ["run": run, "pid": Int(getpid()),
            "sequence": observationSequence, "sampled_at": acquired,
            "isActive": NSApp.isActive, "windows": rows,
            "closed": Dictionary(uniqueKeysWithValues: closedAliases.compactMap { alias in
                numbers[alias].map { (alias, $0) }
            })]
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent("native-observation.json"), options: .atomic)
        } catch {
            fputs("fixture: observation write failed\n", stderr)
            exit(1)
        }
    }

    init(run: String, directory: URL) {
        self.run = run
        self.directory = directory
    }

    func acknowledge(operation: String, alias: String?, accepted: Bool, error: String? = nil) {
        var result: [String: Any] = ["run": run, "sequence": sequence,
            "operation": operation, "alias": alias as Any? ?? NSNull(),
            "accepted": accepted, "pid": Int(getpid()),
            "windowNumber": alias.flatMap { numbers[$0] } as Any? ?? NSNull()]
        if let alias = alias, let frame = creationFrames[alias] { result["creationFrame"] = frame }
        if let error = error { result["error"] = error }
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent("ack.json"), options: .atomic)
        } catch {
            fputs("fixture: acknowledgement write failed\n", stderr)
            exit(1) // never continue processing without a durable acknowledgement
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        acknowledge(operation: "ready", alias: nil, accepted: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.processRequest()
            if self?.observeNative == true { self?.publishObservation() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let alias = windows.first(where: { $0.value === window })?.key else { return }
        closedAliases.insert(alias) // explicit AppKit closure, not snapshot absence
        windows.removeValue(forKey: alias) // release our owning reference; no survivor focus
    }

    func processRequest() {
        let request = directory.appendingPathComponent("request.json")
        guard FileManager.default.fileExists(atPath: request.path) else { return }
        let processing = directory.appendingPathComponent("processing.json")
        var claimed = false
        func finish(operation: String, alias: String?, accepted: Bool, error: String? = nil) {
            if claimed {
                do {
                    try FileManager.default.removeItem(at: processing)
                    claimed = false
                } catch {
                    fputs("fixture: claimed request removal failed\n", stderr)
                    exit(1) // do not acknowledge or continue with an uncleared claim
                }
            }
            acknowledge(operation: operation, alias: alias, accepted: accepted, error: error)
        }
        do {
            try FileManager.default.moveItem(at: request, to: processing)
            claimed = true
            let attributes = try FileManager.default.attributesOfItem(atPath: processing.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue ?? 8193 <= 8192 else {
                finish(operation: "invalid", alias: nil, accepted: false, error: "malformed_request")
                return
            }
            let data = try Data(contentsOf: processing)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == Set(["run", "sequence", "operation", "alias"]),
                  let requestRun = object["run"] as? String,
                  let value = object["sequence"] as? NSNumber,
                  String(cString: value.objCType) != "c",
                  value.doubleValue == Double(value.intValue), value.intValue > 0,
                  let operation = object["operation"] as? String,
                  object["alias"] is NSNull || object["alias"] is String else {
                finish(operation: "invalid", alias: nil, accepted: false, error: "malformed_request")
                return
            }
            guard requestRun == run, sequence < Int.max, value.intValue == sequence + 1 else {
                finish(operation: "invalid", alias: nil, accepted: false, error: "run_or_sequence_mismatch")
                return
            }
            sequence = value.intValue
            let alias = object["alias"] as? String
            guard (operation == "quit" && alias == nil) ||
                  (["create", "createExcluded", "resetClosedAlias", "focus", "close", "renameToExcluded", "renameToManaged", "renameForRanking"].contains(operation) && ["A", "B", "C", "D", "E"].contains(alias ?? "")) else {
                finish(operation: "invalid", alias: nil, accepted: false, error: "unsupported_operation_or_alias")
                return
            }
            if operation == "quit" {
                finish(operation: operation, alias: nil, accepted: true)
                timer?.invalidate()
                NSApp.terminate(nil)
                return
            }
            let name = alias!
            if operation == "resetClosedAlias" {
                guard windows[name] == nil && numbers[name] != nil else {
                    finish(operation: operation, alias: name, accepted: false, error: "alias_not_closed")
                    return
                }
                closedAliases.remove(name)
                numbers.removeValue(forKey: name)
                creationFrames.removeValue(forKey: name)
                finish(operation: operation, alias: name, accepted: true)
                return
            }
            if operation == "create" || operation == "createExcluded" {
                guard numbers[name] == nil else {
                    finish(operation: operation, alias: name, accepted: false, error: "alias_already_used")
                    return
                }
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
                // Record before publishing/ordering: the manager cannot have changed this frame.
                let frame = window.frame
                let top = NSScreen.screens[0].frame.maxY
                creationFrames[name] = ["x": frame.minX, "y": top - frame.maxY,
                    "w": frame.width, "h": frame.height]
                window.title = operation == "createExcluded" ? "10bucks fixture B" : "10bucks fixture \(name)"
                window.isReleasedWhenClosed = false
                window.delegate = self
                windows[name] = window
                // Normal foreground window creation, not post-observation focus repair.
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                numbers[name] = window.windowNumber
            } else {
                guard let window = windows[name] else {
                    finish(operation: operation, alias: name, accepted: false, error: "alias_not_open")
                    return
                }
                if operation == "focus" {
                    NSApp.activate(ignoringOtherApps: true) // explicit control proof ONLY
                    window.makeKeyAndOrderFront(nil)
                } else if operation == "renameToExcluded" {
                    window.title = "10bucks fixture B"
                } else if operation == "renameForRanking" {
                    window.title = name == "A" ? "i---n---b" : "Inbox"
                } else if operation == "renameToManaged" {
                    window.title = "10bucks managed \(name)"
                } else {
                    window.performClose(nil) // AppKit normal close, no survivor focus request
                }
            }
            finish(operation: operation, alias: name, accepted: true)
        } catch {
            finish(operation: "invalid", alias: nil, accepted: false, error: "request_io_or_json_error")
        }
    }
}

let arguments = CommandLine.arguments
 guard (arguments.count == 5 || (arguments.count == 6 && arguments[5] == "--observe-native")), arguments[1] == "--run", arguments[3] == "--control-dir",
       !arguments[2].isEmpty, arguments[2].utf8.count <= 128,
       arguments[2].unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }),
       arguments[4].hasPrefix("/") else {
    fputs("usage: Fixture --run NONCE --control-dir NEW_ABSOLUTE_PRIVATE_DIRECTORY\n", stderr)
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[4], isDirectory: true).standardizedFileURL
guard mkdir(directory.path, 0o700) == 0 else {
    fputs("fixture: control directory must be new, with an existing private parent\n", stderr)
    exit(2)
}
let app = NSApplication.shared
let fixture = Fixture(run: arguments[2], directory: directory)
fixture.observeNative = arguments.count == 6
app.setActivationPolicy(.regular)
app.delegate = fixture
app.run()
