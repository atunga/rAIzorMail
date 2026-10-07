import type { Compose, Signature } from './types';
export const emptySignature: Signature = { text: '', newMessages: true, replies: false };
export function composeChanged(before: Compose, after: Compose) {
  return (['accountId', 'to', 'cc', 'bcc', 'subject', 'text'] as const).some(key => before[key] !== after[key]) ||
    before.attachments.length !== after.attachments.length || before.attachments.some((file, i) => file.id !== after.attachments[i]?.id);
}
export function signatureBlock(signature?: Signature) { return signature?.text.trim() ? `\n\n-- \n${signature.text.trim()}` : ''; }
export function initialSignature(compose: Compose, signature?: Signature) {
  if (compose.draftId || !signature || !(compose.threadId || /^(re|fwd):/i.test(compose.subject) ? signature.replies : signature.newMessages)) return '';
  return signatureBlock(signature);
}
// Replace only the untouched signature we inserted, never edited text or quoted mail.
export function replaceSignature(text: string, previous: string, next: string) {
  const quote = text.indexOf('\n\nOn ');
  const body = quote >= 0 ? text.slice(0, quote) : text;
  const quoted = quote >= 0 ? text.slice(quote) : '';
  if (previous && body.includes(previous)) return body.replace(previous, next) + quoted;
  if (previous || !next || body.includes(next)) return text;
  return body + next + quoted;
}
