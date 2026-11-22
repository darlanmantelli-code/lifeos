import SwiftUI
import SwiftData

struct BudgetsView: View {
    let month: Date

    @Environment(\.modelContext) private var context
    @Query(sort: \FinanceCategory.name) private var categories: [FinanceCategory]
    @Query private var transactions: [FinanceTransaction]

    @State private var editing: FinanceCategory?
    @State private var showEdit = false
    @State private var limitText = ""

    private var key: String { MonthKey.of(month) }

    var body: some View {
        let range = MonthKey.interval(of: month)
        let monthTxns = transactions.filter { $0.date >= range.start && $0.date < range.end }
        List {
            Section {
                ForEach(categories.filter { $0.parent == nil && $0.kind == .despesa }) { c in
                    let spent = FinanceLogic.spent(in: c, monthTxns)
                    let limit = FinanceLogic.effectiveLimit(c.budgets ?? [], key: key)
                    Button { startEdit(c, limit) } label: {
                        HStack {
                            Label(c.name, systemImage: c.icon)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(limit.map(Money.format) ?? "Sem limite")
                                    .foregroundStyle(limit == nil ? Color.secondary : Color.primary)
                                Text("Gasto: \(Money.format(spent))").font(.caption).foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("O limite vale a partir de \(month.formatted(.dateTime.month(.wide).year().locale(.ptBR))) e segue nos meses seguintes até ser alterado. Informe 0 para remover.")
            }
        }
        .navigationTitle("Orçamentos")
        .alert("Limite mensal\(editing.map { " — \($0.name)" } ?? "")", isPresented: $showEdit) {
            TextField("0,00", text: $limitText).keyboardType(.decimalPad)
            Button("Salvar", action: save)
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func startEdit(_ c: FinanceCategory, _ limit: Int64?) {
        editing = c
        limitText = limit.map(Money.format) ?? ""
        showEdit = true
    }

    private func save() {
        guard let c = editing, let cents = Money.parse(limitText.isEmpty ? "0" : limitText), cents >= 0 else { return }
        FinanceStore.setBudget(cents, for: c, from: key, in: context)
    }
}
