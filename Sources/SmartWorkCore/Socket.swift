import Foundation

public enum SocketError: Error, CustomStringConvertible {
    case sys(String), alreadyRunning, notRunning
    public var description: String {
        switch self {
        case .sys(let s): return s
        case .alreadyRunning: return "smart-work is already running"
        case .notRunning: return "smart-work app is not running (no daemon at \(Paths.socket))"
        }
    }
}

private func makeAddr(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count <= cap else { throw SocketError.sys("socket path too long: \(path)") }
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        for (i, b) in bytes.enumerated() { buf[i] = UInt8(bitPattern: b) }
    }
    return addr
}

private func connectFD(_ path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw SocketError.sys("socket: \(String(cString: strerror(errno)))") }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    var addr = try makeAddr(path)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if rc != 0 { close(fd); throw SocketError.notRunning }
    return fd
}

private func readLine(_ fd: Int32, limit: Int = 65536) -> Data? {
    var out = Data()
    var byte: UInt8 = 0
    while out.count < limit {
        let n = read(fd, &byte, 1)
        if n <= 0 { return out.isEmpty ? nil : out }
        if byte == 10 { return out }
        out.append(byte)
    }
    return nil
}

private func writeAll(_ fd: Int32, _ data: Data) {
    var d = data; d.append(10)
    d.withUnsafeBytes { p in
        var off = 0
        while off < p.count {
            let n = write(fd, p.baseAddress! + off, p.count - off)
            if n <= 0 { return }
            off += n
        }
    }
}

public enum Client {
    public static func send(_ req: Request, path: String = Paths.socket) throws -> Response {
        let fd = try connectFD(path)
        defer { close(fd) }
        writeAll(fd, try JSONEncoder().encode(req))
        guard let line = readLine(fd) else { throw SocketError.sys("empty response") }
        return try JSONDecoder().decode(Response.self, from: line)
    }
}

public final class SocketServer {
    private let path: String
    private let handler: (Request) -> Response
    private var fd: Int32 = -1

    public init(path: String = Paths.socket, handler: @escaping (Request) -> Response) {
        self.path = path; self.handler = handler
    }

    public func start() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if let probe = try? connectFD(path) { close(probe); throw SocketError.alreadyRunning }
        unlink(path)
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { throw SocketError.sys("socket: \(String(cString: strerror(errno)))") }
        var addr = try makeAddr(path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0, listen(s, 16) == 0 else {
            let e = String(cString: strerror(errno)); close(s)
            throw SocketError.sys("bind/listen \(path): \(e)")
        }
        chmod(path, 0o600)
        fd = s
        let h = handler
        let listenFD = s
        Thread.detachNewThread {
            while true {
                let c = accept(listenFD, nil, nil)
                if c < 0 { if errno == EINTR { continue } else { return } }
                var one: Int32 = 1
                setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                DispatchQueue.global().async {
                    defer { close(c) }
                    guard let line = readLine(c) else { return }
                    let resp: Response
                    if let req = try? JSONDecoder().decode(Request.self, from: line) {
                        resp = h(req)
                    } else {
                        resp = Response(ok: false, error: "bad request")
                    }
                    if let data = try? JSONEncoder().encode(resp) { writeAll(c, data) }
                }
            }
        }
    }

    public func stop() {
        if fd >= 0 { close(fd); unlink(path); fd = -1 }
    }
}
