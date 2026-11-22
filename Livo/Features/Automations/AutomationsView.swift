import SwiftUI
import SwiftData

struct AutomationsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AutomationRule.createdAt) private var rules: [AutomationRule]
    @Query(sort: \AutomationRun.date, order: .reverse) private var runs: [AutomationRun]
    @State private var running = false
    @State private var lastResult: String?

    var body: some View {
        List {
            Section {
                if rules.isEmpty { Text("Nenhuma regra ainda. Comece por um modelo abaixo.").foregroundStyle(.secondary) }
                ForEach(rules) { r in
                    NavigationLink { AutomationRuleView(rule: r) } label: { AutomationRuleRow(rule: r) }
                }
                .onDelete { idx in for i in idx { context.delete(rules[i]) } }
            } header: {
                Text("Regras")
            } footer: {
                Text("As regras rodam quando você abre o app e quando o iOS libera uma atualização em segundo plano; o horário exato depende do sistema.")
            }

            Section("Modelos prontos") {
                ForEach(AutomationEngine.templates, id: \.2) { t in
                    Button { add(t.0, t.1) } label: {
                        Label(t.2, systemImage: t.0.icon)
                    }
                    .tint(.primary)
                }
            }

            Section {
                Button(running ? "Verificando…" : "Verificar agora", systemImage: "play.circle") {
                    running = true
                    Task {
                        let n = await AutomationEngine.run(in: context)
                        lastResult = n == 0 ? "Nada a disparar agora." : "\(n) ação(ões) executada(s)."
                        running = false
                    }
                }
                .disabled(running || rules.isEmpty)
                if let lastResult { Text(lastResult).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("Histórico") {
                if runs.isEmpty { Text("Nenhuma execução ainda.").foregroundStyle(.secondary) }
                ForEach(runs.prefix(50)) { run in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.message).foregroundStyle(run.ok ? Color.primary : Color.lifeExpense)
                        Text("\(run.ruleLabel) · \(run.date.formatted(.dateTime.day().month().hour().minute().locale(.ptBR)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Automações")
    }

    private func add(_ trigger: AutomationTrigger, _ action: AutomationAction) {
        context.insert(AutomationRule(trigger: trigger, action: action))
        if action == .notificacao { Task { _ = await AutomationNotifier.requestPermission() } }
    }
}

struct AutomationRuleRow: View {
    let rule: AutomationRule
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.trigger.icon)
                .frame(width: 34, height: 34)
                .background(Color.lifeAccent.opacity(0.12), in: Circle())
                .foregroundStyle(Color.lifeAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.trigger.label)
                Text(rule.action.label + (rule.trigger.parameter.map { " · \($0.label.lowercased()): \(rule.parameter)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !rule.enabled { Text("Pausada").font(.caption).foregroundStyle(.orange) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AutomationRuleView: View {
    @Bindable var rule: AutomationRule
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Quando") {
                Label(rule.trigger.label, systemImage: rule.trigger.icon)
                if let p = rule.trigger.parameter {
                    Stepper("\(p.label): \(rule.parameter)", value: $rule.parameter, in: p.range)
                }
            }
            Section("Então") {
                Picker("Ação", selection: $rule.actionRaw) {
                    ForEach(AutomationAction.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Toggle("Ativa", isOn: $rule.enabled)
                Button("Excluir regra", role: .destructive) {
                    dismiss()
                    context.delete(rule)
                }
            }
        }
        .navigationTitle("Regra")
        .onChange(of: rule.actionRaw) { _, raw in
            if raw == AutomationAction.notificacao.rawValue { Task { _ = await AutomationNotifier.requestPermission() } }
        }
    }
}
