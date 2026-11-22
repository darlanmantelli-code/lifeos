import XCTest
import SwiftData
@testable import Livo

final class ShoppingHealthTests: XCTestCase {
    private let cal = Calendar.ptBR

    private func day(_ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: hour))!
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // MARK: Shopping

    @MainActor
    func testEstimateAndGroups() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let list = ShoppingList(name: "Mercado", isWishlist: false)
        ctx.insert(list)
        let banana = ShoppingItem(name: "Banana")
        let arroz = ShoppingItem(name: "Arroz")
        let sabao = ShoppingItem(name: "Sabão")
        for i in [banana, arroz, sabao] { ctx.insert(i); i.list = list }
        banana.category = "Hortifruti"
        banana.quantity = 1.5
        banana.priceCents = 799 // R$ 7,99/kg → R$ 11,99 (11,985 rounded)
        arroz.category = "Mercearia"
        arroz.priceCents = 2_500
        try ctx.save()

        XCTAssertEqual(ShoppingLogic.lineTotal(banana), 1_199)
        let e = ShoppingLogic.estimate(list.items ?? [])
        XCTAssertEqual(e.cents, 1_199 + 2_500)
        XCTAssertEqual(e.missing, 1)
        XCTAssertEqual(ShoppingLogic.groups(list.items ?? []).map(\.category), ["Hortifruti", "Mercearia", ""])
    }

    @MainActor
    func testPriceHistoryOnlyOnChange() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let item = ShoppingItem(name: "Café")
        ctx.insert(item)
        ShoppingStore.setPrice(1_890, store: "Loja A", for: item, at: day(1), in: ctx)
        ShoppingStore.setPrice(1_890, store: "Loja A", for: item, at: day(2), in: ctx)
        ShoppingStore.setPrice(2_090, store: "Loja B", for: item, at: day(3), in: ctx)
        try ctx.save()
        XCTAssertEqual((item.prices ?? []).sorted { $0.observedAt < $1.observedAt }.map(\.priceCents), [1_890, 2_090])
        XCTAssertEqual(item.priceCents, 2_090)
        XCTAssertTrue((item.prices ?? []).allSatisfy { $0.sourceRaw == "manual" })
    }

    @MainActor
    func testClearBought() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let list = ShoppingList(name: "Casa", isWishlist: false)
        ctx.insert(list)
        let a = ShoppingItem(name: "A"), b = ShoppingItem(name: "B")
        for i in [a, b] { ctx.insert(i); i.list = list }
        ShoppingStore.toggleBought(a)
        XCTAssertNotNil(a.boughtAt)
        ShoppingStore.clearBought(list, in: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ShoppingItem>()), 1)
    }

    // MARK: Health

    @MainActor
    private func entries(_ ctx: ModelContext, _ kind: HealthKind, _ values: [(Int, Int, Double)]) -> [HealthEntry] {
        values.map { d, h, v in
            let e = HealthEntry(kind: kind, value: v, date: day(d, hour: h))
            ctx.insert(e)
            return e
        }
    }

    @MainActor
    func testDailySumAndCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let water = entries(ctx, .agua, [(10, 8, 300), (10, 14, 500), (9, 9, 1000), (1, 9, 999)])
        let series = HealthLogic.daily(water, .agua, days: 7, now: day(10, hour: 20))
        XCTAssertEqual(series.map(\.value), [1000, 800]) // day 1 is outside the window
        XCTAssertEqual(HealthLogic.current(water, .agua, now: day(10, hour: 20))?.value, 800)
        XCTAssertNil(HealthLogic.current(water, .agua, now: day(11)))
    }

    @MainActor
    func testLatestAndWeeklyChange() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let weight = entries(ctx, .peso, [(1, 7, 80), (2, 7, 80.4), (8, 7, 79), (9, 7, 78.6), (9, 20, 78.8)])
        let now = day(9, hour: 21)
        XCTAssertEqual(HealthLogic.current(weight, .peso, now: now)?.value, 78.8)
        // Last 7 days (3–9): days 8 → 79, 9 → 78.8 (latest of the day) → 78.9. Previous (−6..2): 80, 80.4 → 80.2.
        XCTAssertEqual(HealthLogic.weeklyChange(weight, .peso, now: now)!, -1.3, accuracy: 0.0001)
    }

    func testFormatPressure() {
        XCTAssertEqual(HealthLogic.format(120, 80, .pressao), "120/80")
        XCTAssertEqual(HealthLogic.format(7.26, nil, .sono), "7,3")
    }

    @MainActor
    func testTargetSetAndRemove() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        try HealthStore.setTarget(2_000, for: .agua, in: ctx)
        try HealthStore.setTarget(2_500, for: .agua, in: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<HealthTarget>()).map(\.value), [2_500])
        try HealthStore.setTarget(nil, for: .agua, in: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<HealthTarget>()), 0)
    }
}
