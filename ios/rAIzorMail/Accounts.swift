import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct GoogleAccount: Codable, Identifiable {
    var id: String
    var email: String
    var name: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var signature = ""
}
struct PhoneSecrets: Codable {
    var accounts: [GoogleAccount] = []
    var geminiKey = ""
    var geminiModel = "gemini-3.8-flash"
}
@MainActor final class Accounts: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var secrets = PhoneSecrets()
    @Published var problem: String?
    @Published var signingIn = false
    private var session: ASWebAuthenticationSession?
    private var refreshing: [String: Task<String, Error>] = [:]
    private let keychainService = "ai.raizorcrest.mail.ios"
    var clientID: String { Bundle.main.object(forInfoDictionaryKey: "GoogleIOSClientID") as? String ?? "" }
    var configured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") && !clientID.contains("YOUR_") }
    var redirectScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    override init() {
        super.init()
        do {
            var item: CFTypeRef?
            let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: "configuration", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &item)
            if status == errSecItemNotFound { return }
            guard status == errSecSuccess, let data = item as? Data else { throw MailFailure("Unlock this iPhone to access your saved accounts.") }
            secrets = try JSONDecoder().decode(PhoneSecrets.self, from: data)
        } catch { problem = error.localizedDescription }
    }
    func save(_ next: PhoneSecrets) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "configuration"]
        let data = try JSONEncoder().encode(next)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MailFailure("Could not save to the iPhone Keychain. Please try again after unlocking it.") }
        secrets = next
    }
    func remove(_ id: String) throws { var next = secrets; next.accounts.removeAll { $0.id == id }; try save(next) }
    func account(_ id: String) throws -> GoogleAccount { guard let value = secrets.accounts.first(where: { $0.id == id }) else { throw MailFailure("Reconnect this account in Settings.") }; return value }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
    private func random(_ count: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw MailFailure("Secure sign-in could not start.") }
        return Data(bytes).base64URL
    }
    func connect() async {
        guard !signingIn else { return }
        guard configured else { problem = "An iOS Google OAuth client must be configured in Xcode before sign-in. See the iPhone setup guide."; return }
        signingIn = true; problem = nil
        defer { signingIn = false; session = nil }
        do {
            let state = try random(32), verifier = try random(48)
            let redirect = redirectScheme + ":/oauthredirect"
            let scopes = ["openid", "email", "profile", "https://www.googleapis.com/auth/gmail.modify", "https://www.googleapis.com/auth/calendar.events", "https://www.googleapis.com/auth/calendar.calendarlist.readonly"]
            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            url.queryItems = ["client_id": clientID, "redirect_uri": redirect, "response_type": "code", "scope": scopes.joined(separator: " "), "access_type": "offline", "prompt": "consent select_account", "state": state, "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL, "code_challenge_method": "S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let flow = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: redirectScheme) { callback, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: MailFailure("Google sign-in did not return a result.")) }
                }
                flow.presentationContextProvider = self
                self.session = flow
                if !flow.start() { continuation.resume(throwing: MailFailure("Google sign-in could not open.")) }
            }
            let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ key: String) -> String? { result.first { $0.name == key }?.value }
            guard callback.scheme == redirectScheme, callback.path == "/oauthredirect", value("state") == state, let code = value("code") else { throw MailFailure("Google sign-in was cancelled or could not be verified.") }
            let token = try await exchange(["code": code, "client_id": clientID, "code_verifier": verifier, "redirect_uri": redirect, "grant_type": "authorization_code"])
            guard let access = token["access_token"] as? String else { throw MailFailure("Google did not provide access. Try connecting again.") }
            var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!); request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
            let profile = try await Self.json(request)
            guard let id = profile["sub"] as? String, let email = profile["email"] as? String else { throw MailFailure("Could not read Google account details.") }
            let previous = secrets.accounts.first { $0.id == id }
            let refresh = token["refresh_token"] as? String ?? previous?.refreshToken ?? ""
            guard !refresh.isEmpty else { throw MailFailure("Google did not grant offline access. Reconnect and approve access again.") }
            var account = GoogleAccount(id: id, email: email, name: profile["name"] as? String ?? email, accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(token["expires_in"] as? Double ?? 3600))
            account.signature = previous?.signature ?? ""
            var next = secrets; next.accounts.removeAll { $0.id == id }; next.accounts.append(account); try save(next)
        } catch { problem = error.localizedDescription }
    }
    private func exchange(_ values: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = values.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        return try await Self.json(request)
    }
    func accessToken(_ id: String, force: Bool = false) async throws -> String {
        let a = try account(id)
        if !force && a.expiresAt > Date().addingTimeInterval(60) { return a.accessToken }
        if let task = refreshing[id] { return try await task.value }
        let task = Task { @MainActor in
            let response = try await self.exchange(["client_id": self.clientID, "refresh_token": a.refreshToken, "grant_type": "refresh_token"])
            guard let access = response["access_token"] as? String else { throw MailFailure("Reconnect \(a.email) in Settings.") }
            var next = self.secrets
            guard let index = next.accounts.firstIndex(where: { $0.id == id }) else { throw MailFailure("Account disconnected.") }
            next.accounts[index].accessToken = access; next.accounts[index].expiresAt = Date().addingTimeInterval(response["expires_in"] as? Double ?? 3600)
            if let refresh = response["refresh_token"] as? String { next.accounts[index].refreshToken = refresh }
            try self.save(next); return access
        }
        refreshing[id] = task; defer { refreshing[id] = nil }
        return try await task.value
    }
    static func json(_ request: URLRequest) async throws -> [String: Any] {
        var request = request; request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MailFailure("No response from Google.") }
        guard (200..<300).contains(http.statusCode) else { throw MailFailure("Google sign-in failed (\(http.statusCode)). Reconnect your account in Settings.") }
        if data.isEmpty { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
