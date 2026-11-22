import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.lifeAccent)
                .environment(\.locale, .ptBR)
        }
        .modelContainer(for: AppSchema.models)
    }
}
