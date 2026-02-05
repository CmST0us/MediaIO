import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Socket connection state
enum SocketState {
    case idle
    case connecting
    case connected
    case disconnected
    case error
}

/// Protocol for socket event callbacks
protocol SocketDelegate: AnyObject {
    func socket(_ socket: SocketConnection, didChangeState state: SocketState)
    func socket(_ socket: SocketConnection, didReceiveData data: Data)
    func socket(_ socket: SocketConnection, didFailWithError error: Error)
}

/// TCP socket connection abstraction
final class SocketConnection {
    let host: String
    let port: Int
    private(set) var state: SocketState = .idle

    weak var delegate: SocketDelegate?
    private var fileDescriptor: Int32 = -1

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func connect() throws {
        state = .connecting
        delegate?.socket(self, didChangeState: .connecting)

        #if canImport(Glibc)
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        hints.ai_protocol = Int32(IPPROTO_TCP)

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, "\(port)", &hints, &result)
        guard status == 0 else {
            state = .error
            throw SocketError.resolutionFailed
        }
        defer { freeaddrinfo(result) }

        guard let addrInfo = result else {
            state = .error
            throw SocketError.resolutionFailed
        }

        fileDescriptor = Glibc.socket(addrInfo.pointee.ai_family,
                                       addrInfo.pointee.ai_socktype,
                                       addrInfo.pointee.ai_protocol)
        guard fileDescriptor >= 0 else {
            state = .error
            throw SocketError.socketCreationFailed
        }

        let connectResult = Glibc.connect(fileDescriptor,
                                           addrInfo.pointee.ai_addr,
                                           addrInfo.pointee.ai_addrlen)
        guard connectResult == 0 else {
            close()
            state = .error
            throw SocketError.connectionFailed
        }

        state = .connected
        delegate?.socket(self, didChangeState: .connected)
        #else
        state = .error
        throw SocketError.platformNotSupported
        #endif
    }

    func send(_ data: Data) throws {
        guard state == .connected, fileDescriptor >= 0 else {
            throw SocketError.notConnected
        }
        #if canImport(Glibc)
        try data.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress else {
                throw SocketError.sendFailed
            }
            var totalSent = 0
            while totalSent < data.count {
                let sent = Glibc.send(fileDescriptor,
                                      pointer.advanced(by: totalSent),
                                      data.count - totalSent,
                                      Int32(MSG_NOSIGNAL))
                guard sent > 0 else { throw SocketError.sendFailed }
                totalSent += sent
            }
        }
        #else
        throw SocketError.platformNotSupported
        #endif
    }

    func receive(maxLength: Int = 4096) throws -> Data {
        guard state == .connected, fileDescriptor >= 0 else {
            throw SocketError.notConnected
        }
        #if canImport(Glibc)
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let bytesRead = Glibc.recv(fileDescriptor, &buffer, maxLength, 0)
        guard bytesRead > 0 else {
            if bytesRead == 0 {
                close()
                throw SocketError.connectionClosed
            }
            throw SocketError.receiveFailed
        }
        return Data(buffer[0..<bytesRead])
        #else
        throw SocketError.platformNotSupported
        #endif
    }

    func close() {
        #if canImport(Glibc)
        if fileDescriptor >= 0 {
            Glibc.close(fileDescriptor)
            fileDescriptor = -1
        }
        #endif
        state = .disconnected
        delegate?.socket(self, didChangeState: .disconnected)
    }

    deinit {
        close()
    }
}

enum SocketError: Error {
    case resolutionFailed
    case socketCreationFailed
    case connectionFailed
    case notConnected
    case sendFailed
    case receiveFailed
    case connectionClosed
    case platformNotSupported
}
