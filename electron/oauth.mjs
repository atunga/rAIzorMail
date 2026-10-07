import http from 'node:http';
import { randomBytes, createHash } from 'node:crypto';
const SCOPES = ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/gmail.modify', 'https://www.googleapis.com/auth/calendar.events', 'https://www.googleapis.com/auth/calendar.calendarlist.readonly'];
export async function connectGoogle(config, openExternal) {
  if (!config.clientId) throw new Error('Import your Google Desktop OAuth credentials in Settings first.');
  const state = randomBytes(32).toString('base64url');
  const verifier = randomBytes(48).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  const server = http.createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const redirect = `http://127.0.0.1:${server.address().port}/oauth/callback`;
  try {
    const codePromise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Google sign-in timed out. Please try again.')), 180000);
      server.on('close', () => clearTimeout(timer));
      server.on('request', (req, res) => {
        const url = new URL(req.url, redirect);
        if (url.pathname !== '/oauth/callback') { res.writeHead(404); res.end(); return; }
        if (url.searchParams.get('state') !== state) { res.writeHead(400); res.end('Invalid sign-in request.'); return; }
        clearTimeout(timer);
        const error = url.searchParams.get('error'); const code = url.searchParams.get('code');
        res.writeHead(error || !code ? 400 : 200, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'" });
        res.end(`<html><body style="background:#20211e;color:#e7e2c9;font:18px system-ui;padding:60px"><h1>rAIzorMail</h1><p>${error || !code ? 'Sign-in was cancelled. Return to rAIzorMail to try again.' : 'Google sign-in received. You can return to rAIzorMail.'}</p></body></html>`);
        if (error || !code) reject(new Error('Google sign-in was cancelled.')); else resolve(code);
      });
    });
    const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    url.search = new URLSearchParams({ client_id: config.clientId, redirect_uri: redirect, response_type: 'code', scope: SCOPES.join(' '), access_type: 'offline', prompt: 'consent select_account', state, code_challenge: challenge, code_challenge_method: 'S256' }).toString();
    // Attach rejection handling before opening the system browser.
    const openPromise = openExternal(url.toString());
    const [code] = await Promise.all([codePromise, openPromise]);
    const tokens = await tokenRequest({ code, client_id: config.clientId, ...(config.clientSecret ? { client_secret: config.clientSecret } : {}), code_verifier: verifier, redirect_uri: redirect, grant_type: 'authorization_code' });
    const userRes = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: `Bearer ${tokens.access_token}` }, signal: AbortSignal.timeout(20000) });
    if (!userRes.ok) throw new Error('Google account details could not be loaded.');
    const profile = await userRes.json();
    return { id: profile.sub, email: profile.email, name: profile.name || profile.email, tokens: { ...tokens, expiresAt: Date.now() + tokens.expires_in * 1000 } };
  } finally { server.close(); server.closeAllConnections(); }
}
export async function tokenRequest(params) {
  const res = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', body: new URLSearchParams(params), signal: AbortSignal.timeout(20000) });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error === 'invalid_grant' ? 'Google sign-in expired. Reconnect this account in Settings.' : 'Google sign-in failed. Check your Desktop OAuth credentials and try again.');
  return data;
}
