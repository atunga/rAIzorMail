# rAIzorMail for iPhone and iPad

This is the first native SwiftUI implementation, targeting iOS 17 or later. It uses Gmail and Google Calendar directly; it does not connect to or depend on the Mac app running.

**Status (October 7, 2026):** full iOS Simulator compilation passes with Xcode 27.0. Personal Team signing is configured and the device build completed. The app is installed on the connected iPhone 17 Pro; Developer Mode is enabled. The user confirmed successful launch and Google sign-in on October 7, 2026. The simulator also installed and launched the app, but visual smoke testing is not complete. Cross-device acceptance testing remains pending. The 12 core checks, four mocked service checks, and five XCTest tests pass.

## Install on your own iPhone

1. Install **Xcode by Apple** from the Mac App Store. Open it once, complete Apple's first-run setup, and install the iOS platform components. Apple may ask you to accept its license.
2. Open `rAIzorMail.xcodeproj` in this directory.
3. In **Xcode → Settings → Accounts**, sign in with your personal Apple ID.
4. Select the **rAIzorMail** target → **Signing & Capabilities**. Choose your **Personal Team** and leave **Automatically manage signing** enabled.
5. Connect your iPhone to the Mac, unlock it, and trust the Mac if asked. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone if Xcode requests it.
6. Choose the iPhone as Xcode's run destination and click **Run**. Complete any device trust prompts yourself.
7. In the app's **Settings**, connect each Google account. Your Mac's OAuth tokens are not copied to the phone. If you want AI, enter your Gemini key in the phone's secure Settings field and tap **Save & test Gemini**.

