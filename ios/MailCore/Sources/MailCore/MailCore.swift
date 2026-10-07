import Foundation

public struct MailFailure: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
}
public struct MailAttachment: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var mime: String
    public var data: Data?
    public var size: Int
    public init(id: String = UUID().uuidString, name: String, mime: String, data: Data? = nil, size: Int = 0) { self.id = id; self.name = name; self.mime = mime; self.data = data; self.size = data?.count ?? size }
}
public struct MailItem: Identifiable {
    public var id: String { accountID + ":" + messageID }
    public let accountID: String
    public let messageID: String
    public let threadID: String
    public var labels: [String]
    public let subject: String
    public let from: String
    public let to: String
    public let cc: String
    public let replyTo: String
    public let internetID: String
    public let references: String
    public let date: Date
    public let snippet: String
    public let text: String
    public let html: String
    public let attachments: [MailAttachment]
    public var unread: Bool { labels.contains("UNREAD") }
    public init(json: [String: Any], accountID: String) {
        self.accountID = accountID; messageID = json["id"] as? String ?? ""; threadID = json["threadId"] as? String ?? ""
        labels = json["labelIds"] as? [String] ?? []
        let payload = json["payload"] as? [String: Any] ?? [:]
        let headers = payload["headers"] as? [[String: Any]] ?? []
        func header(_ name: String) -> String { headers.first { ($0["name"] as? String)?.lowercased() == name.lowercased() }?["value"] as? String ?? "" }
        subject = header("Subject"); from = header("From"); to = header("To"); cc = header("Cc"); replyTo = header("Reply-To"); internetID = header("Message-ID"); references = header("References")
        date = Date(timeIntervalSince1970: (Double(json["internalDate"] as? String ?? "") ?? 0) / 1000)
        snippet = json["snippet"] as? String ?? ""
        var plain: [String] = [], rich: [String] = [], files: [MailAttachment] = []
        func walk(_ part: [String: Any]) {
            let mime = part["mimeType"] as? String ?? "application/octet-stream"
            let body = part["body"] as? [String: Any] ?? [:]
            let data = Data(base64URL: body["data"] as? String ?? "")
            let name = part["filename"] as? String ?? ""
            if !name.isEmpty { files.append(MailAttachment(id: body["attachmentId"] as? String ?? UUID().uuidString, name: name, mime: mime, data: data?.isEmpty == false ? data : nil, size: body["size"] as? Int ?? 0)) }
            else if let data, let value = String(data: data, encoding: .utf8) {
                if mime == "text/plain" { plain.append(value) }
                if mime == "text/html" { rich.append(value) }
            }
            for child in part["parts"] as? [[String: Any]] ?? [] { walk(child) }
        }
        walk(payload); text = plain.joined(separator: "\n"); html = rich.joined(separator: "\n"); attachments = files
    }
}
public struct MailDraft: Identifiable, Equatable {
    public var id = UUID()
    public var accountID = ""
    public var draftID: String?
    public var threadID: String?
    public var to = ""
    public var cc = ""
    public var bcc = ""
    public var subject = ""
    public var text = ""
    public var inReplyTo = ""
    public var references = ""
    public var attachments: [MailAttachment] = []
    public init() {}
    public var hasContent: Bool { ![to, cc, bcc, subject, text].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } || !attachments.isEmpty }
}
public enum MailRules {
    public static let attachmentLimit = 18 * 1024 * 1024
    public static func moveLabels(source: String, destination: String) -> (add: [String], remove: [String]) {
        guard source != destination else { return ([], []) }
        let categories = ["CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES", "CATEGORY_FORUMS"]
        if categories.contains(destination) { return (["INBOX", destination], categories.filter { $0 != destination } + (source.hasPrefix("Label_") ? [source] : [])) }
        let removable = source == "INBOX" || source.hasPrefix("Label_") || categories.contains(source)
        return ([destination], removable ? (categories.contains(source) ? [source, "INBOX"] : [source]) : [])
    }
    public static func safeHeader(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(where: { [0, 10, 13].contains($0.value) }) else { throw MailFailure("An email header contains an invalid line break.") }
        return value
    }
    public static func rawMessage(_ draft: MailDraft, from: String, requireRecipient: Bool = true) throws -> String {
        if requireRecipient && draft.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MailFailure("Add a recipient before sending.") }
        guard draft.attachments.allSatisfy({ $0.data != nil }) else { throw MailFailure("An attachment has not finished downloading.") }
        guard draft.attachments.reduce(0, { $0 + ($1.data?.count ?? 0) }) <= attachmentLimit else { throw MailFailure("Attachments must total less than 18 MB.") }
        let boundary = "raizor-" + UUID().uuidString
        var headers = ["From: \(try safeHeader(from))", "To: \(try safeHeader(draft.to))", "Subject: =?UTF-8?B?\(Data(try safeHeader(draft.subject).utf8).base64EncodedString())?=", "MIME-Version: 1.0", "Content-Type: multipart/mixed; boundary=\"\(boundary)\""]
        for (name, value) in [("Cc", draft.cc), ("Bcc", draft.bcc), ("In-Reply-To", draft.inReplyTo), ("References", draft.references)] where !value.isEmpty { headers.append("\(name): \(try safeHeader(value))") }
        func wrapped(_ data: Data) -> String { let s = Array(data.base64EncodedString()); return stride(from: 0, to: s.count, by: 76).map { String(s[$0..<min($0 + 76, s.count)]) }.joined(separator: "\r\n") }
        var parts = ["Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" + wrapped(Data(draft.text.utf8))]
        for file in draft.attachments {
            let name = try safeHeader(file.name).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "attachment"
            parts.append("Content-Type: \(try safeHeader(file.mime))\r\nContent-Disposition: attachment; filename*=UTF-8''\(name)\r\nContent-Transfer-Encoding: base64\r\n\r\n\(wrapped(file.data!))")
        }
        let message = headers.joined(separator: "\r\n") + "\r\n\r\n--\(boundary)\r\n" + parts.joined(separator: "\r\n--\(boundary)\r\n") + "\r\n--\(boundary)--\r\n"
        return Data(message.utf8).base64URL
    }
    public static func calendarRange(start: String, end: String) throws -> (Date, Date) {
        let parser = ISO8601DateFormatter()
        func parse(_ value: String) -> Date? { parser.formatOptions = [.withInternetDateTime]; if let date = parser.date(from: value) { return date }; parser.formatOptions.insert(.withFractionalSeconds); return parser.date(from: value) }
        guard let s = parse(start), let e = parse(end), e > s, e.timeIntervalSince(s) <= 3660 * 86400 else { throw MailFailure("Choose valid calendar dates within ten years.") }
        return (s, e)
    }
}
