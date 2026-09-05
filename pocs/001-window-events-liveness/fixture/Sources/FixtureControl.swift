import Foundation

public struct FixtureRequest: Equatable {
    public let command: String
    public let fields: [String: String]

    public init(command: String, fields: [String: String]) {
        self.command = command
        self.fields = fields
    }
}

public enum FixtureResponseStatus: Equatable { case accepted }

public struct FixtureResponse: Equatable {
    public let status: FixtureResponseStatus
    public let requestID: String
    public let sampleID: String
    public let fixtureToken: String?
    public let correlationToken: String?
}

public struct ActiveFixtureGeneration: Equatable {
    public let token: String
    public let correlationToken: String
    public let generation: UInt64
    public var closeRequested: Bool
}

public enum FixtureCommandRejection: Equatable {
    case createAlreadyActive
    case unknownFixtureToken
    case closeAlreadyRequested
    case shutDown
}

public enum FixtureControlError: Error, Equatable {
    case invalidRequest
    case commandRejected(FixtureCommandRejection)
}

public struct FixtureControl {
    private let tokenGenerator: TokenGenerating
    private var nextGeneration: UInt64 = 1
    public private(set) var activeGeneration: ActiveFixtureGeneration?
    public private(set) var isShutDown = false

    public init(tokenGenerator: TokenGenerating) {
        self.tokenGenerator = tokenGenerator
    }

    public mutating func handle(_ request: FixtureRequest) throws -> FixtureResponse {
        guard isValidRequest(request) else { throw FixtureControlError.invalidRequest }
        let requestID = request.fields["request_id"]!
        let sampleID = request.fields["sample_id"]!

        if isShutDown { throw FixtureControlError.commandRejected(.shutDown) }
        switch request.command {
        case "create":
            guard activeGeneration == nil else { throw FixtureControlError.commandRejected(.createAlreadyActive) }
            let active = ActiveFixtureGeneration(
                token: try tokenGenerator.fixtureToken(),
                correlationToken: try tokenGenerator.correlationToken(),
                generation: nextGeneration,
                closeRequested: false
            )
            nextGeneration += 1
            activeGeneration = active
            return FixtureResponse(status: .accepted, requestID: requestID, sampleID: sampleID, fixtureToken: active.token, correlationToken: active.correlationToken)
        case "probe_pending_work":
            guard activeGeneration != nil else { throw FixtureControlError.commandRejected(.unknownFixtureToken) }
            return FixtureResponse(status: .accepted, requestID: requestID, sampleID: sampleID, fixtureToken: nil, correlationToken: nil)
        case "close":
            let token = request.fields["fixture_token"]!
            guard var active = activeGeneration, active.token == token else { throw FixtureControlError.commandRejected(.unknownFixtureToken) }
            guard !active.closeRequested else { throw FixtureControlError.commandRejected(.closeAlreadyRequested) }
            active.closeRequested = true
            activeGeneration = active
            return FixtureResponse(status: .accepted, requestID: requestID, sampleID: sampleID, fixtureToken: nil, correlationToken: nil)
        case "shutdown":
            isShutDown = true
            return FixtureResponse(status: .accepted, requestID: requestID, sampleID: sampleID, fixtureToken: nil, correlationToken: nil)
        default:
            throw FixtureControlError.invalidRequest
        }
    }

    @discardableResult
    public mutating func completeClose(token: String, generation: UInt64) -> Bool {
        guard let active = activeGeneration, active.token == token, active.generation == generation else { return false }
        activeGeneration = nil
        return true
    }

    private func isValidRequest(_ request: FixtureRequest) -> Bool {
        let common = ["request_id", "sample_id"]
        let expected: Set<String>
        switch request.command {
        case "create", "probe_pending_work", "shutdown": expected = Set(common)
        case "close": expected = Set(common + ["fixture_token"])
        default: return false
        }
        guard Set(request.fields.keys) == expected,
              common.allSatisfy({ isSafeToken(request.fields[$0]) }) else { return false }
        if request.command == "close" {
            guard let token = request.fields["fixture_token"], token.hasPrefix("fixture-win-"), isSafeToken(token) else { return false }
        }
        return true
    }

    private func isSafeToken(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy {
            switch $0.value {
            case 45, 46, 48...57, 65...90, 95, 97...122: return true
            default: return false
            }
        }
    }
}
