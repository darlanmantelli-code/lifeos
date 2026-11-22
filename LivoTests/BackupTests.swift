import XCTest
import SwiftData
@testable import Livo

final class BackupTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func counts(_ ctx: ModelContext) throws -> [Int] {
        [try ctx.fetchCount(FetchDescriptor<Account>()), try ctx.fetchCount(FetchDescriptor<FinanceCategory>()),
         try ctx.fetchCount(FetchDescriptor<FinanceTransaction>()), try ctx.fetchCount(FetchDescriptor<Budget>()),
         try ctx.fetchCount(FetchDescriptor<Goal>()), try ctx.fetchCount(FetchDescriptor<GoalStep>()),
         try ctx.fetchCount(FetchDescriptor<TaskItem>()), try ctx.fetchCount(FetchDescriptor<Habit>()),
         try ctx.fetchCount(FetchDescriptor<HabitCheckIn>()), try ctx.fetchCount(FetchDescriptor<ShoppingList>()),
         try ctx.fetchCount(FetchDescriptor<ShoppingItem>()), try ctx.fetchCount(FetchDescriptor<PricePoint>()),
         try ctx.fetchCount(FetchDescriptor<HealthEntry>()), try ctx.fetchCount(FetchDescriptor<HealthTarget>())]
    }

    @MainActor
    func testExportWipeRestoreRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = Date.now
        DemoData.seed(ctx, now: now) // exercises every model and relationship
        let before = try counts(ctx)
        let balancesBefore = try ctx.fetch(FetchDescriptor<Account>()).map { "\($0.name)=\(FinanceLogic.balance(of: $0, at: now))" }.sorted()
        let streaksBefore = try ctx.fetch(FetchDescriptor<Habit>()).map { "\($0.name)=\(RoutineLogic.streak($0, asOf: now))" }.sorted()
        let subcategory = FinanceCategory(name: "Mercado", kind: .despesa)
        ctx.insert(subcategory)
        subcategory.parent = try ctx.fetch(FetchDescriptor<FinanceCategory>()).first { $0.name == "Alimentação" }
        try ctx.save()

        let data = try BackupStore.export(ctx)
        try BackupStore.wipe(ctx)
        XCTAssertTrue(try counts(ctx).allSatisfy { $0 == 0 })

        try BackupStore.restore(data, into: ctx)
        var after = try counts(ctx)
        after[1] -= 1 // the extra subcategory
        XCTAssertEqual(after, before)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Account>()).map { "\($0.name)=\(FinanceLogic.balance(of: $0, at: now))" }.sorted(), balancesBefore)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Habit>()).map { "\($0.name)=\(RoutineLogic.streak($0, asOf: now))" }.sorted(), streaksBefore)
        let restoredSub = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FinanceCategory>()).first { $0.name == "Mercado" })
        XCTAssertEqual(restoredSub.parent?.name, "Alimentação")
        let tenis = try XCTUnwrap(try ctx.fetch(FetchDescriptor<ShoppingItem>()).first { $0.name == "Tênis de corrida" })
        XCTAssertEqual(tenis.prices?.count, 2)
        XCTAssertEqual(tenis.list?.isWishlist, true)
    }

    @MainActor
    func testRestoreRejectsForeignOrNewerFiles() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(Account(name: "Mantida", kind: .corrente))
        try ctx.save()

        XCTAssertThrowsError(try BackupStore.restore(Data("{\"foo\":1}".utf8), into: ctx))
        var newer = Backup()
        newer.versao = Backup.currentVersion + 1
        XCTAssertThrowsError(try BackupStore.restore(try Backup.encoder().encode(newer), into: ctx))
        // A rejected file must not touch existing data.
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Account>()), 1)
    }
}
