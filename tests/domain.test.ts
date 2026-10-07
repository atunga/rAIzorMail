import { test } from 'node:test';
import assert from 'node:assert/strict';
import { selectRows, labelChange, mailInFolder, weekStart, localDate, mergeMailPage } from '../src/domain.ts';
import type { Mail } from '../src/types.ts';
import { changeLabels, normalizeMessage, mapLimit, validateEvent } from '../electron/core.mjs';
test('failed account sync preserves visible mail while successful accounts replace their rows', () => {
  const a = { accountId: 'a', id: 'one', date: '2026-10-07' } as Mail;
  const b = { accountId: 'b', id: 'old', date: '2026-10-06' } as Mail;
  const next = { ...b, id: 'new', date: '2026-10-08' };
  const previous = [a, b];
  assert.deepEqual(mergeMailPage(previous, { messages: [], nextPageTokens: {}, failedAccountIds: ['a', 'b'] }), previous);
  assert.deepEqual(mergeMailPage(previous, { messages: [next], nextPageTokens: {}, failedAccountIds: ['a'] }), [next, a]);
  assert.deepEqual(mergeMailPage(previous, { messages: [], nextPageTokens: {} }), []);
  assert.deepEqual(mergeMailPage(previous, { messages: [a, next], nextPageTokens: {} }, true), [next, a, b]);
});
test('single, Command, Shift and Command-Shift selection behave like a desktop list', () => {
  const rows = ['a', 'b', 'c', 'd', 'e'];
  assert.deepEqual(selectRows(rows, ['a'], 'c', 'a', false, false), { selected: ['c'], anchor: 'c' });
  assert.deepEqual(selectRows(rows, ['a'], 'c', 'a', true, false).selected, ['a', 'c']);
  assert.deepEqual(selectRows(rows, ['a', 'c'], 'a', 'c', true, false).selected, ['c']);
  assert.deepEqual(selectRows(rows, ['a'], 'd', 'b', false, true).selected, ['b', 'c', 'd']);
  assert.deepEqual(selectRows(rows, ['a'], 'd', 'c', true, true).selected, ['a', 'c', 'd']);
});
test('folder moves preserve unrelated labels and unread state', () => {
  const labels = ['INBOX', 'CATEGORY_PROMOTIONS', 'UNREAD', 'Clients', 'Tax'];
  const mutation = { kind: 'move' as const, refs: [], source: 'INBOX', target: 'Invoices' };
  const result = labelChange(labels, mutation);
  assert.deepEqual(result.labels, ['CATEGORY_PROMOTIONS', 'UNREAD', 'Clients', 'Tax', 'Invoices']);
  assert.deepEqual(changeLabels(labels, mutation), { added: result.added, removed: result.removed });
  const moved = labelChange(result.labels, { ...mutation, source: 'Invoices', target: 'Projects' });
  assert(moved.labels.includes('UNREAD')); assert(!moved.labels.includes('Invoices')); assert(moved.labels.includes('Tax'));
});
test('category moves remove competing categories while preserving original account labels', () => {
  const mutation = { kind: 'move' as const, refs: [], source: 'INBOX', target: 'CATEGORY_SOCIAL' };
  const result = labelChange(['INBOX', 'CATEGORY_PROMOTIONS', 'UNREAD', 'Clients'], mutation);
  assert.deepEqual(result.labels, ['INBOX', 'UNREAD', 'Clients', 'CATEGORY_SOCIAL']);
  assert.deepEqual(changeLabels(['INBOX', 'CATEGORY_PROMOTIONS', 'UNREAD', 'Clients'], mutation), { added: result.added, removed: result.removed });
});
test('read mutation is explicit and trash delta is reversible', () => {
  const before = ['INBOX', 'UNREAD', 'STARRED', 'Clients'];
  const trashed = labelChange(before, { kind: 'trash', refs: [] });
  assert(trashed.labels.includes('UNREAD'));
  const restored = [...trashed.labels.filter(l => !trashed.added.includes(l)), ...trashed.removed];
  assert.deepEqual(restored.sort(), before.sort());
  assert.deepEqual(labelChange(before, { kind: 'read', refs: [], value: true }).removed, ['UNREAD']);
});
test('moving from a user folder to an inbox tab removes the source folder', () => {
  const labels = ['Invoices', 'Tax', 'UNREAD', 'CATEGORY_PROMOTIONS'];
  const action = { kind: 'move' as const, refs: [], source: 'Invoices', target: 'CATEGORY_PERSONAL' };
  const result = labelChange(labels, action);
  assert.deepEqual(result.labels, ['Tax', 'UNREAD', 'CATEGORY_PERSONAL', 'INBOX']);
  assert.deepEqual(changeLabels(labels, action), { added: result.added, removed: result.removed });
});
test('decodes nested MIME, UTF-8 body and attachment metadata without interpreting HTML', () => {
  const raw = { id: 'abc', threadId: 't', internalDate: '1770000000000', labelIds: ['UNREAD'], payload: { headers: [{ name: 'From', value: '"Maya Chen" <maya@example.com>' }, { name: 'Subject', value: 'Résumé' }], parts: [{ mimeType: 'multipart/alternative', parts: [{ mimeType: 'text/plain', body: { data: Buffer.from('Hello — world').toString('base64url') } }, { mimeType: 'text/html', body: { data: Buffer.from('<b>Hello</b>').toString('base64url') } }] }, { filename: 'notes.pdf', mimeType: 'application/pdf', body: { attachmentId: 'file1', size: 42 } }] } };
  const m = normalizeMessage(raw, 'account1');
  assert.equal(m.text, 'Hello — world'); assert.equal(m.html, '<b>Hello</b>'); assert.equal(m.from, 'Maya Chen'); assert.equal(m.accountId, 'account1'); assert(m.unread); assert.equal(m.attachments[0].id, 'file1');
});
test('date helpers keep local week boundaries and event validation rejects backwards dates', () => {
  assert.equal(localDate(weekStart(new Date(2026, 9, 7, 12))), '2026-10-05');
  assert.throws(() => validateEvent({ title: 'Review', calendarId: 'c', accountId: 'a', start: '2026-10-07T12:00:00Z', end: '2026-10-07T11:00:00Z' }), /end time/);
});
test('bounded requests maintain order and never exceed concurrency', async () => {
  let active = 0, max = 0; const result = await mapLimit([1, 2, 3, 4, 5], 2, async n => { active++; max = Math.max(max, active); await new Promise(r => setTimeout(r, 5)); active--; return n * 2; }); assert.deepEqual(result, [2, 4, 6, 8, 10]); assert.equal(max, 2);
});
