import Foundation
import SwiftData
@preconcurrency import UserNotifications

struct AutomationFiring: Equatable {
    let key: String
    let title: String
    let body: String
}

/// Evaluates rules against the user's records. Runs when the app opens and when iOS grants a background refresh;
/// iOS decides when (and whether) background refresh happens, so date rules fire at the next chance, not to the minute.
@MainActor
enum AutomationEngine {
    /// What a rule would fire now, skipping occurrences it already handled.
    static func firings(for rule: AutomationRule, in ctx: ModelContext, now: Date = .now, calendar: Calendar = .ptBR) -> [AutomationFiring] {
        let all: [AutomationFiring]
        switch rule.trigger {
        case .faturaProxima:
            let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
            all = accounts.filter { !$0.archived && $0.kind == .cartao }.compactMap { card in
                guard let dueDay = card.dueDay else { return nil }
                let due = DashboardLogic.nextDue(day: dueDay, after: now, calendar: calendar)
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: due).day ?? 99
                guard days <= rule.parameter else { return nil }
                let when = days == 0 ? "vence hoje" : days == 1 ? "vence amanhã" : "vence em \(days) dias"
                return AutomationFiring(key: "\(card.name)|\(MonthKey.of(due, calendar: calendar))",
                                        title: "Fatura do \(card.name)",
                                        body: "A fatura \(when) (dia \(dueDay)).")
            }
        case .orcamentoPercentual:
            let month = MonthKey.interval(of: now, calendar: calendar)
            let key = MonthKey.of(now, calendar: calendar)
            let txns = ((try? ctx.fetch(FetchDescriptor<FinanceTransaction>())) ?? []).filter { $0.date >= month.start && $0.date <= now }
            let cats = ((try? ctx.fetch(FetchDescriptor<FinanceCategory>())) ?? []).filter { $0.parent == nil && $0.kind == .despesa }
            all = cats.compactMap { c in
                guard let limit = FinanceLogic.effectiveLimit(c.budgets ?? [], key: key) else { return nil }
                let spent = FinanceLogic.spent(in: c, txns)
                guard spent * 100 >= limit * Int64(rule.parameter) else { return nil }
                let pct = Int((Double(spent) / Double(limit) * 100).rounded())
                return AutomationFiring(key: "\(c.name)|\(key)|\(rule.parameter)",
                                        title: "Orçamento de \(c.name)",
                                        body: "\(pct)% usado: \(Money.format(spent)) de \(Money.format(limit)).")
            }
        case .metaAlcancada:
            let goals = (try? ctx.fetch(FetchDescriptor<Goal>())) ?? []
            all = goals.filter { RoutineLogic.progress($0) >= 1 }.map {
                AutomationFiring(key: "\($0.title)|\($0.createdAt.timeIntervalSince1970)",
                                 title: "Meta alcançada 🎉", body: "Você concluiu “\($0.title)”.")
            }
        case .tarefaAtrasada:
            let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
            all = tasks.filter { RoutineLogic.isOverdue($0, now: now, calendar: calendar) }.map {
                AutomationFiring(key: "\($0.title)|\($0.due.map { MonthKey.of($0) + "-\(calendar.component(.day, from: $0))" } ?? "")",
                                 title: "Tarefa atrasada", body: $0.title)
            }
        case .resumoSemanal:
            guard calendar.component(.weekday, from: now) == 1, calendar.component(.hour, from: now) >= rule.parameter else {
                all = []
                break
            }
            all = [AutomationFiring(key: "semana|\(calendar.startOfDay(for: now).timeIntervalSince1970)",
                                    title: "Resumo da semana", body: weeklySummary(ctx, now: now, calendar: calendar))]
        case .compromisso:
            all = CalendarService.upcoming(days: 1, now: now).filter { $0.start >= now }.map {
                AutomationFiring(key: $0.id, title: "Preparar: \($0.title)",
                                 body: "Compromisso \($0.start.formatted(.dateTime.weekday(.wide).hour().minute().locale(.ptBR))). Revise o que precisa levar ou preparar.")
            }
        }
        return all.filter { !rule.hasFired($0.key) }
    }

    /// Facts only, computed from the last 7 days of records.
    static func weeklySummary(_ ctx: ModelContext, now: Date, calendar: Calendar = .ptBR) -> String {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let txns = ((try? ctx.fetch(FetchDescriptor<FinanceTransaction>())) ?? []).filter { $0.date >= start && $0.date <= now }
        let s = FinanceLogic.summary(txns)
        let done = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { ($0.doneAt ?? .distantPast) >= start }.count
        let checkIns = ((try? ctx.fetch(FetchDescriptor<HabitCheckIn>())) ?? []).filter { $0.date >= start }.count
        return "Últimos 7 dias: despesas de \(Money.format(s.expense)), receitas de \(Money.format(s.income)), "
            + "\(done) tarefa(s) concluída(s) e \(checkIns) registro(s) de hábitos."
    }

    /// Evaluates every enabled rule, performs actions and records the history. Returns how many fired.
    @discardableResult
    static func run(in ctx: ModelContext, now: Date = .now, notify: (AutomationFiring) async -> Bool = AutomationNotifier.send) async -> Int {
        let rules = ((try? ctx.fetch(FetchDescriptor<AutomationRule>())) ?? []).filter(\.enabled)
        var count = 0
        for rule in rules {
            for f in firings(for: rule, in: ctx, now: now) {
                let ok: Bool
                switch rule.action {
                case .notificacao:
                    ok = await notify(f)
                case .tarefa:
                    ctx.insert(TaskItem(title: "\(f.title): \(f.body)", due: Calendar.ptBR.startOfDay(for: now), priority: .alta))
                    ok = true
                }
                rule.markFired(f.key)
                ctx.insert(AutomationRun(ruleLabel: rule.trigger.label,
                                         message: ok ? "\(f.title) — \(f.body)" : "Notificação não enviada (permissão negada): \(f.title)",
                                         ok: ok))
                count += 1
            }
        }
        try? ctx.save()
        return count
    }

    static let templates: [(AutomationTrigger, AutomationAction, String)] = [
        (.faturaProxima, .tarefa, "Quando uma fatura estiver perto do vencimento, criar tarefa para pagar"),
        (.metaAlcancada, .notificacao, "Quando uma meta for alcançada, enviar notificação"),
        (.orcamentoPercentual, .notificacao, "Quando um orçamento chegar a 80%, avisar"),
        (.resumoSemanal, .notificacao, "No domingo, enviar resumo da semana"),
        (.tarefaAtrasada, .notificacao, "Quando uma tarefa atrasar, avisar"),
        (.compromisso, .tarefa, "Quando houver um compromisso, criar tarefa de preparação (checklist)"),
    ]
}

enum AutomationNotifier {
    /// Asks for permission the first time a notification rule actually needs it.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func send(_ f: AutomationFiring) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = f.title
        content.body = f.body
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: f.key, content: content, trigger: nil))
            return true
        } catch {
            return false
        }
    }
}
