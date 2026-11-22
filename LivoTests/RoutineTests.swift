import XCTest
import SwiftData
@testable import Livo

final class RoutineTests: XCTestCase {
    private let cal = Calendar.ptBR

    private func day(_ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func habit(_ ctx: ModelContext, _ f: HabitFrequency = .diaria, target: Int = 1, checkIns: [Date]) -> Habit {
        let h = Habit(name: "Teste", frequency: f, targetPerPeriod: target)
        ctx.insert(h)
        for d in checkIns {
            let c = HabitCheckIn(date: d)
            ctx.insert(c)
            c.habit = h
        }
        return h
    }

    @MainActor
    func testDailyStreakTodayInProgressDoesNotBreak() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let h = habit(ctx, checkIns: [day(3, 8), day(3, 9)])
        try ctx.save()
        XCTAssertEqual(RoutineLogic.streak(h, asOf: day(3, 10)), 2)
        XCTAssertEqual(RoutineLogic.streak(h, asOf: day(3, 9)), 2)
        XCTAssertEqual(RoutineLogic.streak(h, asOf: day(3, 11)), 0) // missed the 10th
    }

    @MainActor
    func testBestStreakAndGap() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let h = habit(ctx, checkIns: [day(3, 1), day(3, 2), day(3, 3), day(3, 5), day(3, 6)])
        try ctx.save()
        XCTAssertEqual(RoutineLogic.bestStreak(h, asOf: day(3, 6)), 3)
        XCTAssertEqual(RoutineLogic.streak(h, asOf: day(3, 6)), 2)
    }

    @MainActor
    func testWeeklyTarget() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Two check-ins in the week of Mar 8–14 2026, one in the following week.
        let h = habit(ctx, .semanal, target: 2, checkIns: [day(3, 9), day(3, 11), day(3, 16)])
        try ctx.save()
        XCTAssertTrue(RoutineLogic.isComplete(h, at: day(3, 12)))
        XCTAssertFalse(RoutineLogic.isComplete(h, at: day(3, 17)))
        XCTAssertEqual(RoutineLogic.streak(h, asOf: day(3, 17)), 1)
    }

    @MainActor
    func testTapCheckInTogglesAtTarget() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let h = habit(ctx, checkIns: [])
        RoutineStore.tapCheckIn(h, at: day(4, 1), in: ctx)
        try ctx.save()
        XCTAssertTrue(RoutineLogic.isComplete(h, at: day(4, 1)))
        RoutineStore.tapCheckIn(h, at: day(4, 1, hour: 18), in: ctx)
        try ctx.save()
        XCTAssertFalse(RoutineLogic.isComplete(h, at: day(4, 1)))
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<HabitCheckIn>()), 0)
    }

    @MainActor
    func testGoalProgress() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let g = Goal(title: "Ler")
        ctx.insert(g)
        XCTAssertEqual(RoutineLogic.progress(g), 0)
        for (i, done) in [true, false, false].enumerated() {
            let s = GoalStep(title: "Etapa \(i)", order: i)
            ctx.insert(s)
            s.goal = g
            s.done = done
        }
        let t = TaskItem(title: "Tarefa")
        ctx.insert(t)
        t.goal = g
        t.done = true
        try ctx.save()
        XCTAssertEqual(RoutineLogic.progress(g), 0.5, accuracy: 0.0001)

        g.targetValue = 10
        g.currentValue = 2.5
        XCTAssertEqual(RoutineLogic.progress(g), 0.25, accuracy: 0.0001)
        g.completed = true
        XCTAssertEqual(RoutineLogic.progress(g), 1)
    }

    @MainActor
    func testTaskOrderingAndToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = day(5, 10)
        let undated = TaskItem(title: "Sem data", priority: .alta)
        let late = TaskItem(title: "Atrasada", due: cal.startOfDay(for: day(5, 8)))
        let todayLow = TaskItem(title: "Hoje baixa", due: cal.startOfDay(for: now), priority: .baixa)
        let todayHigh = TaskItem(title: "Hoje alta", due: cal.startOfDay(for: now), priority: .alta)
        let later = TaskItem(title: "Depois", due: cal.startOfDay(for: day(5, 20)))
        for t in [undated, late, todayLow, todayHigh, later] { ctx.insert(t) }

        let order = RoutineLogic.sorted([undated, later, todayLow, late, todayHigh]).map(\.title)
        XCTAssertEqual(order, ["Atrasada", "Hoje alta", "Hoje baixa", "Depois", "Sem data"])
        XCTAssertTrue(RoutineLogic.isOverdue(late, now: now))
        XCTAssertTrue(RoutineLogic.isForToday(todayLow, now: now))
        XCTAssertFalse(RoutineLogic.isForToday(later, now: now))
        XCTAssertFalse(RoutineLogic.isForToday(undated, now: now))
        RoutineStore.toggle(late)
        XCTAssertFalse(RoutineLogic.isOverdue(late, now: now))
        XCTAssertNotNil(late.doneAt)
    }

    func testParseNumber() {
        XCTAssertEqual(parseNumber("1.234,5"), 1234.5)
        XCTAssertEqual(parseNumber("10"), 10)
        XCTAssertNil(parseNumber("abc"))
    }
}
