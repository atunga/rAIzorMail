export const defaultModel = 'gemini-3.8-flash';
export function stringInput(value, name, limit, required = false) {
  if (typeof value !== 'string' || value.length > limit || (required && !value.trim())) throw new Error(`${name} must be ${required ? 'nonempty and ' : ''}under ${limit.toLocaleString()} characters.`);
  return value;
}
export async function generateJSON(config, instruction, input, properties, maxOutputTokens = 2048) {
  if (!config.geminiKey) throw new Error('Add your Gemini API key in Settings → Gemini AI to use this feature.');
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(config.geminiModel || defaultModel)}:generateContent`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': config.geminiKey },
    body: JSON.stringify({ systemInstruction: { parts: [{ text: instruction }] }, contents: [{ role: 'user', parts: [{ text: input }] }], generationConfig: { responseFormat: { text: { mimeType: 'APPLICATION_JSON', schema: { type: 'object', properties: Object.fromEntries(Object.entries(properties).map(([key, value]) => [key, { ...value, type: value.type.toLowerCase() }])), required: Object.keys(properties) } } }, maxOutputTokens } }), signal: AbortSignal.timeout(60000),
  });
  let data; try { data = await response.json(); } catch { throw new Error('Gemini returned an unreadable response. Please try again.'); }
  if (!response.ok) {
    if (response.status === 429) throw new Error('Gemini is at its request limit. Wait a little and try again, or check your API quota in Google AI Studio.');
    if ([401, 403].includes(response.status)) throw new Error('Gemini could not authorize this request. Check your API key and project access in Settings.');
    if (response.status === 404) throw new Error('This Gemini model is unavailable for your key. Choose an available model in Settings.');
    throw new Error(`Gemini request failed (${response.status}). Please try again.`);
  }
  const candidate = data.candidates?.[0];
  if (data.promptFeedback?.blockReason || !candidate || (candidate.finishReason && candidate.finishReason !== 'STOP')) throw new Error('Gemini could not complete this request. Try a shorter or more specific instruction.');
  let value; try { value = JSON.parse(candidate.content?.parts?.filter(p => !p.thought).map(p => p.text || '').join('') || '{}'); } catch { throw new Error('Gemini returned an invalid result. Please try again.'); }
  for (const key of Object.keys(properties)) if (typeof value?.[key] !== 'string') throw new Error('Gemini returned an incomplete result. Please try again.');
  return value;
}
export function dateContext() { return `Today is ${new Date().toLocaleDateString('en-CA')}. Time zone: ${Intl.DateTimeFormat().resolvedOptions().timeZone}. Current instant: ${new Date().toISOString()}.`; }
export function calendarRange(input) {
  stringInput(input?.query, 'Calendar keywords', 4000);
  for (const field of ['start', 'end']) if (typeof input[field] !== 'string' || !/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(input[field]) || !Number.isFinite(Date.parse(input[field]))) throw new Error('Calendar search needs valid start and end dates with a time zone.');
  const duration = Date.parse(input.end) - Date.parse(input.start);
  if (duration <= 0 || duration > 3660 * 86400000) throw new Error('Choose a calendar search range of up to ten years, with the end after the start.');
  return { query: input.query.trim(), start: new Date(input.start).toISOString(), end: new Date(input.end).toISOString() };
}
