import XCTest
import SwiftData
@testable import Livo

final class AutomationTests: XCTestCase {
    private let cal = Calendar.ptBR

    private func day(_ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    func testInvoiceRuleFiresOncePerMonthAndCanCreateTask() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let card = Account(name: "Cartão X", kind: .cartao)
        ctx.insert(card)
        card.dueDay = 17
        let rule = AutomationRule(trigger: .faturaProxima, action: .tarefa) // default: 3 days
        ctx.insert(rule)

        XCTAssertTrue(AutomationEngine.firings(for: rule, in: ctx, now: day(3, 10)).isEmpty) // 7 days away
        XCTAssertEqual(AutomationEngine.firings(for: rule, in: ctx, now: day(3, 15)).count, 1)

        let fired = await AutomationEngine.run(in: ctx, now: day(3, 15), notify: { _ in XCTFail("no notifications for task action"); return false })
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TaskItem>()).first?.priority, .alta)
        // Same occurrence the next day: already handled.
        let again = await AutomationEngine.run(in: ctx, now: day(3, 16))
        XCTAssertEqual(again, 0)
        // Next month's invoice is a new occurrence.
        XCTAssertEqual(AutomationEngine.firings(for: rule, in: ctx, now: day(4, 15)).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AutomationRun>()).count, 1)
    }

    @MainActor
    func testBudgetGoalAndOverdueRules() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = day(5, 20)
        let conta = Account(name: "Conta", kind: .corrente)
        let food = FinanceCategory(name: "Alimentação", kind: .despesa)
        ctx.insert(conta)
        ctx.insert(food)
        FinanceStore.setBudget(10_000, for: food, from: "2026-05", in: ctx)
        FinanceStore.insert(.init(kind: .despesa, amountCents: 7_900, title: "Mercado", date: day(5, 3), account: conta, category: food), in: ctx)
        let goal = Goal(title: "Correr 5 km")
        ctx.insert(goal)
        goal.completed = true
        ctx.insert(TaskItem(title: "Atrasada", due: cal.startOfDay(for: day(5, 1))))
        try ctx.save()

        let budget80 = AutomationRule(trigger: .orcamentoPercentual)
        XCTAssertTrue(AutomationEngine.firings(for: budget80, in: ctx, now: now).isEmpty) // 79%
        budget80.parameter = 75
        XCTAssertEqual(AutomationEngine.firings(for: budget80, in: ctx, now: now).first?.body.hasPrefix("79%"), true)

        XCTAssertEqual(AutomationEngine.firings(for: AutomationRule(trigger: .metaAlcancada), in: ctx, now: now).count, 1)
        XCTAssertEqual(AutomationEngine.firings(for: AutomationRule(trigger: .tarefaAtrasada), in: ctx, now: now).first?.body, "Atrasada")
    }

    @MainActor
    func testWeeklySummaryOnlySundayAfterHour() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = AutomationRule(trigger: .resumoSemanal) // 18h
        // 2026-05-17 is a Sunday.
        XCTAssertTrue(AutomationEngine.firings(for: rule, in: ctx, now: day(5, 17, hour: 10)).isEmpty)
        XCTAssertEqual(AutomationEngine.firings(for: rule, in: ctx, now: day(5, 17, hour: 19)).count, 1)
        XCTAssertTrue(AutomationEngine.firings(for: rule, in: ctx, now: day(5, 18, hour: 19)).isEmpty)
    }

    func testFiredKeysAreCapped() {
        let rule = AutomationRule(trigger: .tarefaAtrasada)
        for i in 0..<250 { rule.markFired("k\(i)") }
        XCTAssertTrue(rule.hasFired("k249"))
        XCTAssertFalse(rule.hasFired("k0"))
    }
}
