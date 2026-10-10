import Foundation
import AgentAwakeCore

let usage = """
usage:
  agentawake begin <name> [--timeout 30m]   start a session (holds the Mac awake)
  agentawake beat  <name>                   heartbeat; resets the timeout
  agentawake done  <name> [--message text]  finish; notifies your phone
  agentawake run   <name> [--timeout 30m] -- <cmd...>
                                            begin, heartbeat while <cmd> runs, done; exits with <cmd>'s status
  agentawake list
  agentawake agents                         supported agents and whether they're connected
  agentawake connect|disconnect <agent>     add or remove Agent Awake's hooks for one agent
  agentawake hook  <agent> <event>          for agent hooks: reads the agent's JSON payload on stdin;
                                            silent, never fails, always exits 0
timeout = max silence before the session is declared stuck, pinged and released (0 = never).
"""

func fail(_ m: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((m + "\n").utf8)); exit(code)
}

func parseDuration(_ s: String) -> Double? {
    guard let last = s.last else { return nil }
    let mult: Double
    switch last {
    case "s": mult = 1
    case "m": mult = 60
    case "h": mult = 3600
    default: return Double(s)
    }
    guard let n = Double(s.dropLast()), n >= 0 else { return nil }
    return n * mult
}

func call(_ r: Request) -> Response {
    do {
        let resp = try Client.send(r)
        if !resp.ok { fail("agentawake: \(resp.error ?? "failed")") }
        return resp
    } catch { fail("agentawake: \(error)") }
}

/// Reads stdin until EOF or a complete JSON object, for at most `seconds`; nothing when stdin is a terminal.
/// Keeps draining past `limit` bytes so the agent never blocks writing a large payload, but returns nil then
/// (a truncated payload is useless).
func readStdin(seconds: Double, limit: Int = 32 << 20) -> Data? {
    if isatty(0) != 0 { return Data() }
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1e9)
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { break }
        var pfd = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, Int32(max(1, (deadline - now) / 1_000_000)))
        if ready < 0 { if errno == EINTR { continue } else { break } }
        if ready == 0 { break }   // still open but silent: give up
        // POLLNVAL (poll doesn't support some devices on macOS): fall through to read, which won't block on them.
        let n = read(0, &buf, buf.count)
        if n <= 0 { break }
        if out.count <= limit {
            out.append(contentsOf: buf[0..<n])
            // Some agents may keep stdin open after writing: stop as soon as what we have is a whole object.
            if out.last(where: { $0 > 32 }) == UInt8(ascii: "}"),
               (try? JSONSerialization.jsonObject(with: out)) != nil { break }
        }
    }
    return out.count > limit ? nil : out
}

/// `agentawake hook <agent> <event>`: must never block or alter the agent. Silent, fast, exits 0 whatever happens.
func runHook(_ a: [String]) -> Never {
    signal(SIGPIPE, SIG_IGN)
    signal(SIGALRM) { _ in _exit(0) }   // last resort if the app hangs mid-reply
    alarm(4)
    guard a.count >= 2 else { exit(0) }
    let agent = a[0], event = a[1]
    if let out = HookAdapter.stdout(agent: agent, event: event) {
        out.utf8CString.withUnsafeBufferPointer { _ = write(1, $0.baseAddress, $0.count - 1) }
    }
    guard var payload = readStdin(seconds: 2) else { exit(0) }
    if payload.isEmpty, a.count > 2 { payload = Data(a[2].utf8) }   // older Cursor CLIs pass the payload in argv
    var env = ProcessInfo.processInfo.environment
    if env["PWD"] == nil { env["PWD"] = FileManager.default.currentDirectoryPath }
    let requests = HookAdapter.requests(agent: agent, event: event, payload: payload, env: env,
                                        agentPID: HookAdapter.agentPID(from: getppid()), config: Config.load())
    for r in requests { _ = try? Client.send(r) }
    exit(0)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { fail(usage, code: 2) }
args.removeFirst()
if cmd == "hook" { runHook(args) }

var timeout: Double?
var message: String?
var command: [String] = []
var positional: [String] = []
var i = 0
while i < args.count {
    if args[i] == "--" { command = Array(args[(i + 1)...]); break }
    if args[i] == "--timeout" {
        guard i + 1 < args.count, let t = parseDuration(args[i + 1]) else { fail("bad --timeout", code: 2) }
        timeout = t; i += 2; continue
    }
    if args[i] == "--message" {
        guard i + 1 < args.count else { fail("bad --message", code: 2) }
        message = args[i + 1]; i += 2; continue
    }
    positional.append(args[i]); i += 1
}

switch cmd {
case "begin", "beat", "done":
    guard let name = positional.first else { fail(usage, code: 2) }
    _ = call(Request(cmd: cmd, name: name, timeout: timeout, message: message))
case "list":
    for s in call(Request(cmd: "list")).sessions ?? [] {
        let age = formatDuration(Date().timeIntervalSince1970 - s.startedAt)
        print("\(s.name)\t\(age)\ttimeout=\(s.timeout == 0 ? "none" : formatDuration(s.timeout))")
    }
case "agents":
    for i in Integrations.all() {
        let s: String
        switch i.status() {
        case .notInstalled: s = "not installed"
        case .available: s = "not connected"
        case .connected: s = "connected"
        case .needsAction(let m): s = "needs a step: \(m)"
        case .broken(let m): s = "broken: \(m)"
        }
        print("\(i.id)\t\(i.name)\t\(s)")
    }
case "connect", "disconnect":
    guard let id = positional.first else { fail(usage, code: 2) }
    guard let i = Integrations.all().first(where: { $0.id == id }) else {
        fail("agentawake: unknown agent \(id); see `agentawake agents`", code: 2)
    }
    do { try cmd == "connect" ? i.connect() : i.disconnect() } catch { fail("agentawake: \(error.localizedDescription)") }
    if cmd == "connect", case .needsAction(let m) = i.status() { print(m) }
    for f in i.files { print("\(cmd == "connect" ? "wrote" : "cleaned") \(f)") }
case "run":
    // The wrapped command always runs and its exit status is ours, whether or not the app is up.
    guard let name = positional.first, !command.isEmpty else { fail(usage, code: 2) }
    let limit = timeout ?? SessionStore.defaultTimeout
    do { _ = try Client.send(Request(cmd: "begin", name: name, timeout: limit)) } catch {
        FileHandle.standardError.write(Data("agentawake: \(error); running without keeping the Mac awake\n".utf8))
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = command
    do { try p.run() } catch { _ = try? Client.send(Request(cmd: "done", name: name)); fail("agentawake: \(error)") }
    // Heartbeat at a third of the timeout (default 30m -> 10m), at most every 30s. The beat carries the
    // timeout, so it recreates the session if the app restarted meanwhile.
    let period = min(30, max(1, limit / 3))
    let t = DispatchSource.makeTimerSource(queue: .global())
    t.schedule(deadline: .now() + period, repeating: period)
    t.setEventHandler { _ = try? Client.send(Request(cmd: "beat", name: name, timeout: limit)) }
    t.resume()
    p.waitUntilExit()
    t.cancel()
    _ = try? Client.send(Request(cmd: "done", name: name))
    exit(p.terminationStatus)
default:
    fail(usage, code: 2)
}
