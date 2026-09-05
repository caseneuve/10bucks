import Foundation

@main
enum FixtureCTL {
    static func main() {
        do {
            let request = try parse(CommandLine.arguments)
            let runDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let response = try FixtureSocketClient(socketPath: runDirectory.appendingPathComponent("poc001-fixture.sock")).send(request)
            guard response.status == .accepted else { throw IPCError.invalidResponse }
            FileHandle.standardOutput.write(try FixtureCodec.encodeResponse(response))
        } catch {
            // Do not reflect arguments, paths, socket details, or tokens.
            FileHandle.standardError.write(Data("fixturectl: request rejected\n".utf8))
            exit(1)
        }
    }

    private static func parse(_ arguments: [String]) throws -> FixtureRequest {
        guard arguments.count >= 5 else { throw IPCError.invalidRequest }
        let command = arguments[2]
        let requestID = arguments[3]
        let sampleID = arguments[4]
        if ["create", "probe_pending_work", "shutdown"].contains(command), arguments.count == 5 {
            return try FixtureCodec.decodeRequestLine(Data("{\"request_id\":\"\(requestID)\",\"command\":\"\(command)\",\"sample_id\":\"\(sampleID)\"}\n".utf8))
        }
        if command == "close", arguments.count == 6 {
            return try FixtureCodec.decodeRequestLine(Data("{\"request_id\":\"\(requestID)\",\"command\":\"close\",\"sample_id\":\"\(sampleID)\",\"fixture_token\":\"\(arguments[5])\"}\n".utf8))
        }
        throw IPCError.invalidRequest
    }
}
