import SwiftUI

@main
struct LifeOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.lifeAccent)
                .environment(\.locale, .ptBR)
        }
    }
}
