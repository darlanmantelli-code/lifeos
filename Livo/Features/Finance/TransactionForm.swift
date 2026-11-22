import SwiftUI
import SwiftData

struct TransactionForm: View {
    enum RepetitionChoice: String, CaseIterable, Identifiable {
        case unica = "Única", parcelada = "Parcelada", recorrente = "Mensal"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Account> { $0.archived == false }, sort: \Account.createdAt)
    private var accounts: [Account]
    @Query(sort: \FinanceCategory.name) private var categories: [FinanceCategory]

    private let editing: FinanceTransaction?
    @State private var kind: TxnKind
    @State private var amountText = ""
    @State private var title = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var category: FinanceCategory?
    @State private var isFixed = false
    @State private var repetition: RepetitionChoice = .unica
    @State private var installments = 2
    @State private var loaded = false
    @State private var receipts: [String] = []
    /// Receipt files created in this session (deleted again if the form is cancelled).
    @State private var addedReceipts: [String] = []
    @State private var originalReceipts: [String] = []
    @State private var saved = false

    init(initialKind: TxnKind = .despesa) {
        editing = nil
        _kind = State(initialValue: initialKind)
    }

    init(editing: FinanceTransaction) {
        self.editing = editing
        _kind = State(initialValue: editing.kind)
    }

    /// New expense pre-filled from another module (e.g. a shopping list).
    init(prefillTitle: String, amountCents: Int64?) {
        editing = nil
        _kind = State(initialValue: .despesa)
        _title = State(initialValue: prefillTitle)
        _amountText = State(initialValue: amountCents.map(Money.format) ?? "")
    }

    private var amountCents: Int64? {
        guard let v = Money.parse(amountText), v > 0 else { return nil }
        return v
    }

    private var isValid: Bool {
        guard amountCents != nil, let account else { return false }
        if kind == .transferencia { return toAccount != nil && toAccount != account }
        return true
    }

    private var kindCategories: [FinanceCategory] {
        let k: CategoryKind = kind == .receita ? .receita : .despesa
        return categories.filter { $0.kind == k }.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            Form {
                if accounts.isEmpty {
                    Section {
                        Text("Cadastre uma conta em Finanças › Contas e cartões antes de lançar.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Tipo", selection: $kind) {
                        ForEach(TxnKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(.largeTitle, design: .rounded).bold())
                        .accessibilityLabel("Valor")
                    if let cents = amountCents {
                        Text(Money.format(cents)).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Descrição", text: $title)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }

                Section {
                    accountPicker(kind == .transferencia ? "De" : "Conta", selection: $account)
                    if kind == .transferencia {
                        accountPicker("Para", selection: $toAccount)
                    } else {
                        Picker("Categoria", selection: $category) {
                            Text("Sem categoria").tag(FinanceCategory?.none)
                            ForEach(kindCategories) { Text($0.displayName).tag(Optional($0)) }
                        }
                        Toggle(kind == .receita ? "Receita fixa" : "Despesa fixa", isOn: $isFixed)
                    }
                }

                if editing == nil {
                    Section {
                        Picker("Repetição", selection: $repetition) {
                            ForEach(RepetitionChoice.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if repetition == .parcelada {
                            Stepper("\(installments) parcelas", value: $installments, in: 2...48)
                        }
                    } footer: {
                        switch repetition {
                        case .unica: EmptyView()
                        case .parcelada: Text("O valor informado é o total da compra, dividido em parcelas mensais.")
                        case .recorrente: Text("Cria o lançamento todo mês pelos próximos \(FinanceStore.recurringHorizon) meses.")
                        }
                    }
                } else if editing?.groupID != nil {
                    Section {
                        Text("Alterações valem só para esta ocorrência.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                ReceiptsSection(names: $receipts, added: $addedReceipts)

                Section("Observação") {
                    TextField("Opcional", text: $note, axis: .vertical)
                }
            }
            // Attachments are saved to disk before the transaction is: block swipe-to-dismiss so they can't be orphaned.
            .interactiveDismissDisabled(!addedReceipts.isEmpty && !saved)
            .navigationTitle(editing == nil ? "Novo lançamento" : "Editar lançamento")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        ReceiptStore.delete(addedReceipts)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(!isValid) }
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, _ in
                if let c = category, !kindCategories.contains(c) { category = nil }
            }
        }
    }

    private func accountPicker(_ label: String, selection: Binding<Account?>) -> some View {
        Picker(label, selection: selection) {
            Text("Selecione").tag(Account?.none)
            ForEach(accounts) { Text($0.name).tag(Optional($0)) }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let e = editing {
            amountText = Money.format(e.amountCents)
            title = e.title
            note = e.note
            date = e.date
            account = e.account
            toAccount = e.toAccount
            category = e.category
            isFixed = e.isFixed
            receipts = e.receipts
            originalReceipts = e.receipts
        } else {
            account = accounts.first
        }
    }

    private func save() {
        guard let cents = amountCents, let account else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = !trimmed.isEmpty ? trimmed
            : kind == .transferencia ? "Transferência" : (category?.name ?? kind.label)

        if let e = editing {
            e.kind = kind
            e.amountCents = cents
            e.title = finalTitle
            e.note = note
            e.date = date
            e.account = account
            e.toAccount = kind == .transferencia ? toAccount : nil
            e.category = kind == .transferencia ? nil : category
            e.isFixed = isFixed
            e.receipts = receipts
            ReceiptStore.delete(originalReceipts.filter { !receipts.contains($0) })
        } else {
            let rep: Repetition = switch repetition {
            case .unica: .unica
            case .parcelada: .parcelada(installments)
            case .recorrente: .recorrente
            }
            let created = FinanceStore.insert(TransactionDraft(kind: kind, amountCents: cents, title: finalTitle, note: note,
                                                               date: date, account: account, toAccount: toAccount,
                                                               category: category, isFixed: isFixed, repetition: rep),
                                              in: context)
            // For installments/recurring entries the receipt belongs to the first occurrence.
            created.first?.receipts = receipts
        }
        // A file added and then removed again within this session isn't referenced by anything.
        ReceiptStore.delete(addedReceipts.filter { !receipts.contains($0) })
        saved = true
        dismiss()
    }
}
