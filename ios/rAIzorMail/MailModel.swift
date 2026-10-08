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
    @Published var mailSyncError: String?
    @Published var calendarSyncError: String?
    @Published var lastSync: Date?
    @Published var pages: [String: String] = [:]
    @Published var draft: MailDraft?
    @Published var opened: MailItem?
    @Published var eventEditor: CalendarItem?
    @Published var calendarStart = Calendar.current.startOfDay(for: Date())
    @Published var calendarEnd = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))!
    private var mailTask: Task<Void, Never>?
    private var mailTaskKey = ""
    private var mailTaskID = UUID()
    private var mailRevision = 0
    private var calendarRevision = 0
    private var calendarTask: Task<Void, Never>?
    private var calendarTaskKey = ""
    private var calendarTaskID = UUID()
    var accountIDs: [String] { accounts.secrets.accounts.filter { selectedAccount.isEmpty || $0.id == selectedAccount }.map(\.id) }
    var context: String { selectedAccount + "|" + folder + "|" + category + "|" + query + "|" + accounts.secrets.accounts.map(\.id).joined(separator: ",") }
    var customFolderNames: [String] { Array(Set(folders.filter { $0.labelID.hasPrefix("Label_") }.map(\.name))).sorted() }
    init(accounts: Accounts, session: URLSession = .shared) { self.accounts = accounts; api = GoogleAPI(accounts: accounts, session: session); ai = Gemini(accounts: accounts, session: session) }
    func report(_ operation: () async throws -> Void) async { do { try await operation() } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    func reloadFolders() async {
        let expected = context
        var found: [MailFolder] = []
        for id in accountIDs {
            do { found += try await api.labels(id) }
            catch is CancellationError { return }
            catch { mailSyncError = error.localizedDescription; found += folders.filter { $0.accountID == id } }
        }
        if expected == context { folders = found }
    }
    func reloadCalendars() async {
        let ids = accountIDs
        var found: [GoogleCalendar] = []
        for id in ids {
            do { found += try await api.calendars(id) }
            catch is CancellationError { return }
            catch { calendarSyncError = error.localizedDescription; found += calendars.filter { $0.accountID == id } }
        }
        if ids == accountIDs { calendars = found }
    }
    func loadMail(more: Bool = false) async {
        guard !working else { return }
        let key = context + "|" + String(more)
        if let task = mailTask, mailTaskKey == key { await task.value; return }
        mailTask?.cancel()
        let id = UUID(); mailTaskID = id; mailTaskKey = key
        let task = Task { await self.fetchMail(more: more) }; mailTask = task
        await task.value
        if mailTaskID == id { mailTask = nil }
    }
    private func fetchMail(more: Bool) async {
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
        mailSyncError = errors.isEmpty ? nil : Array(Set(errors)).sorted().joined(separator: "\n")
        if errors.isEmpty { lastSync = Date() }
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
        guard !working, trash || destination != nil else { return }
        working = true; defer { working = false }
        // Cancel any older inbox snapshot so it cannot restore messages just deleted.
        mailTask?.cancel(); mailRevision += 1; loading = false
        let pending = messages.filter { selected.contains($0.id) }
        let expected = context
        let sourceFolder = folder
        var failures: Set<String> = [], limitedAccounts: Set<String> = []
        var availableByAccount: [String: [MailFolder]] = [:]
        var succeeded: Set<String> = []
        for mail in pending {
            if limitedAccounts.contains(mail.accountID) { continue }
            do {
                var updated = mail
                var removeFromView = trash && sourceFolder != "TRASH"
                if trash { try await api.trash(mail); updated.labels.removeAll { $0 == "INBOX" }; if !updated.labels.contains("TRASH") { updated.labels.append("TRASH") } }
                else if let destination {
                    let available: [MailFolder]
                    if let existing = availableByAccount[mail.accountID] { available = existing }
                    else { available = try await api.labels(mail.accountID); availableByAccount[mail.accountID] = available }
                    guard let target = available.first(where: { $0.name == destination || $0.labelID == destination }) else { throw MailFailure("Create the folder \(destination) in this account first.") }
                    let source = sourceFolder.hasPrefix("custom:") ? available.first(where: { $0.name == String(sourceFolder.dropFirst(7)) })?.labelID ?? "ALL" : sourceFolder
                    let delta = MailRules.moveLabels(source: source, destination: target.labelID)
                    if !delta.add.isEmpty || !delta.remove.isEmpty { try await api.modify(mail, add: delta.add, remove: delta.remove) }
                    updated.labels = Array(Set(mail.labels).subtracting(delta.remove).union(delta.add))
                    removeFromView = source != target.labelID && (source == "INBOX" || source.hasPrefix("Label_"))
                }
                succeeded.insert(mail.id)
                if context == expected {
                    selected.remove(mail.id)
                    if removeFromView { messages.removeAll { $0.id == mail.id } }
                    else if let index = messages.firstIndex(where: { $0.id == mail.id }) { messages[index] = updated }
                }
            } catch is CancellationError { break }
            catch let limit as GoogleRateLimit { limitedAccounts.insert(mail.accountID); failures.insert(limit.localizedDescription) }
            catch { failures.insert(error.localizedDescription) }
        }
        if context != expected { working = false; await loadMail() }
        // Successful writes already confirm the result. The next normal sync fills the page.
        let remaining = pending.count - succeeded.count
        if remaining > 0 {
            error = "\(succeeded.count) of \(pending.count) messages updated. \(remaining) were not updated and remain selected in the original view.\n" + (failures.isEmpty ? "The operation was interrupted." : failures.sorted().joined(separator: "\n"))
        }
    }
    func loadCalendar() async {
        let key = accountIDs.joined(separator: "|") + "|" + String(calendarStart.timeIntervalSince1970) + "|" + String(calendarEnd.timeIntervalSince1970) + "|" + calendarQuery
        if let task = calendarTask, calendarTaskKey == key { await task.value; return }
        calendarTask?.cancel()
        let id = UUID(); calendarTaskID = id; calendarTaskKey = key
        let task = Task { await self.fetchCalendar() }; calendarTask = task
        await task.value
        if calendarTaskID == id { calendarTask = nil }
    }
    private func fetchCalendar() async {
        calendarRevision += 1; let revision = calendarRevision
        calendarLoading = true; defer { if revision == calendarRevision { calendarLoading = false } }
        let start = calendarStart, end = calendarEnd, query = calendarQuery
        let expectedAccounts = accountIDs
        var found: [CalendarItem] = [], failures: Set<String> = [], limitedAccounts: Set<String> = []
        for cal in calendars.filter({ selectedAccount.isEmpty || $0.accountID == selectedAccount }) {
            if limitedAccounts.contains(cal.accountID) { found += events.filter { $0.calendar.id == cal.id }; continue }
            do { found += try await api.events(cal, start: start, end: end, query: query) }
            catch is CancellationError { return }
            catch let limit as GoogleRateLimit { found += events.filter { $0.calendar.id == cal.id }; limitedAccounts.insert(cal.accountID); failures.insert(limit.localizedDescription) }
            catch { found += events.filter { $0.calendar.id == cal.id }; failures.insert("\(cal.name): \(error.localizedDescription)") }
        }
        guard revision == calendarRevision, expectedAccounts == accountIDs, !Task.isCancelled else { return }
        events = found.sorted { $0.start < $1.start }; calendarSyncError = failures.isEmpty ? nil : failures.sorted().joined(separator: "\n")
    }
    func searchCalendar() async {
        await report {
            if self.aiSearch && !self.calendarSearchText.isEmpty { let plan = try await self.ai.calendarQuery(self.calendarSearchText); self.calendarQuery = plan.0; self.calendarStart = plan.1; self.calendarEnd = plan.2 }
            else { self.calendarQuery = self.calendarSearchText }
            await self.loadCalendar()
        }
    }
    func newEvent(mail: MailItem? = nil) async {
        if calendars.isEmpty { await reloadCalendars() }
        guard let cal = calendars.first(where: { $0.writable && (mail == nil || $0.accountID == mail?.accountID) }) else { error = "Connect a writable Google Calendar first."; return }
        eventEditor = CalendarItem(calendar: cal, eventID: "", title: mail?.subject ?? "", notes: mail.map { "From: \($0.from)\n\n\($0.text.isEmpty ? $0.snippet : $0.text)" } ?? "", location: "", start: Date(), end: Date().addingTimeInterval(3600), allDay: false, shared: false, recurring: false, etag: "")
    }
}
