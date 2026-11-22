import SwiftUI
import SwiftData
import Charts

struct FinanceView: View {
    enum Route: Hashable { case contas, categorias, orcamentos }

    enum FormSheet: Identifiable {
        case new(TxnKind)
        case edit(FinanceTransaction)
        case newAccount
        case importar
        var id: AnyHashable {
            switch self {
            case .new(let k): AnyHashable(k)
            case .edit(let t): AnyHashable(t.persistentModelID)
            case .newAccount: AnyHashable("account")
            case .importar: AnyHashable("import")
            }
        }
    }

    struct DayGroup: Identifiable {
        let day: Date
        let items: [FinanceTransaction]
        var id: Date { day }
    }

    struct BudgetLine: Identifiable {
        let category: FinanceCategory
        let spent: Int64
        let limit: Int64
        var id: PersistentIdentifier { category.persistentModelID }
    }

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Account> { $0.archived == false }, sort: \Account.createdAt)
    private var accounts: [Account]
    // ponytail: loads every transaction and filters the month in memory; move to a month-range @Query if volume hurts.
    @Query(sort: \FinanceTransaction.date, order: .reverse)
    private var transactions: [FinanceTransaction]
    @Query(sort: \FinanceCategory.name) private var categories: [FinanceCategory]

    @State private var month = Date()
    @State private var route: Route?
    @State private var sheet: FormSheet?
    @State private var pendingDelete: FinanceTransaction?
    @State private var confirmDelete = false

    private var monthTxns: [FinanceTransaction] {
        let range = MonthKey.interval(of: month)
        return transactions.filter { $0.date >= range.start && $0.date < range.end }
    }

    private var days: [DayGroup] {
        Dictionary(grouping: monthTxns) { Calendar.ptBR.startOfDay(for: $0.date) }
            .map { DayGroup(day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private var budgetLines: [BudgetLine] {
        let key = MonthKey.of(month)
        let txns = monthTxns
        return categories.filter { $0.parent == nil && $0.kind == .despesa }.compactMap { c in
            guard let limit = FinanceLogic.effectiveLimit(c.budgets ?? [], key: key) else { return nil }
            return BudgetLine(category: c, spent: FinanceLogic.spent(in: c, txns), limit: limit)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty { emptyState } else { content }
            }
            .navigationTitle("Finanças")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Contas e cartões", systemImage: "creditcard") { route = .contas }
                        Button("Categorias", systemImage: "tag") { route = .categorias }
                        Button("Orçamentos", systemImage: "chart.bar") { route = .orcamentos }
                        Button("Importar extrato (OFX/CSV)", systemImage: "square.and.arrow.down") { sheet = .importar }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Mais opções")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .new(.despesa) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Novo lançamento")
                        .disabled(accounts.isEmpty)
                }
            }
            .navigationDestination(item: $route) { r in
                switch r {
                case .contas: AccountsView()
                case .categorias: CategoriesView()
                case .orcamentos: BudgetsView(month: month)
                }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .new(let kind): TransactionForm(initialKind: kind)
                case .edit(let t): TransactionForm(editing: t)
                case .newAccount: AccountForm(editing: nil)
                case .importar: ImportView()
                }
            }
            .confirmationDialog("Apagar lançamento?", isPresented: $confirmDelete, presenting: pendingDelete) { t in
                if t.groupID != nil {
                    Button("Apagar este e os próximos", role: .destructive) {
                        try? FinanceStore.delete(t, includingFuture: true, in: context)
                    }
                }
                Button(t.groupID != nil ? "Apagar só este" : "Apagar", role: .destructive) {
                    try? FinanceStore.delete(t, includingFuture: false, in: context)
                }
            } message: { _ in
                Text("Esta ação não pode ser desfeita.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nenhuma conta ainda", systemImage: "creditcard")
        } description: {
            Text("Cadastre sua primeira conta ou cartão para começar a lançar receitas e despesas.")
        } actions: {
            Button("Criar conta") { sheet = .newAccount }
                .buttonStyle(.borderedProminent)
        }
    }

    private var content: some View {
        let summary = FinanceLogic.summary(monthTxns)
        let consolidated = accounts.reduce(Int64(0)) { $0 + FinanceLogic.balance(of: $1) }
        let byCategory = FinanceLogic.expensesByRootCategory(monthTxns)
        let budgets = budgetLines

        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saldo consolidado hoje").font(.subheadline).foregroundStyle(.secondary)
                    Text(Money.format(consolidated)).font(.largeTitle.bold()).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                monthPicker
                HStack(alignment: .top) {
                    stat("Receitas", summary.income, .lifeIncome)
                    stat("Despesas", summary.expense, .lifeExpense)
                    stat("Resultado", summary.net, .primary)
                }
            }

            if !byCategory.isEmpty {
                Section("Para onde foi o dinheiro") {
                    Chart(byCategory) { item in
                        SectorMark(angle: .value("Valor", Double(item.cents)), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(by: .value("Categoria", item.name))
                            .cornerRadius(4)
                    }
                    .frame(height: 220)
                    .padding(.vertical, Spacing.s)
                }
            }

            if !budgets.isEmpty {
                Section("Orçamentos do mês") {
                    ForEach(budgets) { b in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(b.category.name, systemImage: b.category.icon)
                                Spacer()
                                Text("\(Money.format(b.spent)) de \(Money.format(b.limit))")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(min(b.spent, b.limit)), total: Double(b.limit))
                                .tint(b.spent > b.limit ? Color.lifeExpense : Color.lifeAccent)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if days.isEmpty {
                Section {
                    Text("Nenhum lançamento neste mês.").foregroundStyle(.secondary)
                }
            }
            ForEach(days) { group in
                Section {
                    ForEach(group.items) { t in
                        TransactionRow(t: t)
                            .contentShape(Rectangle())
                            .onTapGesture { sheet = .edit(t) }
                            .swipeActions {
                                Button("Apagar", systemImage: "trash") {
                                    pendingDelete = t
                                    confirmDelete = true
                                }
                                .tint(.red)
                            }
                    }
                } header: {
                    Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.ptBR)))
                }
            }
        }
        .animation(.default, value: month)
    }

    private var monthPicker: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Mês anterior")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year().locale(.ptBR)).firstUppercased)
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Próximo mês")
        }
        .buttonStyle(.borderless)
    }

    private func shiftMonth(_ delta: Int) {
        month = Calendar.ptBR.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func stat(_ label: String, _ cents: Int64, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(cents)).font(.subheadline.bold()).monospacedDigit()
                .foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TransactionRow: View {
    let t: FinanceTransaction

    private var icon: String {
        t.kind == .transferencia ? "arrow.left.arrow.right" : (t.category?.icon ?? "tag")
    }

    private var subtitle: String {
        var parts: [String] = []
        if t.kind == .transferencia {
            parts.append("\(t.account?.name ?? "?") → \(t.toAccount?.name ?? "?")")
        } else {
            parts.append(t.account?.name ?? "Sem conta")
        }
        if let i = t.installmentIndex, let n = t.installmentCount { parts.append("\(i)/\(n)") }
        if t.isRecurring { parts.append("recorrente") }
        if t.date > .now { parts.append("previsto") }
        return parts.joined(separator: " · ")
    }

    private var amount: (String, Color) {
        switch t.kind {
        case .receita: ("+" + Money.format(t.amountCents), .lifeIncome)
        case .despesa: ("−" + Money.format(t.amountCents), .primary)
        case .transferencia: (Money.format(t.amountCents), .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 34, height: 34)
                .background(Color.lifeAccent.opacity(0.12), in: Circle())
                .foregroundStyle(Color.lifeAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(amount.0).monospacedDigit().foregroundStyle(amount.1)
        }
        .opacity(t.date > .now ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
