import Foundation
import SwiftData

enum StudyKind: String, CaseIterable, Identifiable {
    case curso, livro, assunto
    var id: String { rawValue }
    var label: String {
        switch self {
        case .curso: "Curso"
        case .livro: "Livro"
        case .assunto: "Assunto"
        }
    }
    var icon: String {
        switch self {
        case .curso: "graduationcap"
        case .livro: "book.closed"
        case .assunto: "lightbulb"
        }
    }
}

@Model
final class StudyItem {
    var title: String = ""
    var kindRaw: String = StudyKind.curso.rawValue
    /// 0–100, set by the user.
    var progress: Int = 0
    var notes: String = ""
    /// Index into StudyLogic.reviewIntervals; nil = no reviews scheduled.
    var reviewStage: Int?
    var nextReview: Date?
    var archived: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.study)
    var sessions: [FocusSession]? = []

    init(title: String, kind: StudyKind) {
        self.title = title
        self.kindRaw = kind.rawValue
    }

    var kind: StudyKind { StudyKind(rawValue: kindRaw) ?? .curso }
}

/// A completed Pomodoro focus block.
@Model
final class FocusSession {
    var start: Date = Date()
    var minutes: Int = 0
    var study: StudyItem?

    init(start: Date, minutes: Int) {
        self.start = start
        self.minutes = minutes
    }
}
