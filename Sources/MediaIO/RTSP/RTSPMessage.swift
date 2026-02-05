import Foundation

/// RTSP Methods
/// - seealso: RFC 2326 Section 6.1
public enum RTSPMethod: String {
    case DESCRIBE
    case ANNOUNCE
    case GET_PARAMETER
    case OPTIONS
    case PAUSE
    case PLAY
    case RECORD
    case REDIRECT
    case SETUP
    case SET_PARAMETER
    case TEARDOWN
}

/// RTSP Status Codes
/// - seealso: RFC 2326 Section 7.1.1
public enum RTSPStatusCode: Int {
    case `continue` = 100
    case ok = 200
    case created = 201
    case lowOnStorageSpace = 250
    case multipleChoices = 300
    case movedPermanently = 301
    case movedTemporarily = 302
    case seeOther = 303
    case notModified = 304
    case useProxy = 305
    case badRequest = 400
    case unauthorized = 401
    case paymentRequired = 402
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case notAcceptable = 406
    case proxyAuthRequired = 407
    case requestTimeout = 408
    case gone = 410
    case lengthRequired = 411
    case preconditionFailed = 412
    case requestEntityTooLarge = 413
    case requestURITooLarge = 414
    case unsupportedMediaType = 415
    case parameterNotUnderstood = 451
    case conferenceNotFound = 452
    case notEnoughBandwidth = 453
    case sessionNotFound = 454
    case methodNotValidInState = 455
    case headerFieldNotValidForResource = 456
    case invalidRange = 457
    case parameterIsReadOnly = 458
    case aggregateOperationNotAllowed = 459
    case onlyAggregateOperationAllowed = 460
    case unsupportedTransport = 461
    case destinationUnreachable = 462
    case internalServerError = 500
    case notImplemented = 501
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504
    case rtspVersionNotSupported = 505
    case optionNotSupported = 551

    public var reasonPhrase: String {
        switch self {
        case .ok: return "OK"
        case .badRequest: return "Bad Request"
        case .unauthorized: return "Unauthorized"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .sessionNotFound: return "Session Not Found"
        case .internalServerError: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}

/// RTSP Transport parameters
public struct RTSPTransport {
    public var transportProtocol: String = "RTP"
    public var profile: String = "AVP"
    public var lowerTransport: String? = nil // "TCP" or "UDP" (default)
    public var unicast: Bool = true
    public var clientPortRange: (Int, Int)? = nil
    public var serverPortRange: (Int, Int)? = nil
    public var interleaved: (Int, Int)? = nil
    public var ssrc: String? = nil

    public init() {}

    /// Parse a Transport header value
    public static func parse(_ value: String) -> RTSPTransport {
        var transport = RTSPTransport()
        let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }

        for part in parts {
            if part.contains("/") && !part.contains("=") {
                // Protocol specification: RTP/AVP or RTP/AVP/TCP
                let components = part.split(separator: "/").map(String.init)
                if components.count >= 1 { transport.transportProtocol = components[0] }
                if components.count >= 2 { transport.profile = components[1] }
                if components.count >= 3 { transport.lowerTransport = components[2] }
            } else if part == "unicast" {
                transport.unicast = true
            } else if part == "multicast" {
                transport.unicast = false
            } else if part.hasPrefix("client_port=") {
                let range = String(part.dropFirst("client_port=".count))
                let ports = range.split(separator: "-").compactMap { Int($0) }
                if ports.count == 2 { transport.clientPortRange = (ports[0], ports[1]) }
            } else if part.hasPrefix("server_port=") {
                let range = String(part.dropFirst("server_port=".count))
                let ports = range.split(separator: "-").compactMap { Int($0) }
                if ports.count == 2 { transport.serverPortRange = (ports[0], ports[1]) }
            } else if part.hasPrefix("interleaved=") {
                let range = String(part.dropFirst("interleaved=".count))
                let channels = range.split(separator: "-").compactMap { Int($0) }
                if channels.count == 2 { transport.interleaved = (channels[0], channels[1]) }
            } else if part.hasPrefix("ssrc=") {
                transport.ssrc = String(part.dropFirst("ssrc=".count))
            }
        }
        return transport
    }

    /// Serialize to Transport header value
    public func serialize() -> String {
        var parts: [String] = []
        var proto = "\(transportProtocol)/\(profile)"
        if let lt = lowerTransport { proto += "/\(lt)" }
        parts.append(proto)
        parts.append(unicast ? "unicast" : "multicast")
        if let cp = clientPortRange { parts.append("client_port=\(cp.0)-\(cp.1)") }
        if let sp = serverPortRange { parts.append("server_port=\(sp.0)-\(sp.1)") }
        if let il = interleaved { parts.append("interleaved=\(il.0)-\(il.1)") }
        if let s = ssrc { parts.append("ssrc=\(s)") }
        return parts.joined(separator: ";")
    }
}

/// RTSP Request
public struct RTSPRequest {
    public static let version = "RTSP/1.0"

