import Foundation
import SwiftData

// Enums are stored as raw strings (predicates on enum-typed SwiftData columns are unreliable).
// Every stored property has a default and no unique constraints, so CloudKit sync stays possible.

enum AccountKind: String, CaseIterable, Identifiable {
    case corrente, poupanca, carteira, cartao, investimento
    var id: String { rawValue }
    var label: String {
        switch self {
        case .corrente: "Conta corrente"
        case .poupanca: "Poupança"
        case .carteira: "Carteira"
        case .cartao: "Cartão de crédito"
        case .investimento: "Investimento"
        }
    }
    var icon: String {
        switch self {
        case .corrente: "building.columns"
        case .poupanca: "banknote"
        case .carteira: "wallet.pass"
        case .cartao: "creditcard"
        case .investimento: "chart.line.uptrend.xyaxis"
        }
    }
}

enum TxnKind: String, CaseIterable, Identifiable {
    case despesa, receita, transferencia
    var id: String { rawValue }
    var label: String {
        switch self {
        case .despesa: "Despesa"
        case .receita: "Receita"
        case .transferencia: "Transferência"
        }
    }
}

enum TxnSource: String { case manual, importacao, ia }
enum CategoryKind: String { case despesa, receita }

@Model
final class Account {
    var name: String = ""
    var kindRaw: String = AccountKind.corrente.rawValue
    var initialBalanceCents: Int64 = 0
    var creditLimitCents: Int64?
    var closingDay: Int?
    var dueDay: Int?
    var archived: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \FinanceTransaction.account)
    var transactions: [FinanceTransaction]? = []
    @Relationship(deleteRule: .nullify, inverse: \FinanceTransaction.toAccount)
    var incomingTransfers: [FinanceTransaction]? = []

    init(name: String, kind: AccountKind, initialBalanceCents: Int64 = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.initialBalanceCents = initialBalanceCents
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .corrente }
        set { kindRaw = newValue.rawValue }
    }

    var hasTransactions: Bool {
        !(transactions ?? []).isEmpty || !(incomingTransfers ?? []).isEmpty
    }
}

@Model
final class FinanceCategory {
    var name: String = ""
    var kindRaw: String = CategoryKind.despesa.rawValue
    var icon: String = "tag"
    var parent: FinanceCategory?
    @Relationship(deleteRule: .cascade, inverse: \FinanceCategory.parent)
    var children: [FinanceCategory]? = []
    @Relationship(deleteRule: .nullify, inverse: \FinanceTransaction.category)
    var transactions: [FinanceTransaction]? = []
    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget]? = []

    init(name: String, kind: CategoryKind, icon: String = "tag") {
        self.name = name
        self.kindRaw = kind.rawValue
        self.icon = icon
    }

    var kind: CategoryKind { CategoryKind(rawValue: kindRaw) ?? .despesa }
    var displayName: String { parent.map { "\($0.name) › \(name)" } ?? name }
}

/// Amount is always positive; `kind` gives the direction.
@Model
final class FinanceTransaction {
    var date: Date = Date()
    var amountCents: Int64 = 0
    var kindRaw: String = TxnKind.despesa.rawValue
    var title: String = ""
    var note: String = ""
    var isFixed: Bool = false
    var sourceRaw: String = TxnSource.manual.rawValue
    /// Shared by all occurrences of one installment purchase or recurring entry.
    var groupID: UUID?
    var installmentIndex: Int?
    var installmentCount: Int?
    var isRecurring: Bool = false
    var createdAt: Date = Date()
    var account: Account?
    var toAccount: Account?
    var category: FinanceCategory?

    init(kind: TxnKind, amountCents: Int64, title: String, date: Date) {
        self.kindRaw = kind.rawValue
        self.amountCents = amountCents
        self.title = title
        self.date = date
    }

    var kind: TxnKind {
        get { TxnKind(rawValue: kindRaw) ?? .despesa }
        set { kindRaw = newValue.rawValue }
    }
}

/// Limit applies from `month` ("yyyy-MM") onward until a later Budget for the same category replaces it.
/// A limit of 0 means "no budget from this month on".
@Model
final class Budget {
    var month: String = ""
    var limitCents: Int64 = 0
    var category: FinanceCategory?

    init(month: String, limitCents: Int64) {
        self.month = month
        self.limitCents = limitCents
    }
}

enum AppSchema {
    static var models: [any PersistentModel.Type] {
        [Account.self, FinanceCategory.self, FinanceTransaction.self, Budget.self]
    }
}
