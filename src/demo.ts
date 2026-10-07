import type { Account, Mail, MailAPI, CalendarEvent, Compose, MutationResult, Signature } from './types';
import { defaultCalendarRange } from './ai';
import { addDays, categoryLabel, keyOf, labelChange, localDate, mailInFolder } from './domain';
const accounts: Account[] = [
  { id: 'work', name: 'rAIzor crest', email: 'ted@raizorcrest.example', color: '#cf8a4c' },
  { id: 'personal', name: 'Personal', email: 'ted.hebert@example.com', color: '#94a88b' },
];
const base = new Date(); base.setHours(10, 42, 0, 0);
const seeds = [
  ['Maya Chen', 'maya@acme.example', 'Updated proposal for the warehouse rollout', 'Hi Ted, I’ve attached the revised proposal with the phased rollout we discussed.', 'primary', 'work', true, true, 0, 'Hi Ted,\n\nI’ve attached the revised proposal with the phased rollout we discussed. The team is aligned on starting with order intake, then moving into purchasing once the first workflow is running smoothly.\n\nA few updates since our call:\n• Phase one covers the Springfield and Hartford locations.\n• We’ve added a weekly review with the operations team.\n• The target kickoff is next Tuesday.\n\nCould you take a look and let me know what you think? Happy to walk through it together tomorrow.\n\nThanks,\nMaya\nOperations Director, Acme Industrial'],
  ['Alex Rivera', 'alex@northstar.example', 'A few thoughts before tomorrow’s call', 'The inventory team pulled together their top three pain points. Sharing ahead of our conversation.', 'primary', 'work', true, false, 22],
  ['Jamie Brooks', 'jamie@example.com', 'Saturday in the mountains?', 'Weather looks perfect for a hike. Thinking an early start and coffee on the way.', 'primary', 'personal', true, false, 51],
  ['Acme Accounts', 'accounts@acme.example', 'Invoice AC-2048 · September services', 'Your September invoice is ready. Payment details and the itemized breakdown are attached.', 'primary', 'work', true, false, 94],
  ['Morgan Lee', 'morgan@raizorcrest.example', 'Re: Quote-to-order workflow', 'This is looking good. I added a couple of notes on how we handle substitute parts.', 'primary', 'work', false, true, 132],
  ['Figma', 'updates@figma.example', 'Your weekly design roundup', 'A little inspiration for your next big idea. New resources from the community.', 'promotions', 'work', true, false, 140],
  ['Sam Wilson', 'sam@industrial.example', 'Quick introduction — meet the operations team', 'Ted, meet Priya and Chris. They’ll be your main points of contact for the pilot.', 'primary', 'work', false, false, 190],
  ['Taylor Reed', 'taylor@example.com', 'Dinner next week', 'Are you free on Thursday? There’s a new place downtown I think you’d like.', 'primary', 'personal', false, false, 210],
  ['Jordan Ellis', 'jordan@summit.example', 'October delivery schedule', 'Here’s the updated delivery schedule for October. Everything is tracking to plan.', 'primary', 'work', false, false, 260],
  ['LinkedIn', 'notifications@linkedin.example', 'Maya and 3 others shared updates', 'Catch up with your network and see what your connections are working on.', 'social', 'work', true, false, 280],
  ['Patagonia', 'hello@patagonia.example', 'Built for the days outside', 'Cool mornings. Longer trails. Find your next layer for the season ahead.', 'promotions', 'personal', false, false, 350],
  ['Chris Park', 'chris@acme.example', 'Notes from the floor walkthrough', 'Great meeting you yesterday. The attached notes cover receiving, picking, and order entry.', 'primary', 'work', false, false, 1440],
  ['Google Calendar', 'calendar@google.example', 'Accepted: Operations discovery', 'Priya accepted your invitation. Your meeting is on the calendar for tomorrow morning.', 'primary', 'work', false, false, 1500],
  ['Acme Accounts', 'accounts@acme.example', 'Invoice AC-1987 · Previous month', 'The monthly invoice and service summary are attached for your records.', 'primary', 'work', false, false, 43200],
] as const;
function seedMessages(): Mail[] { return seeds.map((s, i) => ({ id: `demo-${i}`, threadId: `thread-${i}`, accountId: s[5], from: s[0], fromEmail: s[1], to: accounts.find(a => a.id === s[5])!.email, subject: s[2], snippet: s[3], text: s[9] || `${s[3]}\n\nLet me know if you have any questions.\n\nBest,\n${s[0]}`, date: new Date(base.getTime() - s[8] * 60000).toISOString(), labels: ['INBOX', categoryLabel[s[4]], ...(s[6] ? ['UNREAD'] : []), ...(s[7] ? ['STARRED'] : [])], unread: s[6], starred: s[7], attachments: [0, 3, 11, 13].includes(i) ? [{ id: 'sample', name: i === 0 ? 'Warehouse rollout — proposal.txt' : 'Service summary.txt', mimeType: 'text/plain', size: 230, data: btoa('Sample attachment for the rAIzorMail demo. Connect your account to view real attachments.') }] : [] })); }
function seedEvents(): CalendarEvent[] {
  return [[0, 11, 'Operations discovery', 'work'], [0, 14, 'Focus time', 'work'], [1, 9, 'Acme rollout review', 'work'], [2, 12, 'Lunch with Jamie', 'personal']].map((s, i) => {
    const start = addDays(base, Number(s[0])); start.setHours(Number(s[1]), 0, 0, 0);
    return { id: `event-${i}`, calendarId: `${s[3]}-calendar`, accountId: String(s[3]), title: String(s[2]), start: start.toISOString(), end: new Date(start.getTime() + 3600000).toISOString(), description: '', location: i === 0 ? 'Google Meet' : '', color: s[3] === 'work' ? '#94a88b' : '#ccac52' };
  });
}
type DemoState = { messages: Mail[]; events: CalendarEvent[]; folders: string[] };
const storageKey = 'raizormail-demo-v1';
function read(): DemoState { try { const s = localStorage.getItem(storageKey); if (s) return JSON.parse(s); } catch { /* Seed a new demo if local storage is unavailable. */ } return { messages: seedMessages(), events: seedEvents(), folders: ['Clients', 'Projects', 'Invoices', 'Reading list'] }; }
function write(s: DemoState) { localStorage.setItem(storageKey, JSON.stringify(s)); const ch = new BroadcastChannel('raizormail'); ch.postMessage('changed'); ch.close(); }
function syncFlags(m: Mail) { m.unread = m.labels.includes('UNREAD'); m.starred = m.labels.includes('STARRED'); }
function matchQuery(m: Mail, query: string) {
  const terms = query.match(/(?:[^\s"]+|"[^"]*")+/g) || [];
  return terms.every(term => {
    const [operator, ...rest] = term.split(':'); const value = rest.join(':').replaceAll('"', '').toLowerCase();
    if (operator === 'from') return `${m.from} ${m.fromEmail}`.toLowerCase().includes(value);
    if (operator === 'to') return m.to.toLowerCase().includes(value);
    if (operator === 'subject') return m.subject.toLowerCase().includes(value);
    if (operator === 'after') return new Date(m.date) >= new Date(value.replaceAll('/', '-'));
    if (operator === 'before') return new Date(m.date) < new Date(value.replaceAll('/', '-'));
    if (operator === 'is') return value === 'unread' ? m.unread : value === 'starred' ? m.starred : true;
    if (operator === 'has' && value === 'attachment') return m.attachments.length > 0;
    return `${m.from} ${m.subject} ${m.text}`.toLowerCase().includes(term.replaceAll('"', '').toLowerCase());
  });
}
export const demoAPI: MailAPI = {
  async getSignatures() { return JSON.parse(localStorage.getItem('raizormail-demo-signatures') || '{}') as Record<string, Signature>; },
  async saveSignature({ accountId, signature }) { const signatures = await this.getSignatures(); localStorage.setItem('raizormail-demo-signatures', JSON.stringify({ ...signatures, [accountId]: signature })); },
  async bootstrap() { return { accounts, config: { googleConfigured: false, geminiConfigured: false, geminiModel: 'gemini-3.8-flash' } }; },
  async listFolders() { return read().folders.map(name => ({ id: name, name })); },
  async listMessages(q) { return { messages: read().messages.filter(m => (!q.accountId || m.accountId === q.accountId) && (q.query ? !m.labels.includes('TRASH') && matchQuery(m, q.query) : mailInFolder(m, q.folder, q.category))).sort((a, b) => +new Date(b.date) - +new Date(a.date)), nextPageTokens: {} }; },
  async getMessage(ref) { const mail = read().messages.find(m => keyOf(m) === keyOf(ref)); if (!mail) throw new Error('This message is no longer available.'); return mail; },
  async materializeAttachments(ref) { return (await this.getMessage(ref)).attachments; },
  async mutate(mutation) { const state = read(); const result: MutationResult = { succeeded: [], failed: [], undo: [] };
    for (const ref of mutation.refs) { const m = state.messages.find(m => keyOf(m) === keyOf(ref)); if (!m) { result.failed.push({ key: keyOf(ref), error: 'Message unavailable' }); continue; } const change = labelChange(m.labels, mutation); m.labels = change.labels; syncFlags(m); result.succeeded.push(keyOf(m)); result.undo.push({ ref, added: change.added, removed: change.removed }); }
    write(state); return result;
  },
  async undo(entries) { const state = read(); for (const e of entries) { const m = state.messages.find(m => keyOf(m) === keyOf(e.ref)); if (m) { m.labels = [...new Set([...m.labels.filter(l => !e.added.includes(l)), ...e.removed])]; syncFlags(m); } } write(state); },
  async send(c) { const state = read(); const a = accounts.find(a => a.id === c.accountId)!; const m = composedMail(c, a, 'SENT'); if (c.draftId) state.messages = state.messages.filter(m => m.draftId !== c.draftId); state.messages.unshift(m); write(state); },
  async saveDraft(c) { const state = read(); const a = accounts.find(a => a.id === c.accountId)!; const id = c.draftId || crypto.randomUUID(); state.messages = state.messages.filter(m => m.draftId !== id); state.messages.unshift({ ...composedMail(c, a, 'DRAFT'), draftId: id }); write(state); return { id }; },
  async listCalendars() { return accounts.map(a => ({ id: `${a.id}-calendar`, accountId: a.id, name: a.name, color: a.color, writable: true })); },
  async listEvents(start, end) { return { events: read().events.filter(e => e.start < end && e.end > start) }; },
  async saveEvent(event) { const state = read(); const saved = { ...event, id: event.id || crypto.randomUUID() }; state.events = [...state.events.filter(e => e.id !== saved.id), saved]; write(state); return saved; },
  async deleteEvent(event) { const state = read(); state.events = state.events.filter(e => e.id !== event.id); write(state); },
  async searchQuery(prompt) {
    // The demo's deliberately limited parser is labeled in the UI; live mode uses Gemini.
    let query = ''; const from = prompt.match(/from\s+([\w@.-]+)/i); if (from) query += `from:${from[1]} `;
    if (/invoice/i.test(prompt)) query += 'invoice ';
    if (/last month/i.test(prompt)) { const d = new Date(); query += `after:${localDate(new Date(d.getFullYear(), d.getMonth() - 1, 1))} before:${localDate(new Date(d.getFullYear(), d.getMonth(), 1))}`; }
    return query.trim() || prompt.replace(/^find\s+/i, '');
  },
  async calendarSearchQuery(prompt) {
    const range = defaultCalendarRange(); const now = new Date();
    if (/next week/i.test(prompt)) { const start = new Date(now); start.setDate(now.getDate() + (8 - (now.getDay() || 7))); start.setHours(0, 0, 0, 0); range.start = start.toISOString(); range.end = addDays(start, 7).toISOString(); }
    if (/last month/i.test(prompt)) { range.start = new Date(now.getFullYear(), now.getMonth() - 1, 1).toISOString(); range.end = new Date(now.getFullYear(), now.getMonth(), 1).toISOString(); }
    return { ...range, query: prompt.replace(/\b(find|show|my|all|events?|meetings?|with|next week|last month)\b/gi, '').trim() };
  },
  async searchEvents(query) { return { events: read().events.filter(e => (!query.accountId || e.accountId === query.accountId) && e.start < query.end && e.end > query.start && `${e.title} ${e.description} ${e.location}`.toLowerCase().includes(query.query.toLowerCase())), nextPageTokens: {} }; },
  async assistWriting(request) { return { subject: request.subject || 'Following up', text: request.text ? `${request.text.trim()}\n\n[Demo suggestion — connect Gemini in Settings for real writing assistance.]` : `Hello,\n\n${request.instruction}\n\n[Demo suggestion — connect Gemini in Settings for a complete draft.]` }; },
  async testGemini() { return { ok: true }; },
  async createFolder(name) { const state = read(); if (!state.folders.includes(name)) state.folders.push(name); write(state); },
  async attachment(_ref, a) { const bytes = Uint8Array.from(atob(a.data || ''), c => c.charCodeAt(0)); const url = URL.createObjectURL(new Blob([bytes], { type: a.mimeType })); const link = document.createElement('a'); link.href = url; link.download = a.name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); },
};
function composedMail(c: Compose, a: Account, label: string): Mail { return { id: crypto.randomUUID(), accountId: c.accountId, threadId: c.threadId || crypto.randomUUID(), from: a.name, fromEmail: a.email, to: c.to, cc: c.cc, bcc: c.bcc, subject: c.subject || '(No subject)', snippet: c.text.split('\n')[0], text: c.text, date: new Date().toISOString(), labels: [label], unread: false, starred: false, attachments: c.attachments }; }
