import SwiftUI
import SwiftData

private let habitIcons = ["checkmark.circle", "drop", "figure.walk", "book", "bed.double", "leaf",
                          "dumbbell", "brain.head.profile", "pills", "fork.knife", "music.note", "pencil"]

struct HabitCheckRow: View {
    @Environment(\.modelContext) private var context
    let habit: Habit

    var body: some View {
        let count = RoutineLogic.count(habit, in: RoutineLogic.period(of: .now, habit.frequency))
        let done = count >= habit.target
        let streak = RoutineLogic.streak(habit)
        HStack(spacing: 12) {
            HabitIcon(name: habit.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                Text("\(count)/\(habit.target) \(habit.frequency.currentPeriodLabel)" + (streak > 0 ? " · sequência de \(streak)" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.snappy) { RoutineStore.tapCheckIn(habit, in: context) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(done ? Color.lifeProgress : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: done)
            .accessibilityLabel(done ? "\(habit.name) concluído, desfazer" : "Registrar \(habit.name)")
        }
    }
}

struct HabitSummaryRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            HabitIcon(name: habit.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                Text("\(habit.target)× \(habit.frequency.perPeriodLabel)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(RoutineLogic.streak(habit))", systemImage: "flame.fill")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.orange)
                .accessibilityLabel("Sequência atual: \(RoutineLogic.streak(habit))")
        }
    }
}

struct HabitIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .frame(width: 34, height: 34)
            .background(Color.lifeAccent.opacity(0.12), in: Circle())
            .foregroundStyle(Color.lifeAccent)
            .accessibilityHidden(true)
    }
}

struct HabitDetailView: View {
    let habit: Habit
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                HStack {
                    stat("Sequência atual", RoutineLogic.streak(habit))
                    stat("Melhor sequência", RoutineLogic.bestStreak(habit))
                    stat("Registros", habit.checkIns?.count ?? 0)
                }
            }
            Section("Últimas 12 semanas") {
                HabitHeatmap(habit: habit).frame(maxWidth: .infinity)
            }
            Section {
                Button(habit.archived ? "Reativar hábito" : "Arquivar hábito", systemImage: "archivebox") {
                    habit.archived.toggle()
                }
                Button("Apagar hábito", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(habit.name)
        .brandScreen()
        .toolbar { Button("Editar") { showEdit = true } }
        .sheet(isPresented: $showEdit) { HabitForm(editing: habit) }
        .confirmationDialog("Apagar \(habit.name)?", isPresented: $confirmDelete) {
            Button("Apagar", role: .destructive) {
                dismiss()
                context.delete(habit)
            }
        } message: {
            Text("Todo o histórico de registros deste hábito também será apagado.")
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// GitHub-style grid: one column per week, one cell per day.
struct HabitHeatmap: View {
    let habit: Habit
    private let weeks = 12

    var body: some View {
        let cal = Calendar.ptBR
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        let counts = Dictionary(grouping: habit.checkIns ?? []) { cal.startOfDay(for: $0.date) }.mapValues(\.count)
        let total = counts.filter { $0.key >= start }.values.reduce(0, +)
        HStack(spacing: 4) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(fill(counts[day] ?? 0, future: day > .now))
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement()
        .accessibilityLabel("\(total) registros nas últimas \(weeks) semanas")
    }

    private func fill(_ count: Int, future: Bool) -> Color {
        if future { return .clear }
        if count == 0 { return Color.secondary.opacity(0.15) }
        return Color.lifeAccent.opacity(min(1, 0.45 + 0.25 * Double(count - 1)))
    }
}

struct HabitForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let editing: Habit?

    @State private var name = ""
    @State private var icon = habitIcons[0]
    @State private var frequency: HabitFrequency = .diaria
    @State private var target = 1
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (ex.: Beber água, Ler 20 min)", text: $name)
                    Picker("Frequência", selection: $frequency) {
                        ForEach(HabitFrequency.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper("\(target)× \(frequency.perPeriodLabel)", value: $target, in: 1...30)
                }
                Section("Ícone") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(habitIcons, id: \.self) { i in
                            Button { icon = i } label: {
                                Image(systemName: i)
                                    .frame(width: 40, height: 40)
                                    .background(icon == i ? Color.lifeAccent.opacity(0.2) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(i)
                            .accessibilityAddTraits(icon == i ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Novo hábito" : "Editar hábito")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let h = editing else { return }
        loaded = true
        name = h.name
        icon = h.icon
        frequency = h.frequency
        target = h.target
    }

    private func save() {
        let h = editing ?? Habit(name: "")
        if editing == nil { context.insert(h) }
        h.name = name.trimmingCharacters(in: .whitespaces)
        h.icon = icon
        h.frequency = frequency
        h.targetPerPeriod = target
        dismiss()
    }
}
