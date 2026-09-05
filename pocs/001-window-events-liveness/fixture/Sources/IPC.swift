import Darwin
import Foundation

// This is intentionally a tiny JSON subset: requests are ASCII token strings
// only, and all command validation remains in FixtureControl.
public enum IPCError: Error, Equatable {
    case invalidUTF8
    case invalidRequest
    case oversizedRequest
    case unsafeRunDirectory
    case unsafeSocketPath
    case socketPathExists
    case socketSetupFailed
    case socketConnectFailed
    case readFailed
    case writeFailed
    case closeFailed
    case invalidResponse
    case cleanupFailed
}

public enum FixtureCodec {
    public static let maximumMessageBytes = 4096

    public static func decodeRequestLine(_ data: Data) throws -> FixtureRequest {
        var fields = try decodeObjectLine(data)
        guard let command = fields.removeValue(forKey: "command") else { throw IPCError.invalidRequest }
        let request = FixtureRequest(command: command, fields: fields)
        guard validRequest(request) else { throw IPCError.invalidRequest }
        return request
    }

    public static func encodeRequest(_ request: FixtureRequest) throws -> Data {
        guard validRequest(request) else { throw IPCError.invalidRequest }
        var fields = request.fields
        fields["command"] = request.command
        return try encodeObject(fields)
    }

    public static func encodeResponse(_ response: FixtureResponse) throws -> Data {
        guard response.status == .accepted,
              safeToken(response.requestID), safeToken(response.sampleID) else { throw IPCError.invalidResponse }
        var fields = ["request_id": response.requestID, "sample_id": response.sampleID, "status": "accepted"]
        if let token = response.fixtureToken {
            guard token.hasPrefix("fixture-win-"), safeToken(token) else { throw IPCError.invalidResponse }
            fields["fixture_token"] = token
        }
        if let token = response.correlationToken {
            guard token.hasPrefix("corr-"), safeToken(token) else { throw IPCError.invalidResponse }
            fields["correlation_token"] = token
        }
        return try encodeObject(fields)
    }

    public static func encodeRejected(requestID: String? = nil, sampleID: String? = nil) throws -> Data {
        var fields = ["status": "rejected"]
        if let requestID, let sampleID, safeToken(requestID), safeToken(sampleID) {
            fields["request_id"] = requestID
            fields["sample_id"] = sampleID
        }
        return try encodeObject(fields)
    }

    static func decodeResponseLine(_ data: Data) throws -> FixtureResponse {
        let fields = try decodeObjectLine(data)
        guard let requestID = fields["request_id"], let sampleID = fields["sample_id"], safeToken(requestID), safeToken(sampleID) else {
            throw IPCError.invalidResponse
        }
        switch fields["status"] {
        case "accepted":
            guard safeKeys(fields, expected: ["status", "request_id", "sample_id", "fixture_token", "correlation_token"]) else { throw IPCError.invalidResponse }
            let fixtureToken = fields["fixture_token"]
            let correlationToken = fields["correlation_token"]
            guard (fixtureToken == nil || (fixtureToken!.hasPrefix("fixture-win-") && safeToken(fixtureToken!))),
                  (correlationToken == nil || (correlationToken!.hasPrefix("corr-") && safeToken(correlationToken!))) else { throw IPCError.invalidResponse }
            return FixtureResponse(status: .accepted, requestID: requestID, sampleID: sampleID, fixtureToken: fixtureToken, correlationToken: correlationToken)
        case "rejected":
            guard Set(fields.keys) == ["status", "request_id", "sample_id"] else { throw IPCError.invalidResponse }
            return FixtureResponse(status: .rejected, requestID: requestID, sampleID: sampleID, fixtureToken: nil, correlationToken: nil)
        default:
            throw IPCError.invalidResponse
        }
    }

    private static func validRequest(_ request: FixtureRequest) -> Bool {
        let expected: Set<String>
        switch request.command {
        case "create", "probe_pending_work", "shutdown": expected = ["request_id", "sample_id"]
        case "close": expected = ["request_id", "sample_id", "fixture_token"]
        default: return false
        }
        guard Set(request.fields.keys) == expected,
              safeToken(request.fields["request_id"] ?? ""), safeToken(request.fields["sample_id"] ?? "") else { return false }
        if let token = request.fields["fixture_token"] {
            return token.hasPrefix("fixture-win-") && safeToken(token)
        }
        return true
    }

    private static func safeKeys(_ fields: [String: String], expected: Set<String>) -> Bool {
        Set(fields.keys).isSubset(of: expected)
    }

    private static func safeToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            switch byte {
            case 45, 46, 48...57, 65...90, 95, 97...122: return true
            default: return false
            }
        }
    }

    private static func encodeObject(_ fields: [String: String]) throws -> Data {
        guard fields.allSatisfy({ safeToken($0.key) && safeToken($0.value) }) else { throw IPCError.invalidRequest }
        let body = fields.keys.sorted().map { "\"\($0)\":\"\(fields[$0]!)\"" }.joined(separator: ",")
        return Data(("{\(body)}\n").utf8)
    }

    private static func decodeObjectLine(_ data: Data) throws -> [String: String] {
        guard data.count <= maximumMessageBytes else { throw IPCError.oversizedRequest }
        guard String(data: data, encoding: .utf8) != nil else { throw IPCError.invalidUTF8 }
        var bytes = Array(data)
        guard bytes.last == 0x0A, !bytes.dropLast().contains(0x0A), !bytes.dropLast().contains(0x0D) else { throw IPCError.invalidRequest }
        bytes.removeLast()
        var parser = JSONTokenObjectParser(bytes: bytes)
        return try parser.parse()
    }
}

