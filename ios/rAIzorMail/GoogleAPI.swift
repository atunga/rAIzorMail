import Foundation

struct MailFolder: Identifiable, Hashable {
    let accountID: String
    let labelID: String
    let name: String
    var id: String { accountID + ":" + labelID }
}
struct GoogleCalendar: Identifiable, Hashable {
    let accountID: String
    let calendarID: String
    let name: String
    let writable: Bool
    var id: String { accountID + ":" + calendarID }
}
struct CalendarItem: Identifiable {
    var calendar: GoogleCalendar
    var eventID: String
    var title: String
    var notes: String
    var location: String
    var start: Date
    var end: Date
    var allDay: Bool
    var shared: Bool
    var recurring: Bool
    var etag: String
    var id: String { calendar.id + ":" + eventID }
}
@MainActor final class GoogleAPI {
    let accounts: Accounts
    let session: URLSession
    private let gmail = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let calendar = "https://www.googleapis.com/calendar/v3"
    private var nextRequest: [String: Date] = [:]
    private var cooldown: [String: Date] = [:]
    private var cache: [String: (Date, [String: Any])] = [:]
    init(accounts: Accounts, session: URLSession = .shared) { self.accounts = accounts; self.session = session }
    func escape(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
    func request(_ id: String, _ url: String, method: String = "GET", body: [String: Any]? = nil, etag: String? = nil, retry: Bool = true) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard let target = URL(string: url), ["gmail.googleapis.com", "www.googleapis.com"].contains(target.host ?? ""), target.scheme == "https" else { throw MailFailure("Invalid Google request.") }
        if let until = cooldown[id], until > Date() { throw MailFailure("Google is temporarily limiting requests. Pull to refresh again shortly.") }
        let key = id + ":" + url
        if method == "GET", let entry = cache[key], entry.0 > Date() { return entry.1 }
        if url.hasPrefix(gmail) {
            let time = max(nextRequest[id] ?? .distantPast, Date()); nextRequest[id] = time.addingTimeInterval(0.15)
            let delay = time.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        }
        let token = try await accounts.accessToken(id)
        var req = URLRequest(url: target); req.httpMethod = method; req.timeoutInterval = 45
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let etag, !etag.isEmpty { req.setValue(etag, forHTTPHeaderField: "If-Match") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MailFailure("No response from Google.") }
        if http.statusCode == 401 && retry { _ = try await accounts.accessToken(id, force: true); return try await request(id, url, method: method, body: body, etag: etag, retry: false) }
        let result = data.isEmpty ? [:] : (try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:])
        guard (200..<300).contains(http.statusCode) else {
            let reason = (result["error"] as? [String: Any])?["message"] as? String ?? ""
            if http.statusCode == 429 || (http.statusCode == 403 && reason.lowercased().contains("quota")) {
                cooldown[id] = Date().addingTimeInterval(max(60, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
                throw MailFailure("Google is temporarily limiting requests. Your current messages are kept here; try again shortly.")
            }
            if http.statusCode == 412 { throw MailFailure("This event changed on another device. Refresh it before saving again.") }
            throw MailFailure("Google request failed (\(http.statusCode)). \(reason)")
        }
        if method != "GET" { cache = cache.filter { !$0.key.hasPrefix(id + ":") } }
        else if url.contains("?format=full") { if cache.count > 300 { cache.removeAll() }; cache[key] = (Date().addingTimeInterval(45), result) }
        return result
    }
    func labels(_ id: String) async throws -> [MailFolder] {
        let data = try await request(id, gmail + "/labels")
        return (data["labels"] as? [[String: Any]] ?? []).compactMap { item in
            guard let label = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return MailFolder(accountID: id, labelID: label, name: name)
        }
    }
    func messages(_ id: String, folder: String, category: String, query: String, page: String? = nil) async throws -> ([MailItem], String?) {
        var params = [URLQueryItem(name: "maxResults", value: "30")]
        if !query.isEmpty { params.append(URLQueryItem(name: "q", value: query)) }
        else if folder != "ALL" { params.append(URLQueryItem(name: "labelIds", value: folder)); if folder == "INBOX" { params.append(URLQueryItem(name: "q", value: "category:" + category)) } }
        if folder == "TRASH" || folder == "SPAM" { params.append(URLQueryItem(name: "includeSpamTrash", value: "true")) }
        if let page { params.append(URLQueryItem(name: "pageToken", value: page)) }
        var url = URLComponents(string: gmail + "/messages")!; url.queryItems = params
        let data = try await request(id, url.url!.absoluteString)
        var items: [MailItem] = []
        for message in data["messages"] as? [[String: Any]] ?? [] {
            if let messageID = message["id"] as? String { items.append(try await self.message(id, messageID)) }
        }
        return (items, data["nextPageToken"] as? String)
    }
    func message(_ accountID: String, _ messageID: String) async throws -> MailItem {
        MailItem(json: try await request(accountID, gmail + "/messages/" + escape(messageID) + "?format=full"), accountID: accountID)
    }
    func modify(_ item: MailItem, add: [String] = [], remove: [String] = []) async throws {
        _ = try await request(item.accountID, gmail + "/messages/" + escape(item.messageID) + "/modify", method: "POST", body: ["addLabelIds": add, "removeLabelIds": remove])
    }
    func trash(_ item: MailItem) async throws { _ = try await request(item.accountID, gmail + "/messages/" + escape(item.messageID) + "/trash", method: "POST") }
    func bytes(_ item: MailItem, file: MailAttachment) async throws -> Data {
        if let data = file.data { return data }
        let result = try await request(item.accountID, gmail + "/messages/" + escape(item.messageID) + "/attachments/" + escape(file.id))
        guard let encoded = result["data"] as? String, let data = Data(base64URL: encoded) else { throw MailFailure("Could not download attachment.") }; return data
    }
    func draft(_ item: MailItem) async throws -> MailDraft {
        var result = MailDraft(); result.accountID = item.accountID; result.to = item.to; result.cc = item.cc; result.subject = item.subject; result.text = item.text; result.threadID = item.threadID
        var page: String?
        repeat {
            let response = try await request(item.accountID, gmail + "/drafts?maxResults=500" + (page.map { "&pageToken=" + escape($0) } ?? ""))
            if let found = (response["drafts"] as? [[String: Any]])?.first(where: { ($0["message"] as? [String: Any])?["id"] as? String == item.messageID }) { result.draftID = found["id"] as? String; break }
            page = response["nextPageToken"] as? String
        } while page != nil
        guard let draftID = result.draftID else { throw MailFailure("This draft changed. Refresh Drafts and open it again.") }
        let response = try await request(item.accountID, gmail + "/drafts/" + escape(draftID) + "?format=full")
        let raw = response["message"] as? [String: Any] ?? [:]
        let headers = (raw["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
        result.bcc = headers.first { ($0["name"] as? String)?.lowercased() == "bcc" }?["value"] as? String ?? ""
        for var attachment in item.attachments { attachment.data = try await bytes(item, file: attachment); result.attachments.append(attachment) }
        return result
    }
    func saveDraft(_ draft: MailDraft) async throws -> String {
        let raw = try MailRules.rawMessage(draft, from: accounts.account(draft.accountID).email, requireRecipient: false)
        var message: [String: Any] = ["raw": raw]; if let thread = draft.threadID { message["threadId"] = thread }
        let url = gmail + "/drafts" + (draft.draftID.map { "/" + escape($0) } ?? "")
        let response = try await request(draft.accountID, url, method: draft.draftID == nil ? "POST" : "PUT", body: ["message": message])
        guard let id = response["id"] as? String else { throw MailFailure("Google did not confirm saving the draft.") }; return id
    }
    func send(_ draft: MailDraft) async throws {
        let raw = try MailRules.rawMessage(draft, from: accounts.account(draft.accountID).email)
        if draft.draftID != nil {
            let id = try await saveDraft(draft)
            _ = try await request(draft.accountID, gmail + "/drafts/send", method: "POST", body: ["id": id])
        } else {
            var body: [String: Any] = ["raw": raw]; if let thread = draft.threadID { body["threadId"] = thread }
            _ = try await request(draft.accountID, gmail + "/messages/send", method: "POST", body: body)
        }
    }
    func calendars(_ id: String) async throws -> [GoogleCalendar] {
        var page: String?, all: [GoogleCalendar] = []
        repeat {
            let result = try await request(id, calendar + "/users/me/calendarList?maxResults=250" + (page.map { "&pageToken=" + escape($0) } ?? ""))
            for item in result["items"] as? [[String: Any]] ?? [] {
                if let key = item["id"] as? String { all.append(GoogleCalendar(accountID: id, calendarID: key, name: item["summary"] as? String ?? key, writable: ["owner", "writer"].contains(item["accessRole"] as? String ?? ""))) }
            }; page = result["nextPageToken"] as? String
        } while page != nil
        return all
    }
    func events(_ cal: GoogleCalendar, start: Date, end: Date, query: String) async throws -> [CalendarItem] {
        let iso = ISO8601DateFormatter(); var page: String?, all: [CalendarItem] = []
        repeat {
            var url = URLComponents(string: calendar + "/calendars/" + escape(cal.calendarID) + "/events")!
            url.queryItems = ["timeMin": iso.string(from: start), "timeMax": iso.string(from: end), "singleEvents": "true", "orderBy": "startTime", "maxResults": "250", "q": query].map { URLQueryItem(name: $0.key, value: $0.value) }
            if let page { url.queryItems?.append(URLQueryItem(name: "pageToken", value: page)) }
            let response = try await request(cal.accountID, url.url!.absoluteString)
            for item in response["items"] as? [[String: Any]] ?? [] {
                guard item["status"] as? String != "cancelled", let id = item["id"] as? String else { continue }
                let s = item["start"] as? [String: String] ?? [:], e = item["end"] as? [String: String] ?? [:]
                func date(_ value: [String: String]) -> Date? {
                    if let raw = value["dateTime"] { return iso.date(from: raw) }
                    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return value["date"].flatMap { f.date(from: $0) }
                }
                guard let start = date(s), let end = date(e) else { continue }
                all.append(CalendarItem(calendar: cal, eventID: id, title: item["summary"] as? String ?? "Untitled event", notes: item["description"] as? String ?? "", location: item["location"] as? String ?? "", start: start, end: end, allDay: s["date"] != nil, shared: !(item["attendees"] as? [Any] ?? []).isEmpty, recurring: item["recurringEventId"] != nil, etag: item["etag"] as? String ?? ""))
            }
            page = response["nextPageToken"] as? String
        } while page != nil
        return all
    }
    func saveEvent(_ event: CalendarItem) async throws {
        guard event.calendar.writable, !event.shared, !event.recurring, event.end > event.start else { throw MailFailure("Choose a writable calendar and valid dates. Edit shared or recurring events in Google Calendar.") }
        let iso = ISO8601DateFormatter(), day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd"
        let body: [String: Any] = ["summary": event.title, "description": event.notes, "location": event.location, "start": event.allDay ? ["date": day.string(from: event.start)] : ["dateTime": iso.string(from: event.start)], "end": event.allDay ? ["date": day.string(from: event.end)] : ["dateTime": iso.string(from: event.end)]]
        _ = try await request(event.calendar.accountID, calendar + "/calendars/" + escape(event.calendar.calendarID) + "/events" + (event.eventID.isEmpty ? "" : "/" + escape(event.eventID)), method: event.eventID.isEmpty ? "POST" : "PATCH", body: body, etag: event.etag)
    }
    func deleteEvent(_ event: CalendarItem) async throws {
        guard event.calendar.writable, !event.shared, !event.recurring else { throw MailFailure("Manage this event in Google Calendar.") }
        _ = try await request(event.calendar.accountID, calendar + "/calendars/" + escape(event.calendar.calendarID) + "/events/" + escape(event.eventID), method: "DELETE", etag: event.etag)
    }
}
