import SwiftUI

@main struct rAIzorMailApp: App {
    @StateObject private var accounts: Accounts
    @StateObject private var model: MailModel
    @AppStorage("appearance") private var appearance = "dark"
    @Environment(\.scenePhase) private var phase
    init() { let accounts = Accounts(); _accounts = StateObject(wrappedValue: accounts); _model = StateObject(wrappedValue: MailModel(accounts: accounts)) }
    var body: some Scene {
        WindowGroup {
            TabView {
                MailScreen().tabItem { Label("Mail", systemImage: "envelope") }
                CalendarScreen().tabItem { Label("Calendar", systemImage: "calendar") }
                SettingsScreen().tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environmentObject(accounts).environmentObject(model)
            .tint(Crest.orange).preferredColorScheme(appearance == "light" ? .light : .dark)
            .sheet(item: $model.draft) { ComposeScreen(initial: $0) }
            .sheet(item: $model.eventEditor) { EventScreen(initial: $0) }
            .alert("rAIzorMail", isPresented: Binding(get: { model.error != nil || accounts.problem != nil }, set: { if !$0 { model.error = nil; accounts.problem = nil } })) {
                Button("OK") { model.error = nil; accounts.problem = nil }
            } message: { Text(model.error ?? accounts.problem ?? "") }
            .task(id: model.context) { await model.reloadFolders(); await model.loadMail() }
            .task(id: phase) {
                guard phase == .active else { return }
                if !model.loading { await model.loadMail() }
                await model.loadCalendar()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                    if !model.loading && !model.working { await model.loadMail() }
                    if !model.calendarLoading && !model.working { await model.loadCalendar() }
                }
            }
        }
    }
}
enum Crest {
    static let orange = Color(red: 0.83, green: 0.54, blue: 0.28)
    static let sage = Color(red: 0.63, green: 0.70, blue: 0.58)
    static let background = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.15, blue: 0.13, alpha: 1) : UIColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1) })
}
struct AccountMenu: View {
    @EnvironmentObject var model: MailModel
    @EnvironmentObject var accounts: Accounts
    var body: some View {
        Menu {
            Picker("Account", selection: $model.selectedAccount) {
                Text("All accounts").tag("")
                ForEach(accounts.secrets.accounts) { Text($0.email).tag($0.id) }
            }
        } label: { Image(systemName: "person.crop.circle").accessibilityLabel("Choose account") }
        .onChange(of: model.selectedAccount) { _, _ in model.messages = []; model.events = []; model.pages = [:]; model.selected = [] }
    }
}
struct MailScreen: View {
    @EnvironmentObject var model: MailModel
    @EnvironmentObject var accounts: Accounts
    @State private var selecting = false
    private let systemFolders = [("INBOX", "Inbox"), ("ALL", "All mail"), ("SENT", "Sent"), ("DRAFT", "Drafts"), ("STARRED", "Starred"), ("TRASH", "Trash"), ("SPAM", "Spam")]
    var title: String { model.folder.hasPrefix("custom:") ? String(model.folder.dropFirst(7)) : systemFolders.first { $0.0 == model.folder }?.1 ?? "Mail" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("Find invoices from Acme last month…", text: $model.searchText).submitLabel(.search).onSubmit { Task { await model.search() } }
                    Toggle("AI", isOn: $model.aiSearch).toggleStyle(.button).accessibilityHint("Use Gemini to interpret the search")
                    Button { Task { await model.search() } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search mail")
                }.padding(12).background(Crest.background)
                if model.folder == "INBOX" && model.query.isEmpty {
                    Picker("Inbox category", selection: $model.category) { Text("Primary").tag("primary"); Text("Promotions").tag("promotions"); Text("Social").tag("social") }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                        .onChange(of: model.category) { _, _ in model.messages = []; model.pages = [:]; model.selected = [] }
                }
                if !model.query.isEmpty {
                    HStack { Text(model.query).font(.caption).lineLimit(2); Spacer(); Button("Clear") { model.messages = []; model.query = ""; model.searchText = "" } }.padding(.horizontal).padding(.vertical, 6)
                }
                if accounts.secrets.accounts.isEmpty {
                    ContentUnavailableView { Label("Your inbox, a little calmer.", systemImage: "tray") } description: { Text("Connect your Google accounts in Settings. Mail and calendar changes sync with Gmail and your Mac.") } actions: { Button("Connect Google") { Task { await accounts.connect() } }.disabled(accounts.signingIn) }
                } else {
                    List {
                        ForEach(model.messages) { mail in
                            Button {
                                if selecting || !model.selected.isEmpty { if model.selected.contains(mail.id) { model.selected.remove(mail.id) } else { model.selected.insert(mail.id) } }
                                else { Task { await model.open(mail) } }
                            } label: { MailRow(mail: mail, email: (try? accounts.account(mail.accountID).email) ?? "") }
                            .buttonStyle(.plain)
                            .listRowBackground(model.selected.contains(mail.id) ? Crest.sage.opacity(0.25) : Crest.background)
                            .onLongPressGesture { selecting = true; model.selected.insert(mail.id) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Trash", role: .destructive) { model.selected = [mail.id]; Task { await model.mutateSelected(trash: true) } }
                                Button("Archive") { Task { await model.report { try await model.api.modify(mail, remove: ["INBOX"]); await model.loadMail() } } }.tint(Crest.sage)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button(mail.unread ? "Read" : "Unread") { Task { await model.report { try await model.api.modify(mail, add: mail.unread ? [] : ["UNREAD"], remove: mail.unread ? ["UNREAD"] : []); await model.loadMail() } } }.tint(Crest.orange)
                            }
                        }
                        if !model.pages.isEmpty { Button("Load more") { Task { await model.loadMail(more: true) } }.disabled(model.loading) }
                        if model.loading { HStack { Spacer(); ProgressView(); Spacer() } }
                        if !model.loading && model.messages.isEmpty { ContentUnavailableView("A little breathing room", systemImage: "tray", description: Text("No messages in this view.")) }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                    .refreshable { await model.reloadFolders(); await model.loadMail() }
                }
                if !model.selected.isEmpty {
                    HStack {
                        Text("\(model.selected.count) selected").font(.caption)
                        Spacer()
                        Menu {
                            Button("Inbox") { Task { await model.mutateSelected(destination: "INBOX") } }
                            ForEach(model.customFolderNames, id: \.self) { name in Button(name) { Task { await model.mutateSelected(destination: name) } } }
                        } label: { Label("Move", systemImage: "folder") }
                        Button(role: .destructive) { Task { await model.mutateSelected(trash: true) } } label: { Image(systemName: "trash") }.accessibilityLabel("Delete selected messages")
                    }.padding().disabled(model.working)
                } else if let sync = model.lastSync { Text("Updated \(sync.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary).padding(5) }
            }
            .background(Crest.background).navigationTitle(model.selectedAccount.isEmpty && model.folder == "INBOX" ? "Unified inbox" : title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(systemFolders, id: \.0) { item in Button(item.1) { model.changeFolder(item.0) } }
                        Divider(); ForEach(model.customFolderNames, id: \.self) { name in Button(name) { model.changeFolder("custom:" + name) } }
                    } label: { Image(systemName: "tray.2").accessibilityLabel("Folders") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    AccountMenu()
                    Button(selecting ? "Done" : "Select") { selecting.toggle(); if !selecting { model.selected = [] } }
                    Button { model.compose() } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("Compose").disabled(accounts.secrets.accounts.isEmpty)
                }
            }
            .navigationDestination(isPresented: Binding(get: { model.opened != nil }, set: { if !$0 { model.opened = nil } })) { if let mail = model.opened { MessageScreen(mail: mail) } }
        }
    }
}
struct MailRow: View {
    let mail: MailItem
    let email: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if mail.unread { Circle().fill(Crest.orange).frame(width: 7, height: 7).accessibilityLabel("Unread") }
                Text(mail.from).font(.subheadline).fontWeight(mail.unread ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 4); Text(mail.date, style: .date).font(.caption2).foregroundStyle(.secondary)
            }
            Text(mail.subject.isEmpty ? "(No subject)" : mail.subject).font(.subheadline).fontWeight(mail.unread ? .semibold : .regular).lineLimit(1)
            Text(mail.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack { Text(email).font(.caption2).foregroundStyle(Crest.sage); if !mail.attachments.isEmpty { Image(systemName: "paperclip").font(.caption2) } }
        }.padding(.vertical, 7).contentShape(Rectangle())
    }
}
