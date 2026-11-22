import SwiftUI
import SwiftData

/// The center "Adicionar" tab: pick a type, then the matching form replaces the menu in the same sheet.
struct AddSheet: View {
    enum Choice: String, CaseIterable, Identifiable {
        case despesa, receita, transferencia, tarefa, checkin, habito, compra, saude
        var id: String { rawValue }
        var title: String {
            switch self {
            case .despesa: "Despesa"
            case .receita: "Receita"
            case .transferencia: "Transferência"
            case .tarefa: "Tarefa"
            case .checkin: "Registrar hábito"
            case .habito: "Novo hábito"
            case .compra: "Item de compra"
            case .saude: "Registro de saúde"
            }
        }
        var icon: String {
            switch self {
            case .despesa: "arrow.up.circle"
            case .receita: "arrow.down.circle"
            case .transferencia: "arrow.left.arrow.right.circle"
            case .tarefa: "checklist"
            case .checkin: "checkmark.circle"
            case .habito: "repeat"
            case .compra: "cart.badge.plus"
            case .saude: "heart.text.square"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice?

    var body: some View {
        Group {
            if let choice { form(choice) } else { menu }
        }
        .presentationDetents(choice == nil ? [.medium, .large] : [.large])
    }

    private var menu: some View {
        NavigationStack {
            List {
                Section("Finanças") { ForEach([Choice.despesa, .receita, .transferencia]) { row($0) } }
                Section("Rotina") { ForEach([Choice.tarefa, .checkin, .habito]) { row($0) } }
                Section("Outros") { ForEach([Choice.compra, .saude]) { row($0) } }
            }
            .navigationTitle("Adicionar")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
    }

    private func row(_ c: Choice) -> some View {
        Button { withAnimation { choice = c } } label: {
            Label(c.title, systemImage: c.icon)
        }
        .tint(.primary)
    }

    @ViewBuilder
    private func form(_ c: Choice) -> some View {
        switch c {
        case .despesa: TransactionForm(initialKind: .despesa)
        case .receita: TransactionForm(initialKind: .receita)
        case .transferencia: TransactionForm(initialKind: .transferencia)
        case .tarefa: TaskForm(editing: nil)
        case .checkin: HabitCheckInSheet()
        case .habito: HabitForm(editing: nil)
        case .compra: QuickShoppingItemForm()
        case .saude: HealthEntryForm(kind: .agua)
        }
    }
}

struct HabitCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Habit> { $0.archived == false }, sort: \Habit.createdAt) private var habits: [Habit]

    var body: some View {
        NavigationStack {
            List {
                if habits.isEmpty { Text("Nenhum hábito ativo. Crie um na aba Rotina.").foregroundStyle(.secondary) }
                ForEach(habits) { HabitCheckRow(habit: $0) }
            }
            .navigationTitle("Registrar hábito")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Concluído") { dismiss() } }
            }
        }
    }
}

struct QuickShoppingItemForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShoppingList.createdAt) private var lists: [ShoppingList]

    @State private var name = ""
    @State private var list: ShoppingList?
    @State private var priceText = ""

    private var price: Int64?? {
        if priceText.isEmpty { return .some(nil) }
        guard let v = Money.parse(priceText), v >= 0 else { return nil }
        return .some(v)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item", text: $name)
                Picker("Lista", selection: $list) {
                    if lists.isEmpty { Text("Nova lista “Mercado”").tag(ShoppingList?.none) }
                    ForEach(lists) { Text($0.name).tag(Optional($0)) }
                }
                LabeledContent("Preço unitário (opcional)") {
                    TextField("0,00", text: $priceText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Item de compra")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || price == nil)
                }
            }
            .onAppear { list = list ?? lists.first { !$0.isWishlist } ?? lists.first }
        }
    }

    private func save() {
        guard let price else { return }
        let target: ShoppingList
        if let list {
            target = list
        } else {
            target = ShoppingList(name: "Mercado", isWishlist: false)
            context.insert(target)
        }
        let item = ShoppingItem(name: name.trimmingCharacters(in: .whitespaces))
        context.insert(item)
        item.list = target
        ShoppingStore.setPrice(price, store: "", for: item, in: context)
        dismiss()
    }
}
