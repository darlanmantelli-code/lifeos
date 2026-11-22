import Foundation
import SwiftData

/// The assistant's tools, executed on device against the local store.
/// Names and inputs mirror `backend/assistant.py` TOOLS. Inputs come from the model: validate everything.
@MainActor
enum AssistantTools {
    struct ToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let writeTools: Set<String> = ["registrar_despesa", "criar_tarefa", "adicionar_item_compra"]
    static func needsConfirmation(_ name: String) -> Bool { writeTools.contains(name) }

    // MARK: Input helpers

    private static let cal = Calendar.ptBR

    static func day(_ text: String?) -> Date? {
        guard let parts = text?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func requiredDay(_ input: JSONValue, _ key: String) throws -> Date {
        guard let d = day(input[key]?.string) else { throw ToolError(message: "Campo '\(key)' deve ser uma data AAAA-MM-DD.") }
        return d
    }

    private static func text(_ input: JSONValue, _ key: String) -> String? {
        input[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func reais(_ cents: Int64) -> JSONValue { .number(Double(cents) / 100) }
    private static func br(_ d: Date) -> String { d.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(.ptBR)) }

    private static func cents(fromReais value: Double?) throws -> Int64 {
        guard let value, value.isFinite, value > 0, value <= 10_000_000 else {
            throw ToolError(message: "Valor deve ser um número positivo em reais.")
        }
        return Int64((value * 100).rounded())
    }

    private static func all<T: PersistentModel>(_ ctx: ModelContext, _: T.Type) -> [T] {
        (try? ctx.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: Dispatch

    /// Human-readable line for confirmations and the action history.
    static func describe(_ name: String, _ input: JSONValue) -> String {
        switch name {
        case "registrar_despesa":
            let kind = input["tipo"]?.string == "receita" ? "receita" : "despesa"
            let value = input["valor"]?.number.map { Money.format(Int64(($0 * 100).rounded())) } ?? "?"
            var parts = ["Registrar \(kind) de \(value)", input["descricao"]?.string ?? ""]
            if let c = input["categoria"]?.string { parts.append("categoria \(c)") }
            if let a = input["conta"]?.string { parts.append("conta \(a)") }
            parts.append(day(input["data"]?.string).map(br) ?? "hoje")
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        case "criar_tarefa":
            var s = "Criar tarefa “\(input["titulo"]?.string ?? "")”"
            if let d = day(input["prazo"]?.string) { s += " para \(br(d))" }
            if let p = input["prioridade"]?.string { s += " · prioridade \(p)" }
            return s
        case "adicionar_item_compra":
            let target = input["desejo"]?.bool == true ? "lista de desejos" : (input["lista"]?.string ?? "lista de compras")
            var s = "Adicionar “\(input["nome"]?.string ?? "")” à \(target)"
            if let p = input["preco"]?.number { s += " · \(Money.format(Int64((p * 100).rounded())))" }
            return s
        case "consultar_financas", "listar_lancamentos":
            return "Consultou lançamentos de \(input["inicio"]?.string ?? "?") a \(input["fim"]?.string ?? "?")"
        case "consultar_saude":
            return "Consultou saúde: \(input["tipo"]?.string ?? "?"), \(Int(input["dias"]?.number ?? 0)) dias"
        default:
            return "Consultou \(name.replacingOccurrences(of: "_", with: " "))"
        }
    }

    static func run(_ name: String, _ input: JSONValue, in ctx: ModelContext, now: Date = .now) throws -> JSONValue {
        switch name {
        case "consultar_financas": return try finances(input, ctx, now)
        case "consultar_saldos": return balances(ctx, now)
        case "listar_lancamentos": return try transactions(input, ctx, now)
        case "listar_tarefas": return try tasks(input, ctx, now)
        case "consultar_metas": return goals(ctx)
        case "consultar_habitos": return habits(ctx, now)
        case "consultar_saude": return try health(input, ctx, now)
        case "listar_compras": return shopping(ctx)
        case "registrar_despesa": return try addTransaction(input, ctx, now)
        case "criar_tarefa": return try addTask(input, ctx)
        case "adicionar_item_compra": return try addShoppingItem(input, ctx)
        default: throw ToolError(message: "Ferramenta desconhecida: \(name)")
        }
    }

    // MARK: Reads

    private static func range(_ input: JSONValue) throws -> (Date, Date) {
        let start = try requiredDay(input, "inicio")
        let end = cal.date(byAdding: .day, value: 1, to: try requiredDay(input, "fim"))!
        guard start < end else { throw ToolError(message: "'inicio' deve ser antes ou igual a 'fim'.") }
        return (start, end)
    }

    private static func finances(_ input: JSONValue, _ ctx: ModelContext, _ now: Date) throws -> JSONValue {
        let (start, end) = try range(input)
        let txns = all(ctx, FinanceTransaction.self).filter { $0.date >= start && $0.date < end }
        let done = txns.filter { $0.date <= now }
        let planned = txns.filter { $0.date > now }
        let s = FinanceLogic.summary(done), p = FinanceLogic.summary(planned)
        let byCat = FinanceLogic.expensesByRootCategory(done).map { JSONValue.object(["categoria": .string($0.name), "valor": reais($0.cents)]) }

        let monthKey = MonthKey.of(cal.date(byAdding: .second, value: -1, to: end)!)
        let monthRange = MonthKey.interval(of: cal.date(byAdding: .second, value: -1, to: end)!)
        let monthDone = all(ctx, FinanceTransaction.self).filter { $0.date >= monthRange.start && $0.date < monthRange.end && $0.date <= now }
        let budgets: [JSONValue] = all(ctx, FinanceCategory.self).filter { $0.parent == nil && $0.kind == .despesa }.compactMap { c in
            guard let limit = FinanceLogic.effectiveLimit(c.budgets ?? [], key: monthKey) else { return nil }
            return ["categoria": .string(c.name), "limite": reais(limit), "gasto": reais(FinanceLogic.spent(in: c, monthDone)), "mes": .string(monthKey)]
        }
        return [
            "periodo": .string("\(br(start)) a \(br(cal.date(byAdding: .day, value: -1, to: end)!))"),
            "realizado": ["receitas": reais(s.income), "despesas": reais(s.expense), "resultado": reais(s.net)],
            "previsto_no_periodo": ["receitas": reais(p.income), "despesas": reais(p.expense)],
            "despesas_por_categoria": .array(byCat),
            "orcamentos": .array(budgets),
            "moeda": "BRL",
        ]
    }

    private static func balances(_ ctx: ModelContext, _ now: Date) -> JSONValue {
        let accounts = all(ctx, Account.self).filter { !$0.archived }.sorted { $0.createdAt < $1.createdAt }
        let rows: [JSONValue] = accounts.map { a in
            let bal = FinanceLogic.balance(of: a, at: now)
            var row: [String: JSONValue] = ["nome": .string(a.name), "tipo": .string(a.kind.label), "saldo": reais(bal)]
            if a.kind == .cartao {
                if let closing = a.closingDay {
                    row["fatura_atual"] = reais(FinanceLogic.invoiceTotal(card: a, key: FinanceLogic.invoiceKey(for: now, closingDay: closing)))
                    row["fechamento_dia"] = .number(Double(closing))
                }
                if let due = a.dueDay { row["vencimento_dia"] = .number(Double(due)) }
                if let limit = a.creditLimitCents { row["limite_disponivel"] = reais(limit + bal) }
            }
            return .object(row)
        }
        let total = accounts.reduce(Int64(0)) { $0 + FinanceLogic.balance(of: $1, at: now) }
        return ["contas": .array(rows), "saldo_consolidado": reais(total), "moeda": "BRL"]
    }

    private static func transactions(_ input: JSONValue, _ ctx: ModelContext, _ now: Date) throws -> JSONValue {
        let (start, end) = try range(input)
        let q = text(input, "texto")
        let list = all(ctx, FinanceTransaction.self)
            .filter { $0.date >= start && $0.date < end }
            .filter { t in q.map { SearchLogic.matches(t.title, $0) || SearchLogic.matches(t.category?.name ?? "", $0) } ?? true }
            .sorted { $0.date > $1.date }
        let rows: [JSONValue] = list.prefix(50).map { t in
            ["data": .string(br(t.date)), "descricao": .string(t.title), "tipo": .string(t.kind.label),
             "valor": reais(t.amountCents), "categoria": .string(t.category?.displayName ?? ""),
             "conta": .string(t.account?.name ?? ""), "previsto": .bool(t.date > now)]
        }
        return ["lancamentos": .array(rows), "total_encontrado": .number(Double(list.count)), "mostrando": .number(Double(rows.count))]
    }

    private static func tasks(_ input: JSONValue, _ ctx: ModelContext, _ now: Date) throws -> JSONValue {
        let items = all(ctx, TaskItem.self)
        let filtered: [TaskItem]
        switch input["filtro"]?.string ?? "" {
        case "pendentes": filtered = items.filter { !$0.done }
        case "hoje": filtered = items.filter { RoutineLogic.isForToday($0, now: now) }
        case "atrasadas": filtered = items.filter { RoutineLogic.isOverdue($0, now: now) }
        case "concluidas": filtered = items.filter(\.done)
        default: throw ToolError(message: "filtro deve ser pendentes, hoje, atrasadas ou concluidas.")
        }
        let rows: [JSONValue] = RoutineLogic.sorted(filtered).prefix(50).map { t in
            ["titulo": .string(t.title), "prazo": t.due.map { JSONValue.string(br($0)) } ?? .null,
             "prioridade": .string(t.priority.label), "concluida": .bool(t.done),
             "atrasada": .bool(RoutineLogic.isOverdue(t, now: now)), "meta": t.goal.map { JSONValue.string($0.title) } ?? .null]
        }
        return ["tarefas": .array(rows)]
    }

    private static func goals(_ ctx: ModelContext) -> JSONValue {
        let rows: [JSONValue] = all(ctx, Goal.self).map { g in
            var row: [String: JSONValue] = [
                "titulo": .string(g.title), "horizonte": .string(g.horizon.label), "concluida": .bool(g.completed),
                "progresso_percentual": .number((RoutineLogic.progress(g) * 100).rounded()),
                "prazo": g.deadline.map { JSONValue.string(br($0)) } ?? .null,
                "etapas": .array((g.steps ?? []).sorted { $0.order < $1.order }.map { ["titulo": .string($0.title), "feita": .bool($0.done)] }),
                "tarefas_ligadas": .number(Double(g.tasks?.count ?? 0)),
            ]
            if let t = g.targetValue {
                row["valor_alvo"] = .number(t)
                row["valor_atual"] = .number(g.currentValue ?? 0)
                row["unidade"] = .string(g.unit)
            }
            return .object(row)
        }
        return ["metas": .array(rows)]
    }

    private static func habits(_ ctx: ModelContext, _ now: Date) -> JSONValue {
        let rows: [JSONValue] = all(ctx, Habit.self).filter { !$0.archived }.map { h in
            ["nome": .string(h.name), "frequencia": .string(h.frequency.label), "meta_por_periodo": .number(Double(h.target)),
             "feitos_no_periodo_atual": .number(Double(RoutineLogic.count(h, in: RoutineLogic.period(of: now, h.frequency)))),
             "sequencia_atual": .number(Double(RoutineLogic.streak(h, asOf: now))),
             "melhor_sequencia": .number(Double(RoutineLogic.bestStreak(h, asOf: now)))]
        }
        return ["habitos": .array(rows)]
    }

    private static func health(_ input: JSONValue, _ ctx: ModelContext, _ now: Date) throws -> JSONValue {
        guard let kind = input["tipo"]?.string.flatMap(HealthKind.init(rawValue:)) else {
            throw ToolError(message: "tipo inválido.")
        }
        let days = min(max(Int(input["dias"]?.number ?? 7), 1), 90)
        let entries = all(ctx, HealthEntry.self).filter { $0.kind == kind }
        let series: [JSONValue] = HealthLogic.daily(entries, kind, days: days, now: now).map { d in
            var row: [String: JSONValue] = ["data": .string(br(d.day)), "valor": .number(d.value)]
            if let v2 = d.value2 { row["valor2"] = .number(v2) }
            return .object(row)
        }
        let target = all(ctx, HealthTarget.self).first { $0.kindRaw == kind.rawValue }?.value
        return ["tipo": .string(kind.label), "unidade": .string(kind.unit), "por_dia": .array(series),
                "media_7_dias": HealthLogic.average(entries, kind, now: now).map(JSONValue.number) ?? .null,
                "meta_diaria": target.map(JSONValue.number) ?? .null,
                "origem": "registros manuais do usuário"]
    }

    private static func shopping(_ ctx: ModelContext) -> JSONValue {
        let lists: [JSONValue] = all(ctx, ShoppingList.self).map { l in
            let pending = (l.items ?? []).filter { !$0.bought }
            return ["nome": .string(l.name), "desejos": .bool(l.isWishlist),
                    "itens_pendentes": .array(pending.map { i in
                        ["nome": .string(i.name), "quantidade": .number(i.quantity), "unidade": .string(i.unit),
                         "preco_unitario_informado": i.priceCents.map(reais) ?? .null]
                    }),
                    "estimativa_informada": reais(ShoppingLogic.estimate(pending).cents)]
        }
        return ["listas": .array(lists), "observacao": "Preços informados pelo usuário, não consultados em lojas."]
    }

    // MARK: Writes (run only after the user confirms)

    private static func addTransaction(_ input: JSONValue, _ ctx: ModelContext, _ now: Date) throws -> JSONValue {
        let amount = try cents(fromReais: input["valor"]?.number)
        guard let title = text(input, "descricao") else { throw ToolError(message: "Informe a descrição.") }
        let kind: TxnKind = input["tipo"]?.string == "receita" ? .receita : .despesa
        let accounts = all(ctx, Account.self).filter { !$0.archived }.sorted { $0.createdAt < $1.createdAt }
        let account: Account
        if let name = text(input, "conta") {
            guard let a = accounts.first(where: { same($0.name, name) }) else {
                throw ToolError(message: "Conta '\(name)' não encontrada. Contas: \(accounts.map(\.name).joined(separator: ", "))")
            }
            account = a
        } else {
            guard let a = accounts.first else { throw ToolError(message: "Nenhuma conta cadastrada no app.") }
            account = a
        }
        var category: FinanceCategory?
        if let name = text(input, "categoria") {
            let wanted: CategoryKind = kind == .receita ? .receita : .despesa
            category = all(ctx, FinanceCategory.self).first { $0.kind == wanted && same($0.name, name) }
            if category == nil { throw ToolError(message: "Categoria '\(name)' não encontrada.") }
        }
        let date = day(input["data"]?.string) ?? now
        FinanceStore.insert(TransactionDraft(kind: kind, amountCents: amount, title: title, date: date,
                                             account: account, category: category, source: .ia), in: ctx)
        return ["ok": true, "registrado": .string("\(kind.label) de \(Money.format(amount)) em \(account.name), \(br(date))")]
    }

    private static func addTask(_ input: JSONValue, _ ctx: ModelContext) throws -> JSONValue {
        guard let title = text(input, "titulo") else { throw ToolError(message: "Informe o título.") }
        let priority: Priority = switch input["prioridade"]?.string ?? "" {
        case "alta": .alta
        case "baixa": .baixa
        default: .media
        }
        let t = TaskItem(title: title, due: day(input["prazo"]?.string), priority: priority)
        ctx.insert(t)
        return ["ok": true, "tarefa": .string(title)]
    }

    private static func addShoppingItem(_ input: JSONValue, _ ctx: ModelContext) throws -> JSONValue {
        guard let name = text(input, "nome") else { throw ToolError(message: "Informe o nome do item.") }
        let wish = input["desejo"]?.bool == true
        let price: Int64? = try input["preco"]?.number.map { try cents(fromReais: $0) }
        let lists = all(ctx, ShoppingList.self).sorted { $0.createdAt < $1.createdAt }
        let list: ShoppingList
        if let wanted = text(input, "lista") {
            guard let l = lists.first(where: { same($0.name, wanted) }) else { throw ToolError(message: "Lista '\(wanted)' não encontrada.") }
            list = l
        } else if let l = lists.first(where: { $0.isWishlist == wish }) {
            list = l
        } else {
            list = ShoppingList(name: wish ? "Desejos" : "Mercado", isWishlist: wish)
            ctx.insert(list)
        }
        let item = ShoppingItem(name: name)
        ctx.insert(item)
        item.list = list
        ShoppingStore.setPrice(price, store: "", for: item, in: ctx)
        return ["ok": true, "lista": .string(list.name), "item": .string(name)]
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
