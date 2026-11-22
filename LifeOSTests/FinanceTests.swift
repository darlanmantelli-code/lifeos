import XCTest
import SwiftData
@testable import LifeOS

final class FinanceTests: XCTestCase {
    private let cal = Calendar.ptBR

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// Callers must keep the returned container alive for the whole test.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testSplitInstallmentsKeepsTotal() {
        XCTAssertEqual(FinanceLogic.splitInstallments(totalCents: 1000, count: 3), [334, 333, 333])
        XCTAssertEqual(FinanceLogic.splitInstallments(totalCents: 99_999, count: 7).reduce(0, +), 99_999)
        XCTAssertEqual(FinanceLogic.splitInstallments(totalCents: 1000, count: 0), [])
    }

    func testMonthlyDatesClampToMonthEnd() {
        let dates = FinanceLogic.monthlyDates(from: day(2026, 1, 31), count: 3)
        XCTAssertEqual(dates.map { cal.component(.day, from: $0) }, [31, 28, 31])
    }

    func testInvoiceKeyRespectsClosingDay() {
        XCTAssertEqual(FinanceLogic.invoiceKey(for: day(2026, 3, 4), closingDay: 5), "2026-03")
        XCTAssertEqual(FinanceLogic.invoiceKey(for: day(2026, 3, 5), closingDay: 5), "2026-04")
        XCTAssertEqual(FinanceLogic.invoiceKey(for: day(2026, 12, 20), closingDay: 5), "2027-01")
    }

    @MainActor
    func testBalancesInstallmentsTransfersAndDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let conta = Account(name: "Conta", kind: .corrente, initialBalanceCents: 100_000)
        let cartao = Account(name: "Cartão", kind: .cartao)
        ctx.insert(conta)
        ctx.insert(cartao)
        cartao.closingDay = 5
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!

        FinanceStore.insert(.init(kind: .receita, amountCents: 50_000, title: "Salário", date: yesterday, account: conta), in: ctx)
        let parcelas = FinanceStore.insert(.init(kind: .despesa, amountCents: 30_000, title: "TV", date: yesterday,
                                                 account: cartao, repetition: .parcelada(3)), in: ctx)
        FinanceStore.insert(.init(kind: .transferencia, amountCents: 10_000, title: "Fatura", date: yesterday,
                                  account: conta, toAccount: cartao), in: ctx)
        try ctx.save()

        XCTAssertEqual(parcelas.map(\.installmentIndex), [1, 2, 3])
        XCTAssertEqual(Set(parcelas.map(\.groupID)).count, 1)
        // Only the first installment is in the past; future ones are planned.
        XCTAssertEqual(FinanceLogic.balance(of: conta), 100_000 + 50_000 - 10_000)
        XCTAssertEqual(FinanceLogic.balance(of: cartao), -10_000 + 10_000)
        XCTAssertEqual(FinanceLogic.summary([parcelas[0]]).expense, 10_000)

        try FinanceStore.delete(parcelas[1], includingFuture: true, in: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<FinanceTransaction>()), 3) // salário, parcela 1, fatura
    }

    @MainActor
    func testRecurringCreatesHorizon() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let conta = Account(name: "Conta", kind: .corrente)
        ctx.insert(conta)
        let created = FinanceStore.insert(.init(kind: .despesa, amountCents: 5_000, title: "Streaming", date: day(2026, 1, 10),
                                                account: conta, repetition: .recorrente), in: ctx)
        XCTAssertEqual(created.count, FinanceStore.recurringHorizon)
        XCTAssertTrue(created.allSatisfy(\.isRecurring))
        XCTAssertEqual(MonthKey.of(created.last!.date), "2026-12")
    }

    @MainActor
    func testBudgetCarriesForwardUntilChanged() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let food = FinanceCategory(name: "Alimentação", kind: .despesa)
        ctx.insert(food)
        FinanceStore.setBudget(80_000, for: food, from: "2026-01", in: ctx)
        FinanceStore.setBudget(0, for: food, from: "2026-04", in: ctx)
        try ctx.save()
        let budgets = food.budgets ?? []
        XCTAssertNil(FinanceLogic.effectiveLimit(budgets, key: "2025-12"))
        XCTAssertEqual(FinanceLogic.effectiveLimit(budgets, key: "2026-03"), 80_000)
        XCTAssertNil(FinanceLogic.effectiveLimit(budgets, key: "2026-05"))
    }

    @MainActor
    func testSeedRunsOnce() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        FinanceStore.seedCategoriesIfNeeded(ctx)
        let first = try ctx.fetchCount(FetchDescriptor<FinanceCategory>())
        FinanceStore.seedCategoriesIfNeeded(ctx)
        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<FinanceCategory>()), first)
    }
}
