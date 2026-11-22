import Foundation
import SwiftData

extension Calendar {
    static let ptBR: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = .ptBR
        return c
    }()
}

enum MonthKey {
    static func of(_ date: Date, calendar: Calendar = .ptBR) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func interval(of date: Date, calendar: Calendar = .ptBR) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)!
    }
}

struct CategoryTotal: Identifiable {
    let name: String
    let cents: Int64
    var id: String { name }
}

/// Pure calculations. Nothing here writes to the store.
enum FinanceLogic {
    /// Remainder cents go to the first installment, so the sum always equals the total.
    static func splitInstallments(totalCents: Int64, count: Int) -> [Int64] {
        guard count > 0 else { return [] }
        let n = Int64(count)
        let base = totalCents / n
        let rest = totalCents - base * n
        return (0..<count).map { $0 == 0 ? base + rest : base }
    }

    /// Adds i months to the start date (Jan 31 → Feb 28 → Mar 31).
    static func monthlyDates(from start: Date, count: Int, calendar: Calendar = .ptBR) -> [Date] {
        (0..<count).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }

    /// Signed effect of one transaction on one account's balance.
    static func effect(of t: FinanceTransaction, on account: Account) -> Int64 {
        switch t.kind {
        case .receita: return t.account == account ? t.amountCents : 0
        case .despesa: return t.account == account ? -t.amountCents : 0
        case .transferencia:
            var v: Int64 = 0
            if t.account == account { v -= t.amountCents }
            if t.toAccount == account { v += t.amountCents }
            return v
        }
    }

    /// Balance on `date`: entries dated in the future are planned, not counted.
    /// Credit cards go negative as purchases add up; paying the invoice is a transfer into the card.
    static func balance(of account: Account, at date: Date = .now) -> Int64 {
        let txns = (account.transactions ?? []) + (account.incomingTransfers ?? [])
        return txns.filter { $0.date <= date }
            .reduce(account.initialBalanceCents) { $0 + effect(of: $1, on: account) }
    }

    /// Invoice ("yyyy-MM" of its closing month) a card purchase falls into.
    /// Purchases on or after the closing day go to the next invoice.
    static func invoiceKey(for date: Date, closingDay: Int, calendar: Calendar = .ptBR) -> String {
        let day = calendar.component(.day, from: date)
        let base = day >= closingDay ? calendar.date(byAdding: .month, value: 1, to: date)! : date
        return MonthKey.of(base, calendar: calendar)
    }

    /// Purchases minus refunds in one invoice. Payments (transfers into the card) are not counted.
    static func invoiceTotal(card: Account, key: String) -> Int64 {
        let closing = card.closingDay ?? 1
        return (card.transactions ?? [])
            .filter { invoiceKey(for: $0.date, closingDay: closing) == key }
            .reduce(0) { total, t in
                switch t.kind {
                case .despesa: total + t.amountCents
                case .receita: total - t.amountCents
                case .transferencia: total
                }
            }
    }

    struct Summary {
        var income: Int64 = 0
        var expense: Int64 = 0
        var net: Int64 { income - expense }
    }

    /// Transfers move money between own accounts and are neither income nor expense.
    static func summary(_ txns: [FinanceTransaction]) -> Summary {
        txns.reduce(into: Summary()) { s, t in
            switch t.kind {
            case .receita: s.income += t.amountCents
            case .despesa: s.expense += t.amountCents
            case .transferencia: break
            }
        }
    }

    static func expensesByRootCategory(_ txns: [FinanceTransaction]) -> [CategoryTotal] {
        var totals: [String: Int64] = [:]
        for t in txns where t.kind == .despesa {
            let root = t.category.map { $0.parent ?? $0 }
            totals[root?.name ?? "Sem categoria", default: 0] += t.amountCents
        }
        return totals.map { CategoryTotal(name: $0.key, cents: $0.value) }.sorted { $0.cents > $1.cents }
    }

    /// Expenses in a category including its subcategories.
    static func spent(in category: FinanceCategory, _ txns: [FinanceTransaction]) -> Int64 {
        txns.filter { $0.kind == .despesa && ($0.category == category || $0.category?.parent == category) }
            .reduce(0) { $0 + $1.amountCents }
    }

    static func effectiveLimit(_ budgets: [Budget], key: String) -> Int64? {
        guard let latest = budgets.filter({ $0.month <= key }).max(by: { $0.month < $1.month }),
              latest.limitCents > 0 else { return nil }
        return latest.limitCents
    }
}
