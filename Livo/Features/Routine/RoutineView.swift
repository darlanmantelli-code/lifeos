import SwiftUI
import SwiftData

struct RoutineView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case hoje = "Hoje", tarefas = "Tarefas", habitos = "Hábitos", metas = "Metas"
        var id: String { rawValue }
    }

    enum FormSheet: Identifiable {
        case task(TaskItem?), habit(Habit?), goal(Goal?)
        var id: AnyHashable {
            switch self {
            case .task(let t): t.map { AnyHashable($0.persistentModelID) } ?? AnyHashable("task")
            case .habit(let h): h.map { AnyHashable($0.persistentModelID) } ?? AnyHashable("habit")
            case .goal(let g): g.map { AnyHashable($0.persistentModelID) } ?? AnyHashable("goal")
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \Goal.createdAt) private var goals: [Goal]

    @State private var segment: Segment = .hoje
    @State private var sheet: FormSheet?

    private var activeHabits: [Habit] { habits.filter { !$0.archived } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Seção", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, Spacing.s)

                List {
                    switch segment {
                    case .hoje: today
                    case .tarefas: taskList
                    case .habitos: habitList
                    case .metas: goalList
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Rotina")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nova tarefa", systemImage: "checklist") { sheet = .task(nil) }
                        Button("Novo hábito", systemImage: "repeat") { sheet = .habit(nil) }
                        Button("Nova meta", systemImage: "target") { sheet = .goal(nil) }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        switch segment {
                        case .hoje, .tarefas: sheet = .task(nil)
                        case .habitos: sheet = .habit(nil)
                        case .metas: sheet = .goal(nil)
                        }
                    }
                    .accessibilityLabel("Adicionar")
                }
            }
            .navigationDestination(for: Habit.self) { HabitDetailView(habit: $0) }
            .navigationDestination(for: Goal.self) { GoalDetailView(goal: $0) }
            .sheet(item: $sheet) { s in
                switch s {
                case .task(let t): TaskForm(editing: t)
                case .habit(let h): HabitForm(editing: h)
                case .goal(let g): GoalForm(editing: g)
                }
            }
        }
    }

    // MARK: Segments

    @ViewBuilder private var today: some View {
        Section("Hábitos") {
            if activeHabits.isEmpty {
                Button("Criar primeiro hábito", systemImage: "plus") { sheet = .habit(nil) }
            }
            ForEach(activeHabits) { HabitCheckRow(habit: $0) }
        }
        Section("Tarefas para hoje") {
            let due = RoutineLogic.sorted(tasks.filter { RoutineLogic.isForToday($0) })
            if due.isEmpty {
                Text("Nada com prazo para hoje.").foregroundStyle(.secondary)
            }
            ForEach(due) { taskRow($0) }
        }
    }

    @ViewBuilder private var taskList: some View {
        let pending = RoutineLogic.sorted(tasks.filter { !$0.done })
        let done = tasks.filter(\.done).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        Section("Pendentes") {
            if pending.isEmpty { Text("Nenhuma tarefa pendente.").foregroundStyle(.secondary) }
            ForEach(pending) { taskRow($0) }
        }
        if !done.isEmpty {
            Section("Concluídas") {
                ForEach(done.prefix(30)) { taskRow($0) }
            }
        }
    }

    @ViewBuilder private var habitList: some View {
        Section {
            if activeHabits.isEmpty { Text("Nenhum hábito ativo.").foregroundStyle(.secondary) }
            ForEach(activeHabits) { h in
                NavigationLink(value: h) { HabitSummaryRow(habit: h) }
            }
        }
        let archived = habits.filter(\.archived)
        if !archived.isEmpty {
            Section("Arquivados") {
                ForEach(archived) { h in
                    NavigationLink(value: h) { HabitSummaryRow(habit: h) }
                }
            }
        }
    }

    @ViewBuilder private var goalList: some View {
        if goals.isEmpty {
            Section { Text("Nenhuma meta ainda.").foregroundStyle(.secondary) }
        }
        ForEach(GoalHorizon.allCases) { horizon in
            let items = goals.filter { $0.horizon == horizon }
                .sorted { ($0.completed ? 1 : 0, -$0.priorityRaw) < ($1.completed ? 1 : 0, -$1.priorityRaw) }
            if !items.isEmpty {
                Section(horizon.label) {
                    ForEach(items) { g in
                        NavigationLink(value: g) { GoalRow(goal: g) }
                    }
                }
            }
        }
    }

    private func taskRow(_ t: TaskItem) -> some View {
        TaskRow(task: t) { sheet = .task(t) }
            .swipeActions {
                Button("Apagar", systemImage: "trash", role: .destructive) { context.delete(t) }
            }
    }
}

struct GoalRow: View {
    let goal: Goal

    var body: some View {
        let progress = RoutineLogic.progress(goal)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.title).strikethrough(goal.completed)
                Spacer()
                Text(progress.formatted(.percent.precision(.fractionLength(0)).locale(.ptBR)))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(Color.lifeAccent)
            if let d = goal.deadline {
                Text("Prazo: \(d.formatted(.dateTime.day().month(.wide).year().locale(.ptBR)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