private struct JSONTokenObjectParser {
    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parse() throws -> [String: String] {
        skipWhitespace(); try consume(0x7B); skipWhitespace()
        var fields: [String: String] = [:]
        if peek() == 0x7D { index += 1; skipWhitespace(); guard index == bytes.count else { throw IPCError.invalidRequest }; return fields }
        while true {
            skipWhitespace(); let key = try string(); skipWhitespace(); try consume(0x3A); skipWhitespace(); let value = try string()
            guard fields[key] == nil else { throw IPCError.invalidRequest }
            fields[key] = value
            skipWhitespace()
            if peek() == 0x7D { index += 1; break }
            try consume(0x2C)
        }
        skipWhitespace()
        guard index == bytes.count else { throw IPCError.invalidRequest }
        return fields
    }

    private mutating func string() throws -> String {
        try consume(0x22)
        let start = index
        while let byte = peek(), byte != 0x22 {
            guard byte >= 0x20, byte < 0x7F, byte != 0x5C else { throw IPCError.invalidRequest }
            index += 1
        }
        guard peek() == 0x22, index > start else { throw IPCError.invalidRequest }
        let result = String(bytes: bytes[start..<index], encoding: .utf8)!
        index += 1
        return result
    }

    private mutating func skipWhitespace() { while let byte = peek(), byte == 0x20 || byte == 0x09 { index += 1 } }
    private func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }
    private mutating func consume(_ byte: UInt8) throws { guard peek() == byte else { throw IPCError.invalidRequest }; index += 1 }
}

public final class FixtureSocketServer {
    public typealias CommandDispatch = (FixtureRequest) throws -> FixtureResponse
    public typealias CommandExecutor = (@escaping () throws -> FixtureResponse) throws -> FixtureResponse
    private let descriptor: Int32
    private let socketPath: String
    private let identity: (dev: dev_t, ino: ino_t)
    private let dispatch: CommandDispatch
    private let execute: CommandExecutor
    private let configureWriteSocket: (Int32) -> Bool
    private var stopped = false

    // Production composes this default with the AppKit main queue. Tests can
    // inject a direct executor without creating an AppKit run loop.
    public init(socketPath: URL, dispatch: @escaping CommandDispatch, execute: @escaping CommandExecutor = FixtureSocketServer.onMainQueue, configureWriteSocket: @escaping (Int32) -> Bool = FixtureSocketServer.configureNoSigPipe) throws {
        try Self.validateRunDirectory(socketPath.deletingLastPathComponent())
        self.socketPath = socketPath.path
        self.dispatch = dispatch
        self.execute = execute
        self.configureWriteSocket = configureWriteSocket
        guard Self.pathDoesNotExist(socketPath.path) else { throw IPCError.socketPathExists }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.socketSetupFailed }
        var boundIdentity: (dev: dev_t, ino: ino_t)?
        do {
            try Self.bind(fd, path: socketPath.path)
            var initial = stat()
            guard lstat(socketPath.path, &initial) == 0, (initial.st_mode & S_IFMT) == S_IFSOCK, initial.st_uid == getuid() else { throw IPCError.socketSetupFailed }
            boundIdentity = (initial.st_dev, initial.st_ino)
            guard chmod(socketPath.path, 0o600) == 0 else { throw IPCError.socketSetupFailed }
            var info = stat()
            guard lstat(socketPath.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
                  info.st_uid == getuid(), (info.st_mode & 0o777) == 0o600,
                  boundIdentity!.dev == info.st_dev, boundIdentity!.ino == info.st_ino,
                  listen(fd, 8) == 0 else { throw IPCError.socketSetupFailed }
            descriptor = fd
            identity = boundIdentity!
        } catch {
            Darwin.close(fd)
            if let boundIdentity { _ = Self.unlinkOwnedSocket(at: socketPath.path, expected: boundIdentity) }
            throw error
        }
    }

    public static func configureNoSigPipe(_ descriptor: Int32) -> Bool {
        configureNoSigPipe(descriptor, setSocketOption: { fd in
            var enabled: Int32 = 1
            return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0
        })
    }

    static func configureNoSigPipe(_ descriptor: Int32, setSocketOption: (Int32) -> Bool) -> Bool {
        setSocketOption(descriptor)
    }

    public static func onMainQueue(_ work: @escaping () throws -> FixtureResponse) throws -> FixtureResponse {
        if Thread.isMainThread { return try work() }
        var result: Result<FixtureResponse, Error>!
        DispatchQueue.main.sync { result = Result { try work() } }
        return try result.get()
    }

    deinit { try? shutdown() }

