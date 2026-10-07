import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { GoogleService } from '../electron/google.mjs';
import { connectGoogle } from '../electron/oauth.mjs';
import { RequestBudget } from '../electron/requests.mjs';
function fixture() { return { data: { accounts: [{ id: 'a', email: 'a@example.com', name: 'Account A', tokens: { access_token: 'token', refresh_token: 'refresh', expiresAt: Date.now() + 3600000 } }, { id: 'b', email: 'b@example.com', name: 'Account B', tokens: { access_token: 'token-b', expiresAt: Date.now() + 3600000 } }], config: { clientId: 'test.apps.googleusercontent.com', geminiKey: 'not-real', geminiModel: 'gemini-2.5-flash' } }, save() {} }; }
test('opening messages across windows shares reads; marking read reloads only the changed body', async t => {
  const service = new GoogleService(fixture(), () => {}); service.budget.take = async () => {};
  const calls: string[] = []; let unread = true;
  t.mock.method(globalThis, 'fetch', async (url: string, options: any) => {
    calls.push(`${options.method} ${url}`);
    if (url.includes('/modify')) unread = false;
    const data = /\/messages\?/.test(url) ? { messages: [{ id: 'one' }, { id: 'two' }] } : { id: url.includes('/two') ? 'two' : 'one', labelIds: unread ? ['INBOX', 'UNREAD'] : ['INBOX'], payload: { mimeType: 'text/plain', body: { data: 'SGVsbG8' } } };
    return new Response(JSON.stringify(data));
  });
  const query = { accountId: 'a', folder: 'INBOX', category: 'primary' };
  await service.listMessages(query);
  assert.equal(calls.length, 3);
  await Promise.all(Array.from({ length: 12 }, () => service.getMessage({ accountId: 'a', id: 'one' })));
  assert.equal(calls.length, 3, 'opening already loaded messages should make no network requests');
  await service.mutate({ kind: 'read', value: true, refs: [{ accountId: 'a', id: 'one' }] });
  const [page] = await Promise.all([service.listMessages(query), service.listMessages(query), service.getMessage({ accountId: 'a', id: 'one' })]);
  assert.equal(calls.length, 7, 'one minimal read, one modify, one list, one changed body');
  assert.equal(page.messages.find((m: any) => m.id === 'one')?.unread, false);
  assert.equal(calls.filter(c => c.includes('/two?')).length, 1);
});
test('concurrent uncached reads coalesce and cached data cannot be mutated by another window', async t => {
  const service = new GoogleService(fixture(), () => {}); service.budget.take = async () => {};
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => { calls++; return new Response(JSON.stringify({ id: 'one', labelIds: ['UNREAD'] })); });
  const url = 'https://gmail.googleapis.com/gmail/v1/users/me/messages/one?format=full';
  const results = await Promise.all(Array.from({ length: 10 }, () => service.request('a', url)));
  results[0].labelIds.length = 0;
  assert.equal(calls, 1); assert.deepEqual(results[1].labelIds, ['UNREAD']);
  await service.request('b', url); assert.equal(calls, 2, 'accounts have separate cache keys');
});
test('429 respects account cooldown and does not hammer Gmail or block other accounts', async t => {
  const service = new GoogleService(fixture(), () => {}); let now = 1000; let calls = 0;
  service.budget = new RequestBudget(() => now, async (ms: number) => { now += ms; });
  t.mock.method(globalThis, 'fetch', async () => { calls++; return calls === 1 ? new Response(JSON.stringify({ error: { message: 'Quota exceeded' } }), { status: 429, headers: { 'Retry-After': '60' } }) : new Response('{}'); });
  const url = 'https://gmail.googleapis.com/gmail/v1/users/me/messages';
  await assert.rejects(() => service.request('a', url), /temporarily limiting/);
  await assert.rejects(() => service.request('a', url), /temporarily limiting/);
  assert.equal(calls, 1);
  await service.request('b', url); assert.equal(calls, 2);
  now += 60000; await service.request('a', url); assert.equal(calls, 3);
});
test('shared Gmail pacing budgets concurrent windows per account', async () => {
  let now = 1000; const waits: number[] = [];
  const budget = new RequestBudget(() => now, async ms => { waits.push(ms); });
  await Promise.all([budget.take('a', 20), budget.take('a', 20), budget.take('a', 20), budget.take('b', 20)]);
  assert.deepEqual(waits, [250, 500]);
});
test('partial mailbox failures identify the account to preserve in the inbox', async () => {
  const service = new GoogleService(fixture(), () => {});
  service.request = async (id: string) => { if (id === 'a') throw new Error('Quota exceeded'); return { messages: [] }; };
  const page = await service.listMessages({ folder: 'INBOX', category: 'primary' });
  assert.deepEqual(page.failedAccountIds, ['a']); assert.equal(page.errors.length, 1);
});
test('unified pagination skips exhausted accounts and keeps Google queries account-local', async () => {
  const service = new GoogleService(fixture(), () => {}); const calls: any[] = [];
  service.request = async (id: string, url: string) => { calls.push({ id, url }); return { messages: [{ id: 'message' }], nextPageToken: 'next2' }; };
  service.getMessage = async (ref: any) => ({ ...ref, date: '2026-10-01' });
  const page = await service.listMessages({ folder: 'INBOX', category: 'promotions', pageTokens: { b: 'next1' } });
  assert.equal(calls.length, 1); assert.equal(calls[0].id, 'b'); assert(new URL(calls[0].url).searchParams.get('q') === 'category:promotions'); assert.deepEqual(page.nextPageTokens, { b: 'next2' }); assert.equal(page.messages[0].accountId, 'b');
});
test('batch folder moves resolve per-account label IDs and report partial failures', async () => {
  const service = new GoogleService(fixture(), () => {}); const changes: any[] = [];
  service.labelId = async (id: string, name: string) => `${id}-${name}`;
  service.request = async (id: string, url: string, method: string, body: any) => { if (url.includes('/broken')) throw new Error('Account permission expired'); if (method === 'POST') { changes.push({ id, body }); return {}; } return { labelIds: ['INBOX', 'UNREAD', `${id}-Clients`] }; };
  const result = await service.mutate({ kind: 'move', source: 'INBOX', target: 'Invoices', refs: [{ accountId: 'a', id: 'one' }, { accountId: 'b', id: 'two' }, { accountId: 'b', id: 'broken' }] });
  assert.equal(result.succeeded.length, 2); assert.equal(result.failed.length, 1); assert.equal(result.undo.length, 2);
  assert.deepEqual(changes[0].body, { addLabelIds: ['a-Invoices'], removeLabelIds: ['INBOX'] }); assert.deepEqual(changes[1].body.addLabelIds, ['b-Invoices']);
});
test('Trash undo restores original labels even when untrash automatically adds Inbox', async () => {
  const service = new GoogleService(fixture(), () => {}); let labels = ['UNREAD', 'Clients'];
  service.request = async (_id: string, url: string, _method: string, body: any) => { if (url.endsWith('/trash')) labels = [...labels, 'TRASH']; else if (url.endsWith('/untrash')) labels = [...labels.filter(l => l !== 'TRASH'), 'INBOX']; else if (url.endsWith('/modify')) labels = [...labels.filter(l => !body.removeLabelIds.includes(l)), ...body.addLabelIds]; return { labelIds: [...labels] }; };
  const result = await service.mutate({ kind: 'trash', refs: [{ accountId: 'a', id: 'one' }] }); assert(labels.includes('TRASH')); await service.undo(result.undo); assert.deepEqual(labels.sort(), ['Clients', 'UNREAD']);
});
test('MIME includes unicode, recipients, reply headers and binary attachments; rejects header injection', async () => {
  const service = new GoogleService(fixture(), () => {});
  const compose = { accountId: 'a', to: 'Maya <maya@example.com>', cc: '', bcc: 'private@example.com', subject: 'Résumé — proposal', text: 'Hello Maya', inReplyTo: '<original@example.com>', threadId: 'thread', attachments: [{ name: 'note.txt', mimeType: 'text/plain', size: 3, data: Buffer.from('abc').toString('base64') }] };
  const encoded = await service.rawMessage(compose); const raw = Buffer.from(encoded.raw, 'base64url').toString('utf8'); assert.equal(encoded.threadId, 'thread'); assert.match(raw, /Bcc: private@example.com/); assert.match(raw, /In-Reply-To: <original@example.com>/); assert.match(raw, /filename=note.txt/); assert.match(raw, /YWJj/);
  await assert.rejects(() => service.rawMessage({ ...compose, subject: 'Hello\r\nBcc: evil@example.com' }), /one line/);
});
test('natural-language search sends only the user request and date context to Gemini', async t => {
  const service = new GoogleService(fixture(), () => {}); let sent: any;
  t.mock.method(globalThis, 'fetch', async (_url: string, options: any) => { sent = JSON.parse(options.body); return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"query":"from:Acme invoice after:2026/09/01 before:2026/10/01"}' }] } }] }), { status: 200 }); });
  const result = await service.searchQuery('find invoices from Acme last month'); assert.match(result, /from:Acme/); assert.equal(sent.contents[0].parts[0].text, 'find invoices from Acme last month'); assert(!JSON.stringify(sent).includes('a@example.com')); assert(!JSON.stringify(sent).includes('token'));
});
test('calendar creation has no inferred attendees and validates time bounds', async () => {
  const service = new GoogleService(fixture(), () => {}); let body: any; let url = '';
  service.request = async (_id: string, u: string, _method: string, b: any) => { body = b; url = u; return { id: 'created' }; };
  const e = { id: '', title: 'Review email', accountId: 'a', calendarId: 'cal@example.com', start: '2026-10-07T13:00:00Z', end: '2026-10-07T14:00:00Z', description: 'Source email', location: '' };
  assert.equal((await service.saveEvent(e)).id, 'created'); assert(!('attendees' in body)); assert.match(url, /sendUpdates=none/); await assert.rejects(() => service.saveEvent({ ...e, end: e.start }), /end time/);
});
test('forwarded and draft attachments resolve their actual bytes', async () => {
  const service = new GoogleService(fixture(), () => {});
  service.getMessage = async () => ({ attachments: [{ id: 'inline', name: 'one.txt', data: 'YWJj', size: 3 }, { id: 'remote', name: 'two.txt', size: 3 }] });
  let requested = '';
  service.request = async (_id: string, url: string) => { requested = url; return { data: 'ZGVm' }; };
  const attachments = await service.materializeAttachments({ accountId: 'a', id: 'message' });
  assert.equal(attachments[0].data, 'YWJj'); assert.equal(attachments[1].data, 'ZGVm'); assert.match(requested, /messages\/message\/attachments\/remote$/);
});
test('OAuth loopback validates state and exchanges a PKCE verifier matching the challenge', async t => {
  const realFetch = globalThis.fetch; let challenge = ''; let tokenBody: URLSearchParams | undefined;
  t.mock.method(globalThis, 'fetch', async (url: string, options?: any) => {
    if (String(url).startsWith('http://127.0.0.1')) return realFetch(url, options);
    if (url.includes('/token')) { tokenBody = options.body; return new Response(JSON.stringify({ access_token: 'fake', refresh_token: 'fake-refresh', expires_in: 3600 }), { status: 200 }); }
    return new Response(JSON.stringify({ sub: 'google-id', email: 'me@example.com', name: 'Me' }), { status: 200 });
  });
  const account = await connectGoogle({ clientId: 'fake.apps.googleusercontent.com' }, async (url: string) => {
    const auth = new URL(url); challenge = auth.searchParams.get('code_challenge')!; const redirect = auth.searchParams.get('redirect_uri')!;
    const wrong = await fetch(`${redirect}?code=fake-code&state=wrong`); assert.equal(wrong.status, 400);
    const valid = await fetch(`${redirect}?code=fake-code&state=${auth.searchParams.get('state')}`); assert.equal(valid.status, 200);
  });
  assert.equal(account.email, 'me@example.com'); assert.equal(tokenBody?.get('code'), 'fake-code'); assert.equal(createHash('sha256').update(tokenBody!.get('code_verifier')!).digest('base64url'), challenge);
});
