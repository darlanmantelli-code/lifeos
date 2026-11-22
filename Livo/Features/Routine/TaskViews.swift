import SwiftUI
import SwiftData

struct TaskRow: View {
    let task: TaskItem
    var onEdit: () -> Void

    private var subtitle: String? {
        var parts: [String] = []
        if let due = task.due { parts.append(RoutineLogic.dueLabel(due)) }
        if task.priority == .alta { parts.append("Prioridade alta") }
        if let g = task.goal { parts.append(g.title) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { RoutineStore.toggle(task) }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.done ? Color.lifeAccent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Marcar \(task.title) como pendente" : "Concluir \(task.title)")
            .sensoryFeedback(.success, trigger: task.done)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Color.secondary : Color.primary)
                if let subtitle {
                    Text(subtitle).font(.caption)
                        .foregroundStyle(RoutineLogic.isOverdue(task) ? Color.lifeExpense : Color.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

struct TaskForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.createdAt) private var goals: [Goal]

    let editing: TaskItem?
    var presetGoal: Goal?

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var priority: Priority = .media
    @State private var goal: Goal?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("O que precisa ser feito?", text: $title)
                    Picker("Prioridade", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Prazo", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Data", selection: $due, displayedComponents: .date)
                    }
                    Picker("Meta", selection: $goal) {
                        Text("Nenhuma").tag(Goal?.none)
                        ForEach(goals.filter { !$0.completed }) { Text($0.title).tag(Optional($0)) }
                    }
                }
                Section("Notas") {
                    TextField("Opcional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(editing == nil ? "Nova tarefa" : "Editar tarefa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        goal = presetGoal
        guard let t = editing else { return }
        title = t.title
        notes = t.notes
        hasDue = t.due != nil
        due = t.due ?? Date()
        priority = t.priority
        goal = t.goal
    }

    private func save() {
        let t = editing ?? TaskItem(title: "")
        if editing == nil { context.insert(t) }
        t.title = title.trimmingCharacters(in: .whitespaces)
        t.notes = notes
        t.due = hasDue ? Calendar.ptBR.startOfDay(for: due) : nil
        t.priority = priority
        t.goal = goal
        dismiss()
    }
}
