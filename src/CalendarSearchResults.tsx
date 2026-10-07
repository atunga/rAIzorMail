import { CalendarDays, Loader2 } from 'lucide-react';
import type { Calendar, CalendarEvent, CalendarResults, CalendarSearch } from './types';
export function CalendarSearchResults({ search, results, calendars, busy, onMore, onClear, onEdit }: { search: CalendarSearch; results: CalendarResults; calendars: Calendar[]; busy: boolean; onMore: () => void; onClear: () => void; onEdit: (event: CalendarEvent) => void }) {
  return <section className="calendar-results"><div className="search-summary"><CalendarDays size={16}/><span>{search.query || 'All events'} · {new Date(search.start).toLocaleDateString()} – {new Date(new Date(search.end).getTime() - 1).toLocaleDateString()}<small>Search ends at {new Date(search.end).toLocaleString()} (exclusive).</small></span><button onClick={onClear}>Back to calendar</button></div>
    {!!results.errors?.length && <div className="warning-banner" role="alert">{results.errors.join(' ')}</div>}
    <div className="calendar-result-list">{results.events.map(event => <button className="calendar-result" key={JSON.stringify([event.accountId, event.calendarId, event.id])} onClick={() => onEdit(event)}><CalendarDays size={20}/><span><strong>{event.title}</strong><small>{event.allDay ? `${event.start} · All day` : new Date(event.start).toLocaleString()} · {calendars.find(c => c.id === event.calendarId && c.accountId === event.accountId)?.name || 'Calendar'}</small>{event.location && <small>{event.location}</small>}</span></button>)}
    {!results.events.length && <div className="empty-state">{busy ? <Loader2 className="spin"/> : <CalendarDays/>}<h2>{busy ? 'Searching calendars…' : 'No matching events'}</h2><p>Try a different name or date range.</p></div>}
    {Object.keys(results.nextPageTokens).length > 0 && <button className="load-more" disabled={busy} onClick={onMore}>{busy ? 'Loading…' : 'Load more events'}</button>}</div>
  </section>;
}
