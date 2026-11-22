import SwiftUI

enum AppTab: String, Hashable {
    case inicio, financas, adicionar, rotina, ia
}

/// Launch arguments (`-tab financas`, `-segment habitos`, `-route saude`) land in UserDefaults;
/// CI uses them to open each screen for screenshots.
enum LaunchArgs {
    static func string(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = AppTab(rawValue: LaunchArgs.string("tab") ?? "") ?? .inicio
    @State private var lastTab: AppTab = AppTab(rawValue: LaunchArgs.string("tab") ?? "") ?? .inicio
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
            AssistantView()
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
        .sheet(isPresented: $showAdd) {
            AddSheet()
        }
        .task { FinanceStore.seedCategoriesIfNeeded(context) }
    }
}


#Preview { RootView().modelContainer(for: AppSchema.models, inMemory: true) }
