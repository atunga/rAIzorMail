import XCTest
@testable import MailCore
final class MailCoreTests: XCTestCase {
    func testMoveRemovesCurrentInboxOrFolder() {
        XCTAssertEqual(MailRules.moveLabels(source: "CATEGORY_PROMOTIONS", destination: "Label_2").remove, ["CATEGORY_PROMOTIONS", "INBOX"])
        XCTAssertEqual(MailRules.moveLabels(source: "Label_1", destination: "Label_2").remove, ["Label_1"])
        XCTAssertEqual(MailRules.moveLabels(source: "ALL", destination: "Label_2").remove, [])
        XCTAssertEqual(MailRules.moveLabels(source: "INBOX", destination: "INBOX").add, [])
    }
    func testMIMERejectsHeaderInjectionAndMissingFiles() throws {
        var draft = MailDraft(); draft.to = "recipient@example.com"; draft.subject = "Hi\r\nBcc: attacker@example.com"
        XCTAssertThrowsError(try MailRules.rawMessage(draft, from: "sender@example.com"))
        draft.subject = "Hello"; draft.attachments = [MailAttachment(name: "file", mime: "text/plain")]
        XCTAssertThrowsError(try MailRules.rawMessage(draft, from: "sender@example.com"))
    }
    func testMessageRoundTripWithUnicodeAndAttachment() throws {
        var draft = MailDraft(); draft.to = "recipient@example.com"; draft.subject = "Résumé"; draft.text = "Hello café"; draft.bcc = "private@example.com"
        draft.attachments = [MailAttachment(name: "notes.txt", mime: "text/plain", data: Data([0, 255, 1]))]
        let raw = try MailRules.rawMessage(draft, from: "sender@example.com")
        let mime = String(data: try XCTUnwrap(Data(base64URL: raw)), encoding: .utf8)!
        XCTAssertTrue(mime.contains("Bcc: private@example.com")); XCTAssertTrue(mime.contains(Data(draft.text.utf8).base64EncodedString())); XCTAssertTrue(mime.contains("AP8B"))
    }
    func testMailIdentityIsAccountScopedAndNestedMIMEIsDecoded() {
        let json: [String: Any] = ["id": "same", "labelIds": ["UNREAD"], "internalDate": "1000", "payload": ["headers": [["name": "sUbJeCt", "value": "Test"]], "parts": [["mimeType": "multipart/alternative", "parts": [["mimeType": "text/plain", "body": ["data": Data("Body".utf8).base64URL]]]]]]]
        let a = MailItem(json: json, accountID: "a"), b = MailItem(json: json, accountID: "b")
        XCTAssertNotEqual(a.id, b.id); XCTAssertEqual(a.text, "Body"); XCTAssertEqual(a.subject, "Test"); XCTAssertTrue(a.unread)
    }
    func testCalendarRangeRejectsBackwardsAndUnboundedDates() throws {
        XCTAssertThrowsError(try MailRules.calendarRange(start: "2026-10-08T00:00:00Z", end: "2026-10-07T00:00:00Z"))
        XCTAssertThrowsError(try MailRules.calendarRange(start: "2000-01-01T00:00:00Z", end: "2026-10-07T00:00:00Z"))
        let range = try MailRules.calendarRange(start: "2026-10-07T00:00:00-04:00", end: "2026-10-08T00:00:00-04:00")
        XCTAssertEqual(range.1.timeIntervalSince(range.0), 86400)
    }
}
