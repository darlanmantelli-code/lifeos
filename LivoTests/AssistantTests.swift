import XCTest
import SwiftData
@testable import Livo

final class AssistantTests: XCTestCase {
    private let cal = Calendar.ptBR

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testJSONValueRoundTripKeepsBlocks() throws {
        let raw = #"[{"type":"thinking","thinking":"","signature":"abc/def"},{"type":"tool_use","id":"t1","name":"x","input":{"n":1.5,"ok":true,"z":null}}]"#
        let decoded = try JSONDecoder().decode([JSONValue].self, from: Data(raw.utf8))
        let again = try JSONDecoder().decode([JSONValue].self, from: Data(JSONValue.array(decoded).text.utf8))
        XCTAssertEqual(decoded, again)
        XCTAssertEqual(decoded[1]["input"]?["ok"]?.bool, true)
        XCTAssertEqual(decoded[1]["input"]?["n"]?.number, 1.5)
        XCTAssertTrue(JSONValue.array(decoded).text.contains("abc/def"))
    }

    @MainActor
    func testFinanceToolAndExpenseWrite() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        FinanceStore.seedCategoriesIfNeeded(ctx)
        let conta = Account(name: "Nubank", kind: .corrente, initialBalanceCents: 100_000)
        ctx.insert(conta)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 10))!

        let written = try AssistantTools.run("registrar_despesa",
                                             ["valor": 75, "descricao": "Combustível", "categoria": "transporte", "data": "2026-11-20"],
                                             in: ctx, now: now)
        XCTAssertEqual(written["ok"]?.bool, true)
        let t = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FinanceTransaction>()).first)
        XCTAssertEqual(t.amountCents, 7_500)
        XCTAssertEqual(t.category?.name, "Transporte") // accent/case-insensitive match
        XCTAssertEqual(t.sourceRaw, TxnSource.ia.rawValue)
        XCTAssertEqual(t.account, conta)

        let report = try AssistantTools.run("consultar_financas", ["inicio": "2026-11-01", "fim": "2026-11-30"], in: ctx, now: now)
        XCTAssertEqual(report["realizado"]?["despesas"]?.number, 75)
        XCTAssertEqual(report["despesas_por_categoria"]?.array?.first?["categoria"]?.string, "Transporte")

        let balances = try AssistantTools.run("consultar_saldos", [:], in: ctx, now: now)
        XCTAssertEqual(balances["saldo_consolidado"]?.number, 925)
    }

    @MainActor
    func testWriteToolsValidateInput() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        XCTAssertThrowsError(try AssistantTools.run("registrar_despesa", ["valor": -5, "descricao": "x"], in: ctx))
        XCTAssertThrowsError(try AssistantTools.run("registrar_despesa", ["valor": 10, "descricao": "x"], in: ctx)) // no account
        XCTAssertThrowsError(try AssistantTools.run("criar_tarefa", ["titulo": "  "], in: ctx))
        XCTAssertThrowsError(try AssistantTools.run("consultar_financas", ["inicio": "ontem", "fim": "2026-11-30"], in: ctx))
        XCTAssertThrowsError(try AssistantTools.run("apagar_tudo", [:], in: ctx))
    }

    @MainActor
    func testLoopRunsReadToolsAndAsksBeforeWriting() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let session = AssistantSession()

        let replies: [TurnResponse] = [
            TurnResponse(content: [["type": "text", "text": "Vou ver."],
                                   ["type": "tool_use", "id": "a", "name": "listar_tarefas", "input": ["filtro": "pendentes"]],
                                   ["type": "tool_use", "id": "b", "name": "criar_tarefa", "input": ["titulo": "Pagar luz"]]],
                         stop_reason: "tool_use", model: "m"),
            TurnResponse(content: [["type": "text", "text": "Pronto, tarefa criada."]], stop_reason: "end_turn", model: "m"),
        ]
        let calls = Counter()
        let transport: AssistantSession.Transport = { _ in replies[await calls.next()] }

        let run = Task { await session.send("Crie a tarefa pagar luz", in: ctx, transport: transport) }
        for _ in 0..<200 where session.pending == nil { await Task.yield() }
        XCTAssertEqual(session.pending?.tool, "criar_tarefa")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<TaskItem>()), 0) // nothing written before confirming
        session.resolve(true)
        await run.value

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<TaskItem>()), 1)
        XCTAssertEqual(session.messages.count, 4) // user, assistant, tool results, assistant
        let results = try XCTUnwrap(session.messages[2]["content"]?.array)
        XCTAssertEqual(results.map { $0["tool_use_id"]?.string }, ["a", "b"]) // both results in one message
        XCTAssertEqual(session.transcript.last?.text, "Pronto, tarefa criada.")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AIActionLog>()).map(\.status).sorted(), ["executada", "executada"])
    }

    @MainActor
    func testDeclinedWriteIsReportedNotExecuted() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let session = AssistantSession()
        let replies: [TurnResponse] = [
            TurnResponse(content: [["type": "tool_use", "id": "w", "name": "criar_tarefa", "input": ["titulo": "X"]]],
                         stop_reason: "tool_use", model: "m"),
            TurnResponse(content: [["type": "text", "text": "Ok, não criei."]], stop_reason: "end_turn", model: "m"),
        ]
        let calls = Counter()
        let run = Task { await session.send("crie X", in: ctx, transport: { _ in replies[await calls.next()] }) }
        for _ in 0..<200 where session.pending == nil { await Task.yield() }
        session.resolve(false)
        await run.value
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<TaskItem>()), 0)
        XCTAssertEqual(session.messages[2]["content"]?.array?.first?["content"]?.string?.contains("recusou"), true)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AIActionLog>()).first?.status, "recusada")
    }

    @MainActor
    func testServerErrorKeepsConversationValid() async throws {
        let container = try makeContainer()
        let session = AssistantSession()
        await session.send("oi", in: container.mainContext, transport: { _ in throw AssistantError.server("fora do ar") })
        XCTAssertEqual(session.error, "fora do ar")
        XCTAssertTrue(session.messages.isEmpty)
    }
}

private actor Counter {
    private var n = 0
    func next() -> Int { defer { n += 1 }; return n }
}
