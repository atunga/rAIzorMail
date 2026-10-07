// Shared by every window. Budget below Gmail's 6,000 units/user/minute limit.
export class RequestBudget {
  constructor(now = Date.now, sleep = ms => new Promise(resolve => setTimeout(resolve, ms))) { this.now = now; this.sleep = sleep; this.accounts = new Map(); }
  state(id) { if (!this.accounts.has(id)) this.accounts.set(id, { next: 0, blocked: 0 }); return this.accounts.get(id); }
  async take(id, cost) {
    const state = this.state(id);
    if (state.blocked > this.now()) throw new Error('Gmail is temporarily limiting requests. Your messages are kept here; syncing will retry automatically shortly.');
    const start = Math.max(this.now(), state.next); state.next = start + cost * 12.5;
    if (start > this.now()) await this.sleep(start - this.now());
    if (state.blocked > this.now()) throw new Error('Gmail is temporarily limiting requests. Your messages are kept here; syncing will retry automatically shortly.');
  }
  pause(id, retryAfter) {
    const seconds = Number(retryAfter);
    const delay = retryAfter && Number.isFinite(seconds) ? seconds * 1000 : retryAfter ? Date.parse(retryAfter) - this.now() : 60000;
    const state = this.state(id); state.blocked = this.now() + Math.max(1000, Number.isFinite(delay) ? delay : 60000); state.next = state.blocked;
  }
}
export function gmailCost(url, method) {
  const path = new URL(url).pathname;
  if (/\/send$/.test(path)) return 100;
  if (/\/attachments\//.test(path) || /\/trash$/.test(path)) return 20;
  if (/\/messages\/[^/]+$/.test(path) && method === 'GET') return 20;
  if (/\/labels(?:\/[^/]+)?$/.test(path) && method === 'GET') return 1;
  return 20; // Conservative allowance for all remaining operations.
}
