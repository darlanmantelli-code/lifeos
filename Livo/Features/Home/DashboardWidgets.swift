import SwiftUI
import SwiftData

struct WidgetCard<Content: View>: View {
    let kind: WidgetKind
    @ViewBuilder var content: Content

    init(_ kind: WidgetKind, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(kind.title).foregroundStyle(Color.lifeInk)
            } icon: {
                Image(systemName: kind.icon).foregroundStyle(Color.lifeAccent)
            }
            .font(.headline)
            content
        }
        .card()
    }
}

private struct EmptyLine: View {
    let text: String
    var body: some View { Text(text).font(.subheadline).foregroundStyle(.secondary) }
}

struct FinanceWidget: View {
    let period: DashPeriod
    @Query(filter: #Predicate<Account> { $0.archived == false }) private var accounts: [Account]
    @Query private var transactions: [FinanceTransaction]

    var body: some View {
        let range = period.interval()
        let summary = FinanceLogic.summary(transactions.filter { $0.date >= range.start && $0.date < range.end })
        let balance = accounts.reduce(Int64(0)) { $0 + FinanceLogic.balance(of: $1) }
        VStack(alignment: .leading, spacing: Spacing.m) {
            if accounts.isEmpty {
                Label("Resumo financeiro", systemImage: WidgetKind.financas.icon).font(.headline)
                Text("Cadastre uma conta na aba Finanças para ver seu saldo aqui.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saldo consolidado").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.75))
                    Text(Money.format(balance))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(balance < 0 ? Color(hex: 0xFFB4B8) : Color.white)
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .top, spacing: Spacing.l) {
                    heroStat("Receitas", summary.income, tint: Color(hex: 0x7DF0C2))
                    heroStat("Despesas", summary.expense, tint: Color(hex: 0xFFB4B8))
                }
                Text("\(period.rawValue) atual · inclui lançamentos previstos")
                    .font(.caption2).foregroundStyle(.white.opacity(0.65))
            }
        }
        .heroCard()
    }

    private func heroStat(_ label: String, _ cents: Int64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            Text(Money.format(cents)).font(.headline).monospacedDigit().foregroundStyle(tint)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AlertsWidget: View {
    @Query private var accounts: [Account]
    @Query private var transactions: [FinanceTransaction]
    @Query private var categories: [FinanceCategory]
    @Query private var tasks: [TaskItem]

    var body: some View {
        let alerts = DashboardLogic.alerts(accounts: accounts, transactions: transactions, categories: categories, tasks: tasks)
        WidgetCard(.alertas) {
            if alerts.isEmpty {
                Label("Tudo em dia", systemImage: "checkmark.seal").foregroundStyle(.secondary)
            }
            ForEach(alerts) { a in
                Label(a.text, systemImage: a.icon)
                    .font(.subheadline)
                    .foregroundStyle(a.tone == .critical ? Color.lifeExpense : Color.orange)
            }
        }
    }
}

struct TasksWidget: View {
    let period: DashPeriod
    @Query private var tasks: [TaskItem]
    @State private var editing: TaskItem?

    var body: some View {
        let end = period.interval().end
        let items = RoutineLogic.sorted(tasks.filter { !$0.done && ($0.due ?? .distantFuture) < end }).prefix(5)
        WidgetCard(.tarefas) {
            if items.isEmpty { EmptyLine(text: "Nenhuma tarefa com prazo \(period.untilLabel).") }
            ForEach(Array(items)) { t in
                TaskRow(task: t) { editing = t }
            }
        }
        .sheet(item: $editing) { TaskForm(editing: $0) }
    }
}

struct HabitsWidget: View {
    @Query(filter: #Predicate<Habit> { $0.archived == false }, sort: \Habit.createdAt) private var habits: [Habit]

    var body: some View {
        let pending = habits.filter { !RoutineLogic.isComplete($0) }
        WidgetCard(.habitos) {
            if habits.isEmpty {
                EmptyLine(text: "Crie hábitos na aba Rotina.")
            } else if pending.isEmpty {
                Label("Todos os hábitos do período feitos", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            ForEach(pending) { HabitCheckRow(habit: $0) }
        }
    }
}

struct PaymentsWidget: View {
    let period: DashPeriod
    @Query private var transactions: [FinanceTransaction]

    var body: some View {
        let items = DashboardLogic.upcomingPayments(transactions, until: period.interval().end)
        WidgetCard(.pagamentos) {
            if items.isEmpty { EmptyLine(text: "Nada programado \(period.untilLabel).") }
            ForEach(items.prefix(5)) { t in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).lineLimit(1)
                        Text(t.date.formatted(.dateTime.weekday(.abbreviated).day().month().locale(.ptBR)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.format(t.amountCents)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            if items.count > 1 {
                LabeledContent("Total", value: Money.format(items.reduce(0) { $0 + $1.amountCents }))
                    .font(.subheadline.bold()).monospacedDigit()
            }
        }
    }
}

struct GoalsWidget: View {
    @Query private var goals: [Goal]

    var body: some View {
        let active = goals.filter { !$0.completed }
            .sorted { ($0.priorityRaw, $1.deadline ?? .distantFuture) > ($1.priorityRaw, $0.deadline ?? .distantFuture) }
            .prefix(3)
        WidgetCard(.metas) {
            if active.isEmpty { EmptyLine(text: "Nenhuma meta ativa.") }
            ForEach(Array(active)) { g in
                NavigationLink(value: g) { GoalRow(goal: g) }.buttonStyle(.plain)
            }
        }
    }
}

struct HealthWidget: View {
    @Query private var entries: [HealthEntry]
    @Query private var targets: [HealthTarget]
    private let kinds: [HealthKind] = [.passos, .agua, .sono, .exercicio]

    var body: some View {
        WidgetCard(.saude) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(kinds[(row * 2)..<(row * 2 + 2)]) { k in cell(k) }
                    }
                }
            }
            NavigationLink("Ver saúde", value: HomeRoute.saude).font(.subheadline)
        }
    }

    private func cell(_ k: HealthKind) -> some View {
        let value = HealthLogic.current(entries.filter { $0.kind == k }, k)?.value
        let target = targets.first { $0.kindRaw == k.rawValue }?.value
        return VStack(alignment: .leading, spacing: 4) {
            Label(k.label, systemImage: k.icon).font(.caption).foregroundStyle(.secondary)
            Text(value.map { "\(HealthLogic.format($0, k)) \(k.unit)" } ?? "—").font(.subheadline.bold()).monospacedDigit()
            if let target {
                ProgressView(value: min((value ?? 0) / target, 1)).tint(Color.lifeProgress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ShoppingWidget: View {
    @Query(filter: #Predicate<ShoppingItem> { $0.bought == false }) private var pending: [ShoppingItem]

    var body: some View {
        let shopping = pending.filter { $0.list?.isWishlist == false }
        let wishes = pending.filter { $0.list?.isWishlist == true }
        let estimate = ShoppingLogic.estimate(shopping)
        WidgetCard(.compras) {
            if pending.isEmpty {
                EmptyLine(text: "Nenhum item pendente.")
            } else {
                LabeledContent("Itens a comprar", value: "\(shopping.count)")
                if estimate.cents > 0 {
                    LabeledContent("Estimativa (informada por você)", value: Money.format(estimate.cents)).monospacedDigit()
                }
                LabeledContent("Desejos", value: "\(wishes.count)")
            }
            NavigationLink("Ver compras", value: HomeRoute.compras).font(.subheadline)
        }
        .font(.subheadline)
    }
}
