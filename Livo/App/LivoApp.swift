import SwiftUI
import SwiftData

@main
struct LivoApp: App {
    @AppStorage(DemoMode.key) private var demo = false
    @State private var containers = ContainerStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            LockGate {
                RootView()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if demo { DemoBanner().padding(.bottom, 4) }
                    }
            }
            .id(demo) // rebuild the whole tree when switching between real and demo data
            .modelContainer(containers.container(demo: demo))
            .tint(.lifeAccent)
            .environment(\.locale, .ptBR)
        }
        .onChange(of: phase) { _, new in
            switch new {
            case .active: Task { await AutomationScheduler.runInForeground() }
            case .background: AutomationScheduler.scheduleNext()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AutomationScheduler.taskID)) {
            await AutomationScheduler.runInBackground()
        }
    }
}

/// Real data lives on disk; demo data is a separate in-memory store, recreated each time demo mode is turned on.
@MainActor
final class ContainerStore {
    private var real: ModelContainer?
    private var demoContainer: ModelContainer?

    func container(demo: Bool) -> ModelContainer {
        if demo {
            if let demoContainer { return demoContainer }
            let c = make(inMemory: true)
            DemoData.seed(c.mainContext)
            demoContainer = c
            return c
        }
        demoContainer = nil
        if let real { return real }
        let c = make(inMemory: false)
        real = c
        AutomationScheduler.container = c
        return c
    }

    private func make(inMemory: Bool) -> ModelContainer {
        do {
            return try ModelContainer(for: Schema(AppSchema.models),
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            fatalError("Não foi possível abrir o banco local: \(error)")
        }
    }
}
