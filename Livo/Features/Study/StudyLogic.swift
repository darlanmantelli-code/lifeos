import Foundation
import SwiftData
@preconcurrency import UserNotifications

enum StudyLogic {
    /// Spaced review: days until the next review after each successful one.
    static let reviewIntervals = [1, 3, 7, 14, 30, 60]

    static func totalMinutes(_ item: StudyItem) -> Int {
        (item.sessions ?? []).reduce(0) { $0 + $1.minutes }
    }

    static func minutes(_ sessions: [FocusSession], since start: Date) -> Int {
        sessions.filter { $0.start >= start }.reduce(0) { $0 + $1.minutes }
    }

    static func isReviewDue(_ item: StudyItem, now: Date = .now, calendar: Calendar = .ptBR) -> Bool {
        guard !item.archived, let next = item.nextReview else { return false }
        return calendar.startOfDay(for: next) <= calendar.startOfDay(for: now)
    }

    /// Starts reviews (first one tomorrow) or advances to the next interval after a review.
    static func markReviewed(_ item: StudyItem, now: Date = .now, calendar: Calendar = .ptBR) {
        let stage = item.reviewStage.map { min($0 + 1, reviewIntervals.count - 1) } ?? 0
        item.reviewStage = stage
        item.nextReview = calendar.date(byAdding: .day, value: reviewIntervals[stage], to: calendar.startOfDay(for: now))
    }

    static func stopReviews(_ item: StudyItem) {
        item.reviewStage = nil
        item.nextReview = nil
    }
}

/// Pomodoro state derived from wall-clock dates, so it stays right while the app is suspended.
struct PomodoroTimer: Equatable {
    enum Phase: Equatable { case idle, focus, pause }

    var phase: Phase = .idle
    var endsAt: Date?
    var startedAt: Date?

    func remaining(at now: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    func isFinished(at now: Date) -> Bool { phase != .idle && remaining(at: now) == 0 }

    mutating func start(_ phase: Phase, minutes: Int, at now: Date) {
        self.phase = phase
        startedAt = now
        endsAt = now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    mutating func stop() {
        phase = .idle
        endsAt = nil
        startedAt = nil
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

enum PomodoroNotifier {
    static let id = "livo.pomodoro"

    static func schedule(at date: Date, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
