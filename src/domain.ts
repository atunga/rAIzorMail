import type { Mail, MailPage, Mutation, Category } from './types';
export function mergeMailPage(previous: Mail[], page: MailPage, more = false) {
  const failed = new Set(page.failedAccountIds || []);
  const retained = more ? previous : previous.filter(m => failed.has(m.accountId));
  return [...new Map([...retained, ...page.messages].map(m => [keyOf(m), m])).values()].sort((a, b) => +new Date(b.date) - +new Date(a.date));
}
export const keyOf = (m: { accountId: string; id: string }) => `${m.accountId}:${m.id}`;
export const categoryLabel: Record<Category, string> = { primary: 'CATEGORY_PERSONAL', promotions: 'CATEGORY_PROMOTIONS', social: 'CATEGORY_SOCIAL' };
export function selectRows(keys: string[], current: string[], clicked: string, anchor: string | null, meta: boolean, shift: boolean) {
  if (shift && anchor && keys.includes(anchor)) {
    const a = keys.indexOf(anchor), b = keys.indexOf(clicked);
    const range = keys.slice(Math.min(a, b), Math.max(a, b) + 1);
    return { selected: meta ? [...new Set([...current, ...range])] : range, anchor };
  }
  if (meta) return { selected: current.includes(clicked) ? current.filter(k => k !== clicked) : [...current, clicked], anchor: clicked };
  return { selected: [clicked], anchor: clicked };
}
export function localDate(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
export function localDateTime(date: Date) { return `${localDate(date)}T${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`; }
export function weekStart(date: Date) { const d = new Date(date); d.setDate(d.getDate() - (d.getDay() + 6) % 7); d.setHours(0, 0, 0, 0); return d; }
export function addDays(date: Date, days: number) { const d = new Date(date); d.setDate(d.getDate() + days); return d; }
export function initials(name: string) { return name.split(/[ @._-]+/).slice(0, 2).map(n => n[0]).join('').toUpperCase(); }
export function labelChange(labels: string[], mutation: Mutation) {
  let add: string[] = [], remove: string[] = [];
  if (mutation.kind === 'trash') { add = ['TRASH']; remove = ['INBOX', 'SPAM']; }
  if (mutation.kind === 'archive') remove = ['INBOX'];
  if (mutation.kind === 'read') { if (mutation.value) remove = ['UNREAD']; else add = ['UNREAD']; }
  if (mutation.kind === 'star') { if (mutation.value) add = ['STARRED']; else remove = ['STARRED']; }
  if (mutation.kind === 'move') {
    const target = mutation.target!;
    if (target.startsWith('CATEGORY_')) {
      add = [target, 'INBOX']; remove = labels.filter(l => l.startsWith('CATEGORY_') && l !== target);
      if (mutation.source && !['INBOX', 'ALL', 'STARRED', 'SEARCH', 'SENT', 'DRAFT'].includes(mutation.source) && !mutation.source.startsWith('CATEGORY_')) remove.push(mutation.source);
    } else {
      add = [target];
      if (mutation.source === 'INBOX' || mutation.source?.startsWith('CATEGORY_')) remove.push('INBOX');
      else if (mutation.source && !['ALL', 'STARRED', 'SEARCH', 'SENT', 'DRAFT'].includes(mutation.source)) remove.push(mutation.source);
    }
    if (target !== 'TRASH') remove.push('TRASH');
    if (target !== 'SPAM') remove.push('SPAM');
  }
  add = [...new Set(add)].filter(l => !labels.includes(l));
  remove = [...new Set(remove)].filter(l => labels.includes(l) && l !== mutation.target);
  return { added: add, removed: remove, labels: [...labels.filter(l => !remove.includes(l)), ...add] };
}
export function mailInFolder(m: Mail, folder: string, category: Category) {
  if (folder === 'ALL') return !m.labels.includes('TRASH') && !m.labels.includes('SPAM');
  if (folder === 'INBOX') return m.labels.includes('INBOX') && (category === 'primary' ? !m.labels.some(l => ['CATEGORY_PROMOTIONS', 'CATEGORY_SOCIAL'].includes(l)) : m.labels.includes(categoryLabel[category]));
  return m.labels.includes(folder) && (folder === 'TRASH' || !m.labels.includes('TRASH'));
}
