import AppIntents
import SwiftData

// Siri / Shortcuts actions. They write to the real store through the same validated tools the assistant uses.

struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar despesa" }
    static var description: IntentDescription { IntentDescription("Registra uma despesa no livo, na primeira conta ativa.") }

    @Parameter(title: "Valor (R$)") var valor: Double
    @Parameter(title: "Descrição") var descricao: String
    @Parameter(title: "Categoria") var categoria: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var input: [String: JSONValue] = ["valor": .number(valor), "descricao": .string(descricao)]
        if let categoria, !categoria.isEmpty { input["categoria"] = .string(categoria) }
        let text = try LivoIntentActions.run("registrar_despesa", .object(input))
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct BalanceIntent: AppIntent {
    static var title: LocalizedStringResource { "Consultar saldo" }
    static var description: IntentDescription { IntentDescription("Diz o saldo consolidado das suas contas no livo.") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: LivoIntentActions.balanceText()))
    }
}

struct CreateTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Criar tarefa" }
    static var description: IntentDescription { IntentDescription("Cria uma tarefa no livo.") }

    @Parameter(title: "Tarefa") var titulo: String
    @Parameter(title: "Para hoje", default: false) var hoje: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var input: [String: JSONValue] = ["titulo": .string(titulo)]
        if hoje { input["prazo"] = .string(Date.now.formatted(.iso8601.year().month().day())) }
        _ = try LivoIntentActions.run("criar_tarefa", .object(input))
        return .result(dialog: "Tarefa “\(titulo)” criada.")
    }
}

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource { "Registrar água" }
    static var description: IntentDescription { IntentDescription("Registra um copo de água no livo.") }

    @Parameter(title: "Quantidade (ml)", default: 250) var ml: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try LivoIntentActions.logWater(ml)))
    }
}

@MainActor
enum LivoIntentActions {
    static var context: ModelContext { SharedStore.real.mainContext }

    static func run(_ tool: String, _ input: JSONValue, in ctx: ModelContext? = nil) throws -> String {
        let ctx = ctx ?? context
        let out = try AssistantTools.run(tool, input, in: ctx)
        ctx.insert(AIActionLog(tool: tool, summary: "Siri/Atalhos: " + AssistantTools.describe(tool, input), status: "executada"))
        try ctx.save()
        return out["registrado"]?.string.map { "Registrado: \($0)." } ?? "Feito."
    }

    static func balanceText(in ctx: ModelContext? = nil) -> String {
        let ctx = ctx ?? context
        let accounts = ((try? ctx.fetch(FetchDescriptor<Account>())) ?? []).filter { !$0.archived }
        guard !accounts.isEmpty else { return "Você ainda não cadastrou contas no livo." }
        let total = accounts.reduce(Int64(0)) { $0 + FinanceLogic.balance(of: $1) }
        return "Seu saldo consolidado é \(Money.format(total))."
    }

    static func logWater(_ ml: Int, in ctx: ModelContext? = nil) throws -> String {
        guard (1...5_000).contains(ml) else { throw AssistantTools.ToolError(message: "Quantidade deve ficar entre 1 e 5000 ml.") }
        let ctx = ctx ?? context
        ctx.insert(HealthEntry(kind: .agua, value: Double(ml), date: .now))
        try ctx.save()
        let today = ((try? ctx.fetch(FetchDescriptor<HealthEntry>())) ?? []).filter { $0.kind == .agua }
        let total = HealthLogic.current(today, .agua)?.value ?? Double(ml)
        return "Registrado: \(ml) ml. Hoje: \(HealthLogic.format(total, .agua)) ml."
    }
}

struct LivoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogExpenseIntent(),
                    phrases: ["Registrar despesa no \(.applicationName)", "Anotar gasto no \(.applicationName)"],
                    shortTitle: "Registrar despesa", systemImageName: "creditcard")
        AppShortcut(intent: BalanceIntent(),
                    phrases: ["Qual meu saldo no \(.applicationName)", "Saldo do \(.applicationName)"],
                    shortTitle: "Saldo", systemImageName: "banknote")
        AppShortcut(intent: CreateTaskIntent(),
                    phrases: ["Criar tarefa no \(.applicationName)", "Nova tarefa no \(.applicationName)"],
                    shortTitle: "Criar tarefa", systemImageName: "checklist")
        AppShortcut(intent: LogWaterIntent(),
                    phrases: ["Registrar água no \(.applicationName)", "Bebi água no \(.applicationName)"],
                    shortTitle: "Registrar água", systemImageName: "drop.fill")
    }
}
