import SwiftUI
import WebKit

struct MessageScreen: View {
    @EnvironmentObject var model: MailModel
    @Environment(\.dismiss) var dismiss
    let mail: MailItem
    @State private var remoteImages = true
    @State private var attachmentURL: URL?
    @State private var downloading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(mail.subject.isEmpty ? "(No subject)" : mail.subject).font(.title2.bold())
                Text(mail.from).font(.subheadline).textSelection(.enabled)
                Text("To: \(mail.to)\n\(mail.date.formatted())").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                if !mail.html.isEmpty {
                    Toggle("Remote images", isOn: $remoteImages).font(.caption)
                    EmailHTML(html: mail.html, images: remoteImages).frame(minHeight: 550)
                } else { Text(mail.text.isEmpty ? mail.snippet : mail.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(mail.attachments) { file in
                    Button {
                        downloading = true
                        Task {
                            defer { downloading = false }
                            await model.report {
                                let data = try await model.api.bytes(mail, file: file)
                                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                let url = folder.appendingPathComponent(URL(fileURLWithPath: file.name).lastPathComponent)
                                try data.write(to: url, options: [.atomic, .completeFileProtection]); attachmentURL = url
                            }
                        }
                    } label: { Label(file.name, systemImage: "paperclip") }.disabled(downloading)
                }
                if let attachmentURL { ShareLink("Save or share attachment", item: attachmentURL) }
            }.padding()
        }.background(Crest.background).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { model.compose(reply: mail) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                Spacer()
                Button { Task { await model.forward(mail) } } label: { Image(systemName: "arrowshape.turn.up.right") }.accessibilityLabel("Forward").disabled(model.working)
                Spacer()
                Button { Task { await model.newEvent(mail: mail) } } label: { Image(systemName: "calendar.badge.plus") }.accessibilityLabel("Create calendar event")
                Spacer()
                Button(role: .destructive) { Task { await model.report { try await model.api.trash(mail); dismiss(); await model.loadMail() } } } label: { Image(systemName: "trash") }.accessibilityLabel("Move message to Trash")
            }
        }
        .onDisappear { if let attachmentURL { try? FileManager.default.removeItem(at: attachmentURL.deletingLastPathComponent()) } }
    }
}
struct EmailHTML: UIViewRepresentable {
    let html: String
    let images: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration); view.navigationDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .clear; return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let signature = "\(images)" + html
        guard context.coordinator.loaded != signature else { return }; context.coordinator.loaded = signature
        // Scripts, frames, forms, network connections and non-image resources are blocked.
        let policy = "default-src 'none'; script-src 'none'; img-src data: \(images ? "https:" : ""); style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-src 'none'"
        view.loadHTMLString("<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><meta name=\"referrer\" content=\"no-referrer\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><style>body{font:16px -apple-system;color:#222;background:#fff;overflow-wrap:anywhere;margin:12px}img{max-width:100%;height:auto}table{max-width:100%}</style></head><body>\(html)</body></html>", baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded = ""
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url); decisionHandler(.cancel) }
            else { decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel) }
        }
    }
}
