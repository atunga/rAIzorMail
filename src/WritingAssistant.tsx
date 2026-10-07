import { useState } from 'react';
import { Loader2, Sparkles } from 'lucide-react';
import type { Compose, MailAPI, WritingResult } from './types';
import { splitWritingText } from './ai';
export function WritingAssistant({ draft, api, demo, onApply, onClose, onError }: { draft: Compose; api: MailAPI; demo: boolean; onApply: (result: WritingResult) => void; onClose: () => void; onError: (error: unknown) => void }) {
  const [instruction, setInstruction] = useState(''); const [context, setContext] = useState(false); const [busy, setBusy] = useState(false);
  const [suggestion, setSuggestion] = useState<{ result: WritingResult; subject: string; original: string } | null>(null);
  const [undo, setUndo] = useState<{ original: WritingResult; applied: WritingResult } | null>(null);
  const parts = splitWritingText(draft.text);
  const stale = suggestion && (suggestion.original !== draft.text || suggestion.subject !== draft.subject);
  async function generate(prompt = instruction) {
    if (busy || !prompt.trim()) return; setBusy(true); setSuggestion(null); setInstruction(prompt);
    const original = draft.text, subject = draft.subject;
    try { const result = await api.assistWriting({ instruction: prompt, subject, text: parts.text, ...(context && parts.context ? { context: parts.context } : {}) }); setSuggestion({ result: { subject: result.subject, text: result.text + parts.suffix }, original, subject }); }
    catch (error) { onError(error); } finally { setBusy(false); }
  }
  return <div className="writing-assistant"><div className="writing-heading"><strong><Sparkles size={15}/>{demo ? 'Writing help · demo' : 'Write with Gemini'}</strong><button type="button" className="text-button" onClick={onClose}>Close</button></div>
    <label>Writing instructions<textarea rows={2} value={instruction} onChange={e => setInstruction(e.target.value)} placeholder="Draft a friendly follow-up asking for an update on the proposal…" maxLength={3000}/></label>
    <div className="writing-actions">{['Make it shorter', 'Make it more professional', 'Make it friendlier', 'Fix spelling and grammar'].map(prompt => <button type="button" className="secondary" disabled={busy || !parts.text.trim()} key={prompt} onClick={() => void generate(prompt)}>{prompt}</button>)}</div>
    {!!parts.context && <label className="writing-context"><input type="checkbox" checked={context} onChange={e => setContext(e.target.checked)}/>Include quoted email for reply context</label>}
    <p className="form-hint">{demo ? 'Sample suggestions only; Gemini is not called in the demo.' : 'Gemini receives your instruction, subject and draft text. Quoted history is included only when selected. Attachments are not sent.'}</p>
    <button type="button" className="secondary" disabled={busy || !instruction.trim()} onClick={() => void generate()}>{busy ? <Loader2 size={14} className="spin"/> : <Sparkles size={14}/>} {busy ? 'Writing…' : 'Generate suggestion'}</button>
    {suggestion && <div className="writing-suggestion"><strong>Suggested email</strong><label>Suggested subject<input readOnly value={suggestion.result.subject}/></label><label>Suggested message<textarea rows={5} readOnly value={suggestion.result.text}/></label>{stale && <p className="form-hint">Your draft changed. Generate a fresh suggestion to keep those edits.</p>}<div className="writing-actions"><button type="button" className="primary" disabled={!!stale} onClick={() => { setUndo({ original: { subject: suggestion.subject, text: suggestion.original }, applied: suggestion.result }); onApply(suggestion.result); setSuggestion(null); }}>Use suggestion</button><button type="button" className="text-button" onClick={() => setSuggestion(null)}>Dismiss</button></div></div>}
    {undo && draft.subject === undo.applied.subject && draft.text === undo.applied.text && <button type="button" className="text-button" onClick={() => { onApply(undo.original); setUndo(null); }}>Undo AI changes</button>}
  </div>;
}
