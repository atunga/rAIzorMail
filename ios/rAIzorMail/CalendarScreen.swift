import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject var model: MailModel
    @State private var day = Date()
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    TextField("Meetings with Acme next week…", text: $model.calendarSearchText).submitLabel(.search).onSubmit { Task { await model.searchCalendar() } }
                    Toggle("AI", isOn: $model.aiSearch).toggleStyle(.button)
                    Button { Task { await model.searchCalendar() } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search calendar")
                }.padding(.horizontal)
                DatePicker("Week of", selection: $day, displayedComponents: .date).padding(.horizontal)
                    .onChange(of: day) { _, date in
                        model.calendarStart = Calendar.current.startOfDay(for: date)
                        model.calendarEnd = Calendar.current.date(byAdding: .day, value: 7, to: model.calendarStart)!
                        model.calendarQuery = ""; model.calendarSearchText = ""
                        Task { await model.loadCalendar() }
                    }
                Text("\(model.calendarStart.formatted(date: .abbreviated, time: .omitted)) – \(model.calendarEnd.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                if let notice = model.calendarSyncError { Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                List {
                    ForEach(model.events) { event in
                        Button { model.eventEditor = event } label: {
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(Crest.orange).frame(width: 3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(event.start.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened)).font(.caption).foregroundStyle(Crest.sage)
                                    Text(event.title).font(.headline)
                                    Text(event.calendar.name).font(.caption).foregroundStyle(.secondary)
                                    if !event.location.isEmpty { Label(event.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
                                    if event.allDay { Text("All day").font(.caption) }
                                }
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain).listRowBackground(Crest.background)
                    }
                    if model.calendarLoading { ProgressView() }
                    else if model.events.isEmpty { ContentUnavailableView("Room in your day", systemImage: "calendar", description: Text("No events in this date range.")) }
                }.listStyle(.plain).scrollContentBackground(.hidden).refreshable { await model.reloadCalendars(); await model.loadCalendar() }
            }.background(Crest.background).navigationTitle("Calendar")
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { AccountMenu(); Button { Task { await model.newEvent() } } label: { Image(systemName: "plus") }.accessibilityLabel("New event") } }
            .task(id: model.selectedAccount + model.accounts.secrets.accounts.map(\.id).joined()) { await model.reloadCalendars(); await model.loadCalendar() }
        }
    }
}
struct EventScreen: View {
    @EnvironmentObject var model: MailModel
    @Environment(\.dismiss) var dismiss
    @State private var event: CalendarItem
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    init(initial: CalendarItem) { _event = State(initialValue: initial) }
    var readOnly: Bool { !event.calendar.writable || event.shared || event.recurring }
    var body: some View {
        NavigationStack {
            Form {
                if readOnly { Text("Shared and recurring events are read-only here. Manage invitations or the series in Google Calendar.").font(.caption) }
                Section {
                    TextField("Event title", text: $event.title)
                    if event.eventID.isEmpty {
                        Picker("Calendar", selection: $event.calendar) { ForEach(model.calendars.filter(\.writable)) { Text($0.name).tag($0) } }
                    } else { LabeledContent("Calendar", value: event.calendar.name) }
                    Toggle("All day", isOn: $event.allDay)
                    DatePicker("Starts", selection: $event.start, displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker(event.allDay ? "Ends (exclusive date)" : "Ends", selection: $event.end, displayedComponents: event.allDay ? [.date] : [.date, .hourAndMinute])
                    TextField("Location", text: $event.location)
                }.disabled(readOnly || busy)
                Section("Notes") { TextEditor(text: $event.notes).frame(minHeight: 180).disabled(readOnly || busy) }
                if !event.eventID.isEmpty && !readOnly { Button("Delete event", role: .destructive) { confirmDelete = true }.disabled(busy) }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(Crest.background)
            .navigationTitle(event.eventID.isEmpty ? "New event" : "Event").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) }
                if !readOnly { ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy || event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            }
            .interactiveDismissDisabled(busy)
            .confirmationDialog("Delete this event from Google Calendar?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete event", role: .destructive) { Task { busy = true; do { try await model.api.deleteEvent(event); dismiss(); await model.loadCalendar() } catch { self.error = error.localizedDescription }; busy = false } }
            }
        }
    }
    func save() async {
        busy = true; error = nil; defer { busy = false }
        do {
            if event.allDay { event.start = Calendar.current.startOfDay(for: event.start); event.end = Calendar.current.startOfDay(for: event.end) }
            try await model.api.saveEvent(event); dismiss(); await model.loadCalendar()
        } catch { self.error = error.localizedDescription }
    }
}
