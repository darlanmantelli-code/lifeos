import SwiftUI
import SwiftData

enum HomeRoute: String, Hashable { case compras, saude, automacoes, configuracoes }

struct HomeView: View {
    @AppStorage("dash.order") private var orderRaw = ""
    @AppStorage("dash.hidden") private var hiddenRaw = ""
    @AppStorage("dash.period") private var period: DashPeriod = .dia
    @State private var query = ""
    @State private var showEditor = false
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        if let r = HomeRoute(rawValue: LaunchArgs.string("route") ?? "") { p.append(r) }
        return p
    }()

    private var greeting: String {
        switch Calendar.ptBR.component(.hour, from: .now) {
        case 5..<12: "Bom dia"
        case 12..<18: "Boa tarde"
        default: "Boa noite"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    dashboard
                } else {
                    SearchResultsView(query: query)
                }
            }
            .navigationTitle(greeting)
            .searchable(text: $query, prompt: "Buscar lançamentos, tarefas, compras…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Módulos") {
                            Button("Compras", systemImage: "cart") { path.append(HomeRoute.compras) }
                            Button("Saúde", systemImage: "heart") { path.append(HomeRoute.saude) }
                            Button("Automações", systemImage: "gearshape.2") { path.append(HomeRoute.automacoes) }
                        }
                        Button("Editar painel", systemImage: "slider.horizontal.3") { showEditor = true }
                        Button("Configurações", systemImage: "gearshape") { path.append(HomeRoute.configuracoes) }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel("Menu geral")
                }
            }
            .navigationDestination(for: HomeRoute.self) { r in
                switch r {
                case .compras: ShoppingHomeView()
                case .saude: HealthView()
                case .automacoes: AutomationsView()
                case .configuracoes: SettingsView()
                }
            }
            .navigationDestination(for: Goal.self) { GoalDetailView(goal: $0) }
            .navigationDestination(for: Habit.self) { HabitDetailView(habit: $0) }
            .navigationDestination(for: ShoppingList.self) { ShoppingListView(list: $0) }
            .sheet(isPresented: $showEditor) { DashboardEditor(orderRaw: $orderRaw, hiddenRaw: $hiddenRaw) }
        }
    }

    private var dashboard: some View {
        let widgets = DashboardLayout.visible(orderRaw: orderRaw, hiddenRaw: hiddenRaw)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.ptBR)).firstUppercased)
                    .foregroundStyle(.secondary)
                Picker("Período", selection: $period) {
                    ForEach(DashPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if widgets.isEmpty {
                    ContentUnavailableView {
                        Label("Painel vazio", systemImage: "square.grid.2x2")
                    } actions: {
                        Button("Escolher widgets") { showEditor = true }
                    }
                }
                ForEach(widgets) { widget($0) }

                Text("livo · sua vida mais inteligente")
                    .font(.footnote).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.s)
            }
            .padding()
            .animation(.snappy, value: widgets)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func widget(_ kind: WidgetKind) -> some View {
        switch kind {
        case .financas: FinanceWidget(period: period)
        case .alertas: AlertsWidget()
        case .tarefas: TasksWidget(period: period)
        case .habitos: HabitsWidget()
        case .pagamentos: PaymentsWidget(period: period)
        case .metas: GoalsWidget()
        case .saude: HealthWidget()
        case .compras: ShoppingWidget()
        }
    }
}

struct DashboardEditor: View {
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss
    @State private var order: [WidgetKind] = []
    @State private var hidden: Set<WidgetKind> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { k in
                        Button {
                            if hidden.contains(k) { hidden.remove(k) } else { hidden.insert(k) }
                        } label: {
                            HStack {
                                Label(k.title, systemImage: k.icon)
                                Spacer()
                                Image(systemName: hidden.contains(k) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(hidden.contains(k) ? Color.secondary : Color.lifeAccent)
                            }
                        }
                        .tint(.primary)
                        .accessibilityAddTraits(hidden.contains(k) ? [] : .isSelected)
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Toque para mostrar ou ocultar. Arraste para reordenar.")
                }
                Section {
                    Button("Restaurar padrão") {
                        order = WidgetKind.allCases
                        hidden = []
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Editar painel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluído") {
                        orderRaw = DashboardLayout.encode(order)
                        hiddenRaw = DashboardLayout.encode(order.filter { hidden.contains($0) })
                        dismiss()
                    }
                }
            }
            .onAppear {
                order = DashboardLayout.order(orderRaw)
                hidden = DashboardLayout.hidden(hiddenRaw)
            }
        }
    }
}

struct SearchResultsView: View {
    enum Sheet: Identifiable {
        case transaction(FinanceTransaction), task(TaskItem)
        var id: AnyHashable {
            switch self {
            case .transaction(let t): AnyHashable(t.persistentModelID)
            case .task(let t): AnyHashable(t.persistentModelID)
            }
        }
    }

    let query: String
    // ponytail: in-memory search over every record; move to #Predicate queries if volume hurts.
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var transactions: [FinanceTransaction]
    @Query private var tasks: [TaskItem]
    @Query private var goals: [Goal]
    @Query private var habits: [Habit]
    @Query private var items: [ShoppingItem]
    @State private var sheet: Sheet?

    private func m(_ s: String) -> Bool { SearchLogic.matches(s, query) }

    var body: some View {
        let tx = transactions.filter { m($0.title) || m($0.note) || m($0.category?.name ?? "") }.prefix(20)
        let ts = RoutineLogic.sorted(tasks.filter { m($0.title) || m($0.notes) })
        let gs = goals.filter { m($0.title) || m($0.notes) }
        let hs = habits.filter { m($0.name) }
        let its = items.filter { $0.list != nil && (m($0.name) || m($0.store) || m($0.note)) }
        List {
            if tx.isEmpty && ts.isEmpty && gs.isEmpty && hs.isEmpty && its.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            if !tx.isEmpty {
                Section("Lançamentos") {
                    ForEach(Array(tx)) { t in
                        TransactionRow(t: t).contentShape(Rectangle()).onTapGesture { sheet = .transaction(t) }
                    }
                }
            }
            if !ts.isEmpty {
                Section("Tarefas") {
                    ForEach(ts) { t in TaskRow(task: t) { sheet = .task(t) } }
                }
            }
            if !gs.isEmpty {
                Section("Metas") {
                    ForEach(gs) { g in NavigationLink(value: g) { GoalRow(goal: g) } }
                }
            }
            if !hs.isEmpty {
                Section("Hábitos") {
                    ForEach(hs) { h in NavigationLink(value: h) { HabitSummaryRow(habit: h) } }
                }
            }
            if !its.isEmpty {
                Section("Compras") {
                    ForEach(its) { i in
                        if let list = i.list {
                            NavigationLink(value: list) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(i.name).strikethrough(i.bought)
                                    Text(list.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .transaction(let t): TransactionForm(editing: t)
            case .task(let t): TaskForm(editing: t)
            }
        }
    }
}
