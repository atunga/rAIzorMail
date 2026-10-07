import Foundation
import SwiftUI
struct GoogleAccount: Identifiable { var id: String; var email: String; var signature = "" }
struct PhoneSecrets { var accounts: [GoogleAccount] = []; var geminiKey = ""; var geminiModel = "gemini-3.8-flash" }
@MainActor final class Accounts: ObservableObject {
 var secrets = PhoneSecrets()
 func account(_ id: String) throws -> GoogleAccount { GoogleAccount(id: id, email: "test@example.com") }
 func accessToken(_ id: String, force: Bool = false) async throws -> String { "test" }
}
