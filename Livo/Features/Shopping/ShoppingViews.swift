import SwiftUI
import SwiftData

struct ShoppingHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingList.createdAt) private var lists: [ShoppingList]

    @State private var newName = ""
    @State private var newIsWish = false
    @State private var showNew = false
    @State private var pendingDelete: ShoppingList?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if lists.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma lista", systemImage: "cart")
                } description: {
                    Text("Crie uma lista de compras ou uma lista de desejos.")
                } actions: {
                    Button("Nova lista de compras") { startNew(wish: false) }.buttonStyle(.borderedProminent)
                    Button("Nova lista de desejos") { startNew(wish: true) }
                }
            }
            section("Listas de compras", lists.filter { !$0.isWishlist })
            section("Desejos", lists.filter(\.isWishlist))
        }
        .navigationTitle("Compras")
        .brandScreen()
        .toolbar {
            Menu {
                Button("Nova lista de compras", systemImage: "cart") { startNew(wish: false) }
                Button("Nova lista de desejos", systemImage: "star") { startNew(wish: true) }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Nova lista")
        }
        .alert(newIsWish ? "Nova lista de desejos" : "Nova lista de compras", isPresented: $showNew) {
            TextField("Nome", text: $newName)
            Button("Criar", action: create)
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("Apagar lista?", isPresented: $confirmDelete, presenting: pendingDelete) { l in
            Button("Apagar \(l.name)", role: .destructive) { context.delete(l) }
        } message: { _ in
            Text("Todos os itens e o histórico de preços da lista serão apagados.")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ShoppingList]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { l in
                    NavigationLink {
                        ShoppingListView(list: l)
                    } label: {
                        let pending = (l.items ?? []).filter { !$0.bought }.count
                        HStack {
                            Label(l.name, systemImage: l.icon)
                            Spacer()
                            if pending > 0 { Text("\(pending)").monospacedDigit().foregroundStyle(.secondary) }
                        }
                    }
                    .swipeActions {
                        Button("Apagar", systemImage: "trash") {
                            pendingDelete = l
                            confirmDelete = true
                        }
                        .tint(.red)
                    }
                }
            }
        }
    }

    private func startNew(wish: Bool) {
        newIsWish = wish
        newName = wish ? "Desejos" : ""
        showNew = true
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(ShoppingList(name: name, isWishlist: newIsWish))
    }
}

struct ShoppingListView: View {
    enum Sheet: Identifiable {
        case item(ShoppingItem)
        case expense(title: String, cents: Int64)
        var id: AnyHashable {
            switch self {
            case .item(let i): AnyHashable(i.persistentModelID)
            case .expense(let t, let c): AnyHashable("\(t)-\(c)")
            }
        }
    }

    let list: ShoppingList
    @Environment(\.modelContext) private var context
    @State private var newItem = ""
    @State private var sheet: Sheet?
    @State private var confirmClear = false
    @FocusState private var addFocused: Bool

    private var pending: [ShoppingItem] { (list.items ?? []).filter { !$0.bought } }
    private var bought: [ShoppingItem] {
        (list.items ?? []).filter(\.bought).sorted { ($0.boughtAt ?? .distantPast) > ($1.boughtAt ?? .distantPast) }
    }

