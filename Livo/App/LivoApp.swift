import SwiftUI
import SwiftData

@main
struct LivoApp: App {
    @AppStorage(DemoMode.key) private var demo = false
    @State private var containers = ContainerStore()
    @Environment(\.scenePhase) private var phase

    init() {
        BrandAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            LockGate {
                // A VStack (not safeAreaInset) so the banner takes its own row instead of covering navigation bars.
                VStack(spacing: 0) {
                    if demo {
                        DemoBanner()
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Color.lifeCanvas)
                    }
                    RootView()
                }
            }
            .id(demo) // rebuild the whole tree when switching between real and demo data
            .modelContainer(containers.container(demo: demo))
            .tint(.lifeAccent)
            .fontDesign(.rounded) // SF Rounded everywhere: it echoes the logo's rounded letterforms
            .environment(\.locale, .ptBR)
        }
        .onChange(of: phase) { _, new in
            switch new {
            case .active: Task { await AutomationScheduler.runInForeground() }
            case .background:
                AutomationScheduler.scheduleNext()
                WidgetSnapshotWriter.refresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AutomationScheduler.taskID)) {
            await AutomationScheduler.runInBackground()
        }
    }
}

/// The one on-disk store, shared by the app UI, Siri/Shortcuts intents and background refresh.
/// iCloud sync (CloudKit private database) is opt-in and decided once per launch.
@MainActor
enum SharedStore {
    enum CloudStatus: Equatable {
        case off, on, failed(String)
    }

    static let syncKey = "icloud.sync"
    static private(set) var cloudStatus: CloudStatus = .off
    static let real: ModelContainer = makeReal()

    static var cloudContainerID: String? { Bundle.main.object(forInfoDictionaryKey: "LivoCloudContainer") as? String }

    private static func makeReal() -> ModelContainer {
        if UserDefaults.standard.bool(forKey: syncKey), let id = cloudContainerID {
            do {
                // Same default store file as the local configuration, so turning sync on keeps existing data.
                let c = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(cloudKitDatabase: .private(id)))
                cloudStatus = .on
                return c
            } catch {
                cloudStatus = .failed(error.localizedDescription)
            }
        }
        return ContainerStore.make(inMemory: false)
    }
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
                                      // `.none` explicitly: with the iCloud entitlement present, the default
                                      // (`.automatic`) would start syncing without the user opting in.
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none))
        } catch {
            fatalError("Não foi possível abrir o banco local: \(error)")
        }
    }
}
