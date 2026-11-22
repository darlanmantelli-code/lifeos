import Foundation
import SwiftData
import BackgroundTasks

/// Background refresh: iOS runs it when it decides (battery, usage); we only ask for "not before 4 h from now".
/// Always works on the real store; demo data never triggers automations.
@MainActor
enum AutomationScheduler {
    static let taskID = "com.livo.app.refresh"

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func runInBackground() async {
        scheduleNext()
        await runInForeground()
    }

    static func runInForeground() async {
        guard !DemoMode.isOn else { return }
        if SharedStore.cloudStatus == .on { _ = try? FinanceStore.mergeDuplicateCategories(SharedStore.real.mainContext) }
        if UserDefaults.standard.bool(forKey: HealthSync.autoKey) {
            _ = try? await HealthSync.sync(days: 7, into: SharedStore.real.mainContext)
        }
        await AutomationEngine.run(in: SharedStore.real.mainContext)
        WidgetSnapshotWriter.refresh()
    }
}
