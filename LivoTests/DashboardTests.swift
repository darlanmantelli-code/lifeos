import XCTest
import SwiftData
@testable import Livo

final class DashboardTests: XCTestCase {
    private let cal = Calendar.ptBR

    private func day(_ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: d, hour: hour))!
    }

    func testLayoutOrderIgnoresUnknownAndAppendsNew() {
        let order = DashboardLayout.order("tarefas,xyz,financas,tarefas")
        XCTAssertEqual(Array(order.prefix(2)), [.tarefas, .financas])
        XCTAssertEqual(Set(order), Set(WidgetKind.allCases))
        XCTAssertEqual(order.count, WidgetKind.allCases.count)
        XCTAssertEqual(DashboardLayout.visible(orderRaw: "", hiddenRaw: "saude,compras").count, WidgetKind.allCases.count - 2)
        XCTAssertEqual(DashboardLayout.order(DashboardLayout.encode(order)), order)
    }

    func testPeriodIntervalContainsNow() {
        let now = day(15)
        for p in DashPeriod.allCases {
            XCTAssertTrue(p.interval(at: now).contains(now))
        }
        XCTAssertEqual(cal.component(.day, from: DashPeriod.mes.interval(at: now).start), 1)
    }

    func testNextDue() {
        XCTAssertEqual(cal.component(.day, from: DashboardLogic.nextDue(day: 20, after: day(15))), 20)
        let rolled = DashboardLogic.nextDue(day: 10, after: day(15))
        XCTAssertEqual(cal.component(.month, from: rolled), 8)
        XCTAssertEqual(DashboardLogic.nextDue(day: 15, after: day(15, hour: 22)), cal.startOfDay(for: day(15)))
    }

    func testSearchIsAccentAndCaseInsensitive() {
        XCTAssertTrue(SearchLogic.matches("Alimentação", "alimentacao"))
        XCTAssertTrue(SearchLogic.matches("Tênis de corrida", "TENIS"))
        XCTAssertFalse(SearchLogic.matches("Mercado", "  "))
    }

    @MainActor
    func testAlerts() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let now = day(15)

        let conta = Account(name: "Conta", kind: .corrente, initialBalanceCents: 1_000)
        let cartao = Account(name: "Cartão X", kind: .cartao)
        ctx.insert(conta)
        ctx.insert(cartao)
        cartao.closingDay = 10
        cartao.dueDay = 17

        let food = FinanceCategory(name: "Alimentação", kind: .despesa)
        let fun = FinanceCategory(name: "Lazer", kind: .despesa)
        ctx.insert(food)
        ctx.insert(fun)
        FinanceStore.setBudget(10_000, for: food, from: "2026-07", in: ctx)
        FinanceStore.setBudget(10_000, for: fun, from: "2026-07", in: ctx)

        FinanceStore.insert(.init(kind: .despesa, amountCents: 12_000, title: "Mercado", date: day(5), account: conta, category: food), in: ctx)
        FinanceStore.insert(.init(kind: .despesa, amountCents: 8_500, title: "Cinema", date: day(6), account: cartao, category: fun), in: ctx)
        // Planned for later this month: must not count toward the budget alert.
        FinanceStore.insert(.init(kind: .despesa, amountCents: 50_000, title: "Show", date: day(28), account: cartao, category: fun), in: ctx)

        let late = TaskItem(title: "Atrasada", due: cal.startOfDay(for: day(10)))
        ctx.insert(late)
        try ctx.save()

        let alerts = DashboardLogic.alerts(accounts: [conta, cartao], transactions: try ctx.fetch(FetchDescriptor<FinanceTransaction>()),
                                           categories: [food, fun], tasks: [late], now: now)
        let ids = Set(alerts.map(\.id))
        XCTAssertTrue(ids.contains("budget-Alimentação"))  // 120 of 100
        XCTAssertTrue(ids.contains("budget-Lazer"))        // 85%
        XCTAssertTrue(ids.contains("card-Cartão X"))       // due in 2 days
        XCTAssertTrue(ids.contains("negative-Conta"))      // 10 - 120
        XCTAssertTrue(ids.contains("overdue"))
        XCTAssertEqual(alerts.first { $0.id == "budget-Lazer" }?.tone, .warning)
        XCTAssertEqual(alerts.first?.tone, .critical)

        let upcoming = DashboardLogic.upcomingPayments(try ctx.fetch(FetchDescriptor<FinanceTransaction>()), now: now,
                                                       until: DashPeriod.mes.interval(at: now).end)
        XCTAssertEqual(upcoming.map(\.title), ["Show"])
    }
}

final class CalendarAutomationTests: XCTestCase {
    @MainActor
    func testEventRuleIsSilentWithoutCalendarAccess() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        // Test host has no calendar permission: no events, no firings, no crash.
        XCTAssertFalse(CalendarService.eventsAuthorized)
        XCTAssertTrue(CalendarService.upcoming().isEmpty)
        XCTAssertTrue(AutomationEngine.firings(for: AutomationRule(trigger: .compromisso), in: container.mainContext).isEmpty)
        XCTAssertTrue(DashboardLayout.order("").contains(.agenda))
    }
}
