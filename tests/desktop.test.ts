import { test } from 'node:test';
import assert from 'node:assert/strict';
import { messageBounds } from '../electron/window-position.mjs';
import { readAttachments, attachmentLimit } from '../src/attachments.ts';

test('message windows center on the mailbox display, including negative monitor coordinates', () => {
  assert.deepEqual(messageBounds({ x: 2100, y: 100, width: 1200, height: 900 }, { x: 1920, y: 25, width: 1920, height: 1055 }), { x: 2250, y: 150, width: 900, height: 800 });
  assert.deepEqual(messageBounds({ x: -1800, y: 100, width: 1200, height: 900 }, { x: -1920, y: 25, width: 1920, height: 1055 }), { x: -1650, y: 150, width: 900, height: 800 });
});
test('message placement respects display edges and the menu bar / dock work area', () => {
  assert.deepEqual(messageBounds({ x: -300, y: -100, width: 1000, height: 960 }, { x: 0, y: 30, width: 1280, height: 690 }), { x: 0, y: 30, width: 900, height: 690 });
  assert.deepEqual(messageBounds({ x: 900, y: 600, width: 1000, height: 960 }, { x: 0, y: 30, width: 1280, height: 690 }), { x: 380, y: 30, width: 900, height: 690 });
});
test('multiple dropped attachments preserve names, binary bytes and MIME types', async () => {
  const files = [new File(['Hello — world'], 'notes.txt', { type: 'text/plain' }), new File([new Uint8Array([0, 128, 255])], 'binary.dat')];
  const attachments = await readAttachments(files, 0);
  assert.deepEqual(attachments.map(a => a.name), ['notes.txt', 'binary.dat']);
  assert.equal(Buffer.from(attachments[0].data!, 'base64').toString(), 'Hello — world');
  assert.deepEqual([...Buffer.from(attachments[1].data!, 'base64')], [0, 128, 255]);
  assert.equal(attachments[0].mimeType, 'text/plain');
  assert.equal(attachments[1].mimeType, 'application/octet-stream');
  assert.notEqual(attachments[0].id, attachments[1].id);
});
test('attachment size includes existing files; unreadable files reject the entire batch', async () => {
  await assert.rejects(readAttachments([new File(['xx'], 'too-big.txt')], attachmentLimit - 1), /18 MB/);
  const badFile = new File([''], 'unreadable.txt'); badFile.arrayBuffer = async () => { throw new Error('Denied'); };
  await assert.rejects(readAttachments([new File(['ok'], 'good.txt'), badFile], 0), /Could not read unreadable.txt/);
});
