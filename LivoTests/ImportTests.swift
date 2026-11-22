import XCTest
import SwiftData
@testable import Livo

final class ImportTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func ymd(_ d: Date) -> [Int] {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return [c.year!, c.month!, c.day!]
    }

    func testAmountFormats() {
        XCTAssertEqual(StatementParser.parseAmount("1.234,56"), 123_456)
        XCTAssertEqual(StatementParser.parseAmount("-50,00"), -5_000)
        XCTAssertEqual(StatementParser.parseAmount("R$ 12,90"), 1_290)
        XCTAssertEqual(StatementParser.parseAmount("12.5"), 1_250)
        XCTAssertEqual(StatementParser.parseAmount("-1234.56"), -123_456)
        XCTAssertEqual(StatementParser.parseAmount("1,234.56"), 123_456)
        XCTAssertEqual(StatementParser.parseAmount("1.234"), 123_400) // dot as thousands
        XCTAssertEqual(StatementParser.parseAmount("(30,00)"), -3_000)
        XCTAssertNil(StatementParser.parseAmount("abc"))
    }

    func testOFXSgml() throws {
        let ofx = """
        OFXHEADER:100
        <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
        <STMTTRN>
        <TRNTYPE>DEBIT
        <DTPOSTED>20261105120000[-3:BRT]
        <TRNAMT>-75.50
        <FITID>abc123
        <MEMO>POSTO IPIRANGA
        </STMTTRN>
        <STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20261106<TRNAMT>8500.00<FITID>sal1<NAME>SALARIO EMPRESA</STMTTRN>
        </BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
        """
        let lines = try StatementParser.parse(Data(ofx.utf8))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].id, "abc123")
        XCTAssertEqual(lines[0].amountCents, -7_550)
        XCTAssertEqual(lines[0].description, "POSTO IPIRANGA")
        XCTAssertEqual(ymd(lines[0].date), [2026, 11, 5])
        XCTAssertEqual(lines[1].amountCents, 850_000)
        XCTAssertEqual(lines[1].description, "SALARIO EMPRESA")
    }

    func testCSVBrazilianBank() throws {
        let csv = "Data;Histórico;Valor\n05/11/2026;\"Padaria; centro\";-12,50\n06/11/26;Salário;8.500,00\n\n"
        let lines = try StatementParser.parse(Data(csv.utf8))
        XCTAssertEqual(lines.map(\.amountCents), [-1_250, 850_000])
        XCTAssertEqual(lines[0].description, "Padaria; centro")
        XCTAssertEqual(ymd(lines[1].date), [2026, 11, 6])
    }

    func testCSVNubankCard() throws {
        let csv = "date,title,amount\n2026-11-01,Uber *Trip,23.9\n2026-11-02,Netflix.com,55.90\n"
        let lines = try StatementParser.parse(Data(csv.utf8))
        XCTAssertEqual(lines.map(\.amountCents), [2_390, 5_590])
    }

    func testCSVWithoutKnownColumnsFails() {
        XCTAssertThrowsError(try StatementParser.parse(Data("a;b;c\n1;2;3".utf8)))
    }

    @MainActor
    func testSuggestionsDuplicatesAndCommit() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        FinanceStore.seedCategoriesIfNeeded(ctx)
        let card = Account(name: "Cartão", kind: .cartao)
        ctx.insert(card)
        let lazer = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FinanceCategory>()).first { $0.name == "Lazer" })
        // Learned: the user already filed "Bar do Zé" under Lazer.
        FinanceStore.insert(.init(kind: .despesa, amountCents: 4_000, title: "Bar do Zé", date: .now, account: card, category: lazer), in: ctx)
        try ctx.save()

        let lines = try StatementParser.parse(Data("date,title,amount\n2026-11-01,Uber *Trip,23.9\n2026-11-02,bar do ze,40\n2026-11-03,Loja X,10\n".utf8))
        var cands = StatementImporter.candidates(lines, account: card, positiveIsExpense: true, in: ctx)
        XCTAssertEqual(cands.map { $0.category?.name }, ["Transporte", "Lazer", nil])
        XCTAssertTrue(cands.allSatisfy(\.include))

        XCTAssertEqual(StatementImporter.commit(cands, account: card, positiveIsExpense: true, in: ctx), 3)
        try ctx.save()
        let imported = try ctx.fetch(FetchDescriptor<FinanceTransaction>()).filter { $0.sourceRaw == TxnSource.importacao.rawValue }
        XCTAssertEqual(imported.count, 3)
        XCTAssertTrue(imported.allSatisfy { $0.kind == .despesa && $0.externalID != nil })

        // Re-importing the same file: everything flagged as duplicate and unselected.
        cands = StatementImporter.candidates(lines, account: card, positiveIsExpense: true, in: ctx)
        XCTAssertTrue(cands.allSatisfy { $0.duplicate && !$0.include })
    }
}
