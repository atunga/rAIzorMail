import type { MailAPI } from './types';
import { demoAPI } from './demo';
export const liveAPI = new Proxy({} as MailAPI, { get: (_, method: string) => (input?: unknown, second?: unknown) => {
  if (!window.desktop) throw new Error('Connect your Google account in the rAIzorMail Mac app.');
  return window.desktop.invoke(method, second === undefined ? input : [input, second]);
} });
export function getAPI(demo: boolean) { return demo ? demoAPI : liveAPI; }