    var body: some View {
        let pendingEstimate = ShoppingLogic.estimate(pending)
        let boughtEstimate = ShoppingLogic.estimate(bought)
        List {
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.lifeAccent).accessibilityHidden(true)
                    TextField(list.isWishlist ? "Adicionar desejo" : "Adicionar item", text: $newItem)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                }
            }
            ForEach(ShoppingLogic.groups(pending)) { g in
                Section(g.category.isEmpty ? "Sem categoria" : g.category) {
                    ForEach(g.items) { row($0) }
                }
            }
            if !bought.isEmpty {
                Section(list.isWishlist ? "Conquistados" : "Comprados") {
                    ForEach(bought) { row($0) }
                }
            }
            Section {
                LabeledContent("Total estimado (pendentes)", value: Money.format(pendingEstimate.cents))
                    .monospacedDigit()
            } footer: {
                Text(pendingEstimate.missing > 0 ? "\(pendingEstimate.missing) item(ns) sem preço ficaram fora do total. " : "")
                    + Text("Preços informados por você, não consultados em lojas.")
            }
        }
        .navigationTitle(list.name)
        .brandScreen()
        .toolbar {
            Menu {
                Button("Lançar compra dos itens marcados", systemImage: "creditcard") {
                    sheet = .expense(title: list.name, cents: boughtEstimate.cents)
                }
                .disabled(bought.isEmpty)
                Button("Limpar marcados", systemImage: "trash", role: .destructive) { confirmClear = true }
                    .disabled(bought.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Mais opções")
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .item(let i): ShoppingItemForm(item: i)
            case .expense(let title, let cents): TransactionForm(prefillTitle: title, amountCents: cents > 0 ? cents : nil)
            }
        }
        .confirmationDialog("Remover \(bought.count) item(ns) marcado(s)?", isPresented: $confirmClear) {
            Button("Remover", role: .destructive) { ShoppingStore.clearBought(list, in: context) }
        }
    }

    private func row(_ i: ShoppingItem) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { ShoppingStore.toggleBought(i) }
            } label: {
                Image(systemName: i.bought ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(i.bought ? Color.lifeProgress : Color.secondary)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: i.bought)
            .accessibilityLabel(i.bought ? "Desmarcar \(i.name)" : "Marcar \(i.name)")

            VStack(alignment: .leading, spacing: 2) {
                Text(i.name).strikethrough(i.bought)
                if let d = detail(i) { Text(d).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let line = ShoppingLogic.lineTotal(i) {
                Text(Money.format(line)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { sheet = .item(i) }
        .swipeActions {
            Button("Apagar", systemImage: "trash", role: .destructive) { context.delete(i) }
        }
        .swipeActions(edge: .leading) {
            if let line = ShoppingLogic.lineTotal(i) {
                Button("Lançar despesa", systemImage: "creditcard") { sheet = .expense(title: i.name, cents: line) }
                    .tint(.lifeAccent)
            }
        }
    }

    private func detail(_ i: ShoppingItem) -> String? {
        var parts: [String] = []
        if i.quantity != 1 || !i.unit.isEmpty {
            parts.append("\(i.quantity.formatted(.number.locale(.ptBR))) \(i.unit)".trimmingCharacters(in: .whitespaces))
        }
        if !i.store.isEmpty { parts.append(i.store) }
        if list.isWishlist && i.priority == .alta { parts.append("Prioridade alta") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let i = ShoppingItem(name: name)
        context.insert(i)
        i.list = list
        newItem = ""
        addFocused = true
    }
}

struct ShoppingItemForm: View {
    let item: ShoppingItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantityText = ""
    @State private var unit = ""
    @State private var category = ""
    @State private var priceText = ""
    @State private var store = ""
    @State private var link = ""
    @State private var note = ""
    @State private var priority: Priority = .media
    @State private var loaded = false

    private var quantity: Double? { quantityText.isEmpty ? 1 : parseNumber(quantityText) }
    private var price: Int64?? {
        // .some(nil) = cleared; nil = invalid.
        if priceText.isEmpty { return .some(nil) }
        guard let v = Money.parse(priceText), v >= 0 else { return nil }
        return .some(v)
    }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (quantity ?? 0) > 0 && price != nil
    }

    var body: some View {
        let history = (item.prices ?? []).sorted { $0.observedAt > $1.observedAt }
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $name)
                    LabeledContent("Quantidade") {
                        TextField("1", text: $quantityText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    TextField("Unidade (kg, un, pct)", text: $unit)
                    Picker("Categoria", selection: $category) {
                        Text("Sem categoria").tag("")
                        ForEach(ShoppingLogic.categories, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    LabeledContent("Preço unitário") {
                        TextField("0,00", text: $priceText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    TextField("Loja", text: $store)
                } header: {
                    Text("Preço")
                } footer: {
                    Text("Preço informado por você. Cada alteração fica registrada no histórico com a data.")
                }
                if item.list?.isWishlist == true {
                    Section {
                        Picker("Prioridade", selection: $priority) {
                            ForEach(Priority.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        TextField("Link do produto", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
                            Link("Abrir link", destination: url)
                        }
                    }
                }
                Section("Observação") {
                    TextField("Opcional", text: $note, axis: .vertical)
                }
                if !history.isEmpty {
                    Section("Histórico de preços") {
                        ForEach(history) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Money.format(p.priceCents)).monospacedDigit()
                                Text([p.store, p.observedAt.formatted(.dateTime.day().month().year().locale(.ptBR)), "informado por você"]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Item")
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
        guard !loaded else { return }
        loaded = true
        name = item.name
        quantityText = item.quantity == 1 ? "" : item.quantity.formatted(.number.locale(.ptBR))
        unit = item.unit
        category = item.category
        priceText = item.priceCents.map(Money.format) ?? ""
        store = item.store
        link = item.link
        note = item.note
        priority = item.priority
    }

    private func save() {
        guard let quantity, let price else { return }
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.quantity = quantity
        item.unit = unit
        item.category = category
        item.link = link
        item.note = note
        item.priority = priority
        ShoppingStore.setPrice(price, store: store, for: item, in: context)
        dismiss()
    }
}
