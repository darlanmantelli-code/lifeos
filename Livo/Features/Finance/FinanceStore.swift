import Foundation
import SwiftData

enum Repetition: Hashable {
    case unica
    case parcelada(Int)
    case recorrente
}

struct TransactionDraft {
    var kind: TxnKind
    var amountCents: Int64
    var title: String
    var note = ""
    var date: Date
    var account: Account
    var toAccount: Account?
    var category: FinanceCategory?
    var isFixed = false
    var repetition: Repetition = .unica
    var source: TxnSource = .manual
}

/// All finance writes go through here (UI today, LIFE AI tools later).
@MainActor
enum FinanceStore {
    // ponytail: recurring entries are materialized 12 months ahead; extend on launch when we add the automation engine.
    static let recurringHorizon = 12

    @discardableResult
    static func insert(_ d: TransactionDraft, in ctx: ModelContext) -> [FinanceTransaction] {
        let amounts: [Int64] = switch d.repetition {
        case .unica: [d.amountCents]
        case .parcelada(let n): FinanceLogic.splitInstallments(totalCents: d.amountCents, count: max(n, 1))
        case .recorrente: Array(repeating: d.amountCents, count: recurringHorizon)
        }
        let dates = FinanceLogic.monthlyDates(from: d.date, count: amounts.count)
        let group: UUID? = amounts.count > 1 ? UUID() : nil
        let isTransfer = d.kind == .transferencia

        var created: [FinanceTransaction] = []
        for (i, (amount, date)) in zip(amounts, dates).enumerated() {
            let t = FinanceTransaction(kind: d.kind, amountCents: amount, title: d.title, date: date)
            ctx.insert(t)
            t.note = d.note
            t.isFixed = d.isFixed
            t.sourceRaw = d.source.rawValue
            t.groupID = group
            t.isRecurring = d.repetition == .recorrente
            if case .parcelada = d.repetition {
                t.installmentIndex = i + 1
                t.installmentCount = amounts.count
            }
            t.account = d.account
            t.toAccount = isTransfer ? d.toAccount : nil
            t.category = isTransfer ? nil : d.category
            created.append(t)
        }
        return created
    }

    /// `includingFuture` also deletes later occurrences of the same installment/recurring group.
    static func delete(_ t: FinanceTransaction, includingFuture: Bool, in ctx: ModelContext) throws {
        guard includingFuture, let gid = t.groupID else {
            ctx.delete(t)
            return
        }
        let target: UUID? = gid
        let from = t.date
        let group = try ctx.fetch(FetchDescriptor<FinanceTransaction>(predicate: #Predicate<FinanceTransaction> { $0.groupID == target }))
        for x in group where x.date >= from { ctx.delete(x) }
    }

    static func setBudget(_ cents: Int64, for category: FinanceCategory, from key: String, in ctx: ModelContext) {
        if let existing = (category.budgets ?? []).first(where: { $0.month == key }) {
            existing.limitCents = cents
        } else {
            let b = Budget(month: key, limitCents: cents)
            ctx.insert(b)
            b.category = category
        }
    }

    /// Default categories are configuration, not demo data: created once, editable by the user.
    static func seedCategoriesIfNeeded(_ ctx: ModelContext) {
        guard (try? ctx.fetchCount(FetchDescriptor<FinanceCategory>())) == 0 else { return }
        let despesas = [("Alimentação", "fork.knife"), ("Moradia", "house"), ("Transporte", "car"),
                        ("Saúde", "cross.case"), ("Educação", "book"), ("Lazer", "gamecontroller"),
                        ("Compras", "bag"), ("Assinaturas", "repeat"), ("Impostos e taxas", "doc.text"),
                        ("Outros", "ellipsis.circle")]
        let receitas = [("Salário", "briefcase"), ("Rendimentos", "chart.line.uptrend.xyaxis"),
                        ("Outras receitas", "plus.circle")]
        for (name, icon) in despesas { ctx.insert(FinanceCategory(name: name, kind: .despesa, icon: icon)) }
        for (name, icon) in receitas { ctx.insert(FinanceCategory(name: name, kind: .receita, icon: icon)) }
    }
}
