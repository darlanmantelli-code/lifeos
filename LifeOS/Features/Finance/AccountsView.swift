import SwiftUI
import SwiftData

struct AccountsView: View {
    enum Target: Identifiable {
        case new, edit(Account)
        var id: AnyHashable {
            switch self {
            case .new: AnyHashable("new")
            case .edit(let a): AnyHashable(a.persistentModelID)
            }
        }
        var account: Account? {
            switch self {
            case .new: nil
            case .edit(let a): a
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var target: Target?

    var body: some View {
        let active = accounts.filter { !$0.archived }
        let archived = accounts.filter(\.archived)
        List {
            Section {
                ForEach(active) { row($0) }
            } footer: {
                Text("Contas com lançamentos são arquivadas em vez de apagadas, para preservar o histórico.")
            }
            if !archived.isEmpty {
                Section("Arquivadas") { ForEach(archived) { row($0) } }
            }
        }
        .navigationTitle("Contas e cartões")
        .toolbar {
            Button { target = .new } label: { Image(systemName: "plus") }
                .accessibilityLabel("Nova conta")
        }
        .sheet(item: $target) { AccountForm(editing: $0.account) }
    }

    private func row(_ a: Account) -> some View {
        Button { target = .edit(a) } label: { AccountRow(account: a) }
            .tint(.primary)
            .swipeActions {
                if a.hasTransactions {
                    Button(a.archived ? "Reativar" : "Arquivar", systemImage: "archivebox") { a.archived.toggle() }
                        .tint(.orange)
                } else {
                    Button("Apagar", systemImage: "trash", role: .destructive) { context.delete(a) }
                }
            }
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        let balance = FinanceLogic.balance(of: account)
        HStack(spacing: 12) {
            Image(systemName: account.kind.icon)
                .frame(width: 34, height: 34)
                .background(Color.lifeAccent.opacity(0.12), in: Circle())
                .foregroundStyle(Color.lifeAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.kind.label).font(.caption).foregroundStyle(.secondary)
                if account.kind == .cartao, let closing = account.closingDay {
                    let key = FinanceLogic.invoiceKey(for: .now, closingDay: closing)
                    Text("Fatura atual: \(Money.format(FinanceLogic.invoiceTotal(card: account, key: key)))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let limit = account.creditLimitCents {
                        Text("Limite disponível: \(Money.format(limit + balance))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(Money.format(balance)).monospacedDigit()
                .foregroundStyle(balance < 0 ? Color.lifeExpense : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AccountForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let editing: Account?

    @State private var name = ""
    @State private var kind: AccountKind = .corrente
    @State private var initialText = ""
    @State private var limitText = ""
    @State private var closingDay = 1
    @State private var dueDay = 10
    @State private var loaded = false

    private var initialCents: Int64? { initialText.isEmpty ? 0 : Money.parse(initialText) }
    private var limitCents: Int64? { limitText.isEmpty ? nil : Money.parse(limitText) }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && initialCents != nil
            && (limitText.isEmpty || limitCents != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (ex.: Nubank, Itaú)", text: $name)
                    Picker("Tipo", selection: $kind) {
                        ForEach(AccountKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                }
                if kind == .cartao {
                    Section("Cartão") {
                        LabeledContent("Limite") {
                            TextField("0,00", text: $limitText)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        Stepper("Fechamento: dia \(closingDay)", value: $closingDay, in: 1...28)
                        Stepper("Vencimento: dia \(dueDay)", value: $dueDay, in: 1...28)
                    }
                }
                Section {
                    LabeledContent("Saldo inicial") {
                        TextField("0,00", text: $initialText)
                            .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text(kind == .cartao
                         ? "Para um cartão, informe a fatura em aberto como valor negativo (ex.: -350,00)."
                         : "Use valor negativo para saldo devedor.")
                }
            }
            .navigationTitle(editing == nil ? "Nova conta" : "Editar conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(!isValid) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let a = editing else { return }
        loaded = true
        name = a.name
        kind = a.kind
        initialText = a.initialBalanceCents == 0 ? "" : Money.format(a.initialBalanceCents)
        limitText = a.creditLimitCents.map(Money.format) ?? ""
        closingDay = a.closingDay ?? 1
        dueDay = a.dueDay ?? 10
    }

    private func save() {
        guard let initial = initialCents else { return }
        let a = editing ?? Account(name: "", kind: kind)
        if editing == nil { context.insert(a) }
        a.name = name.trimmingCharacters(in: .whitespaces)
        a.kind = kind
        a.initialBalanceCents = initial
        if kind == .cartao {
            a.creditLimitCents = limitCents
            a.closingDay = closingDay
            a.dueDay = dueDay
        } else {
            a.creditLimitCents = nil
            a.closingDay = nil
            a.dueDay = nil
        }
        dismiss()
    }
}
