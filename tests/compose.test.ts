import { test } from 'node:test';
import assert from 'node:assert/strict';
import { composeChanged, initialSignature, replaceSignature, signatureBlock } from '../src/compose.ts';
import type { Compose } from '../src/types.ts';
const blank: Compose = { accountId: 'a', to: '', cc: '', bcc: '', subject: '', text: '', attachments: [] };
const signature = { text: 'Alex\nExample Company', newMessages: true, replies: false };
test('closing a composer distinguishes unchanged drafts from changed fields and attachments', () => {
  assert.equal(composeChanged(blank, { ...blank }), false);
  for (const field of ['accountId', 'to', 'cc', 'bcc', 'subject', 'text']) assert.equal(composeChanged(blank, { ...blank, [field]: 'changed' }), true);
  const attached = { ...blank, attachments: [{ id: 'file', name: 'test.txt', size: 1, mimeType: 'text/plain' }] };
  assert.equal(composeChanged(blank, attached), true);
  assert.equal(composeChanged(attached, blank), true);
  assert.equal(composeChanged({ ...blank, draftId: 'saved' }, { ...blank, draftId: 'saved' }), false);
});
test('signature defaults apply to new mail, opt-in replies, and never overwrite saved drafts', () => {
  assert.equal(initialSignature(blank, signature), signatureBlock(signature));
  assert.equal(initialSignature({ ...blank, threadId: 'reply' }, signature), '');
  assert.equal(initialSignature({ ...blank, subject: 'Fwd: Example' }, { ...signature, replies: true }), signatureBlock(signature));
  assert.equal(initialSignature({ ...blank, draftId: 'saved' }, signature), '');
  assert.equal(initialSignature(blank, { ...signature, newMessages: false }), '');
});
test('signature is inserted above quoted mail and account changes replace an untouched signature', () => {
  const first = signatureBlock(signature), second = signatureBlock({ ...signature, text: 'Personal' });
  const quote = '\n\nOn Monday, Alex wrote:\n> Earlier message';
  const composed = replaceSignature('Hello' + quote, '', first);
  assert.equal(composed, 'Hello' + first + quote);
  assert.equal(replaceSignature(composed, '', first), composed);
  assert.equal(replaceSignature(composed, first, second), 'Hello' + second + quote);
  assert.equal(replaceSignature(composed, first, ''), 'Hello' + quote);
  const edited = composed.replace('Example Company', 'Edited company');
  assert.equal(replaceSignature(edited, first, second), edited);
  assert.equal(replaceSignature(edited + first, first, second), edited + first, 'quoted signature is never replaced');
  assert.equal(replaceSignature('Hello' + quote + first, '', first), 'Hello' + first + quote + first, 'a signature in quoted text does not prevent our own signature');
});
