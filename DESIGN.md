# rAIzorMail

Mac desktop mail and calendar for an individual, with multiple Google accounts. Electron provides real independent message windows; React provides the interface. Gmail remains the source of truth. Calendar drops create editable drafts, never automatic invitations.

## Design direction

The rAIzor Crest site uses Sansita display type, DM Sans interface text, mountain imagery, and an earthy palette. Adapt that identity into a quiet work surface: charcoal #20211e, ink #292b26, cream #e7e2c9, orange #ce803b, sage #94a88b, gold #ccac52. Sansita is reserved for the wordmark and major view title; DM Sans handles dense mail data. The memorable element is the crest wordmark with a mountain silhouette in the sidebar footer. All working content is left aligned.

Layout: slim app rail, account/folder sidebar, spacious list with inline first-line previews, optional resizable reading pane, and a collapsible agenda strip. Calendar uses a week grid alongside a small date navigator. The compact command bar stays close to the selected messages.

```
rail | brand / accounts | title / search / view
     | folders         | category tabs / mail actions
     |                 | sender / subject + snippet | optional reading pane
     | mini calendar   | mail rows                 | agenda
```

Reviewed against the brief: use genuine desktop density and restrained brand type instead of marketing-page headings or decorative cards. Dark is default; light uses the same orange and sage accents. Reading pane starts off and is controlled from View. Every row always shows a one-line body excerpt.

## Interaction contract

- Click selects; Command-click toggles; Shift-click selects a contiguous range. No checkboxes.
- Preview never marks as read. Double-click opens an independent, movable, resizable window and marks that message read. Escape closes that window.
- Dragging any selected row carries the selection. Folder moves remove the current user label (or inbox/category context), preserve unrelated labels, and stay within each original account. Dropping on another category recategorizes the messages.
- Delete sends to Trash, with Undo. Bulk operations report any partial failures.
- Every account has separate OAuth tokens, secured through macOS-backed Electron safeStorage. Message HTML is sanitized inside a sandbox; remote email images are blocked by default.
- AI search sends only the typed request and current date to Gemini, which returns Gmail query syntax. No mailbox bodies go to AI.
- Dragging to Calendar or a date opens a prefilled event draft. Saving creates a personal event in the chosen writable Google Calendar. No guests are inferred.

## Live setup

Google Cloud Desktop OAuth credentials and user consent are required to connect accounts. Gemini search additionally requires a Gemini API key. A clearly labeled, locally persisted demo is available without credentials. Google Calendar and Gmail integration code share the same interface as the demo provider.
