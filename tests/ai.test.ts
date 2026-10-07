import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GoogleService } from '../electron/google.mjs';
import { calendarRange, generateJSON } from '../electron/ai.mjs';
import { splitWritingText } from '../src/ai.ts';
const config = { geminiKey: 'test-only-secret', geminiModel: 'gemini-3.8-flash' };
function service() { return new GoogleService({ data: { config, accounts: [{ id: 'a', email: 'a@example.com' }, { id: 'b', email: 'b@example.com' }] } }, () => {}); }
function response(value: unknown, finishReason = 'STOP') { return new Response(JSON.stringify({ candidates: [{ finishReason, content: { parts: [{ text: JSON.stringify(value) }] } }] })); }
test('calendar AI returns timezone-aware filters without sending calendar content', async t => {
  let request: any;
  t.mock.method(globalThis, 'fetch', async (_url: string, options: any) => { request = JSON.parse(options.body); return response({ query: 'Acme', start: '2026-10-12T00:00:00-04:00', end: '2026-10-19T00:00:00-04:00' }); });
  const result = await service().calendarSearchQuery('meetings with Acme next week');
  assert.deepEqual(result, { query: 'Acme', start: '2026-10-12T04:00:00.000Z', end: '2026-10-19T04:00:00.000Z' });
  assert.equal(request.contents[0].parts[0].text, 'meetings with Acme next week');
  assert(!JSON.stringify(request).includes('a@example.com')); assert(!JSON.stringify(request).includes(config.geminiKey));
  assert.equal(request.generationConfig.responseFormat.text.schema.type, 'object');
  assert.equal(request.generationConfig.responseFormat.text.mimeType, 'APPLICATION_JSON');
});
test('calendar search validates dates before contacting Google', () => {
  for (const input of [{ query: '', start: '2026-10-07', end: '2026-10-08' }, { query: '', start: '2026-10-07T00:00:00Z', end: '2026-10-06T00:00:00Z' }, { query: '', start: '2000-01-01T00:00:00Z', end: '2026-01-01T00:00:00Z' }]) assert.throws(() => calendarRange(input));
});
test('calendar results use server-side keywords, recurring instances, selected accounts and pagination', async () => {
  const google = service(); const calls: any[] = [];
  google.listCalendars = async () => [{ id: 'shared@example.com', accountId: 'a', name: 'A' }, { id: 'shared@example.com', accountId: 'b', name: 'B' }];
  google.request = async (id: string, url: string) => { calls.push({ id, params: new URL(url).searchParams }); return { items: [{ id: 'event', summary: 'Acme review', start: { dateTime: '2026-10-12T09:00:00-04:00' }, end: { dateTime: '2026-10-12T10:00:00-04:00' }, recurringEventId: 'series' }, { id: 'cancelled', status: 'cancelled' }], nextPageToken: 'more' }; };
  const plan = { query: 'Acme', start: '2026-10-12T00:00:00-04:00', end: '2026-10-19T00:00:00-04:00', accountId: 'b' };
  const result = await google.searchEvents(plan);
  assert.equal(calls.length, 1); assert.equal(calls[0].id, 'b'); assert.equal(calls[0].params.get('q'), 'Acme'); assert.equal(calls[0].params.get('singleEvents'), 'true');
  assert.equal(result.events.length, 1); assert(result.events[0].recurring);
  await google.searchEvents({ ...plan, pageTokens: result.nextPageTokens }); assert.equal(calls[1].params.get('pageToken'), 'more');
  await google.searchEvents({ ...plan, pageTokens: {} }); assert.equal(calls.length, 2);
});
test('calendar search reports partial failures while keeping successful results', async () => {
  const google = service(); google.listCalendars = async () => [{ id: 'one', accountId: 'a', name: 'Working' }, { id: 'two', accountId: 'b', name: 'Offline' }];
  google.request = async (id: string) => { if (id === 'b') throw new Error('Reconnect'); return { items: [{ id: 'one', start: { date: '2026-10-12' }, end: { date: '2026-10-13' } }] }; };
  const result = await google.searchEvents({ query: '', start: '2026-10-01T00:00:00Z', end: '2026-11-01T00:00:00Z' });
  assert.equal(result.events.length, 1); assert(result.events[0].allDay); assert.match(result.errors[0], /Offline: Reconnect/);
});
test('writing sends only explicitly provided draft fields and never sends mail', async t => {
  let payload: any; let url = ''; const google = service(); google.send = async () => { throw new Error('Must not send mail'); };
  t.mock.method(globalThis, 'fetch', async (target: string, options: any) => { url = target; payload = JSON.parse(options.body); return response({ subject: 'Checking in', text: 'Hello, could you share an update?' }); });
  const result = await google.assistWriting({ instruction: 'Make this polite', subject: 'Update', text: 'Send an update', attachments: [{ data: 'private-file' }], to: 'private@example.com' });
  assert.equal(result.subject, 'Checking in'); assert.match(url, /generativelanguage.googleapis.com/);
  assert.deepEqual(JSON.parse(payload.contents[0].parts[0].text), { instruction: 'Make this polite', subject: 'Update', text: 'Send an update', context: '' });
  assert(!JSON.stringify(payload).includes('private-file')); assert(!JSON.stringify(payload).includes('private@example.com'));
});
test('writing preserves signature and quoted history outside the generated body', () => {
  const text = 'Please send an update.\n\n-- \nAlex\n\nOn Monday, Sam wrote:\n> Original';
  const split = splitWritingText(text);
  assert.equal(split.text, 'Please send an update.'); assert.match(split.context, /^\n\nOn Monday/);
  assert.equal('Rewritten' + split.suffix, text.replace('Please send an update.', 'Rewritten'));
});
test('missing key, Gemini limits, blocked and incomplete responses produce useful errors', async t => {
  await assert.rejects(generateJSON({}, '', '', { query: { type: 'STRING' } }), /API key/);
  let mode = 'limit'; t.mock.method(globalThis, 'fetch', async () => mode === 'limit' ? new Response('{}', { status: 429 }) : mode === 'blocked' ? response({}, 'SAFETY') : response({}));
  await assert.rejects(generateJSON(config, '', '', { query: { type: 'STRING' } }), /request limit/);
  mode = 'blocked'; await assert.rejects(generateJSON(config, '', '', { query: { type: 'STRING' } }), /could not complete/);
  mode = 'incomplete'; await assert.rejects(generateJSON(config, '', '', { query: { type: 'STRING' } }), /incomplete/);
});
test('writing rejects malformed subjects and connection test validates its response', async t => {
  let value: any = { subject: 'Bad\nSubject', text: 'Body' }; t.mock.method(globalThis, 'fetch', async () => response(value));
  await assert.rejects(service().assistWriting({ instruction: 'Write', subject: '', text: '' }), /invalid subject/);
  value = { status: 'unexpected' }; await assert.rejects(service().testGemini(), /unexpectedly/);
  value = { status: 'ok' }; assert.deepEqual(await service().testGemini(), { ok: true });
});
