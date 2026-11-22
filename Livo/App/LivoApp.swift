import SwiftUI
import SwiftData

@main
struct LivoApp: App {
    private let container: ModelContainer
    private let isDemo = DemoMode.isOn

    init() {
        let demo = DemoMode.isOn
        do {
            container = try ModelContainer(for: Schema(AppSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: demo))
        } catch {
            fatalError("Não foi possível abrir o banco local: \(error)")
        }
        if demo { DemoData.seed(container.mainContext) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isDemo { DemoBanner().padding(.bottom, 4) }
                }
                .tint(.lifeAccent)
                .environment(\.locale, .ptBR)
        }
        .modelContainer(container)
    }
}
