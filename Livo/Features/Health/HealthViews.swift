import SwiftUI
import SwiftData
import Charts

private let healthDisclaimer = "Registros pessoais para acompanhamento. O livo não faz diagnósticos nem recomendações clínicas; para isso, procure um profissional de saúde. A integração com o app Saúde da Apple chega em uma etapa futura."

struct HealthView: View {
    // ponytail: loads every entry and filters per card in memory; per-kind queries if volume hurts.
    @Query(sort: \HealthEntry.date, order: .reverse) private var entries: [HealthEntry]
    @Query private var targets: [HealthTarget]
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(HealthKind.allCases) { k in
                    NavigationLink {
                        HealthMetricView(kind: k)
                    } label: {
                        HealthCard(kind: k, entries: entries.filter { $0.kind == k },
                                   target: targets.first { $0.kindRaw == k.rawValue }?.value)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            Text(healthDisclaimer)
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Saúde")
        .toolbar {
            Button { showAdd = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Novo registro")
        }
        .sheet(isPresented: $showAdd) { HealthEntryForm(kind: .agua) }
    }
}

struct HealthCard: View {
    let kind: HealthKind
    let entries: [HealthEntry]
    let target: Double?

    var body: some View {
        let current = HealthLogic.current(entries, kind)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(kind.label, systemImage: kind.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.lifeAccent)
                .lineLimit(1)
            if let current {
                (Text(HealthLogic.format(current.value, current.value2, kind)).font(.title2.bold())
                    + Text(" \(kind.unit)").font(.caption).foregroundStyle(.secondary))
                    .monospacedDigit()
                Text(kind.aggregation == .sum ? "hoje" : current.date.formatted(.dateTime.day().month().locale(.ptBR)))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Sem registros").font(.subheadline).foregroundStyle(.secondary)
            }
            if kind.supportsDailyTarget, let target {
                ProgressView(value: min((current?.value ?? 0) / target, 1))
                    .tint(Color.lifeAccent)
                    .accessibilityLabel("Meta diária: \(HealthLogic.format(target, kind)) \(kind.unit)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct HealthMetricView: View {
    let kind: HealthKind
    @Environment(\.modelContext) private var context
    @Query private var entries: [HealthEntry]
    @Query private var targets: [HealthTarget]
    @State private var showAdd = false
    @State private var showTarget = false
    @State private var targetText = ""

    init(kind: HealthKind) {
        self.kind = kind
        let raw = kind.rawValue
        _entries = Query(filter: #Predicate<HealthEntry> { $0.kindRaw == raw }, sort: \HealthEntry.date, order: .reverse)
    }

    private var target: Double? { targets.first { $0.kindRaw == kind.rawValue }?.value }

    var body: some View {
        let series = HealthLogic.daily(entries, kind, days: 30)
        let avg = HealthLogic.average(entries, kind)
        let change = HealthLogic.weeklyChange(entries, kind)
        List {
            Section("Últimos 30 dias") {
                if series.isEmpty {
                    Text("Sem registros no período.").foregroundStyle(.secondary)
                } else {
                    chart(series).frame(height: 220).padding(.vertical, Spacing.s)
                }
            }
            Section {
                LabeledContent("Média diária (7 dias)", value: avg.map { "\(HealthLogic.format($0, kind)) \(kind.unit)" } ?? "—")
                LabeledContent("Variação vs. semana anterior",
                               value: change.map { ($0 > 0 ? "+" : "") + "\(HealthLogic.format($0, kind)) \(kind.unit)" } ?? "—")
                if kind.supportsDailyTarget {
                    Button {
                        targetText = target.map { HealthLogic.format($0, kind) } ?? ""
                        showTarget = true
                    } label: {
                        LabeledContent("Meta diária", value: target.map { "\(HealthLogic.format($0, kind)) \(kind.unit)" } ?? "Definir")
                    }
                    .tint(.primary)
                }
            }
            .monospacedDigit()
            Section("Registros") {
                if entries.isEmpty { Text("Nenhum registro ainda.").foregroundStyle(.secondary) }
                ForEach(entries.prefix(100)) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(HealthLogic.format(e.value, e.value2, kind)) \(kind.unit)").monospacedDigit()
                            if !e.note.isEmpty { Text(e.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(e.date.formatted(.dateTime.day().month().hour().minute().locale(.ptBR)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Apagar", systemImage: "trash", role: .destructive) { context.delete(e) }
                    }
                }
            }
            Section { Text(healthDisclaimer).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle(kind.label)
        .toolbar {
            Button { showAdd = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Novo registro de \(kind.label)")
        }
        .sheet(isPresented: $showAdd) { HealthEntryForm(kind: kind) }
        .alert("Meta diária (\(kind.unit))", isPresented: $showTarget) {
            TextField("0", text: $targetText).keyboardType(.decimalPad)
            Button("Salvar") { try? HealthStore.setTarget(parseNumber(targetText), for: kind, in: context) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deixe vazio ou 0 para remover a meta.")
        }
    }

    @ViewBuilder
    private func chart(_ series: [DayValue]) -> some View {
        Chart {
            ForEach(series) { p in
                if kind.aggregation == .sum {
                    BarMark(x: .value("Dia", p.day, unit: .day), y: .value(kind.unit, p.value))
                        .foregroundStyle(Color.lifeAccent)
                        .cornerRadius(3)
                } else {
                    LineMark(x: .value("Dia", p.day, unit: .day), y: .value(kind.unit, p.value),
                             series: .value("Medida", kind.hasSecondValue ? "Sistólica" : kind.label))
                        .foregroundStyle(Color.lifeAccent)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Dia", p.day, unit: .day), y: .value(kind.unit, p.value))
                        .foregroundStyle(Color.lifeAccent)
                    if let v2 = p.value2 {
                        LineMark(x: .value("Dia", p.day, unit: .day), y: .value(kind.unit, v2),
                                 series: .value("Medida", "Diastólica"))
                            .foregroundStyle(Color.lifeAccent.opacity(0.5))
                            .interpolationMethod(.catmullRom)
                    }
                }
            }
            if kind.supportsDailyTarget, let target {
                RuleMark(y: .value("Meta", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Meta").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: kind.aggregation == .sum))
        .accessibilityLabel("Gráfico de \(kind.label) nos últimos 30 dias")
    }
}

struct HealthEntryForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: HealthKind
    @State private var valueText = ""
    @State private var value2Text = ""
    @State private var date = Date()
    @State private var note = ""

    init(kind: HealthKind) { _kind = State(initialValue: kind) }

    private var value: Double? { parseNumber(valueText).flatMap { $0 > 0 ? $0 : nil } }
    private var value2: Double? { parseNumber(value2Text).flatMap { $0 > 0 ? $0 : nil } }
    private var isValid: Bool { value != nil && (!kind.hasSecondValue || value2 != nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $kind) {
                        ForEach(HealthKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    LabeledContent(kind.hasSecondValue ? "Sistólica (\(kind.unit))" : "Valor (\(kind.unit))") {
                        TextField("0", text: $valueText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if kind.hasSecondValue {
                        LabeledContent("Diastólica (\(kind.unit))") {
                            TextField("0", text: $value2Text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    if kind == .agua {
                        HStack {
                            ForEach([200, 300, 500], id: \.self) { ml in
                                Button("\(ml) ml") { valueText = "\(ml)" }.buttonStyle(.bordered)
                            }
                        }
                    }
                    DatePicker("Quando", selection: $date, in: ...Date.now)
                }
                Section("Observação") {
                    TextField("Opcional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Novo registro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(!isValid) }
            }
        }
    }

    private func save() {
        guard let value else { return }
        let e = HealthEntry(kind: kind, value: value, value2: kind.hasSecondValue ? value2 : nil, date: date)
        e.note = note
        context.insert(e)
        dismiss()
    }
}
