import XCTest
import SwiftData
@testable import Livo

final class IntentTests: XCTestCase {
    @MainActor
    func testIntentActionsWriteThroughValidatedTools() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        XCTAssertEqual(LivoIntentActions.balanceText(in: ctx), "Você ainda não cadastrou contas no livo.")
        XCTAssertThrowsError(try LivoIntentActions.run("registrar_despesa", ["valor": 10, "descricao": "x"], in: ctx)) // no account

        ctx.insert(Account(name: "Conta", kind: .corrente, initialBalanceCents: 10_000))
        let reply = try LivoIntentActions.run("registrar_despesa", ["valor": 25.5, "descricao": "Almoço"], in: ctx)
        XCTAssertTrue(reply.contains("R$"))
        XCTAssertEqual(LivoIntentActions.balanceText(in: ctx).replacingOccurrences(of: "\u{00A0}", with: " "),
                       "Seu saldo consolidado é R$ 74,50.")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AIActionLog>()).first?.summary.hasPrefix("Siri/Atalhos"), true)

        _ = try LivoIntentActions.logWater(300, in: ctx)
        let water = try LivoIntentActions.logWater(200, in: ctx)
        XCTAssertTrue(water.hasSuffix("Hoje: 500 ml."))
        XCTAssertThrowsError(try LivoIntentActions.logWater(0, in: ctx))
    }
}
