import AppKit
import Darwin

// One main-thread mailbox; this is a test fixture, not a manager or native oracle.
final class Fixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let run: String
    let directory: URL
    var sequence = 0
    var windows: [String: NSWindow] = [:]
    var numbers: [String: Int] = [:] // aliases are never reusable, even after close
    var timer: Timer?

    init(run: String, directory: URL) {
        self.run = run
        self.directory = directory
    }

    func acknowledge(operation: String, alias: String?, accepted: Bool, error: String? = nil) {
        var result: [String: Any] = ["run": run, "sequence": sequence,
            "operation": operation, "alias": alias as Any? ?? NSNull(),
            "accepted": accepted, "pid": Int(getpid()),
            "windowNumber": alias.flatMap { numbers[$0] } as Any? ?? NSNull()]
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
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let alias = windows.first(where: { $0.value === window })?.key else { return }
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
                  (["create", "focus", "close"].contains(operation) && ["A", "B"].contains(alias ?? "")) else {
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
            if operation == "create" {
                guard numbers[name] == nil else {
                    finish(operation: operation, alias: name, accepted: false, error: "alias_already_used")
                    return
                }
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
                window.title = "10bucks fixture \(name)"
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
 guard arguments.count == 5, arguments[1] == "--run", arguments[3] == "--control-dir",
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
app.setActivationPolicy(.regular)
app.delegate = fixture
app.run()
