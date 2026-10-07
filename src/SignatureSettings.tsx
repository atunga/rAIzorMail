import { useEffect, useState } from 'react';
import type { Account, MailAPI, Signature } from './types';
import { emptySignature } from './compose';
export function SignatureSettings({ accounts, api, onError }: { accounts: Account[]; api: MailAPI; onError: (e: unknown) => void }) {
  const [accountId, setAccountId] = useState(accounts[0]?.id || '');
  const [signatures, setSignatures] = useState<Record<string, Signature>>({});
  const [loading, setLoading] = useState(true); const [busy, setBusy] = useState(false); const [saved, setSaved] = useState(false);
  useEffect(() => { let alive = true; setLoading(true); api.getSignatures().then(value => { if (alive) setSignatures(value); }).catch(onError).finally(() => { if (alive) setLoading(false); }); return () => { alive = false; }; }, [api, onError]);
  useEffect(() => { if (!accounts.some(a => a.id === accountId)) setAccountId(accounts[0]?.id || ''); }, [accounts, accountId]);
  const signature = signatures[accountId] || emptySignature;
  function change(value: Partial<Signature>) { setSaved(false); setSignatures(previous => ({ ...previous, [accountId]: { ...signature, ...value } })); }
  async function save() { setBusy(true); try { await api.saveSignature({ accountId, signature }); setSaved(true); } catch (error) { onError(error); } finally { setBusy(false); } }
  return <section className="signature-settings"><h3>Email signatures</h3><p>Create a signature for each account. Signatures use plain text and are saved in rAIzorMail on this Mac.</p>
    {!accounts.length ? <p>Connect a Google account to create a signature.</p> : <>
      <label>Signature account<select value={accountId} disabled={busy || loading} onChange={e => { setAccountId(e.target.value); setSaved(false); }}>{accounts.map(account => <option key={account.id} value={account.id}>{account.email}</option>)}</select></label>
      <label>Signature text<textarea rows={6} maxLength={10000} value={signature.text} disabled={busy || loading} onChange={e => change({ text: e.target.value })} placeholder={'Your name\nTitle · Company\nPhone · Website'}/></label>
      <div className="signature-defaults"><label><input type="checkbox" checked={signature.newMessages} disabled={busy || loading} onChange={e => change({ newMessages: e.target.checked })}/>Add to new messages</label><label><input type="checkbox" checked={signature.replies} disabled={busy || loading} onChange={e => change({ replies: e.target.checked })}/>Add to replies and forwards</label></div>
      <div className="signature-preview"><small>Preview</small><pre>{signature.text.trim() || 'Your signature will appear here.'}</pre></div>
      <div className="setting-actions"><button type="button" className="secondary" disabled={busy || loading} onClick={() => void save()}>{busy ? 'Saving…' : saved ? 'Signature saved' : 'Save signature'}</button><button type="button" className="text-button" disabled={busy || loading} onClick={() => { const account = accounts.find(a => a.id === accountId); change({ text: `${account?.name || ''}\n${account?.email || ''}` }); }}>Start with my name and email</button></div>
      <p className="form-hint">Save an empty signature to remove it. Existing drafts keep their original text.</p>
    </>}
  </section>;
}
