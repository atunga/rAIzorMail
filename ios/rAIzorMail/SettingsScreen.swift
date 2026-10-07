import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject var accounts: Accounts
    @EnvironmentObject var model: MailModel
    @AppStorage("appearance") private var appearance = "dark"
    @State private var key = ""
    @State private var geminiModel = "gemini-3.8-flash"
    @State private var busy = false
    @State private var connection = ""
    @State private var error: String?
    @State private var removeAccount: GoogleAccount?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("rAIzorMail").font(.largeTitle.weight(.bold)).foregroundStyle(Crest.sage)
                    Text("A calmer inbox, wherever you are.").foregroundStyle(.secondary)
                }.listRowBackground(Crest.background)
                Section("Google accounts") {
                    ForEach(accounts.secrets.accounts) { account in
                        NavigationLink {
                            SignatureScreen(accountID: account.id)
                        } label: { VStack(alignment: .leading) { Text(account.name); Text(account.email).font(.caption).foregroundStyle(.secondary) } }
                        .swipeActions { Button("Disconnect", role: .destructive) { removeAccount = account } }
                    }
                    Button(accounts.signingIn ? "Connecting…" : "Add Google account") { Task { await accounts.connect() } }.disabled(accounts.signingIn)
                    if !accounts.configured { Text("iOS sign-in needs its own Google OAuth client. Follow ios/README.md before running on your iPhone.").font(.caption).foregroundStyle(.secondary) }
                    Text("Each device signs in separately. Gmail and Google Calendar keep your messages, saved drafts, folders, and events in sync.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") { Picker("Theme", selection: $appearance) { Text("Dark").tag("dark"); Text("Light").tag("light") } }
                Section("Gemini AI") {
                    SecureField(accounts.secrets.geminiKey.isEmpty ? "Gemini API key" : "Key saved — enter to replace", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model", text: $geminiModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(busy ? "Testing…" : "Save & test Gemini") {
                        Task {
                            busy = true; error = nil; connection = ""; defer { busy = false }
                            do {
                                var next = accounts.secrets; if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next.geminiKey = key.trimmingCharacters(in: .whitespacesAndNewlines) }; next.geminiModel = geminiModel
                                try accounts.save(next); key = ""
                                let result = try await model.ai.generate("Return JSON with status set to ok.", input: "Connection test", fields: ["status"])
                                guard result["status"] == "ok" else { throw MailFailure("Gemini returned an unexpected result.") }
                                connection = "Connected to Gemini"
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy || (key.isEmpty && accounts.secrets.geminiKey.isEmpty))
                    if !connection.isEmpty { Label(connection, systemImage: "checkmark.circle").foregroundStyle(Crest.sage) }
                    Text("Stored in this iPhone’s Keychain. The API key and app preferences do not sync from your Mac. AI search sends only your search request; AI writing sends the draft text you choose to work on.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Sync") {
                    Text("Refreshes when opened, when you pull to refresh, and every minute while active. Changes need an internet connection. No background push notifications in this personal build.").font(.caption)
                    Text("Save unfinished messages to Gmail Drafts before closing the app to continue on another device.").font(.caption)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollContentBackground(.hidden).background(Crest.background).navigationTitle("Make it yours")
            .onAppear { geminiModel = accounts.secrets.geminiModel }
            .confirmationDialog("Disconnect this account from this iPhone?", isPresented: Binding(get: { removeAccount != nil }, set: { if !$0 { removeAccount = nil } }), titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    if let account = removeAccount { do { try accounts.remove(account.id); model.messages.removeAll { $0.accountID == account.id }; model.events.removeAll { $0.calendar.accountID == account.id }; if model.selectedAccount == account.id { model.selectedAccount = "" } } catch { self.error = error.localizedDescription } }; removeAccount = nil
                }
            } message: { Text("Your Google data and Mac connection will remain available.") }
        }
    }
}
struct SignatureScreen: View {
    @EnvironmentObject var accounts: Accounts
    let accountID: String
    @State private var text = ""
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Email signature") { TextEditor(text: $text).frame(minHeight: 200) }
            Text("Added to new messages and replies on this iPhone. This setting is stored per device.").font(.caption).foregroundStyle(.secondary)
            Button(saved ? "Saved" : "Save signature") {
                do { var next = accounts.secrets; guard let index = next.accounts.firstIndex(where: { $0.id == accountID }) else { return }; next.accounts[index].signature = text; try accounts.save(next); saved = true } catch { self.error = error.localizedDescription }
            }.disabled(text.count > 10000)
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Signature").onAppear { text = (try? accounts.account(accountID).signature) ?? "" }.onChange(of: text) { _, _ in saved = false }
    }
}
