import SwiftUI
import UniformTypeIdentifiers

struct ComposeScreen: View {
    @EnvironmentObject var model: MailModel
    @EnvironmentObject var accounts: Accounts
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var phase
    let initial: MailDraft
    @State private var draft: MailDraft
    @State private var lastSaved: MailDraft
    @State private var busy = false
    @State private var askClose = false
    @State private var importer = false
    @State private var showAI = false
    @State private var error: String?
    @State private var status = ""
    @State private var instruction = ""
    @State private var suggestion: (subject: String, text: String)?
    @State private var suggestionSource: MailDraft?
    @State private var undoAI: MailDraft?
    init(initial: MailDraft) { self.initial = initial; _draft = State(initialValue: initial); _lastSaved = State(initialValue: initial) }
    var changed: Bool { draft != lastSaved || (draft.draftID == nil && draft.hasContent) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $draft.accountID) { ForEach(accounts.secrets.accounts) { Text($0.email).tag($0.id) } }.disabled(draft.draftID != nil || draft.threadID != nil)
                    TextField("To", text: $draft.to).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    TextField("Cc", text: $draft.cc).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    TextField("Bcc", text: $draft.bcc).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    TextField("Subject", text: $draft.subject)
                }
                Section { TextEditor(text: $draft.text).frame(minHeight: 220).accessibilityLabel("Message body") }
                Section {
                    ForEach(draft.attachments) { file in HStack { Label(file.name, systemImage: "paperclip"); Spacer(); Button { draft.attachments.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Remove \(file.name)") } }
                    Button("Add attachments", systemImage: "paperclip") { importer = true }
                    Text("Up to 18 MB total. Files are not sent to Gemini.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Insert signature", systemImage: "signature") {
                        if let value = try? accounts.account(draft.accountID).signature, !value.isEmpty { draft.text += "\n\n-- \n" + value }
                    }
                    Toggle("AI writing", isOn: $showAI)
                    if showAI {
                        TextField("How would you like to improve this email?", text: $instruction, axis: .vertical)
                        HStack { aiButton("Shorten", prompt: "Make this email shorter."); aiButton("Polish", prompt: "Make this email clear and professional.") }
                        Button("Generate suggestion", systemImage: "sparkles") { Task { await write(instruction) } }.disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Sends your instruction, subject, and editable body to Gemini. Signature and quoted history stay outside the suggestion.").font(.caption).foregroundStyle(.secondary)
                        if let suggestion {
                            Text(suggestion.subject).font(.headline); Text(suggestion.text).textSelection(.enabled)
                            Button("Use suggestion") {
                                undoAI = draft; draft.subject = suggestion.subject; draft.text = suggestion.text + writingParts(draft.text).suffix; self.suggestion = nil
                            }.disabled(suggestionSource != draft)
                            Button("Dismiss suggestion", role: .cancel) { self.suggestion = nil }
                            if suggestionSource != draft { Text("Your draft changed. Generate a fresh suggestion.").font(.caption) }
                        }
                        if let undoAI { Button("Undo AI changes") { draft = undoAI; self.undoAI = nil } }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            .disabled(busy).scrollContentBackground(.hidden).background(Crest.background)
            .navigationTitle(draft.draftID == nil ? "New message" : "Draft").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { if changed { askClose = true } else { dismiss() } }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Send", systemImage: "paperplane.fill") { Task { await send() } }.disabled(busy || draft.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                ToolbarItem(placement: .bottomBar) { Button("Save draft") { Task { await save(close: false) } }.disabled(busy) }
            }
            .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .confirmationDialog("Keep this message?", isPresented: $askClose, titleVisibility: .visible) {
                Button("Keep in Gmail Drafts") { Task { await save(close: true) } }
                Button(draft.draftID == nil ? "Discard" : "Discard unsaved changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Saved drafts are available on your Mac and in Gmail.") }
            .interactiveDismissDisabled(changed || busy)
            .fileImporter(isPresented: $importer, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get(); var files: [MailAttachment] = []
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                        guard info.isDirectory != true else { throw MailFailure("Zip folders before attaching them.") }
                        guard (info.fileSize ?? 0) + draft.attachments.reduce(0, { $0 + $1.size }) + files.reduce(0, { $0 + $1.size }) <= MailRules.attachmentLimit else { throw MailFailure("Attachments must total less than 18 MB.") }
                        let bytes = try Data(contentsOf: url)
                        files.append(MailAttachment(name: url.lastPathComponent, mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", data: bytes))
                    }
                    guard draft.attachments.reduce(0, { $0 + $1.size }) + files.reduce(0, { $0 + $1.size }) <= MailRules.attachmentLimit else { throw MailFailure("Attachments must total less than 18 MB.") }
                    draft.attachments += files
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func writingParts(_ value: String) -> (body: String, suffix: String) {
        let indices = [value.range(of: "\n\n-- \n")?.lowerBound, value.range(of: "\n\nOn ")?.lowerBound].compactMap { $0 }
        guard let cut = indices.min() else { return (value, "") }; return (String(value[..<cut]), String(value[cut...]))
    }
    func aiButton(_ label: String, prompt: String) -> some View { Button(label) { Task { await write(prompt) } }.buttonStyle(.bordered) }
    func write(_ prompt: String) async {
        busy = true; error = nil; defer { busy = false }
        do { suggestionSource = draft; let result = try await model.ai.write(instruction: prompt, subject: draft.subject, text: writingParts(draft.text).body); suggestion = (result.0, result.1) }
        catch { self.error = error.localizedDescription }
    }
    func save(close: Bool) async {
        busy = true; error = nil; defer { busy = false }
        do { draft.draftID = try await model.api.saveDraft(draft); lastSaved = draft; status = "Saved to Gmail Drafts"; if close { dismiss() }; await model.loadMail() }
        catch { self.error = error.localizedDescription }
    }
    func send() async {
        busy = true; error = nil; defer { busy = false }
        do { try await model.api.send(draft); dismiss(); await model.loadMail() }
        catch { self.error = error.localizedDescription + " If the connection dropped while sending, check Sent before retrying." }
    }
}
