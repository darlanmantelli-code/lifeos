import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotWriter {
    /// Facts from the real store for the widget. Demo data is never written.
    static func make(_ ctx: ModelContext, now: Date = .now) -> WidgetSnapshot {
        let accounts = ((try? ctx.fetch(FetchDescriptor<Account>())) ?? []).filter { !$0.archived }
        let month = MonthKey.interval(of: now)
        let txns = ((try? ctx.fetch(FetchDescriptor<FinanceTransaction>())) ?? []).filter { $0.date >= month.start && $0.date <= now }
        let tasks = RoutineLogic.sorted(((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { RoutineLogic.isForToday($0, now: now) })
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? []).filter { !$0.archived }
        let water = ((try? ctx.fetch(FetchDescriptor<HealthEntry>())) ?? []).filter { $0.kind == .agua }
        let waterTarget = ((try? ctx.fetch(FetchDescriptor<HealthTarget>())) ?? []).first { $0.kindRaw == HealthKind.agua.rawValue }?.value
        return WidgetSnapshot(
            updatedAt: now,
            balanceCents: accounts.isEmpty ? nil : accounts.reduce(Int64(0)) { $0 + FinanceLogic.balance(of: $1, at: now) },
            monthExpenseCents: FinanceLogic.summary(txns).expense,
            tasksToday: tasks.count,
            nextTask: tasks.first?.title,
            habitsPending: habits.filter { !RoutineLogic.isComplete($0, at: now) }.count,
            habitsTotal: habits.count,
            waterMl: HealthLogic.current(water, .agua, now: now)?.value,
            waterTargetMl: waterTarget)
    }

    static func refresh() {
        guard !DemoMode.isOn, make(SharedStore.real.mainContext).save() else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
