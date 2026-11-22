import Foundation

struct BalancePoint: Identifiable {
    let day: Date
    let cents: Int64
    var id: Date { day }
}

struct MonthTotals: Identifiable {
    let month: Date   // first day of the month
    let income: Int64
    let expense: Int64
    var id: Date { month }
}

struct UnusualExpense: Equatable {
    let title: String
    let category: String
    let cents: Int64
    let typicalCents: Int64
}

/// Estimates and patterns derived from the user's own records. Every number here is a calculation,
/// labelled as such in the UI, never presented as a fact from the bank.
enum FinanceInsights {
    /// Consolidated balance today plus planned (future-dated) entries, day by day.
    /// Transfers between own accounts don't change the consolidated total.
    static func projection(accounts: [Account], transactions: [FinanceTransaction], days: Int = 90,
                           now: Date = .now, calendar: Calendar = .ptBR) -> [BalancePoint] {
        let active = accounts.filter { !$0.archived }
        var balance = active.reduce(Int64(0)) { $0 + FinanceLogic.balance(of: $1, at: now) }
        let ids = Set(active.map(\.persistentModelID))
        let end = calendar.date(byAdding: .day, value: days, to: now)!
        var byDay: [Date: Int64] = [:]
        for t in transactions where t.date > now && t.date <= end {
            let fromActive = t.account.map { ids.contains($0.persistentModelID) } ?? false
            let toActive = t.toAccount.map { ids.contains($0.persistentModelID) } ?? false
            let delta: Int64 = switch t.kind {
            case .receita: fromActive ? t.amountCents : 0
            case .despesa: fromActive ? -t.amountCents : 0
            case .transferencia: (toActive ? t.amountCents : 0) - (fromActive ? t.amountCents : 0)
            }
            byDay[calendar.startOfDay(for: t.date), default: 0] += delta
        }
        var points = [BalancePoint(day: calendar.startOfDay(for: now), cents: balance)]
        for i in 1...days {
            let day = calendar.date(byAdding: .day, value: i, to: calendar.startOfDay(for: now))!
            balance += byDay[day] ?? 0
            points.append(BalancePoint(day: day, cents: balance))
        }
        return points
    }

    static func projected(_ points: [BalancePoint], afterDays d: Int) -> Int64? {
        points.indices.contains(d) ? points[d].cents : nil
    }

    /// Income and expense per month for the last `months` months (current included), oldest first.
    static func monthly(_ transactions: [FinanceTransaction], months: Int = 6, now: Date = .now,
                        calendar: Calendar = .ptBR) -> [MonthTotals] {
        let thisMonth = MonthKey.interval(of: now, calendar: calendar).start
        return (0..<months).reversed().map { back in
            let start = calendar.date(byAdding: .month, value: -back, to: thisMonth)!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            let s = FinanceLogic.summary(transactions.filter { $0.date >= start && $0.date < end && $0.date <= now })
            return MonthTotals(month: start, income: s.income, expense: s.expense)
        }
    }

    /// Expenses from the last 7 days that are far above what the user usually spends in that category
    /// (more than 2.5× the median of the previous 90 days, with at least 3 past entries and above R$ 50).
    static func unusualExpenses(_ transactions: [FinanceTransaction], now: Date = .now,
                                calendar: Calendar = .ptBR) -> [UnusualExpense] {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let historyStart = calendar.date(byAdding: .day, value: -97, to: now)!
        let expenses = transactions.filter { $0.kind == .despesa && $0.date <= now }
        return expenses.filter { $0.date >= weekAgo && $0.amountCents > 5_000 && $0.category != nil }.compactMap { t in
            let past = expenses.filter { $0.category == t.category && $0.date >= historyStart && $0.date < weekAgo }
                .map(\.amountCents).sorted()
            guard past.count >= 3 else { return nil }
            let median = past[past.count / 2]
            guard median > 0, t.amountCents * 10 > median * 25 else { return nil }
            return UnusualExpense(title: t.title, category: t.category?.name ?? "", cents: t.amountCents, typicalCents: median)
        }
    }
}
