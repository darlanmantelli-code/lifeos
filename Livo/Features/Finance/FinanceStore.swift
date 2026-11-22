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
            ReceiptStore.delete(t.receipts)
            ctx.delete(t)
            return
        }
        let target: UUID? = gid
        let from = t.date
        let group = try ctx.fetch(FetchDescriptor<FinanceTransaction>(predicate: #Predicate<FinanceTransaction> { $0.groupID == target }))
        for x in group where x.date >= from {
            ReceiptStore.delete(x.receipts)
            ctx.delete(x)
        }
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

    /// With iCloud sync, each device seeds its own default categories, so the same category can arrive twice.
    /// Merges categories with the same name, kind and parent: keeps the most used one and moves
    /// transactions, budgets and subcategories onto it. Returns how many duplicates were removed.
    @discardableResult
    static func mergeDuplicateCategories(_ ctx: ModelContext) throws -> Int {
        let all = try ctx.fetch(FetchDescriptor<FinanceCategory>())
        func key(_ c: FinanceCategory) -> String {
            "\(c.kindRaw)|\(c.parent.map { StatementParser.normalize($0.name) } ?? "")|\(StatementParser.normalize(c.name))"
        }
        var gone = Set<PersistentIdentifier>()
        // Roots first, so children re-key against their surviving parent.
        for c in all.sorted(by: { ($0.parent == nil ? 0 : 1) < ($1.parent == nil ? 0 : 1) }) where !gone.contains(c.persistentModelID) {
            let twins = all.filter { !gone.contains($0.persistentModelID) && key($0) == key(c) }
            guard twins.count > 1 else { continue }
            let keep = twins.max { ($0.transactions?.count ?? 0) < ($1.transactions?.count ?? 0) }!
            let dups = twins.filter { $0 != keep }
            for dup in dups {
                for t in dup.transactions ?? [] { t.category = keep }
                for b in dup.budgets ?? [] { b.category = keep }
                for child in dup.children ?? [] { child.parent = keep }
            }
            // Flush the moves before deleting: the cascade rules must not see moved children/budgets.
            try ctx.save()
            for dup in dups {
                gone.insert(dup.persistentModelID)
                ctx.delete(dup)
            }
            try ctx.save()
        }
        return gone.count
    }
}
