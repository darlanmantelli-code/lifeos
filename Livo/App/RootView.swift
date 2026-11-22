import SwiftUI

enum AppTab: Hashable {
    case inicio, financas, adicionar, rotina, ia
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .inicio
    @State private var lastTab: AppTab = .inicio
    @State private var showAdd = false

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Início", systemImage: "house") }.tag(AppTab.inicio)
            FinanceView()
                .tabItem { Label("Finanças", systemImage: "creditcard") }.tag(AppTab.financas)
            Color.clear
                .tabItem { Label("Adicionar", systemImage: "plus.circle.fill") }.tag(AppTab.adicionar)
            RoutineView()
                .tabItem { Label("Rotina", systemImage: "checklist") }.tag(AppTab.rotina)
            PlaceholderScreen(title: "LIFE AI", icon: "sparkles", etapa: 5)
                .tabItem { Label("IA", systemImage: "sparkles") }.tag(AppTab.ia)
        }
        // "Adicionar" is an action, not a screen: open the sheet and stay on the previous tab.
        .onChange(of: tab) { _, new in
            if new == .adicionar {
                tab = lastTab
                showAdd = true
            } else {
                lastTab = new
            }
        }
        // ponytail: Adicionar opens the transaction form directly; becomes a type chooser in stage 4.
        .sheet(isPresented: $showAdd) {
            TransactionForm(initialKind: .despesa)
        }
        .task { FinanceStore.seedCategoriesIfNeeded(context) }
    }
}

/// Honest placeholder: says which implementation stage delivers the screen. No fake data.
struct PlaceholderScreen: View {
    let title: String
    let icon: String
    let etapa: Int

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Em construção",
                systemImage: icon,
                description: Text("Esta tela chega na etapa \(etapa) do MVP.")
            )
            .navigationTitle(title)
        }
    }
}

#Preview { RootView().modelContainer(for: AppSchema.models, inMemory: true) }
