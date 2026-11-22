import XCTest
import SwiftData
@testable import Livo

final class StudyTests: XCTestCase {
    private let cal = Calendar.ptBR

    private func day(_ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour))!
    }

    @MainActor
    func testSpacedReviewsAdvanceAndCap() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = StudyItem(title: "Swift", kind: .curso)
        container.mainContext.insert(item)

        StudyLogic.markReviewed(item, now: day(1))
        XCTAssertEqual(cal.component(.day, from: item.nextReview!), 2) // +1
        XCTAssertFalse(StudyLogic.isReviewDue(item, now: day(1)))
        XCTAssertTrue(StudyLogic.isReviewDue(item, now: day(2, hour: 8)))
        StudyLogic.markReviewed(item, now: day(2))
        XCTAssertEqual(cal.component(.day, from: item.nextReview!), 5) // +3
        for _ in 0..<10 { StudyLogic.markReviewed(item, now: day(5)) }
        XCTAssertEqual(item.reviewStage, StudyLogic.reviewIntervals.count - 1) // capped at 60 days
        StudyLogic.stopReviews(item)
        XCTAssertFalse(StudyLogic.isReviewDue(item, now: day(30)))
    }

    @MainActor
    func testFocusMinutesAndBackupRoundTrip() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let item = StudyItem(title: "Livro X", kind: .livro)
        ctx.insert(item)
        for (d, m) in [(1, 25), (3, 25), (10, 50)] {
            let s = FocusSession(start: day(d), minutes: m)
            ctx.insert(s)
            s.study = item
        }
        ctx.insert(AutomationRule(trigger: .metaAlcancada))
        try ctx.save()
        XCTAssertEqual(StudyLogic.totalMinutes(item), 100)
        XCTAssertEqual(StudyLogic.minutes(try ctx.fetch(FetchDescriptor<FocusSession>()), since: day(2)), 75)

        let data = try BackupStore.export(ctx)
        try BackupStore.restore(data, into: ctx)
        let restored = try XCTUnwrap(try ctx.fetch(FetchDescriptor<StudyItem>()).first)
        XCTAssertEqual(StudyLogic.totalMinutes(restored), 100)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<AutomationRule>()), 1)
    }

    func testPomodoroTimerUsesWallClock() {
        var t = PomodoroTimer()
        let start = day(1, hour: 9)
        t.start(.focus, minutes: 25, at: start)
        XCTAssertEqual(t.remaining(at: start.addingTimeInterval(60)), 24 * 60)
        XCTAssertFalse(t.isFinished(at: start.addingTimeInterval(24 * 60)))
        XCTAssertTrue(t.isFinished(at: start.addingTimeInterval(26 * 60))) // e.g. app was suspended
        XCTAssertEqual(PomodoroTimer.clock(24 * 60 + 5), "24:05")
        t.stop()
        XCTAssertEqual(t.phase, .idle)
    }

    func testOldBackupWithoutNewSectionsStillDecodes() throws {
        let json = #"{"app":"livo","versao":1,"exportadoEm":"2026-01-01T00:00:00Z","contas":[],"categorias":[],"lancamentos":[],"orcamentos":[],"metas":[],"etapas":[],"tarefas":[],"habitos":[],"registrosHabitos":[],"listas":[],"itens":[],"precos":[],"saude":[],"metasSaude":[],"historicoIA":[]}"#
        let b = try Backup.decoder().decode(Backup.self, from: Data(json.utf8))
        XCTAssertNil(b.estudos)
    }
}
