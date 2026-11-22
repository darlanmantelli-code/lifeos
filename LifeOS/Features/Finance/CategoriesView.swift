import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinanceCategory.name) private var categories: [FinanceCategory]

    // Add: either a root category of `addKind` or a child of `addParent`.
    @State private var addKind: CategoryKind = .despesa
    @State private var addParent: FinanceCategory?
    @State private var showAdd = false
    @State private var newName = ""
    @State private var pendingDelete: FinanceCategory?
    @State private var confirmDelete = false

    var body: some View {
        List {
            section(.despesa, title: "Despesas")
            section(.receita, title: "Receitas")
        }
        .navigationTitle("Categorias")
        .alert(addParent.map { "Subcategoria de \($0.name)" } ?? "Nova categoria", isPresented: $showAdd) {
            TextField("Nome", text: $newName)
            Button("Adicionar", action: add)
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("Apagar categoria?", isPresented: $confirmDelete, presenting: pendingDelete) { c in
            Button("Apagar \(c.name)", role: .destructive) { context.delete(c) }
        } message: { _ in
            Text("Subcategorias e orçamentos dela também serão apagados. Os lançamentos ficam sem categoria.")
        }
    }

    private func section(_ kind: CategoryKind, title: String) -> some View {
        Section(title) {
            ForEach(categories.filter { $0.parent == nil && $0.kind == kind }) { c in
                Label(c.name, systemImage: c.icon)
                    .swipeActions {
                        deleteButton(c)
                        Button("Sub", systemImage: "plus") { startAdd(kind, parent: c) }.tint(.lifeAccent)
                    }
                ForEach((c.children ?? []).sorted { $0.name < $1.name }) { child in
                    Text(child.name)
                        .padding(.leading, 40)
                        .swipeActions { deleteButton(child) }
                }
            }
            Button("Adicionar categoria", systemImage: "plus") { startAdd(kind, parent: nil) }
        }
    }

    private func deleteButton(_ c: FinanceCategory) -> some View {
        Button("Apagar", systemImage: "trash") {
            pendingDelete = c
            confirmDelete = true
        }
        .tint(.red)
    }

    private func startAdd(_ kind: CategoryKind, parent: FinanceCategory?) {
        addKind = kind
        addParent = parent
        newName = ""
        showAdd = true
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let c = FinanceCategory(name: name, kind: addKind, icon: addParent?.icon ?? "tag")
        context.insert(c)
        c.parent = addParent
    }
}
