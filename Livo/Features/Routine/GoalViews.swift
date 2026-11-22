import SwiftUI
import SwiftData

struct GoalDetailView: View {
    let goal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newStep = ""
    @State private var showEdit = false
    @State private var showNewTask = false
    @State private var editingTask: TaskItem?
    @State private var showValue = false
    @State private var valueText = ""
    @State private var confirmDelete = false

    private var steps: [GoalStep] { (goal.steps ?? []).sorted { $0.order < $1.order } }
    private var tasks: [TaskItem] { RoutineLogic.sorted(goal.tasks ?? []) }

    var body: some View {
        let progress = RoutineLogic.progress(goal)
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(progress.formatted(.percent.precision(.fractionLength(0)).locale(.ptBR)))
                        .font(.largeTitle.bold()).monospacedDigit()
                    ProgressView(value: progress).tint(Color.lifeProgress)
                    if let target = goal.targetValue {
                        Text("\(format(goal.currentValue ?? 0)) de \(format(target)) \(goal.unit)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let d = goal.deadline {
                        Text("Prazo: \(d.formatted(.dateTime.day().month(.wide).year().locale(.ptBR)))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if goal.targetValue != nil {
                    Button("Atualizar valor atual", systemImage: "pencil") {
                        valueText = format(goal.currentValue ?? 0)
                        showValue = true
                    }
                }
            }

            Section("Etapas") {
                ForEach(steps) { s in
                    Button {
                        withAnimation { s.done.toggle() }
                    } label: {
                        Label(s.title, systemImage: s.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(s.done ? Color.secondary : Color.primary)
                    }
                    .swipeActions {
                        Button("Apagar", systemImage: "trash", role: .destructive) { context.delete(s) }
                    }
                }
                TextField("Nova etapa", text: $newStep)
                    .submitLabel(.done)
                    .onSubmit(addStep)
            }

            Section("Tarefas") {
                ForEach(tasks) { t in
                    TaskRow(task: t) { editingTask = t }
                }
                Button("Nova tarefa para esta meta", systemImage: "plus") { showNewTask = true }
            }

            if !goal.notes.isEmpty {
                Section("Notas") { Text(goal.notes) }
            }

            Section {
                Button(goal.completed ? "Reabrir meta" : "Marcar como concluída", systemImage: "flag.checkered") {
                    goal.completed.toggle()
                }
                Button("Apagar meta", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(goal.title)
        .brandScreen()
        .toolbar { Button("Editar") { showEdit = true } }
        .sheet(isPresented: $showEdit) { GoalForm(editing: goal) }
        .sheet(isPresented: $showNewTask) { TaskForm(editing: nil, presetGoal: goal) }
        .sheet(item: $editingTask) { TaskForm(editing: $0) }
        .alert("Valor atual (\(goal.unit))", isPresented: $showValue) {
            TextField("0", text: $valueText).keyboardType(.decimalPad)
            Button("Salvar") { if let v = parseNumber(valueText) { goal.currentValue = v } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("Apagar \(goal.title)?", isPresented: $confirmDelete) {
            Button("Apagar", role: .destructive) {
                dismiss()
                context.delete(goal)
            }
        } message: {
            Text("As etapas serão apagadas. As tarefas ligadas continuam, sem meta.")
        }
    }

    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let step = GoalStep(title: title, order: (steps.last?.order ?? -1) + 1)
        context.insert(step)
        step.goal = goal
        newStep = ""
    }

    private func format(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).locale(.ptBR))
    }
}

/// "1.234,5" → 1234.5 (Brazilian separators).
func parseNumber(_ text: String) -> Double? {
    Double(text.filter { !$0.isWhitespace }
        .replacingOccurrences(of: ".", with: "")
        .replacingOccurrences(of: ",", with: "."))
}

struct GoalForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let editing: Goal?

    @State private var title = ""
    @State private var notes = ""
    @State private var horizon: GoalHorizon = .curto
    @State private var priority: Priority = .media
    @State private var hasDeadline = false
    @State private var deadline = Calendar.ptBR.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var numeric = false
    @State private var targetText = ""
    @State private var currentText = ""
    @State private var unit = ""
    @State private var loaded = false

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (!numeric || (parseNumber(targetText) ?? 0) > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Objetivo (ex.: Correr 10 km)", text: $title)
                    Picker("Horizonte", selection: $horizon) {
                        ForEach(GoalHorizon.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Prioridade", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Prazo", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Data", selection: $deadline, displayedComponents: .date)
                    }
                }
                Section {
                    Toggle("Meta numérica", isOn: $numeric.animation())
                    if numeric {
                        LabeledContent("Alvo") {
                            TextField("0", text: $targetText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Atual") {
                            TextField("0", text: $currentText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        TextField("Unidade (ex.: km, livros, R$)", text: $unit)
                    }
                } footer: {
                    Text(numeric ? "O progresso é o valor atual sobre o alvo."
                                 : "Sem meta numérica, o progresso vem das etapas e tarefas concluídas.")
                }
                Section("Notas") {
                    TextField("Por que esta meta importa?", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(editing == nil ? "Nova meta" : "Editar meta")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(!isValid) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let g = editing else { return }
        loaded = true
        title = g.title
        notes = g.notes
        horizon = g.horizon
        priority = g.priority
        hasDeadline = g.deadline != nil
        deadline = g.deadline ?? deadline
        numeric = g.targetValue != nil
        targetText = g.targetValue.map { $0.formatted(.number.locale(.ptBR)) } ?? ""
        currentText = g.currentValue.map { $0.formatted(.number.locale(.ptBR)) } ?? ""
        unit = g.unit
    }

    private func save() {
        let g = editing ?? Goal(title: "")
        if editing == nil { context.insert(g) }
        g.title = title.trimmingCharacters(in: .whitespaces)
        g.notes = notes
        g.horizon = horizon
        g.priority = priority
        g.deadline = hasDeadline ? deadline : nil
        g.targetValue = numeric ? parseNumber(targetText) : nil
        g.currentValue = numeric ? (parseNumber(currentText) ?? 0) : nil
        g.unit = numeric ? unit : ""
        dismiss()
    }
}
