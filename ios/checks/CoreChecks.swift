import Foundation
@main struct CoreChecks {
    static func main() throws {
        func require(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); print("PASS: \(name)") }
        func rejects(_ name: String, _ action: () throws -> Void) { do { try action(); preconditionFailure(name) } catch { print("PASS: \(name)") } }
        require(MailRules.moveLabels(source: "CATEGORY_PROMOTIONS", destination: "Label_2").remove == ["CATEGORY_PROMOTIONS", "INBOX"], "Moving a category message removes it from Inbox")
        require(MailRules.moveLabels(source: "Label_1", destination: "Label_2").remove == ["Label_1"], "Moving removes the source folder")
        require(MailRules.moveLabels(source: "ALL", destination: "Label_2").remove.isEmpty, "All mail does not remove unrelated labels")
        require(MailRules.moveLabels(source: "INBOX", destination: "INBOX").add.isEmpty, "Same-folder move is a no-op")
        var draft = MailDraft(); draft.to = "recipient@example.com"; draft.subject = "Hello\r\nBcc: attacker@example.com"
        rejects("Header injection rejected") { _ = try MailRules.rawMessage(draft, from: "sender@example.com") }
        draft.subject = "Résumé"; draft.text = "Hello café"; draft.attachments = [MailAttachment(name: "file", mime: "text/plain")]
        rejects("Unloaded attachment rejected") { _ = try MailRules.rawMessage(draft, from: "sender@example.com") }
        draft.attachments = [MailAttachment(name: "notes.txt", mime: "text/plain", data: Data([0, 255, 1]))]
        let encoded = try MailRules.rawMessage(draft, from: "sender@example.com")
        let raw = String(data: Data(base64URL: encoded)!, encoding: .utf8)!
        require(raw.contains(Data(draft.text.utf8).base64EncodedString()) && raw.contains("AP8B"), "Unicode email and binary attachment preserved")
        draft.attachments = [MailAttachment(name: "big", mime: "text/plain", data: Data(count: MailRules.attachmentLimit + 1))]
        rejects("Attachment limit enforced") { _ = try MailRules.rawMessage(draft, from: "sender@example.com") }
        let json: [String: Any] = ["id": "same", "labelIds": ["UNREAD"], "payload": ["headers": [["name": "sUbJeCt", "value": "Test"]], "parts": [["mimeType": "text/plain", "body": ["data": Data("Body".utf8).base64URL]]]]]
        let a = MailItem(json: json, accountID: "a"), b = MailItem(json: json, accountID: "b")
        require(a.id != b.id && a.text == "Body" && a.subject == "Test" && a.unread, "Account-scoped identity, headers, body, and read state")
        rejects("Backwards calendar range rejected") { _ = try MailRules.calendarRange(start: "2026-10-08T00:00:00Z", end: "2026-10-07T00:00:00Z") }
        rejects("Unbounded calendar range rejected") { _ = try MailRules.calendarRange(start: "2000-01-01T00:00:00Z", end: "2026-10-07T00:00:00Z") }
        let dates = try MailRules.calendarRange(start: "2026-10-07T00:00:00-04:00", end: "2026-10-08T00:00:00-04:00")
        require(dates.1.timeIntervalSince(dates.0) == 86400, "Calendar timezone respected")
    }
}
