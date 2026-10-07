# rAIzorMail

A Mac desktop app for Gmail and Google Calendar, with the rAIzor Crest palette and typography.

## Open the app

Installers are generated locally and are not committed. On a fresh clone, run `npm ci` and `npm run installer` to create the Mac installer below.

Open `release/rAIzorMail-0.1.0-arm64.dmg`, drag **rAIzorMail** onto **Applications**, and launch it from Applications. This installer is for Apple Silicon Macs. Quit any running copy before installing or updating, then eject the disk image after copying. Existing connected accounts, signatures, and Gemini settings remain in this Mac's application data folder.

The unpacked build is also at `release/mac-arm64/rAIzorMail.app`. On a fresh setup, it starts with a clearly labeled sample mailbox until you connect Google. This is an ad-hoc-signed personal build, not an Apple-notarized public release.

### Connect Gmail and Calendar

1. In [Google Cloud Console](https://console.cloud.google.com/), create or choose a project.
2. Enable **Gmail API** and **Google Calendar API** in the API Library.
3. Configure **Google Auth Platform** branding and audience. For an external app in Testing, add each of your Gmail accounts as a test user. A Workspace account may also require administrator approval.
4. Create an OAuth client with application type **Desktop app**. Download its JSON file.
5. In rAIzorMail, open **Settings → First-time Google setup → Import Google OAuth JSON**.
6. Click **Connect Google account**, finish Google's consent screen in your browser, and repeat for each account.

Do not paste passwords or credentials into chat or commit downloaded OAuth files. The JSON is imported by the app, and tokens are encrypted using Electron safeStorage backed by macOS Keychain. Account disconnect removes local credentials; Google access can also be revoked from your Google Account's third-party connections page.

Gmail and Calendar OAuth access is required. Google apps using restricted Gmail scopes in Testing commonly have refresh tokens that expire after seven days. Reconnect as needed during personal testing. Public distribution will require Google's applicable verification, an Apple Developer signing identity, notarization, and a production release process.

### Gemini search and writing

Open **Settings → Gemini AI**, add a [Gemini API key](https://aistudio.google.com/api-keys), and click **Save & test Gemini**. Keys are encrypted on this Mac. New setups default to `gemini-3.8-flash`, a stable model listed in [Google's model catalog](https://ai.google.dev/gemini-api/docs/models); the model remains editable. API billing is separate from a consumer Gemini/Gmail subscription.

Choose **Mail** or **Calendar** beside the search box. With **AI** enabled, try “find invoices from Acme last month” or “meetings with Acme next week.” Gemini receives only the request and date/time-zone context, then returns validated search filters. Gmail and Google Calendar perform the actual searches across the chosen account or all connected accounts. Calendar results include recurring instances, open event details, and offer Load more when another page is available. The resolved date range is displayed; requests without dates search the previous and next year. Explicit ranges can span up to ten years. With AI off, Mail accepts Gmail syntax and Calendar accepts keywords.

In a message, click **AI writing** to draft from instructions, shorten text, adjust tone, or fix spelling and grammar. Review the suggestion, choose **Use suggestion**, and optionally **Undo AI changes**. Gemini receives the instruction, subject, and editable body; quoted reply history is sent only when selected. Signatures and quoted history are preserved outside the generated text. Attachments are never sent to Gemini. AI writing cannot send messages, change recipients, or alter calendar events.

The browser/sample mailbox uses labeled deterministic demonstrations instead of Gemini calls. It does not validate a real API key.

## Everyday controls

- **Click** selects an email. Inline body excerpts are always shown.
- **Command-click** toggles selection; **Shift-click** selects a range; **Command-A** selects all loaded messages.
- **Double-click** or **Enter** opens a separate movable Mac window centered over the mailbox on the same display and marks that message read. **Esc** closes that message window.
- **View → Reading pane** toggles the resizable full preview. Previewing does not mark mail read. Dismiss the View menu with Esc, its close button, another click on View, or a click outside it. Dark appearance is the default; light mode is available in View and the sun button.
- **Delete** or the trash button moves selected mail to Trash. Undo is available in the notification and with **Command-Z**.
- Drag any selected message to a folder to move the whole selection. Messages stay in their original Google account. A missing destination label is created in that account. Moves remove the current user folder or Inbox membership and preserve unrelated labels. All mail, Sent, and Starred are system views rather than exclusive folders.
- Drag to another inbox category to recategorize. Primary, Promotions, and Social map to Gmail categories.
- Drag an email or selection to the Calendar icon or My day panel to open a prefilled personal event. Choose time and calendar, then save. No email sender is automatically invited.
- Calendar week view supports creating, editing, and deleting personal events. Existing meetings with guests are displayed read-only; manage invitations in Google Calendar.
- Compose supports To/Cc/Bcc, plain-text messages, replies, reply-all, forwarding, attachments, and Gmail drafts. **Esc** or closing a changed composer asks whether to Save draft, Discard, or Keep editing. Closing the window or quitting the Mac app uses the same prompt. Discarding changes to an existing draft keeps its last saved version. **Save & close** saves directly. Forwarding includes attachments. Drag one or more files into the composer to attach them, or use the paperclip. Zip folders before attaching them. Attachments are limited to 18 MB total to leave room for MIME encoding.
- **Settings → Email signatures** creates a plain-text signature per account with a live preview and independent defaults for new messages and replies/forwards. Signatures are stored encrypted on this Mac. The composer also has an **Insert signature** button; reopening a draft preserves its text.
- **Command-K** focuses search. **Command-N** starts a message. App menu shortcuts are available under File, View, and Message.

## Synchronization and limits

Mail and calendar refresh every 60 seconds while the mailbox window is open, after relevant actions, and using Refresh. Message windows share a short-lived in-memory cache and receive change notifications without their own polling. Requests are deduplicated and paced per account; temporary Gmail quota errors retain the visible inbox and respect Google's retry delay. Gmail stays the source of truth. Each page loads up to 40 messages per account; Load more fetches additional pages. Counts describe the currently loaded view, not the entire mailbox. The initial release has no persistent offline mailbox cache, recurring-event editor, meeting-invitation composer, or notification service.

Email HTML is sanitized inside a sandboxed frame. Remote email images load by default without referrer information, with a Hide remote images control in each email; scripts remain blocked. Attachments download through a native Save dialog. Credentials and Gmail operations run in the Electron main process, with a narrow IPC interface and trusted-frame checks. The browser preview only uses fictional local data and cannot connect Google.

## Development

Requires macOS and Node.js 22.20 or newer.

```sh
npm install
npm run dev       # browser demo at http://127.0.0.1:5173
npm run desktop   # builds and launches Electron
npm test          # selection, Gmail operations, MIME, OAuth and calendar tests
npm run package   # builds, packages and ad-hoc signs the Mac app
npm run installer # builds the signed app and drag-to-Applications DMG
```

Local credentials, signing configuration, account screenshots, development toolkits, dependencies, and generated installers/builds are excluded from Git.

Source layout: `src/` contains the React interface and demo provider; `electron/` contains OAuth, encrypted storage, Gmail, Calendar, Gemini search/writing, and native windows. `DESIGN.md` records the interaction and brand decisions. Tests use fictional data and mocked Google responses; they never send email or alter a real account.

## Validation

TypeScript and production build pass. Automated tests cover multi-selection, folder/category changes, undo, partial account failures, pagination, MIME/Bcc/attachments, natural-language search privacy, calendar event boundaries, and OAuth state/PKCE. Manual UI checks cover previews staying unread, bulk actions, multi-message dragging, calendar drops, and native double-click / Esc behavior.

Google OAuth sign-in, live Gmail folder/message retrieval, and Google Calendar event retrieval were verified on October 7, 2026 with the first connected account. Live sending and write operations were not exercised during setup. Local AI work is deferred. Gemini search and writing require an API key, while normal mail and calendar access do not. Gemini requests are covered by mocked tests and demo UI checks. On October 7, 2026, a Gemini key was created in the rAIzorMail project and saved through Settings in encrypted storage. A live connection test using the saved configuration and the application service passed after correcting the response-format MIME enum. Mail/calendar query and writing workflows remain covered by mocked tests and demo UI checks.

The configured Google Cloud project is **rAIzorMail** (`neural-service-510918-a9`), with a **Desktop app** client named **rAIzorMail Mac**. Gmail and Calendar APIs are enabled. The OAuth audience is External / Testing. To connect another account, first add its email address under [Google Auth Platform → Audience](https://console.cloud.google.com/auth/audience?project=neural-service-510918-a9), then use **Settings → Connect Google account** in the Mac app. The existing imported client configuration supports all added accounts; a new client or credential import is not needed per account.

## iPhone version

The native SwiftUI first pass is in [`ios/`](ios/README.md), with an Xcode project at `ios/rAIzorMail.xcodeproj`. It uses Gmail and Google Calendar directly, so cloud changes become visible across devices after refresh. The iOS Google OAuth client has been created and configured. Core and mocked service checks pass, and the full iOS Simulator build succeeds with Xcode 27.0. Personal Team signing is configured and the app is installed on the connected iPhone; the user confirmed successful launch and Google sign-in on October 7, 2026. Cross-device acceptance testing remains pending. Five core XCTest tests also pass. See the iOS guide for installation through your personal Apple ID, seven-day provisioning limits, per-device settings, and current feature gaps.
