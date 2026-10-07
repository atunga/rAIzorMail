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
