import { convert } from 'html-to-text';
export function keyOf(ref) { return `${ref.accountId}:${ref.id}`; }
export function changeLabels(labels, mutation) {
  let add = [], remove = [];
  if (mutation.kind === 'trash') { add = ['TRASH']; remove = ['INBOX', 'SPAM']; }
  if (mutation.kind === 'archive') remove = ['INBOX'];
  if (mutation.kind === 'read') { if (mutation.value) remove = ['UNREAD']; else add = ['UNREAD']; }
  if (mutation.kind === 'star') { if (mutation.value) add = ['STARRED']; else remove = ['STARRED']; }
  if (mutation.kind === 'move') {
    const target = mutation.target;
    if (!target) throw new Error('Choose a destination folder.');
    if (target.startsWith('CATEGORY_')) { add = [target, 'INBOX']; remove = labels.filter(l => l.startsWith('CATEGORY_') && l !== target); if (mutation.source && !['INBOX', 'ALL', 'STARRED', 'SEARCH', 'SENT', 'DRAFT'].includes(mutation.source) && !mutation.source.startsWith('CATEGORY_')) remove.push(mutation.source); }
    else { add = [target]; if (mutation.source === 'INBOX' || mutation.source?.startsWith('CATEGORY_')) remove.push('INBOX'); else if (mutation.source && !['ALL', 'STARRED', 'SEARCH', 'SENT', 'DRAFT'].includes(mutation.source)) remove.push(mutation.source); }
    if (target !== 'TRASH') remove.push('TRASH');
    if (target !== 'SPAM') remove.push('SPAM');
  }
  return { added: [...new Set(add)].filter(l => !labels.includes(l)), removed: [...new Set(remove)].filter(l => labels.includes(l) && l !== mutation.target) };
}
export function normalizeMessage(raw, accountId) {
  const headers = raw.payload?.headers || [];
  const header = name => headers.find(h => h.name.toLowerCase() === name)?.value || '';
  const from = header('from'); const match = from.match(/^(.*?)\s*<([^>]+)>$/);
  let text = '', html = ''; const attachments = [];
  function walk(p) {
    if (!p) return;
    if (p.filename) attachments.push({ id: p.body?.attachmentId || p.partId, name: p.filename, size: p.body?.size || 0, mimeType: p.mimeType, ...(p.body?.data ? { data: p.body.data } : {}) });
    else if (p.body?.data) { const body = Buffer.from(p.body.data, 'base64url').toString('utf8'); if (p.mimeType === 'text/plain') text += body; if (p.mimeType === 'text/html') html += body; }
    for (const part of p.parts || []) walk(part);
  }
  walk(raw.payload);
  const labels = raw.labelIds || [];
  return { id: raw.id, threadId: raw.threadId, accountId, from: match ? match[1].replace(/^"|"$/g, '') || match[2] : from, fromEmail: match ? match[2] : from, to: header('to'), cc: header('cc'), bcc: header('bcc'), subject: header('subject') || '(No subject)', snippet: raw.snippet || '', text: text || (html ? convert(html, { wordwrap: false, selectors: [{ selector: 'img', format: 'skip' }] }) : ''), html, date: new Date(Number(raw.internalDate) || Date.parse(header('date')) || Date.now()).toISOString(), labels, unread: labels.includes('UNREAD'), starred: labels.includes('STARRED'), attachments, messageId: header('message-id'), references: header('references'), replyTo: header('reply-to') };
}
export function validateEvent(event) {
  if (!event.title?.trim()) throw new Error('Give your event a title.');
  if (!event.calendarId || !event.accountId) throw new Error('Choose a calendar.');
  if (!Number.isFinite(Date.parse(event.start)) || !Number.isFinite(Date.parse(event.end)) || Date.parse(event.end) <= Date.parse(event.start)) throw new Error('The end time must be after the start time.');
}
export async function mapLimit(items, limit, fn) {
  const results = new Array(items.length); let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => { while (cursor < items.length) { const i = cursor++; results[i] = await fn(items[i], i); } }));
  return results;
}
