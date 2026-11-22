import Foundation

enum DashPeriod: String, CaseIterable, Identifiable {
    case dia = "Dia", semana = "Semana", mes = "Mês"
    var id: String { rawValue }

    func interval(at now: Date = .now, calendar: Calendar = .ptBR) -> DateInterval {
        let component: Calendar.Component = switch self {
        case .dia: .day
        case .semana: .weekOfYear
        case .mes: .month
        }
        return calendar.dateInterval(of: component, for: now)!
    }

    var untilLabel: String {
        switch self {
        case .dia: "até o fim do dia"
        case .semana: "até o fim da semana"
        case .mes: "até o fim do mês"
        }
    }
}

enum WidgetKind: String, CaseIterable, Identifiable {
    case financas, alertas, tarefas, habitos, pagamentos, metas, saude, compras
    var id: String { rawValue }

    var title: String {
        switch self {
        case .financas: "Resumo financeiro"
        case .alertas: "Alertas"
        case .tarefas: "Tarefas prioritárias"
        case .habitos: "Hábitos pendentes"
        case .pagamentos: "Pagamentos programados"
        case .metas: "Metas"
        case .saude: "Saúde hoje"
        case .compras: "Compras"
        }
    }

    var icon: String {
        switch self {
        case .financas: "creditcard"
        case .alertas: "exclamationmark.triangle"
        case .tarefas: "checklist"
        case .habitos: "repeat"
        case .pagamentos: "calendar.badge.clock"
        case .metas: "target"
        case .saude: "heart"
        case .compras: "cart"
        }
    }
}

/// Widget order and visibility, stored as comma-separated ids in @AppStorage.
enum DashboardLayout {
    /// Known ids in stored order, then any widget missing from storage (new widgets show up automatically).
    static func order(_ raw: String) -> [WidgetKind] {
        var seen = Set<WidgetKind>()
        var out: [WidgetKind] = []
        for id in raw.split(separator: ",") {
            if let k = WidgetKind(rawValue: String(id)), seen.insert(k).inserted { out.append(k) }
        }
        return out + WidgetKind.allCases.filter { !seen.contains($0) }
    }

    static func hidden(_ raw: String) -> Set<WidgetKind> {
        Set(raw.split(separator: ",").compactMap { WidgetKind(rawValue: String($0)) })
    }

    static func visible(orderRaw: String, hiddenRaw: String) -> [WidgetKind] {
        let h = hidden(hiddenRaw)
        return order(orderRaw).filter { !h.contains($0) }
    }

    static func encode(_ kinds: [WidgetKind]) -> String {
        kinds.map(\.rawValue).joined(separator: ",")
    }
}

struct DashAlert: Identifiable {
    enum Tone { case warning, critical }
    let id: String
    let icon: String
    let text: String
    let tone: Tone
}

/// Rule-based alerts computed from the user's own records. No guesses.
enum DashboardLogic {
    /// Next calendar date with `day` (1–28) on or after today.
    static func nextDue(day: Int, after now: Date, calendar: Calendar = .ptBR) -> Date {
        let today = calendar.startOfDay(for: now)
        var c = calendar.dateComponents([.year, .month], from: today)
        c.day = day
        let candidate = calendar.date(from: c)!
        return candidate >= today ? candidate : calendar.date(byAdding: .month, value: 1, to: candidate)!
    }

    static func alerts(accounts: [Account], transactions: [FinanceTransaction], categories: [FinanceCategory],
                       tasks: [TaskItem], now: Date = .now, calendar: Calendar = .ptBR) -> [DashAlert] {
        var out: [DashAlert] = []

        // Budgets: spent so far this month (planned future entries excluded).
        let month = MonthKey.interval(of: now, calendar: calendar)
        let key = MonthKey.of(now, calendar: calendar)
        let spentSoFar = transactions.filter { $0.date >= month.start && $0.date <= now }
        for c in categories where c.parent == nil && c.kind == .despesa {
            guard let limit = FinanceLogic.effectiveLimit(c.budgets ?? [], key: key) else { continue }
            let spent = FinanceLogic.spent(in: c, spentSoFar)
            if spent > limit {
                out.append(DashAlert(id: "budget-\(c.name)", icon: "chart.bar.fill",
                                     text: "Orçamento de \(c.name) estourado: \(Money.format(spent)) de \(Money.format(limit))",
                                     tone: .critical))
            } else if spent * 10 >= limit * 8 {
                let pct = Int((Double(spent) / Double(limit) * 100).rounded())
                out.append(DashAlert(id: "budget-\(c.name)", icon: "chart.bar",
                                     text: "\(c.name) já usou \(pct)% do orçamento do mês", tone: .warning))
            }
        }

        for a in accounts where !a.archived {
            if a.kind == .cartao, let due = a.dueDay {
                let date = nextDue(day: due, after: now, calendar: calendar)
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day ?? 0
                if days <= 5 {
                    let when = days == 0 ? "vence hoje" : days == 1 ? "vence amanhã" : "vence em \(days) dias"
                    out.append(DashAlert(id: "card-\(a.name)", icon: "creditcard.fill",
                                         text: "Fatura do \(a.name) \(when)", tone: days <= 1 ? .critical : .warning))
                }
            } else if a.kind != .cartao, FinanceLogic.balance(of: a, at: now) < 0 {
                out.append(DashAlert(id: "negative-\(a.name)", icon: "minus.circle.fill",
                                     text: "\(a.name) está com saldo negativo", tone: .critical))
            }
        }

        let overdue = tasks.filter { RoutineLogic.isOverdue($0, now: now, calendar: calendar) }.count
        if overdue > 0 {
            out.append(DashAlert(id: "overdue", icon: "clock.badge.exclamationmark",
                                 text: overdue == 1 ? "1 tarefa atrasada" : "\(overdue) tarefas atrasadas", tone: .warning))
        }
        return out.sorted { ($0.tone == .critical ? 0 : 1) < ($1.tone == .critical ? 0 : 1) }
    }

    /// Planned expenses (dated after `now`) until `end`, soonest first.
    static func upcomingPayments(_ transactions: [FinanceTransaction], now: Date = .now, until end: Date) -> [FinanceTransaction] {
        transactions.filter { $0.kind == .despesa && $0.date > now && $0.date < end }.sorted { $0.date < $1.date }
    }
}

enum SearchLogic {
    /// Case- and accent-insensitive ("alimentacao" finds "Alimentação").
    static func matches(_ text: String, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && text.localizedStandardContains(q)
    }
}