    public var method: RTSPMethod
    public var url: String
    public var headers: [(String, String)] = []
    public var body: Data? = nil

    public var cseq: Int {
        get {
            for (key, value) in headers where key == "CSeq" {
                return Int(value) ?? 0
            }
            return 0
        }
        set {
            setHeader("CSeq", value: "\(newValue)")
        }
    }

    public init(method: RTSPMethod, url: String) {
        self.method = method
        self.url = url
    }

    public mutating func setHeader(_ key: String, value: String) {
        if let index = headers.firstIndex(where: { $0.0 == key }) {
            headers[index] = (key, value)
        } else {
            headers.append((key, value))
        }
    }

    public func getHeader(_ key: String) -> String? {
        headers.first(where: { $0.0.lowercased() == key.lowercased() })?.1
    }

    /// Serialize to wire format
    public func serialize() -> Data {
        var lines: [String] = []
        lines.append("\(method.rawValue) \(url) \(RTSPRequest.version)")
        for (key, value) in headers {
            lines.append("\(key): \(value)")
        }
        if let body = body {
            lines.append("Content-Length: \(body.count)")
        }
        lines.append("") // Empty line before body
        lines.append("")
        var result = Data(lines.joined(separator: "\r\n").utf8)
        if let body = body {
            result.append(body)
        }
        return result
    }

    /// Parse from wire format
    public static func parse(from data: Data) throws -> RTSPRequest {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RTSPError.invalidMessage
        }
        let lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw RTSPError.invalidMessage }

        // Parse request line
        let requestLine = lines[0].split(separator: " ", maxSplits: 2).map(String.init)
        guard requestLine.count >= 2 else { throw RTSPError.invalidMessage }
        guard let method = RTSPMethod(rawValue: requestLine[0]) else {
            throw RTSPError.invalidMethod
        }

        var request = RTSPRequest(method: method, url: requestLine[1])

        // Parse headers
        var bodyStart = lines.count
        for i in 1..<lines.count {
            if lines[i].isEmpty {
                bodyStart = i + 1
                break
            }
            let headerParts = lines[i].split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if headerParts.count == 2 {
                request.headers.append((headerParts[0], headerParts[1]))
            }
        }

        // Parse body
        if bodyStart < lines.count {
            let bodyText = lines[bodyStart...].joined(separator: "\r\n")
            if !bodyText.isEmpty {
                request.body = Data(bodyText.utf8)
            }
        }

        return request
    }
}

/// RTSP Response
public struct RTSPResponse {
    public static let version = "RTSP/1.0"

    public var statusCode: Int
    public var reasonPhrase: String
    public var headers: [(String, String)] = []
    public var body: Data? = nil

    public var cseq: Int {
        get {
            for (key, value) in headers where key == "CSeq" {
                return Int(value) ?? 0
            }
            return 0
        }
        set {
            setHeader("CSeq", value: "\(newValue)")
        }
    }

    public init(statusCode: Int, reasonPhrase: String? = nil) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase ?? (RTSPStatusCode(rawValue: statusCode)?.reasonPhrase ?? "Unknown")
    }

    public mutating func setHeader(_ key: String, value: String) {
        if let index = headers.firstIndex(where: { $0.0 == key }) {
            headers[index] = (key, value)
        } else {
            headers.append((key, value))
        }
    }

    public func getHeader(_ key: String) -> String? {
        headers.first(where: { $0.0.lowercased() == key.lowercased() })?.1
    }

    public func serialize() -> Data {
        var lines: [String] = []
        lines.append("\(RTSPResponse.version) \(statusCode) \(reasonPhrase)")
        for (key, value) in headers {
            lines.append("\(key): \(value)")
        }
        if let body = body {
            lines.append("Content-Length: \(body.count)")
        }
        lines.append("")
        lines.append("")
        var result = Data(lines.joined(separator: "\r\n").utf8)
        if let body = body {
            result.append(body)
        }
        return result
    }

    public static func parse(from data: Data) throws -> RTSPResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RTSPError.invalidMessage
        }
        let lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw RTSPError.invalidMessage }

        let statusLine = lines[0].split(separator: " ", maxSplits: 2).map(String.init)
        guard statusLine.count >= 2 else { throw RTSPError.invalidMessage }
        guard let code = Int(statusLine[1]) else { throw RTSPError.invalidMessage }

        var response = RTSPResponse(statusCode: code, reasonPhrase: statusLine.count >= 3 ? statusLine[2] : nil)

        var bodyStart = lines.count
        for i in 1..<lines.count {
            if lines[i].isEmpty {
                bodyStart = i + 1
                break
            }
            let parts = lines[i].split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                response.headers.append((parts[0], parts[1]))
            }
        }

        if bodyStart < lines.count {
            let bodyText = lines[bodyStart...].joined(separator: "\r\n")
            if !bodyText.isEmpty {
                response.body = Data(bodyText.utf8)
            }
        }

        return response
    }
}

public enum RTSPError: Error {
    case invalidMessage
    case invalidMethod
    case invalidStatusCode
    case sessionNotFound
    case transportError
}
