import XCTest
import SwiftData
@testable import Livo

final class WidgetSnapshotTests: XCTestCase {
    @MainActor
    func testSnapshotSummarizesRealRecords() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let now = Date.now
        DemoData.seed(ctx, now: now)
        let s = WidgetSnapshotWriter.make(ctx, now: now)
        let accounts = try ctx.fetch(FetchDescriptor<Account>()).filter { !$0.archived }
        XCTAssertEqual(s.balanceCents, accounts.reduce(Int64(0)) { $0 + FinanceLogic.balance(of: $1, at: now) })
        XCTAssertEqual(s.habitsTotal, 4)
        XCTAssertEqual(s.tasksToday, 3) // two due today + one overdue in the demo set
        XCTAssertEqual(s.nextTask, "Renovar documento")
        XCTAssertEqual(s.waterTargetMl, 2_000)

        // Round-trips through JSON the way the widget reads it.
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(WidgetSnapshot.self, from: e.encode(s))
        XCTAssertEqual(back.tasksToday, s.tasksToday)
    }
}
