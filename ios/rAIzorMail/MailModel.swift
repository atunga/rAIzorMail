import SwiftUI

@MainActor final class MailModel: ObservableObject {
    let accounts: Accounts
    let api: GoogleAPI
    let ai: Gemini
    @Published var messages: [MailItem] = []
    @Published var folders: [MailFolder] = []
    @Published var calendars: [GoogleCalendar] = []
    @Published var events: [CalendarItem] = []
    @Published var selectedAccount = ""
    @Published var folder = "INBOX"
    @Published var category = "primary"
    @Published var selected: Set<String> = []
    @Published var query = ""
    @Published var calendarQuery = ""
    @Published var searchText = ""
    @Published var calendarSearchText = ""
    @Published var aiSearch = true
    @Published var loading = false
    @Published var calendarLoading = false
    @Published var working = false
    @Published var error: String?
    @Published var lastSync: Date?
    @Published var pages: [String: String] = [:]
    @Published var draft: MailDraft?
    @Published var opened: MailItem?
    @Published var eventEditor: CalendarItem?
    @Published var calendarStart = Calendar.current.startOfDay(for: Date())
    @Published var calendarEnd = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))!
    private var mailRevision = 0
    private var calendarRevision = 0
    var accountIDs: [String] { accounts.secrets.accounts.filter { selectedAccount.isEmpty || $0.id == selectedAccount }.map(\.id) }
    var context: String { selectedAccount + "|" + folder + "|" + category + "|" + query + "|" + accounts.secrets.accounts.map(\.id).joined(separator: ",") }
    var customFolderNames: [String] { Array(Set(folders.filter { $0.labelID.hasPrefix("Label_") }.map(\.name))).sorted() }
    init(accounts: Accounts) { self.accounts = accounts; api = GoogleAPI(accounts: accounts); ai = Gemini(accounts: accounts) }
    func report(_ operation: () async throws -> Void) async { do { try await operation() } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    func reloadFolders() async {
        var found: [MailFolder] = [], cals: [GoogleCalendar] = []
        for id in accountIDs {
            do { found += try await api.labels(id); cals += try await api.calendars(id) }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription; found += folders.filter { $0.accountID == id }; cals += calendars.filter { $0.accountID == id } }
        }
        folders = found; calendars = cals
    }
    func loadMail(more: Bool = false) async {
        mailRevision += 1; let revision = mailRevision, expected = context
        loading = true; defer { if revision == mailRevision { loading = false } }
        let old = messages; var rows: [MailItem] = more ? old : [], tokens = more ? pages : [:], errors: [String] = []
        let ids = accountIDs; let folder = self.folder, category = self.category, query = self.query
        for id in ids {
            if more && pages[id] == nil { continue }
            do {
                var label = folder
                if folder.hasPrefix("custom:") {
                    let name = String(folder.dropFirst(7))
                    let available = try await api.labels(id)
                    guard let found = available.first(where: { $0.name == name && $0.labelID.hasPrefix("Label_") }) else { continue }; label = found.labelID
                }
                let page = try await api.messages(id, folder: label, category: category, query: query, page: more ? pages[id] : nil)
                try Task.checkCancellation(); rows += page.0; tokens[id] = page.1
            } catch is CancellationError { return }
            catch {
                if !more { rows += old.filter { $0.accountID == id } }
                errors.append("\((try? accounts.account(id).email) ?? "Account"): \(error.localizedDescription)")
            }
        }
        guard revision == mailRevision, context == expected, !Task.isCancelled else { return }
        var seen: Set<String> = []
        messages = rows.filter { seen.insert($0.id).inserted }.sorted { $0.date > $1.date }; pages = tokens
        selected.formIntersection(Set(messages.map(\.id)))
        if errors.isEmpty { lastSync = Date() } else { error = errors.joined(separator: "\n") }
    }
    func changeFolder(_ name: String) { if folder != name { messages = []; pages = [:] }; folder = name; selected = []; query = ""; searchText = "" }
    func search() async {
        await report { let resolved = self.aiSearch && !self.searchText.isEmpty ? try await self.ai.mailQuery(self.searchText) : self.searchText; self.messages = []; self.query = resolved; self.selected = [] }
    }
    func open(_ mail: MailItem) async {
        if mail.labels.contains("DRAFT") { await report { self.draft = try await self.api.draft(mail) }; return }
        opened = mail
        if mail.unread {
            await report {
                try await self.api.modify(mail, remove: ["UNREAD"])
                if let i = self.messages.firstIndex(where: { $0.id == mail.id }) { self.messages[i].labels.removeAll { $0 == "UNREAD" } }
            }
        }
    }
    func compose(reply: MailItem? = nil, forward: Bool = false) {
        var value = MailDraft(); value.accountID = reply?.accountID ?? accountIDs.first ?? ""
        if let reply {
            value.subject = (forward ? "Fwd: " : "Re: ") + reply.subject
            if !forward { value.to = reply.replyTo.isEmpty ? reply.from : reply.replyTo; value.threadID = reply.threadID; value.inReplyTo = reply.internetID; value.references = (reply.references + " " + reply.internetID).trimmingCharacters(in: .whitespaces) }
            value.text = "\n\nOn \(reply.date.formatted()), \(reply.from) wrote:\n" + (reply.text.isEmpty ? reply.snippet : reply.text).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        }
        if let signature = try? accounts.account(value.accountID).signature, !signature.isEmpty { value.text = "\n\n-- \n" + signature + value.text }
        draft = value
    }
    func forward(_ mail: MailItem) async {
        working = true; defer { working = false }
        await report {
            var files: [MailAttachment] = []
            for var file in mail.attachments { file.data = try await self.api.bytes(mail, file: file); files.append(file) }
            self.compose(reply: mail, forward: true); self.draft?.attachments = files
        }
    }
    func mutateSelected(destination: String? = nil, trash: Bool = false) async {
        guard !working else { return }; working = true; defer { working = false }
        var failures: [String] = []
        for mail in messages.filter({ selected.contains($0.id) }) {
            do {
                if trash { try await api.trash(mail) }
                else if let destination {
                    let available = try await api.labels(mail.accountID)
                    guard let target = available.first(where: { $0.name == destination || $0.labelID == destination }) else { throw MailFailure("Create the folder \(destination) in this account first.") }
                    let source: String
                    if folder.hasPrefix("custom:") { source = available.first(where: { $0.name == String(folder.dropFirst(7)) })?.labelID ?? "ALL" }
                    else { source = folder }
                    let delta = MailRules.moveLabels(source: source, destination: target.labelID)
                    try await api.modify(mail, add: delta.add, remove: delta.remove)
                }
                selected.remove(mail.id)
            } catch { failures.append("\(mail.subject): \(error.localizedDescription)") }
        }
        await loadMail(); if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
    func loadCalendar() async {
        calendarRevision += 1; let revision = calendarRevision
        calendarLoading = true; defer { if revision == calendarRevision { calendarLoading = false } }
        let start = calendarStart, end = calendarEnd, query = calendarQuery
        var found: [CalendarItem] = [], failures: [String] = []
        for cal in calendars.filter({ selectedAccount.isEmpty || $0.accountID == selectedAccount }) {
            do { found += try await api.events(cal, start: start, end: end, query: query) }
            catch is CancellationError { return }
            catch { found += events.filter { $0.calendar.id == cal.id }; failures.append("\(cal.name): \(error.localizedDescription)") }
        }
        guard revision == calendarRevision, !Task.isCancelled else { return }
        events = found.sorted { $0.start < $1.start }; if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
    func searchCalendar() async {
        await report {
            if self.aiSearch && !self.calendarSearchText.isEmpty { let plan = try await self.ai.calendarQuery(self.calendarSearchText); self.calendarQuery = plan.0; self.calendarStart = plan.1; self.calendarEnd = plan.2 }
            else { self.calendarQuery = self.calendarSearchText }
            await self.loadCalendar()
        }
    }
    func newEvent(mail: MailItem? = nil) async {
        if calendars.isEmpty { await reloadFolders() }
        guard let cal = calendars.first(where: { $0.writable && (mail == nil || $0.accountID == mail?.accountID) }) else { error = "Connect a writable Google Calendar first."; return }
        eventEditor = CalendarItem(calendar: cal, eventID: "", title: mail?.subject ?? "", notes: mail.map { "From: \($0.from)\n\n\($0.text.isEmpty ? $0.snippet : $0.text)" } ?? "", location: "", start: Date(), end: Date().addingTimeInterval(3600), allDay: false, shared: false, recurring: false, etag: "")
    }
}
