import Foundation

/// Receipt and invoice files attached to transactions. They live in the app's Documents folder, protected while the
/// device is locked. They stay on this device: they are not part of the JSON export and are not synced.
enum ReceiptStore {
    static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "pdf"]

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Receipts", directoryHint: .isDirectory)
    }

    /// Names come from the database: refuse anything that could point outside the receipts folder.
    static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && name.count < 80 && !name.contains("/") && !name.contains("\\") && !name.contains("..")
    }

    /// Writes `data` as a new file and returns its name. Unknown extensions are stored as "bin".
    static func save(_ data: Data, ext: String) throws -> String {
        let clean = ext.lowercased().filter(\.isLetter)
        let safe = allowedExtensions.contains(clean) ? clean : "bin"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let name = "\(UUID().uuidString).\(safe)"
        try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// The file's URL, or nil if the name is unsafe or the file is gone.
    static func url(_ name: String) -> URL? {
        guard isSafe(name) else { return nil }
        let url = directory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(_ names: [String]) {
        for name in names where isSafe(name) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
