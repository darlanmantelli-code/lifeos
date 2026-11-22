import Foundation
import SwiftData

enum RoutineLogic {
    static func period(of date: Date, _ f: HabitFrequency, calendar: Calendar = .ptBR) -> DateInterval {
        let component: Calendar.Component = switch f {
        case .diaria: .day
        case .semanal: .weekOfYear
        case .mensal: .month
        }
        return calendar.dateInterval(of: component, for: date)!
    }

    static func count(_ habit: Habit, in p: DateInterval) -> Int {
        (habit.checkIns ?? []).filter { $0.date >= p.start && $0.date < p.end }.count
    }

    static func isComplete(_ habit: Habit, at date: Date = .now, calendar: Calendar = .ptBR) -> Bool {
        count(habit, in: period(of: date, habit.frequency, calendar: calendar)) >= habit.target
    }

    private static func periodCounts(_ habit: Habit, _ calendar: Calendar) -> [Date: Int] {
        Dictionary(grouping: habit.checkIns ?? []) { period(of: $0.date, habit.frequency, calendar: calendar).start }
            .mapValues(\.count)
    }

    /// Consecutive complete periods up to `now`. The current period counts once complete;
    /// while still in progress it does not break the streak.
    static func streak(_ habit: Habit, asOf now: Date = .now, calendar: Calendar = .ptBR) -> Int {
        let counts = periodCounts(habit, calendar)
        var p = period(of: now, habit.frequency, calendar: calendar)
        var streak = (counts[p.start] ?? 0) >= habit.target ? 1 : 0
        while true {
            p = period(of: p.start.addingTimeInterval(-1), habit.frequency, calendar: calendar)
            guard (counts[p.start] ?? 0) >= habit.target else { break }
            streak += 1
        }
        return streak
    }

    static func bestStreak(_ habit: Habit, asOf now: Date = .now, calendar: Calendar = .ptBR) -> Int {
        guard let first = (habit.checkIns ?? []).map(\.date).min() else { return 0 }
        let counts = periodCounts(habit, calendar)
        let end = period(of: now, habit.frequency, calendar: calendar).end
        var p = period(of: first, habit.frequency, calendar: calendar)
        var best = 0, current = 0
        while p.start < end {
            if (counts[p.start] ?? 0) >= habit.target {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
            p = period(of: p.end, habit.frequency, calendar: calendar)
        }
        return best
    }

    /// 0...1. Numeric target wins; otherwise done steps + done linked tasks over the total.
    static func progress(_ g: Goal) -> Double {
        if g.completed { return 1 }
        if let target = g.targetValue, target > 0 {
            return min(max((g.currentValue ?? 0) / target, 0), 1)
        }
        let items = (g.steps ?? []).map(\.done) + (g.tasks ?? []).map(\.done)
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0 }.count) / Double(items.count)
    }

    /// Dated before undated; earlier day first; then higher priority; then oldest.
    static func sorted(_ tasks: [TaskItem], calendar: Calendar = .ptBR) -> [TaskItem] {
        tasks.sorted { a, b in
            switch (a.due, b.due) {
            case (nil, .some): return false
            case (.some, nil): return true
            case let (.some(da), .some(db)) where !calendar.isDate(da, inSameDayAs: db): return da < db
            default: break
            }
            if a.priorityRaw != b.priorityRaw { return a.priorityRaw > b.priorityRaw }
            return a.createdAt < b.createdAt
        }
    }

    static func isOverdue(_ t: TaskItem, now: Date = .now, calendar: Calendar = .ptBR) -> Bool {
        guard !t.done, let due = t.due else { return false }
        return due < calendar.startOfDay(for: now)
    }

    /// Pending tasks due today or overdue.
    static func isForToday(_ t: TaskItem, now: Date = .now, calendar: Calendar = .ptBR) -> Bool {
        guard !t.done, let due = t.due else { return false }
        return isOverdue(t, now: now, calendar: calendar) || calendar.isDate(due, inSameDayAs: now)
    }

    static func dueLabel(_ due: Date, now: Date = .now, calendar: Calendar = .ptBR) -> String {
        if calendar.isDate(due, inSameDayAs: now) { return "Hoje" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            return "Amanhã"
        }
        let text = due.formatted(.dateTime.day().month(.abbreviated).locale(.ptBR))
        return due < calendar.startOfDay(for: now) ? "Atrasada · \(text)" : text
    }
}

@MainActor
enum RoutineStore {
    /// Tap adds a check-in until the period target is met; tapping a complete habit undoes the last one.
    static func tapCheckIn(_ habit: Habit, at date: Date = .now, in ctx: ModelContext) {
        let p = RoutineLogic.period(of: date, habit.frequency)
        let inPeriod = (habit.checkIns ?? []).filter { $0.date >= p.start && $0.date < p.end }.sorted { $0.date < $1.date }
        if inPeriod.count >= habit.target, let last = inPeriod.last {
            habit.checkIns?.removeAll { $0 == last }
            ctx.delete(last)
        } else {
            let c = HabitCheckIn(date: date)
            ctx.insert(c)
            c.habit = habit
        }
    }

    static func toggle(_ task: TaskItem) {
        task.done.toggle()
        task.doneAt = task.done ? .now : nil
    }
}
