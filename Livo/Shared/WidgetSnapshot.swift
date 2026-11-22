import Foundation

/// The few numbers the home-screen widget shows. Written by the app into the App Group container;
/// the widget never opens the database.
struct WidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var balanceCents: Int64?
    var monthExpenseCents: Int64
    var tasksToday: Int
    var nextTask: String?
    var habitsPending: Int
    var habitsTotal: Int
    var waterMl: Double?
    var waterTargetMl: Double?

    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "LivoAppGroup") as? String }

    /// nil when the App Group isn't available (e.g. unsigned simulator builds).
    static var fileURL: URL? {
        guard let id = groupID, let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return dir.appending(path: "widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL else { return false }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(self) else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
}
