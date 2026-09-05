import Foundation
import Darwin

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(message) }
}

func expectThrows<T: Error & Equatable>(_ expected: T, _ body: () throws -> Void) throws {
    do {
        try body()
        throw TestFailure("expected \(expected), but no error was thrown")
    } catch let actual as T {
        try expect(actual == expected, "expected \(expected), got \(actual)")
    }
}

final class DeterministicTokenGenerator: TokenGenerating {
    private var values: [String]

    init(values: [String]) { self.values = values }

    func fixtureToken() throws -> String { "fixture-win-" + (try next()) }
    func correlationToken() throws -> String { "corr-" + (try next()) }

    private func next() throws -> String {
        guard !values.isEmpty else { throw TokenGenerationError.randomSourceFailure }
        return values.removeFirst()
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("poc001-fixture-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

func fileMode(_ url: URL) -> mode_t {
    var info = stat()
    guard stat(url.path, &info) == 0 else { return 0 }
    return info.st_mode & 0o777
}

func setFileMode(_ url: URL, mode: mode_t) throws {
    guard chmod(url.path, mode) == 0 else { throw POSIXError(.EPERM) }
}
