import Foundation
import SwiftData

/// Every tool the assistant ran (or tried to run) on this device: what, when, and what happened.
@Model
final class AIActionLog {
    var date: Date = Date()
    var tool: String = ""
    var summary: String = ""
    /// "executada", "recusada" or "erro".
    var status: String = ""

    init(tool: String, summary: String, status: String) {
        self.tool = tool
        self.summary = summary
        self.status = status
    }
}
