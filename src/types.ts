export type Account = { id: string; email: string; name: string; color: string };
export type Attachment = { id: string; name: string; size: number; mimeType: string; data?: string };
export type Mail = { id: string; accountId: string; threadId: string; from: string; fromEmail: string; to: string; cc?: string; bcc?: string; subject: string; snippet: string; text: string; html?: string; date: string; labels: string[]; unread: boolean; starred: boolean; attachments: Attachment[]; messageId?: string; references?: string; replyTo?: string; draftId?: string };
export type Folder = { id: string; name: string; count?: number; accountId?: string };
export type Calendar = { id: string; accountId: string; name: string; color: string; writable: boolean };
export type CalendarEvent = { id: string; calendarId: string; accountId: string; title: string; start: string; end: string; description: string; location: string; allDay?: boolean; color?: string; attendees?: string[]; recurring?: boolean };
export type CalendarSearch = { query: string; start: string; end: string; accountId?: string; pageTokens?: Record<string, string> };
export type CalendarResults = { events: CalendarEvent[]; errors?: string[]; nextPageTokens: Record<string, string> };
export type WritingRequest = { instruction: string; subject: string; text: string; context?: string };
export type WritingResult = { subject: string; text: string };
export type Category = 'primary' | 'promotions' | 'social';
export type MailQuery = { accountId?: string; folder: string; category: Category; query?: string; pageTokens?: Record<string, string> };
export type MailPage = { messages: Mail[]; nextPageTokens: Record<string, string>; failedAccountIds?: string[]; errors?: string[] };
export type MailRef = { id: string; accountId: string };
export type Mutation = { kind: 'trash' | 'move' | 'read' | 'star' | 'archive'; refs: MailRef[]; target?: string; source?: string; value?: boolean };
export type UndoEntry = { ref: MailRef; added: string[]; removed: string[] };
export type MutationResult = { succeeded: string[]; failed: { key: string; error: string }[]; undo: UndoEntry[] };
export type Compose = { accountId: string; to: string; cc: string; bcc: string; subject: string; text: string; attachments: Attachment[]; threadId?: string; inReplyTo?: string; references?: string; draftId?: string };
export type Signature = { text: string; newMessages: boolean; replies: boolean };
export type Config = { googleConfigured: boolean; geminiConfigured: boolean; geminiModel: string };
export type Boot = { accounts: Account[]; config: Config };
export interface MailAPI {
  getSignatures(): Promise<Record<string, Signature>>;
  saveSignature(input: { accountId: string; signature: Signature }): Promise<void>;
  bootstrap(): Promise<Boot>;
  listFolders(): Promise<Folder[]>;
  listMessages(query: MailQuery): Promise<MailPage>;
  getMessage(ref: MailRef): Promise<Mail>;
  materializeAttachments(ref: MailRef): Promise<Attachment[]>;
  mutate(mutation: Mutation): Promise<MutationResult>;
  undo(entries: UndoEntry[]): Promise<void>;
  send(compose: Compose): Promise<void>;
  saveDraft(compose: Compose): Promise<{ id: string }>;
  listCalendars(): Promise<Calendar[]>;
  listEvents(start: string, end: string): Promise<{ events: CalendarEvent[]; errors?: string[] }>;
  saveEvent(event: CalendarEvent): Promise<CalendarEvent>;
  deleteEvent(event: CalendarEvent): Promise<void>;
  searchQuery(prompt: string): Promise<string>;
  calendarSearchQuery(prompt: string): Promise<CalendarSearch>;
  searchEvents(query: CalendarSearch): Promise<CalendarResults>;
  assistWriting(request: WritingRequest): Promise<WritingResult>;
  testGemini(): Promise<{ ok: boolean }>;
  createFolder(name: string, accountId?: string): Promise<void>;
  attachment(ref: MailRef, attachment: Attachment): Promise<void>;
}
declare global {
  interface Window { desktop?: {
    invoke<T>(method: string, input?: unknown): Promise<T>;
    openMessage(ref: MailRef, demo: boolean): Promise<void>;
    closeWindow(): void;
    setCloseGuard(active: boolean): void;
    resolveClose(allow: boolean): void;
    onRequestClose(callback: () => void): () => void;
    onCommand(callback: (command: string) => void): () => void;
    onChanged(callback: (change?: { scope: 'mail' | 'calendar' }) => void): () => void;
  } }
}