A free Personal Team's provisioning profile lasts **seven days**. Rebuild/reinstall through Xcode after expiration. TestFlight and App Store distribution require a paid Apple Developer Program membership. See [Apple's account guidance](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Google sign-in configuration

A separate **iOS** OAuth client named **rAIzorMail iPhone** was created in the existing Google Cloud project `neural-service-510918-a9` on October 7, 2026. It is configured for bundle ID `ai.raizorcrest.mail.ios`. The local `Configuration/Local.xcconfig` contains its public client identifier, reversed URL scheme, and signing team; it is excluded from Git. For a fresh clone, copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig` and fill in your configuration. No client secret is used in the iOS app.

If Xcode requires a different bundle ID for your Personal Team, first change the Google iOS client's bundle ID to match, then override `PRODUCT_BUNDLE_IDENTIFIER` in `Local.xcconfig`. The callback URL scheme must match the reversed Google client ID. A new clone can copy `Local.xcconfig.example` and fill the public identifiers from Google Cloud → Google Auth Platform → Clients.

The OAuth audience remains External / Testing, so any additional account must be added as a Google test user. The same Gmail and Calendar scopes as the desktop app are requested. Authentication uses the system ASWebAuthenticationSession, a random state, and PKCE S256. Refresh tokens, signatures and the separately entered Gemini key are stored in the iPhone Keychain with `WhenUnlockedThisDeviceOnly` access. No credentials are bundled in the app or synchronized through iCloud.

## What sync means

| Data | Behavior |
| --- | --- |
| Messages, read status, labels/folders, Trash, sent mail | Written directly to Gmail; the Mac/Gmail/phone see the changes after their next successful refresh. |
| Saved drafts and their attachments | Stored in Gmail Drafts; can be reopened on either device. Save and close on one device before editing on another to avoid overwriting edits. |
| Google Calendar events | Written directly to Google Calendar; event updates use ETags to reject stale edits. |
| Unsent text still open in the composer | Not synchronized until saved as a Gmail draft. Save before leaving the app; iOS can terminate background apps without showing a confirmation dialog. |
| Signature, theme, accounts connected, Gemini key/model | Per-device settings in this first version. Configure separately. |

Refresh happens on foreground activation, pull-to-refresh, and approximately every 60 seconds while active. Cached message bodies are short-lived. Background execution on iOS is not continuous, and this personal build does not claim instant closed-app delivery. There is no persistent offline mailbox or queued offline mutation support.

Future background notifications require a server that receives Gmail watch notifications through Google Cloud Pub/Sub, fetches mailbox history changes, and sends APNs notifications. Watches must be renewed and missed history must recover with a full sync. Calendar push notifications require their own channels. APNs setup is outside this free Personal Team build. See [Gmail sync](https://developers.google.com/workspace/gmail/api/guides/sync), [Gmail push](https://developers.google.com/workspace/gmail/api/guides/push), and [Apple background tasks](https://developer.apple.com/documentation/backgroundtasks/refreshing-and-maintaining-your-app-using-background-tasks).

## First version controls

- Unified inbox or individual account; separate Primary, Promotions and Social tabs; system folders and Google user labels.
- Tap opens and marks a message read. Long-press or **Select** enters selection mode; tap additional rows to select. One action moves or trashes the selected messages. iPhone does not require double-clicking or keyboard modifiers.
- Swipe actions for archive, read/unread and Trash. A folder move removes the current folder/Inbox label. If a destination folder is missing in one account, that account's operation fails visibly and its selected messages remain selected.
- Inline body excerpt on every row; HTML reading with scripts/forms/frames blocked, optional HTTPS remote images, and links opening only after a user tap.
- Compose, reply, forward including attachments; add attachments from Files; save/update Gmail drafts; close confirmation with Keep, Discard, or Keep editing. Discarding edits to an existing draft does not delete that saved Gmail draft.
- Calendar agenda and date navigation; create/edit/delete personal events; **calendar-plus** on a message creates an editable event. Shared and recurring events are read-only in this first version.
- Mail and calendar natural-language search through Gemini. Writing suggestions require explicit Apply; they do not send messages. Signatures and quoted text stay outside AI rewrites; attachments are never sent to Gemini.
- Signature editor per account; dark default and light toggle. Uses native controls with the desktop's olive, cream, sage and orange palette.

Known gaps from desktop: no reply-all, no drag-to-calendar gesture (use calendar-plus), no drag/drop attachments (use Files), no folder creation, no desktop reading-pane toggle, no bulk undo, and no settings sync. Native fonts are used for Dynamic Type. This implementation is a first pass, not verified feature parity or a public release.

## Build and checks

No third-party native SDK or package installation is required.

```sh
# From the repository root, using the currently available Mac command-line SDK:
./ios/check.sh

# Use the full Xcode SDK without changing the global command-line selection:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/rAIzorMail.xcodeproj -scheme rAIzorMail \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/DerivedData CODE_SIGNING_ALLOWED=NO build

# XCTest variants when full Xcode is available:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path ios/MailCore
```

`check.sh` runs 12 core checks and four mocked service checks, type-checks the OAuth/Keychain account provider, mail/calendar/Gemini services and view model with the macOS SDK, parses all Swift source, and validates project/plist files. The service checks use a mock account provider and never access actual credentials. The checks do **not** type-check the iPhone SwiftUI/UIKit screens or validate real-device OAuth/Keychain behavior. The separate full iOS build now also type-checks the SwiftUI/UIKit screens; runtime and live account behavior require device testing.

Regenerate the checked-in Xcode project after adding source files with `python3 ios/generate-project.py`. The project only includes `rAIzorMail/*.swift` and `MailCore/Sources/MailCore/*.swift`; mock account providers and checks are excluded from the app target.

Before using real sending or edits, verify on-device: multi-account sign-in and relaunch, move/delete/read reflected on the Mac, Mac edits reflected on pull-to-refresh, saved drafts on both devices, attachment round-trips, calendar conflict behavior, cancellation, and network errors. Use disposable messages/events for write testing. Do not publish an archive until Apple signing, Google verification, privacy disclosures and release testing are completed.
