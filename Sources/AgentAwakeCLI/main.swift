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

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { fail(usage, code: 2) }
args.removeFirst()

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
case "run":
    guard let name = positional.first, !command.isEmpty else { fail(usage, code: 2) }
    _ = call(Request(cmd: "begin", name: name, timeout: timeout))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = command
    do { try p.run() } catch { _ = call(Request(cmd: "done", name: name)); fail("agentawake: \(error)") }
    // Heartbeat at a third of the timeout (default 30m -> 10m), at most every 30s.
    let period = min(30, max(1, (timeout ?? SessionStore.defaultTimeout) / 3))
    let t = DispatchSource.makeTimerSource(queue: .global())
    t.schedule(deadline: .now() + period, repeating: period)
    t.setEventHandler { _ = try? Client.send(Request(cmd: "beat", name: name)) }
    t.resume()
    p.waitUntilExit()
    t.cancel()
    _ = call(Request(cmd: "done", name: name))
    exit(p.terminationStatus)
default:
    fail(usage, code: 2)
}
