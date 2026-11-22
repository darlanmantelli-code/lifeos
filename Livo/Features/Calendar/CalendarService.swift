import Foundation
import SwiftUI
import EventKit

/// A calendar event copied out of EventKit (events are read live, never stored by the app).
struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let isAllDay: Bool
    let color: Color
}

/// Apple Calendar (read) and Reminders (write, on request). Permission is asked only when the user taps to connect.
@MainActor
enum CalendarService {
    private static let store = EKEventStore()

    static var eventsAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    static var remindersAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    static func requestEvents() async -> Bool {
        await withCheckedContinuation { c in
            store.requestFullAccessToEvents { @Sendable granted, _ in c.resume(returning: granted) }
        }
    }

    static func requestReminders() async -> Bool {
        await withCheckedContinuation { c in
            store.requestFullAccessToReminders { @Sendable granted, _ in c.resume(returning: granted) }
        }
    }

    /// Events from now until `days` ahead, soonest first. Empty without permission.
    static func upcoming(days: Int = 7, now: Date = .now) -> [AgendaEvent] {
        guard eventsAuthorized, let end = Calendar.ptBR.date(byAdding: .day, value: days, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                AgendaEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "|\(e.startDate.timeIntervalSince1970)",
                            title: e.title ?? "Compromisso", start: e.startDate, isAllDay: e.isAllDay,
                            color: e.calendar.map { Color(cgColor: $0.cgColor) } ?? .lifeAccent)
            }
    }

    static func sendToReminders(_ task: TaskItem) async throws {
        guard remindersAuthorized || (await requestReminders()) else {
            throw AssistantTools.ToolError(message: "Sem acesso aos Lembretes. Libere em Ajustes › livo.")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = task.title
        reminder.notes = task.notes.isEmpty ? nil : task.notes
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = task.due { reminder.dueDateComponents = Calendar.ptBR.dateComponents([.year, .month, .day], from: due) }
        reminder.priority = task.priority == .alta ? 1 : task.priority == .baixa ? 9 : 5
        try store.save(reminder, commit: true)
    }
}