    public func serveOne() throws {
        guard !stopped else { throw IPCError.readFailed }
        let connection = try Self.acceptConnection(descriptor)
        defer { Darwin.close(connection) }
        guard configureWriteSocket(connection) else { throw IPCError.socketSetupFailed }
        let raw = try Self.readOneMessage(connection)
        do {
            let request = try FixtureCodec.decodeRequestLine(raw)
            do { try Self.writeAll(connection, data: FixtureCodec.encodeResponse(try execute { try self.dispatch(request) })) }
            catch { try Self.writeAll(connection, data: FixtureCodec.encodeRejected(requestID: request.fields["request_id"], sampleID: request.fields["sample_id"])) }
        } catch {
            try Self.writeAll(connection, data: FixtureCodec.encodeRejected())
        }
    }

    public func shutdown() throws {
        guard !stopped else { return }
        stopped = true
        let closeSucceeded = Darwin.close(descriptor) == 0
        guard Self.unlinkOwnedSocket(at: socketPath, expected: identity) else { throw IPCError.cleanupFailed }
        guard closeSucceeded else { throw IPCError.closeFailed }
    }

    static func validateRunDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(), (info.st_mode & 0o777) == 0o700 else { throw IPCError.unsafeRunDirectory }
    }

    static func validateExistingSocket(_ url: URL) throws {
        try validateRunDirectory(url.deletingLastPathComponent())
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(), (info.st_mode & 0o777) == 0o600 else { throw IPCError.unsafeSocketPath }
    }

    private static func pathDoesNotExist(_ path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 { return false }
        return errno == ENOENT
    }

    private static func bind(_ fd: Int32, path: String) throws {
        var address = sockaddr_un()
        let encoded = Array(path.utf8)
        guard encoded.count < MemoryLayout.size(ofValue: address.sun_path) else { throw IPCError.socketSetupFailed }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            encoded.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            Darwin.bind(fd, UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_un>.size))
        }
        guard result == 0 else { throw IPCError.socketSetupFailed }
    }

    private static func acceptConnection(_ fd: Int32) throws -> Int32 {
        while true {
            let connection = accept(fd, nil, nil)
            if connection >= 0 { return connection }
            if errno == EINTR { continue }
            throw IPCError.readFailed
        }
    }

    static func readOneMessage(_ fd: Int32) throws -> Data {
        var output = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw IPCError.readFailed }
            output.append(byte)
            if output.count > FixtureCodec.maximumMessageBytes { throw IPCError.oversizedRequest }
        }
        return output
    }

    static func writeAll(_ fd: Int32, data: Data, writeChunk: ((Int32, UnsafeRawPointer?, Int) -> ssize_t)? = nil) throws {
        let operation = writeChunk ?? { descriptor, pointer, count in Darwin.write(descriptor, pointer, count) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw IPCError.writeFailed }
            var offset = 0
            while offset < data.count {
                let result = operation(fd, base.advanced(by: offset), data.count - offset)
                if result < 0 && errno == EINTR { continue }
                guard result > 0, result <= data.count - offset else { throw IPCError.writeFailed }
                offset += result
            }
        }
    }

    @discardableResult
    private static func unlinkOwnedSocket(at path: String, expected: (dev: dev_t, ino: ino_t)? = nil) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(), expected.map({ $0.dev == info.st_dev && $0.ino == info.st_ino }) ?? true else { return false }
        return unlink(path) == 0
    }
}

public struct FixtureSocketClient {
    private let socketURL: URL
    private let socketPath: String
    private let configureWriteSocket: (Int32) -> Bool

    public init(socketPath: URL, configureWriteSocket: @escaping (Int32) -> Bool = FixtureSocketServer.configureNoSigPipe) {
        self.socketURL = socketPath
        self.socketPath = socketPath.path
        self.configureWriteSocket = configureWriteSocket
    }

    public func send(_ request: FixtureRequest) throws -> FixtureResponse {
        try FixtureSocketServer.validateExistingSocket(socketURL)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.socketConnectFailed }
        guard configureWriteSocket(fd) else { Darwin.close(fd); throw IPCError.socketSetupFailed }
        defer { Darwin.close(fd) }
        // connect constructs the same AF_UNIX address as the server without binding a local pathname.
        var address = sockaddr_un()
        let encoded = Array(socketPath.utf8)
        guard encoded.count < MemoryLayout.size(ofValue: address.sun_path) else { throw IPCError.socketConnectFailed }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size); address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in destination.initializeMemory(as: UInt8.self, repeating: 0); encoded.withUnsafeBytes { destination.copyBytes(from: $0) } }
        while true {
            let result = withUnsafePointer(to: &address) { Darwin.connect(fd, UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_un>.size)) }
            if result == 0 { break }
            if errno == EINTR { continue }
            throw IPCError.socketConnectFailed
        }
        try FixtureSocketServer.writeAll(fd, data: FixtureCodec.encodeRequest(request))
        while shutdown(fd, SHUT_WR) != 0 {
            if errno == EINTR { continue }
            throw IPCError.writeFailed
        }
        return try FixtureCodec.decodeResponseLine(try FixtureSocketServer.readOneMessage(fd))
    }
}
