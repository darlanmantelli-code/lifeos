import SwiftUI
import SwiftData

struct StudiesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyItem.createdAt) private var items: [StudyItem]
    @Query(sort: \FocusSession.start, order: .reverse) private var sessions: [FocusSession]
    @State private var showNew = false

    var body: some View {
        let weekStart = Calendar.ptBR.dateInterval(of: .weekOfYear, for: .now)!.start
        let due = items.filter { StudyLogic.isReviewDue($0) }
        List {
            Section {
                NavigationLink { PomodoroView(study: nil) } label: {
                    Label("Iniciar foco (Pomodoro)", systemImage: "timer")
                }
                LabeledContent("Foco nesta semana", value: "\(StudyLogic.minutes(sessions, since: weekStart)) min")
            }
            if !due.isEmpty {
                Section("Revisões para hoje") {
                    ForEach(due) { item in
                        HStack {
                            Label(item.title, systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            Button("Revisei") { withAnimation { StudyLogic.markReviewed(item) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            ForEach(StudyKind.allCases) { kind in
                let list = items.filter { $0.kind == kind && !$0.archived }
                if !list.isEmpty {
                    Section(kind.label + "s") {
                        ForEach(list) { item in
                            NavigationLink { StudyDetailView(item: item) } label: { StudyRow(item: item) }
                        }
                    }
                }
            }
            if items.isEmpty {
                Section { Text("Cadastre cursos, livros ou assuntos para acompanhar progresso, tempo e revisões.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Estudos")
        .toolbar {
            Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Novo estudo")
        }
        .sheet(isPresented: $showNew) { StudyForm(editing: nil) }
    }
}

struct StudyRow: View {
    let item: StudyItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(item.title, systemImage: item.kind.icon)
                Spacer()
                Text("\(item.progress)%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(item.progress), total: 100).tint(Color.lifeAccent)
            Text("\(StudyLogic.totalMinutes(item)) min de foco" + (item.nextReview.map { " · revisão em \($0.formatted(.dateTime.day().month().locale(.ptBR)))" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StudyDetailView: View {
    @Bindable var item: StudyItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                Stepper("Progresso: \(item.progress)%", value: $item.progress, in: 0...100, step: 5)
                ProgressView(value: Double(item.progress), total: 100).tint(Color.lifeAccent)
                LabeledContent("Tempo de foco", value: "\(StudyLogic.totalMinutes(item)) min")
                NavigationLink { PomodoroView(study: item) } label: { Label("Focar neste estudo", systemImage: "timer") }
            }
            Section {
                if let next = item.nextReview {
                    LabeledContent("Próxima revisão", value: next.formatted(.dateTime.day().month().year().locale(.ptBR)))
                    Button("Revisei agora") { StudyLogic.markReviewed(item) }
                    Button("Parar revisões", role: .destructive) { StudyLogic.stopReviews(item) }
                } else {
                    Button("Programar revisões") { StudyLogic.markReviewed(item) }
                }
            } header: {
                Text("Revisões")
            } footer: {
                Text("Intervalos crescentes: 1, 3, 7, 14, 30 e 60 dias.")
            }
            Section("Notas") {
                TextField("Resumo, capítulos, links…", text: $item.notes, axis: .vertical)
            }
            Section {
                Toggle("Arquivado", isOn: $item.archived)
                Button("Apagar", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(item.title)
        .confirmationDialog("Apagar \(item.title)?", isPresented: $confirmDelete) {
            Button("Apagar", role: .destructive) {
                dismiss()
                context.delete(item)
            }
        } message: {
            Text("As sessões de foco continuam registradas, sem vínculo.")
        }
    }
}

struct StudyForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let editing: StudyItem?
    @State private var title = ""
    @State private var kind: StudyKind = .curso
    @State private var reviews = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Título", text: $title)
                Picker("Tipo", selection: $kind) {
                    ForEach(StudyKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                Toggle("Programar revisões espaçadas", isOn: $reviews)
            }
            .navigationTitle("Novo estudo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let item = StudyItem(title: title.trimmingCharacters(in: .whitespaces), kind: kind)
                        context.insert(item)
                        if reviews { StudyLogic.markReviewed(item) }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct PomodoroView: View {
    let study: StudyItem?
    @Environment(\.modelContext) private var context
    @AppStorage("pomodoro.focus") private var focusMinutes = 25
    @AppStorage("pomodoro.pause") private var pauseMinutes = 5
    @State private var timer = PomodoroTimer()
    @State private var completed = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            VStack(spacing: Spacing.l) {
                if let study { Label(study.title, systemImage: study.kind.icon).foregroundStyle(.secondary) }
                Text(phaseLabel).font(.title3.weight(.semibold)).foregroundStyle(Color.lifeAccent)
                Text(PomodoroTimer.clock(timer.phase == .idle ? TimeInterval(focusMinutes * 60) : timer.remaining(at: now)))
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Tempo restante")
                HStack(spacing: Spacing.m) {
                    if timer.phase == .idle {
                        Button("Iniciar foco") { start(.focus) }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Parar", role: .destructive) { stop() }.buttonStyle(.bordered)
                    }
                }
                if timer.phase == .idle {
                    Stepper("Foco: \(focusMinutes) min", value: $focusMinutes, in: 5...90, step: 5)
                    Stepper("Pausa: \(pauseMinutes) min", value: $pauseMinutes, in: 1...30)
                }
                Text("Blocos concluídos agora: \(completed)").font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .onChange(of: timer.isFinished(at: now)) { _, finished in if finished { finish() } }
        }
        .navigationTitle("Foco")
        .onDisappear { if timer.phase == .pause { stop() } }
    }

    private var phaseLabel: String {
        switch timer.phase {
        case .idle: "Pronto para focar"
        case .focus: "Foco"
        case .pause: "Pausa"
        }
    }

    private func start(_ phase: PomodoroTimer.Phase) {
        let minutes = phase == .focus ? focusMinutes : pauseMinutes
        timer.start(phase, minutes: minutes, at: .now)
        if let end = timer.endsAt {
            Task {
                await PomodoroNotifier.schedule(at: end, title: phase == .focus ? "Bloco de foco concluído" : "Pausa encerrada",
                                                body: phase == .focus ? "Hora de uma pausa de \(pauseMinutes) min." : "Pronto para o próximo bloco?")
            }
        }
    }

    private func finish() {
        if timer.phase == .focus, let started = timer.startedAt {
            let session = FocusSession(start: started, minutes: focusMinutes)
            context.insert(session)
            session.study = study
            completed += 1
            start(.pause)
        } else {
            timer.stop()
        }
    }

    private func stop() {
        PomodoroNotifier.cancel()
        // A focus block interrupted midway still counts the whole minutes already spent.
        if timer.phase == .focus, let started = timer.startedAt {
            let spent = Int(Date.now.timeIntervalSince(started) / 60)
            if spent >= 1 {
                let session = FocusSession(start: started, minutes: spent)
                context.insert(session)
                session.study = study
            }
        }
        timer.stop()
    }
}
