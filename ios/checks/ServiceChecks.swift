import Foundation
final class MockProtocol: URLProtocol {
    static var handle: (URLRequest) throws -> (Int, [String: Any]) = { _ in throw MailFailure("Unexpected request") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@main struct ServiceChecks {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: configuration), accounts = Accounts()
        let api = GoogleAPI(accounts: accounts, session: session)
        var calls = 0
        MockProtocol.handle = { request in
            calls += 1
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test")
            if request.url!.path.hasSuffix("/messages") {
                let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                precondition(q.contains(URLQueryItem(name: "labelIds", value: "INBOX")))
                precondition(q.contains(URLQueryItem(name: "q", value: "category:promotions")))
                return (200, ["messages": [["id":"one"]], "nextPageToken":"next"])
            }
            return (200, ["id":"one", "payload":[:]])
        }
        let mail = try await api.messages("a", folder: "INBOX", category: "promotions", query: "")
        precondition(mail.0.count == 1 && mail.1 == "next" && calls == 2)
        _ = try await api.message("a", "one"); precondition(calls == 2)
        print("PASS: Gmail categories, pagination, account credentials, and read cache")
        MockProtocol.handle = { _ in calls += 1; return (429, ["error":["message":"Quota exceeded"]]) }
        do { _ = try await api.labels("a"); preconditionFailure("429 accepted") } catch {}
        let previous = calls
        do { _ = try await api.labels("a"); preconditionFailure("Cooldown not respected") } catch {}
        precondition(calls == previous); print("PASS: Rate-limit cooldown prevents repeated requests")
        let other = GoogleAPI(accounts: accounts, session: session)
        MockProtocol.handle = { request in
            precondition(request.value(forHTTPHeaderField: "If-Match") == "original")
            return (412, ["error":["message":"Conflict"]])
        }
        let cal = GoogleCalendar(accountID:"a", calendarID:"primary", name:"My calendar", writable:true)
        let event = CalendarItem(calendar:cal, eventID:"event", title:"Meeting", notes:"", location:"", start:Date(), end:Date().addingTimeInterval(3600), allDay:false, shared:false, recurring:false, etag:"original")
        do { try await other.saveEvent(event); preconditionFailure("Conflict accepted") } catch { precondition(error.localizedDescription.contains("another device")) }
        print("PASS: Stale calendar edits are rejected")
        // A write only invalidates its own cached message, not every visible body.
        let cached = GoogleAPI(accounts: accounts, session: session)
        var readIDs: [String] = []
        MockProtocol.handle = { request in
            if request.httpMethod == "GET" { readIDs.append(request.url!.lastPathComponent) }
            return (200, ["id": request.url!.lastPathComponent, "payload": [:]])
        }
        let first = try await cached.message("a", "first")
        _ = try await cached.message("a", "second")
        try await cached.trash(first)
        _ = try await cached.message("a", "second")
        _ = try await cached.message("a", "first")
        precondition(readIDs == ["first", "second", "first"])
        print("PASS: Deleting one message preserves unrelated cached messages")

        // The Gmail cooldown above cannot block Calendar for the same account.
        MockProtocol.handle = { request in
            precondition(request.url!.host == "www.googleapis.com")
            return (200, ["items": []])
        }
        _ = try await api.calendars("a")
        print("PASS: Gmail rate limits do not block Calendar")

        func message(_ id: String, account: String = "a") -> MailItem {
            MailItem(json: ["id": id, "labelIds": ["INBOX"], "payload": [:]], accountID: account)
        }
        accounts.secrets.accounts = [GoogleAccount(id: "a", email: "a@example.com"), GoogleAccount(id: "b", email: "b@example.com")]
        let bulk = MailModel(accounts: accounts, session: session)
        bulk.messages = [message("one"), message("two"), message("three"), message("four", account: "b")]
        bulk.selected = Set(bulk.messages.map(\.id))
        var writes: [String] = []
        MockProtocol.handle = { request in
            precondition(request.httpMethod == "POST" && request.url!.lastPathComponent == "trash", "Bulk delete must not reload mail or calendars")
            let id = request.url!.deletingLastPathComponent().lastPathComponent
            writes.append(id)
            if id == "two" { return (403, ["error": ["message": "Too many requests", "errors": [["reason": "userRateLimitExceeded"]]]]) }
            return (200, ["id": id])
        }
        await bulk.mutateSelected(trash: true)
        precondition(writes == ["one", "two", "four"])
        precondition(bulk.selected == ["a:two", "a:three"])
        precondition(bulk.messages.map(\.id) == ["a:two", "a:three"])
        precondition(bulk.error?.contains("2 of 4") == true)
        precondition(bulk.error!.components(separatedBy: "temporarily limiting").count == 2)
        print("PASS: Partial bulk delete keeps failures selected, stops throttled account, continues other accounts, and never refreshes")

        let calendarModel = MailModel(accounts: accounts, session: session)
        calendarModel.calendars = (1...8).map { GoogleCalendar(accountID: "a", calendarID: "cal\($0)", name: "Calendar \($0)", writable: true) }
        var cachedEvent = event; cachedEvent.calendar = calendarModel.calendars[3]
        calendarModel.events = [cachedEvent]
        var calendarCalls = 0
        MockProtocol.handle = { _ in calendarCalls += 1; return (429, ["error": ["message": "Quota exceeded"]]) }
        await calendarModel.loadCalendar()
        precondition(calendarCalls == 1 && calendarModel.error == nil && calendarModel.events.map(\.id) == [cachedEvent.id])
        precondition(calendarModel.calendarSyncError?.components(separatedBy: "temporarily limiting").count == 2)
        print("PASS: Calendar quota failure produces one inline notice, not eight modal errors")

        let duplicate = MailModel(accounts: accounts, session: session)
        duplicate.selectedAccount = "a"
        var lists = 0
        MockProtocol.handle = { request in
            precondition(request.url!.lastPathComponent == "messages")
            lists += 1; return (200, ["messages": []])
        }
        async let refresh1: Void = duplicate.loadMail()
        async let refresh2: Void = duplicate.loadMail()
        _ = await (refresh1, refresh2)
        precondition(lists == 1)
        print("PASS: Overlapping inbox refreshes share one request")
        let sameFolder = MailModel(accounts: accounts, session: session)
        sameFolder.messages = [message("one")]; sameFolder.selected = ["a:one"]
        MockProtocol.handle = { request in
            precondition(request.httpMethod == "GET" && request.url!.lastPathComponent == "labels")
            return (200, ["labels": [["id": "INBOX", "name": "INBOX"]]])
        }
        await sameFolder.mutateSelected(destination: "INBOX")
        precondition(sameFolder.messages.count == 1 && sameFolder.selected.isEmpty)
        print("PASS: Moving to the same folder keeps the message visible without a write")
        accounts.secrets.geminiKey = "test-only-key"
        let ai = Gemini(accounts: accounts, session: session)
        MockProtocol.handle = { request in
            precondition(request.url!.host == "generativelanguage.googleapis.com")
            precondition(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-only-key")
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data(reading: request.httpBodyStream!)) as! [String:Any]
            let config = body["generationConfig"] as! [String:Any], format = config["responseFormat"] as! [String:Any], text = format["text"] as! [String:Any]
            precondition(text["mimeType"] as? String == "APPLICATION_JSON")
            let contents = body["contents"] as! [[String:Any]], parts = contents[0]["parts"] as! [[String:String]]
            precondition(parts[0]["text"] == "invoices last month")
            return (200, ["candidates":[["finishReason":"STOP", "content":["parts":[["text":"{\"query\":\"invoice newer_than:1m\"}"]]]]]])
        }
        let query = try await ai.mailQuery("invoices last month")
        precondition(query == "invoice newer_than:1m")
        print("PASS: Gemini sends only the search and uses the validated response format")
    }
}
extension Data {
    init(reading stream: InputStream) {
        self.init(); stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating:0,count:4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer,maxLength:buffer.count); if count <= 0 { break }; append(buffer,count:count) }
    }
}
