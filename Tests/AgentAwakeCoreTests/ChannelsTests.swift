import Foundation
import XCTest
@testable import AgentAwakeCore

private let emojiTitle = "✅ Claude Code is done — ünïcode 🎉"

private func json(_ r: URLRequest?) throws -> [String: Any] {
    let body = try XCTUnwrap(try XCTUnwrap(r).httpBody)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func assertJSONPost(_ r: URLRequest?, url: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(r?.url?.absoluteString, url, file: file, line: line)
    XCTAssertEqual(r?.httpMethod, "POST", file: file, line: line)
    XCTAssertEqual(r?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8", file: file, line: line)
    // Raw UTF-8 on the wire, not \u escapes or stripped characters.
    let raw = r?.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
    XCTAssertTrue(raw.contains("🎉") && raw.contains("ünïcode"), "UTF-8 lost: \(raw)", file: file, line: line)
}

final class ChannelRequestTests: XCTestCase {
    let urgent = Alert(title: emojiTitle, body: "Needs — you", level: .urgent, session: "claude-42")
    let info = Alert(title: emojiTitle, body: "Finished.", level: .info, session: nil)

    func testNtfyPublishesJSONToServerRoot() throws {
        let n = NtfyNotifier(server: "https://ntfy.example/", topic: "secret-topic")
        let r = n.request(for: urgent)
        assertJSONPost(r, url: "https://ntfy.example/")
        let b = try json(r)
        XCTAssertEqual(b["topic"] as? String, "secret-topic")
        XCTAssertEqual(b["title"] as? String, emojiTitle)
        XCTAssertEqual(b["message"] as? String, "Needs — you")
        XCTAssertEqual(b["priority"] as? Int, 4)
        XCTAssertEqual(b["tags"] as? [String], ["warning"])
        XCTAssertEqual(b["sequence_id"] as? String, "claude-42")

        let i = try json(n.request(for: info))
        XCTAssertEqual(i["priority"] as? Int, 3)
        XCTAssertEqual(i["tags"] as? [String], ["white_check_mark"])
        XCTAssertNil(i["sequence_id"])
    }

    func testNtfyDefaultsAndMissingTopic() {
        XCTAssertEqual(NtfyNotifier(topic: "t").request(for: info)?.url?.absoluteString, "https://ntfy.sh/")
        XCTAssertNil(NtfyNotifier(config: Config()).request(for: info))
        XCTAssertEqual(NtfyNotifier(config: Config(ntfyServer: "http://h:8/", ntfyTopic: "t"))
            .request(for: info)?.url?.absoluteString, "http://h:8/")
    }

    func testReplaceIDsAreSafeStableAndDistinct() throws {
        XCTAssertEqual(ChannelText.replaceID("claude-42_a"), "claude-42_a")
        XCTAssertNil(ChannelText.replaceID(nil))
        let mapped = try XCTUnwrap(ChannelText.replaceID("claude:42"))
        XCTAssertNotEqual(mapped, "claude-42")
        XCTAssertEqual(mapped, ChannelText.replaceID("claude:42"))
        let long = try XCTUnwrap(ChannelText.replaceID(String(repeating: "x", count: 200)))
        XCTAssertLessThanOrEqual(long.count, 64)
        XCTAssertNotNil(long.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
    }

    func testBark() throws {
        let r = BarkNotifier(key: "barkkey", server: nil).request(for: urgent)
        assertJSONPost(r, url: "https://api.day.app/push")
        let b = try json(r)
        XCTAssertEqual(b["device_key"] as? String, "barkkey")
        XCTAssertEqual(b["title"] as? String, emojiTitle)
        XCTAssertEqual(b["body"] as? String, "Needs — you")
        XCTAssertEqual(b["level"] as? String, "timeSensitive")
        XCTAssertEqual(b["group"] as? String, "Agent Awake")
        XCTAssertEqual(b["id"] as? String, "claude-42")
        let i = BarkNotifier(key: "k", server: "http://bark.local:8080/").request(for: info)
        XCTAssertEqual(i?.url?.absoluteString, "http://bark.local:8080/push")
        XCTAssertEqual(try json(i)["level"] as? String, "active")
        XCTAssertNil(try json(i)["id"])
    }

    func testPushover() throws {
        let r = PushoverNotifier(token: "apptoken", user: "userkey").request(for: urgent)
        assertJSONPost(r, url: "https://api.pushover.net/1/messages.json")
        let b = try json(r)
        XCTAssertEqual(b["token"] as? String, "apptoken")
        XCTAssertEqual(b["user"] as? String, "userkey")
        XCTAssertEqual(b["title"] as? String, emojiTitle)
        XCTAssertEqual(b["message"] as? String, "Needs — you")
        XCTAssertEqual(b["priority"] as? Int, 1)
        let i = try json(PushoverNotifier(token: "a", user: "u").request(for: Alert(title: emojiTitle, body: "")))
        XCTAssertEqual(i["priority"] as? Int, 0)
        XCTAssertEqual(i["message"] as? String, emojiTitle, "Pushover requires a non-empty message")
    }

    func testTelegramEscapesHTML() throws {
        let n = TelegramNotifier(token: "123:ABC", chatId: "987")
        let r = n.request(for: urgent)
        assertJSONPost(r, url: "https://api.telegram.org/bot123:ABC/sendMessage")
        let b = try json(r)
        XCTAssertEqual(b["chat_id"] as? String, "987")
        XCTAssertEqual(b["parse_mode"] as? String, "HTML")
        XCTAssertEqual(b["text"] as? String, "<b>\(emojiTitle)</b>\nNeeds — you")
        let e = try json(n.request(for: Alert(title: "<script> & co", body: "a<b>c")))
        XCTAssertEqual(e["text"] as? String, "<b>&lt;script&gt; &amp; co</b>\na&lt;b&gt;c")
    }

    func testDiscord() throws {
        let hook = "https://discord.com/api/webhooks/1/secret"
        let r = DiscordNotifier(webhook: hook).request(for: urgent)
        assertJSONPost(r, url: hook)
        let b = try json(r)
        XCTAssertEqual(b["content"] as? String, "**\(emojiTitle)**\nNeeds — you")
        XCTAssertEqual((b["allowed_mentions"] as? [String: Any])?["parse"] as? [String], [])
        XCTAssertNil(DiscordNotifier(webhook: "not a url").request(for: urgent))
    }

    func testSlack() throws {
        let hook = "https://hooks.slack.com/services/T/B/secret"
        let r = SlackNotifier(webhook: hook).request(for: urgent)
        assertJSONPost(r, url: hook)
        XCTAssertEqual(try json(r)["text"] as? String, "*\(emojiTitle)*\nNeeds — you")
        let e = try json(SlackNotifier(webhook: hook).request(for: Alert(title: "a<b", body: "x & y")))
        XCTAssertEqual(e["text"] as? String, "*a&lt;b*\nx &amp; y")
    }

    func testChannelsListsEveryConfiguredChannel() {
        XCTAssertTrue(Channels.phone(Config()).isEmpty)
        var c = Config(ntfyServer: nil, ntfyTopic: "t")
        c.bark = .init(key: "k")
        c.pushover = .init(token: "t", user: "u")
        c.telegram = .init(token: "1:A", chatId: "2")
        c.discordWebhook = "https://discord.com/api/webhooks/1/x"
        c.slackWebhook = "https://hooks.slack.com/services/x"
        XCTAssertEqual(Channels.phone(c).map(\.name), ["ntfy", "Bark", "Pushover", "Telegram", "Discord", "Slack"])

        var blank = Config(ntfyServer: nil, ntfyTopic: "  ")
        blank.bark = .init(key: "")
        blank.pushover = .init(token: "t", user: " ")
        blank.telegram = .init(token: "1:A", chatId: "")
        blank.discordWebhook = ""
        XCTAssertTrue(Channels.phone(blank).isEmpty)
    }

    func testTelegramChatIdFromUpdates() {
        let updates = #"{"ok":true,"result":[{"update_id":1,"message":{"chat":{"id":111}}},"#
            + #"{"update_id":2,"message":{"chat":{"id":-1001234567890}}}]}"#
        XCTAssertEqual(Telegram.chatId(fromUpdates: Data(updates.utf8)), "-1001234567890")
        XCTAssertNil(Telegram.chatId(fromUpdates: Data(#"{"ok":true,"result":[]}"#.utf8)))
    }

    func testRetryAfterParsing() {
        XCTAssertEqual(HTTPSender.retryAfter("120"), 120)
        XCTAssertNil(HTTPSender.retryAfter(nil))
        XCTAssertNil(HTTPSender.retryAfter("soon"))
        let now = Date(timeIntervalSince1970: 1_000_000_000)   // Sun, 09 Sep 2001 01:46:40 GMT
        XCTAssertEqual(HTTPSender.retryAfter("Sun, 09 Sep 2001 01:47:10 GMT", now: now), 30)
    }

    func testTransportFailureLogHasNoSecrets() {
        let secretURL = "https://api.telegram.org/bot123:SECRET/sendMessage"
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: [
            NSURLErrorFailingURLStringErrorKey: secretURL,
            NSLocalizedDescriptionKey: "Could not connect to \(secretURL)",
        ])
        let msg = HTTPSender.transportFailure(channel: "Telegram", error: err)
        XCTAssertFalse(msg.contains("SECRET"))
        XCTAssertTrue(msg.contains("Telegram") && msg.contains("-1004"))
    }
}

// MARK: - Router

private struct FakePresence: PresenceSource {
    var away: Bool
    var asked: ((Double) -> Void)? = nil
    func isAway(after seconds: Double) -> Bool { asked?(seconds); return away }
}

final class AlertRouterTests: XCTestCase {
    func testRoutesEveryCombination() {
        for when in Config.PingWhen.allCases {
            for away in [true, false] {
                for configured in [true, false] {
                    var c = Config(); c.pingWhen = when
                    let local = FakeNotifier(), phone = FakeNotifier()
                    let r = AlertRouter(config: { c }, presence: FakePresence(away: away), local: local,
                                        phone: { _ in configured ? [phone] : [] })
                    r.send(Alert(title: "t", body: "b"))
                    let wantPhone = configured && (when == .always || (when == .away && away))
                    let label = "\(when) away=\(away) configured=\(configured)"
                    XCTAssertEqual(phone.alerts.count, wantPhone ? 1 : 0, label)
                    XCTAssertEqual(local.alerts.count, wantPhone ? 0 : 1, label)
                    XCTAssertEqual(r.route(for: c), wantPhone ? .phone : .local, label)
                }
            }
        }
    }

    func testDefaultIsAwayWithConfiguredThreshold() {
        var c = Config(); c.awayAfterMinutes = 2
        var asked: Double?
        let local = FakeNotifier(), phone = FakeNotifier()
        let r = AlertRouter(config: { c }, presence: FakePresence(away: true, asked: { asked = $0 }), local: local,
                            phone: { _ in [phone] })
        r.send(Alert(title: "t", body: "b"))
        XCTAssertEqual(asked, 120)
        XCTAssertEqual(phone.alerts.count, 1)
    }

    func testEveryPhoneChannelGetsTheAlert() {
        var c = Config(); c.pingWhen = .always
        let a = FakeNotifier(), b = FakeNotifier(), local = FakeNotifier()
        AlertRouter(config: { c }, presence: FakePresence(away: false), local: local, phone: { _ in [a, b] })
            .send(Alert(title: "t", body: "b"))
        XCTAssertEqual([a.alerts.count, b.alerts.count, local.alerts.count], [1, 1, 0])
    }

    func testCoalescesIdenticalAlertsWithin30Seconds() {
        var t = 1000.0
        let local = FakeNotifier()
        let r = AlertRouter(config: { Config() }, presence: FakePresence(away: false), local: local,
                            phone: { _ in [] }, now: { t })
        r.send(Alert(title: "a", body: "x"))
        t += 10; r.send(Alert(title: "a", body: "x", level: .urgent))
        r.send(Alert(title: "a", body: "y"))
        r.send(Alert(title: "b", body: "x"))
        t += 21; r.send(Alert(title: "a", body: "x"))
        XCTAssertEqual(local.sent.map { "\($0.0)/\($0.1)" }, ["a/x", "a/y", "b/x", "a/x"])
    }

    func testSystemPresenceReadsWithoutCrashing() {
        XCTAssertGreaterThanOrEqual(SystemPresence.idleSeconds, 0)
        XCTAssertTrue(SystemPresence().isAway(after: 0), "idle ≥ 0 s is always away")
        _ = SystemPresence.lidClosed
    }
}

// MARK: - Live smoke against a local HTTP stub

/// Minimal HTTP/1.1 server on 127.0.0.1 that records requests. Nothing leaves the machine.
final class StubHTTPServer {
    struct Hit { let method: String, path: String, headers: [String: String], body: Data }

    let port: UInt16
    private let fd: Int32
    private let lock = NSLock()
    private var recorded: [Hit] = []
    private let respond: (Int) -> (status: Int, headers: [String: String], body: String)

    var hits: [Hit] { lock.lock(); defer { lock.unlock() }; return recorded }

    init(respond: @escaping (Int) -> (status: Int, headers: [String: String], body: String) = { _ in (200, [:], #"{"ok":true}"#) }) throws {
        self.respond = respond
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, len) == 0 && listen(s, 16) == 0 && getsockname(s, $0, &len) == 0
            }
        }
        guard ok else { close(s); throw NSError(domain: "stub", code: Int(errno)) }
        fd = s
        port = UInt16(bigEndian: addr.sin_port)
        let listener = s
        Thread.detachNewThread { [weak self] in
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 { return }
                self?.handle(c)
                close(c)
            }
        }
    }

    deinit { shutdown(fd, SHUT_RDWR); close(fd) }

    var base: String { "http://127.0.0.1:\(port)" }

    private func handle(_ c: Int32) {
        var buf = Data(), chunk = [UInt8](repeating: 0, count: 65536)
        let crlf2 = Data("\r\n\r\n".utf8)
        while buf.range(of: crlf2) == nil {
            let n = read(c, &chunk, chunk.count)
            if n <= 0 { return }
            buf.append(contentsOf: chunk[0..<n])
        }
        let sep = buf.range(of: crlf2)!
        var lines = String(decoding: buf[..<sep.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ").map(String.init)
        var headers: [String: String] = [:]
        for l in lines {
            guard let colon = l.firstIndex(of: ":") else { continue }
            headers[l[..<colon].lowercased()] = l[l.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var body = Data(buf[sep.upperBound...])
        let want = Int(headers["content-length"] ?? "0") ?? 0
        while body.count < want {
            let n = read(c, &chunk, chunk.count)
            if n <= 0 { break }
            body.append(contentsOf: chunk[0..<n])
        }
        lock.lock()
        let index = recorded.count
        recorded.append(Hit(method: start.first ?? "", path: start.count > 1 ? start[1] : "", headers: headers, body: body))
        lock.unlock()
        let (status, extra, text) = respond(index)
        var head = "HTTP/1.1 \(status) Stub\r\nContent-Type: application/json\r\nContent-Length: \(text.utf8.count)\r\nConnection: close\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        let out = Data((head + "\r\n" + text).utf8)
        _ = out.withUnsafeBytes { write(c, $0.baseAddress, out.count) }
    }
}

private final class LogCapture {
    private let lock = NSLock()
    private var lines: [String] = []
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
}

final class ChannelLiveSmokeTests: XCTestCase {
    private func deliver(_ ch: HTTPChannel, _ alert: Alert, via sender: HTTPSender) -> Int? {
        let done = expectation(description: ch.channelName)
        var status: Int?
        ch.send(alert, via: sender) { status = $0; done.fulfill() }
        wait(for: [done], timeout: 10)
        return status
    }

    func testNtfyAndBarkReachStubWithUTF8Intact() throws {
        let stub = try StubHTTPServer()
        let log = LogCapture()
        let sender = HTTPSender(log: log.add)
        let alert = Alert(title: emojiTitle, body: "Body — ✓", level: .urgent, session: "s1")

        XCTAssertEqual(deliver(NtfyNotifier(server: stub.base, topic: "topic-secret"), alert, via: sender), 200)
        XCTAssertEqual(deliver(BarkNotifier(key: "bark-secret", server: stub.base + "/"), alert, via: sender), 200)
        XCTAssertEqual(deliver(TelegramNotifier(token: "1:TGSECRET", chatId: "5", api: stub.base), alert, via: sender), 200)

        let hits = stub.hits
        XCTAssertEqual(hits.map(\.path), ["/", "/push", "/bot1:TGSECRET/sendMessage"])
        XCTAssertEqual(Set(hits.map(\.method)), ["POST"])
        let ntfy = try XCTUnwrap(JSONSerialization.jsonObject(with: hits[0].body) as? [String: Any])
        XCTAssertEqual(ntfy["title"] as? String, emojiTitle)
        XCTAssertEqual(ntfy["message"] as? String, "Body — ✓")
        XCTAssertEqual(ntfy["topic"] as? String, "topic-secret")
        XCTAssertEqual(ntfy["priority"] as? Int, 4)
        let bark = try XCTUnwrap(JSONSerialization.jsonObject(with: hits[1].body) as? [String: Any])
        XCTAssertEqual(bark["title"] as? String, emojiTitle)
        XCTAssertEqual(bark["device_key"] as? String, "bark-secret")
        XCTAssertTrue(String(decoding: hits[2].body, as: UTF8.self).contains(emojiTitle))
        XCTAssertEqual(hits[0].headers["content-type"], "application/json; charset=utf-8")
        XCTAssertTrue(log.all.isEmpty, "\(log.all)")
    }

    func testRetriesOnceOn429AndNeverOn4xx() throws {
        let limited = try StubHTTPServer { i in i == 0 ? (429, ["Retry-After": "0"], "{}") : (200, [:], "{}") }
        let log = LogCapture()
        let sender = HTTPSender(log: log.add)
        XCTAssertEqual(deliver(SlackNotifier(webhook: limited.base + "/services/SLACKSECRET"), Alert(title: "t", body: "b"),
                               via: sender), 200)
        XCTAssertEqual(limited.hits.count, 2)

        let always = try StubHTTPServer { _ in (429, ["Retry-After": "0"], "{}") }
        XCTAssertEqual(deliver(DiscordNotifier(webhook: always.base + "/api/webhooks/1/DISCORDSECRET"),
                               Alert(title: "t", body: "b"), via: sender), 429)
        XCTAssertEqual(always.hits.count, 2, "429 is retried exactly once")

        let refused = try StubHTTPServer { _ in (401, [:], #"{"ok":false,"description":"Unauthorized"}"#) }
        XCTAssertEqual(deliver(TelegramNotifier(token: "9:TGSECRET", chatId: "1", api: refused.base),
                               Alert(title: "t", body: "b"), via: sender), 401)
        XCTAssertEqual(refused.hits.count, 1)

        XCTAssertTrue(log.all.contains("Telegram: HTTP 401, ping not delivered"), "\(log.all)")
        for line in log.all { XCTAssertFalse(line.contains("SECRET"), line) }
    }

    func testUnreachableServerLogsWithoutSecrets() {
        let log = LogCapture()
        let status = deliver(TelegramNotifier(token: "1:TGSECRET", chatId: "1", api: "http://127.0.0.1:9"),
                             Alert(title: "t", body: "b"), via: HTTPSender(log: log.add))
        XCTAssertNil(status)
        XCTAssertEqual(log.all.count, 1)
        XCTAssertFalse(log.all.joined().contains("SECRET"), "\(log.all)")
    }

    func testDiscoverChatIdAgainstStub() async throws {
        let stub = try StubHTTPServer { _ in (200, [:], #"{"ok":true,"result":[{"update_id":7,"message":{"chat":{"id":4242}}}]}"#) }
        let id = try await Telegram.discoverChatId(token: "5:TOKEN", api: stub.base, session: URLSession(configuration: .ephemeral))
        XCTAssertEqual(id, "4242")
        XCTAssertEqual(stub.hits.first?.path, "/bot5:TOKEN/getUpdates")

        let bad = try StubHTTPServer { _ in (401, [:], #"{"ok":false,"description":"Unauthorized"}"#) }
        do {
            _ = try await Telegram.discoverChatId(token: "5:TOKEN", api: bad.base, session: URLSession(configuration: .ephemeral))
            XCTFail("expected an error")
        } catch let Telegram.SetupError.refused(status, reason) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(reason, "Unauthorized")
        }
    }
}
