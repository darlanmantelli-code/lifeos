import XCTest
import SwiftData
@testable import Livo

final class HealthSyncTests: XCTestCase {
    @MainActor
    func testApplyReplacesImportedDaysAndKeepsManualEntries() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let cal = Calendar.ptBR
        let d1 = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let d2 = cal.date(byAdding: .day, value: 1, to: d1)!

        ctx.insert(HealthEntry(kind: .agua, value: 300, date: d2.addingTimeInterval(9 * 3600))) // manual
        XCTAssertEqual(try HealthSync.apply([.passos: [d1: 8_000, d2: 5_000], .peso: [d2: 80.2]], from: d1, in: ctx), 3)
        // Re-sync with fresher numbers: imported values replaced, not duplicated; zeros skipped.
        XCTAssertEqual(try HealthSync.apply([.passos: [d1: 8_100, d2: 0]], from: d1, in: ctx), 1)

        let all = try ctx.fetch(FetchDescriptor<HealthEntry>())
        let imported = all.filter { $0.sourceRaw == HealthSync.source }
        XCTAssertEqual(imported.map(\.value), [8_100])
        XCTAssertEqual(all.filter { $0.sourceRaw == "manual" }.count, 1)
        XCTAssertEqual(cal.component(.hour, from: imported[0].date), 12)
    }
}
