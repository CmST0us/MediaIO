import Foundation

/// RTSP Session manages the RTSP request/response flow
public final class RTSPSession {
    public private(set) var sessionID: String?
    public private(set) var url: String = ""
    private var cseq: Int = 0
    public private(set) var state: RTSPSessionState = .idle

    /// Supported methods from OPTIONS response
    public private(set) var supportedMethods: [RTSPMethod] = []

    /// SDP content from DESCRIBE response
    public private(set) var sdpContent: String?

    /// Transport info from SETUP response
    public private(set) var transport: RTSPTransport?

    public enum RTSPSessionState {
        case idle
        case optionsSent
        case described
        case setup
        case playing
        case recording
        case paused
        case teardown
    }

    public init() {}

    /// Create an OPTIONS request
    public func createOptionsRequest(url: String) -> RTSPRequest {
        self.url = url
        cseq += 1
        var request = RTSPRequest(method: .OPTIONS, url: url)
        request.cseq = cseq
        request.setHeader("User-Agent", value: "MediaIO/1.0")
        state = .optionsSent
        return request
    }

    /// Create a DESCRIBE request
    public func createDescribeRequest() -> RTSPRequest {
        cseq += 1
        var request = RTSPRequest(method: .DESCRIBE, url: url)
        request.cseq = cseq
        request.setHeader("Accept", value: "application/sdp")
        request.setHeader("User-Agent", value: "MediaIO/1.0")
        return request
    }

    /// Create a SETUP request
    public func createSetupRequest(trackURL: String, transport: RTSPTransport) -> RTSPRequest {
        cseq += 1
        var request = RTSPRequest(method: .SETUP, url: trackURL)
        request.cseq = cseq
        request.setHeader("Transport", value: transport.serialize())
        request.setHeader("User-Agent", value: "MediaIO/1.0")
        if let sid = sessionID {
            request.setHeader("Session", value: sid)
        }
        return request
    }

    /// Create a PLAY request
    public func createPlayRequest(range: String = "npt=0.000-") -> RTSPRequest {
        cseq += 1
        var request = RTSPRequest(method: .PLAY, url: url)
        request.cseq = cseq
        request.setHeader("Range", value: range)
        request.setHeader("User-Agent", value: "MediaIO/1.0")
        if let sid = sessionID {
            request.setHeader("Session", value: sid)
        }
        return request
    }

    /// Create a PAUSE request
    public func createPauseRequest() -> RTSPRequest {
        cseq += 1
        var request = RTSPRequest(method: .PAUSE, url: url)
        request.cseq = cseq
        request.setHeader("User-Agent", value: "MediaIO/1.0")
        if let sid = sessionID {
            request.setHeader("Session", value: sid)
        }
        return request
    }

    /// Create a TEARDOWN request
    public func createTeardownRequest() -> RTSPRequest {
        cseq += 1
        var request = RTSPRequest(method: .TEARDOWN, url: url)
        request.cseq = cseq
        request.setHeader("User-Agent", value: "MediaIO/1.0")
        if let sid = sessionID {
            request.setHeader("Session", value: sid)
        }
        return request
    }

    /// Process an RTSP response
    public func processResponse(_ response: RTSPResponse, for method: RTSPMethod) {
        guard response.statusCode == 200 else { return }

        switch method {
        case .OPTIONS:
            if let publicHeader = response.getHeader("Public") {
                supportedMethods = publicHeader.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .compactMap { RTSPMethod(rawValue: $0) }
            }
            state = .optionsSent

        case .DESCRIBE:
            if let body = response.body {
                sdpContent = String(data: body, encoding: .utf8)
            }
            state = .described

        case .SETUP:
            if let sessionHeader = response.getHeader("Session") {
                let parts = sessionHeader.split(separator: ";")
                sessionID = String(parts[0]).trimmingCharacters(in: .whitespaces)
            }
            if let transportHeader = response.getHeader("Transport") {
                transport = RTSPTransport.parse(transportHeader)
            }
            state = .setup

        case .PLAY:
            state = .playing

        case .PAUSE:
            state = .paused

        case .TEARDOWN:
            state = .teardown
            sessionID = nil

        default:
            break
        }
    }

    public func reset() {
        sessionID = nil
        cseq = 0
        state = .idle
        supportedMethods = []
        sdpContent = nil
        transport = nil
    }
}
