export function defaultCalendarRange() {
  const start = new Date(); start.setFullYear(start.getFullYear() - 1); start.setHours(0, 0, 0, 0);
  const end = new Date(); end.setFullYear(end.getFullYear() + 1); end.setHours(0, 0, 0, 0);
  return { start: start.toISOString(), end: end.toISOString() };
}
export function splitWritingText(text: string) {
  const quoteAt = text.indexOf('\n\nOn ');
  const signatureAt = text.indexOf('\n\n-- \n');
  const cuts = [quoteAt, signatureAt].filter(index => index >= 0);
  const split = cuts.length ? Math.min(...cuts) : text.length;
  return { text: text.slice(0, split), suffix: text.slice(split), context: quoteAt >= 0 ? text.slice(quoteAt) : '' };
}
