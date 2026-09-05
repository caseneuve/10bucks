import Darwin
import Foundation

private func requestData(_ string: String) -> Data { Data(string.utf8) }

func testIPCCodecAcceptsOnlyExactStringSchemasAndProducesPrivateResponses() throws {
    let create = try FixtureCodec.decodeRequestLine(requestData("{\"request_id\":\"req-001\",\"command\":\"create\",\"sample_id\":\"sample-001\"}\n"))
    try expect(create == FixtureRequest(command: "create", fields: ["request_id": "req-001", "sample_id": "sample-001"]), "decodes exact create schema")

    for invalid in [
        "{\"request_id\":\"req-001\",\"command\":\"create\",\"sample_id\":1}\n",
        "{\"request_id\":\"req-001\",\"command\":\"create\",\"command\":\"shutdown\",\"sample_id\":\"sample-001\"}\n",
        "{\"request_id\":\"req-001\",\"command\":\"create\",\"sample_id\":\"sample-001\",\"extra\":\"x\"}\n",
        "{\"request_id\":\"req-001\",\"command\":\"create\",\"sample_id\":\"bad value\"}\n",
        "{\"request_id\":\"req-001\",\"command\":\"create\",\"sample_id\":\"sample-001\"}\n{\"request_id\":\"req-002\"}\n",
    ] {
        try expectThrows(IPCError.invalidRequest) { _ = try FixtureCodec.decodeRequestLine(requestData(invalid)) }
    }
    try expectThrows(IPCError.invalidUTF8) {
        _ = try FixtureCodec.decodeRequestLine(Data([0x7B, 0xFF, 0x7D, 0x0A]))
    }

    let accepted = try FixtureCodec.encodeResponse(FixtureResponse(status: .accepted, requestID: "req-001", sampleID: "sample-001", fixtureToken: "fixture-win-AAAA", correlationToken: "corr-BBBB"))
    let acceptedObject = try JSONSerialization.jsonObject(with: accepted) as! [String: Any]
    try expect(Set(acceptedObject.keys) == ["request_id", "sample_id", "status", "fixture_token", "correlation_token"], "accepted response exposes only approved fields")
    let rejected = try FixtureCodec.encodeRejected(requestID: "req-001", sampleID: "sample-001")
    let rejectedObject = try JSONSerialization.jsonObject(with: rejected) as! [String: Any]
    try expect(Set(rejectedObject.keys) == ["request_id", "sample_id", "status"] && rejectedObject["status"] as? String == "rejected", "rejection does not disclose parser or control details")
}

func testIPCWriteAllRetriesInterruptedAndPartialWrites() throws {
    let expected = Data("response\\n".utf8)
    var results: [ssize_t] = [2, -1, 100]
    var written = Data()
    try FixtureSocketServer.writeAll(-1, data: expected, writeChunk: { _, bytes, count in
        let result = results.removeFirst()
        if result == -1 { errno = EINTR; return -1 }
        let accepted = min(Int(result), count)
        written.append(bytes!.assumingMemoryBound(to: UInt8.self), count: accepted)
        return ssize_t(accepted)
    })
    try expect(written == expected, "write seam retries EINTR and completes partial writes")
}

func testIPCServerRequiresPrivatePreexistingDirectoryAndSafeSocketPath() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let socket = root.appendingPathComponent("poc001-fixture.sock")
    try setFileMode(root, mode: 0o700)

    FileManager.default.createFile(atPath: socket.path, contents: Data("do not unlink".utf8))
    try setFileMode(socket, mode: 0o600)
    try expectThrows(IPCError.socketPathExists) {
        _ = try FixtureSocketServer(socketPath: socket, dispatch: { _ in fatalError("must not dispatch") })
    }
    try expect(FileManager.default.contents(atPath: socket.path) == Data("do not unlink".utf8), "never unlinks an arbitrary pre-existing path")
    try FileManager.default.removeItem(at: socket)

    try setFileMode(root, mode: 0o755)
    try expectThrows(IPCError.unsafeRunDirectory) {
        _ = try FixtureSocketServer(socketPath: socket, dispatch: { _ in fatalError("must not dispatch") })
    }
}

func testIPCClientServerOneRequestAndDeterministicCleanup() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try setFileMode(root, mode: 0o700)
    let socket = root.appendingPathComponent("poc001-fixture.sock")
    var handled: [FixtureRequest] = []
    let server = try FixtureSocketServer(socketPath: socket, dispatch: { request in
        handled.append(request)
        return FixtureResponse(status: .accepted, requestID: request.fields["request_id"]!, sampleID: request.fields["sample_id"]!, fixtureToken: nil, correlationToken: nil)
    }, execute: { try $0() })
    try expect(fileMode(socket) == 0o600, "server creates an exact owner-private socket")

    let serverResult = DispatchSemaphore(value: 0)
    var serverError: Error?
    DispatchQueue.global().async {
        defer { serverResult.signal() }
        do { try server.serveOne() } catch { serverError = error }
    }
    let response = try FixtureSocketClient(socketPath: socket).send(FixtureRequest(command: "shutdown", fields: ["request_id": "req-001", "sample_id": "sample-001"]))
    try expect(serverResult.wait(timeout: .now() + 2) == .success, "server completes one bounded connection")
    try expect(serverError == nil, "server accepts the client request")
    try expect(handled == [FixtureRequest(command: "shutdown", fields: ["request_id": "req-001", "sample_id": "sample-001"])], "dispatch receives exactly one decoded request")
    try expect(response.status == .accepted && response.requestID == "req-001", "client receives one response")
    try server.shutdown()
    try expect(!FileManager.default.fileExists(atPath: socket.path), "shutdown removes only the server-created socket")
}

let ipcTests: [(String, () throws -> Void)] = [
    ("IPC codec requires four strict request schemas and private responses", testIPCCodecAcceptsOnlyExactStringSchemasAndProducesPrivateResponses),
    ("IPC write seam retries interrupted partial output", testIPCWriteAllRetriesInterruptedAndPartialWrites),
    ("IPC server rejects unsafe directories and never unlinks existing paths", testIPCServerRequiresPrivatePreexistingDirectoryAndSafeSocketPath),
    ("IPC client and server exchange one request and clean up deterministically", testIPCClientServerOneRequestAndDeterministicCleanup),
]
