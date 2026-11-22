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
                // A VStack (not safeAreaInset) so the banner takes its own row instead of covering navigation bars.
                VStack(spacing: 0) {
                    if demo { DemoBanner().padding(.vertical, 4) }
                    RootView()
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

/// The one on-disk store, shared by the app UI, Siri/Shortcuts intents and background refresh.
@MainActor
enum SharedStore {
    static let real: ModelContainer = ContainerStore.make(inMemory: false)
}

/// Real data lives on disk; demo data is a separate in-memory store, recreated each time demo mode is turned on.
@MainActor
final class ContainerStore {
    private var demoContainer: ModelContainer?

    func container(demo: Bool) -> ModelContainer {
        if demo {
            if let demoContainer { return demoContainer }
            let c = Self.make(inMemory: true)
            DemoData.seed(c.mainContext)
            demoContainer = c
            return c
        }
        demoContainer = nil
        return SharedStore.real
    }

    static func make(inMemory: Bool) -> ModelContainer {
        do {
            return try ModelContainer(for: Schema(AppSchema.models),
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            fatalError("Não foi possível abrir o banco local: \(error)")
        }
    }
}
