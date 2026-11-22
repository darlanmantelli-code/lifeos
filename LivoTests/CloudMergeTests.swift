import XCTest
import SwiftData
@testable import Livo

final class CloudMergeTests: XCTestCase {
    @MainActor
    func testMergeDuplicateCategoriesFromTwoDevices() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        // Device A and device B each seeded the defaults; sync brought both sets together.
        FinanceStore.seedCategoriesIfNeeded(ctx)
        let seeded = try ctx.fetchCount(FetchDescriptor<FinanceCategory>())
        for c in try ctx.fetch(FetchDescriptor<FinanceCategory>()) {
            ctx.insert(FinanceCategory(name: c.name, kind: c.kind, icon: c.icon))
        }
        let cats = try ctx.fetch(FetchDescriptor<FinanceCategory>())
        let foodA = cats.first { $0.name == "Alimentação" }!
        let foodB = cats.last { $0.name == "Alimentação" }!
        XCTAssertNotEqual(foodA, foodB)
        let sub = FinanceCategory(name: "Mercado", kind: .despesa)
        ctx.insert(sub)
        sub.parent = foodB

        let conta = Account(name: "Conta", kind: .corrente)
        ctx.insert(conta)
        FinanceStore.insert(.init(kind: .despesa, amountCents: 1_000, title: "A", date: .now, account: conta, category: foodA), in: ctx)
        FinanceStore.insert(.init(kind: .despesa, amountCents: 2_000, title: "B", date: .now, account: conta, category: foodB), in: ctx)
        FinanceStore.insert(.init(kind: .despesa, amountCents: 3_000, title: "C", date: .now, account: conta, category: foodB), in: ctx)
        FinanceStore.setBudget(50_000, for: foodA, from: "2026-11", in: ctx)
        try ctx.save()

        XCTAssertEqual(try FinanceStore.mergeDuplicateCategories(ctx), seeded)
        let after = try ctx.fetch(FetchDescriptor<FinanceCategory>())
        XCTAssertEqual(after.count, seeded + 1) // defaults once + the subcategory
        let food = try XCTUnwrap(after.first { $0.name == "Alimentação" })
        XCTAssertEqual(food.transactions?.count, 3)          // nothing lost
        XCTAssertEqual(food.budgets?.count, 1)
        XCTAssertEqual(food.children?.map(\.name), ["Mercado"]) // child survived the delete
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<FinanceTransaction>()), 3)
        XCTAssertEqual(try FinanceStore.mergeDuplicateCategories(ctx), 0) // idempotent
    }
}
