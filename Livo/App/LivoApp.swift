import SwiftUI
import SwiftData

@main
struct LivoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.lifeAccent)
                .environment(\.locale, .ptBR)
        }
        .modelContainer(for: AppSchema.models)
    }
}
