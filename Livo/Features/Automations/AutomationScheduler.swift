import Foundation
import SwiftData
import BackgroundTasks

/// Background refresh: iOS runs it when it decides (battery, usage); we only ask for "not before 4 h from now".
@MainActor
enum AutomationScheduler {
    static let taskID = "com.livo.app.refresh"
    /// The on-disk store. Demo data never triggers automations.
    static var container: ModelContainer?

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func runInBackground() async {
        scheduleNext()
        guard !DemoMode.isOn, let container else { return }
        await AutomationEngine.run(in: container.mainContext)
    }

    static func runInForeground() async {
        guard !DemoMode.isOn, let container else { return }
        await AutomationEngine.run(in: container.mainContext)
    }
}
