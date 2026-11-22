import Foundation
import SwiftData

struct DayValue: Identifiable {
    let day: Date
    let value: Double
    var value2: Double?
    var id: Date { day }
}

enum HealthLogic {
    static func aggregate(_ entries: [HealthEntry], _ kind: HealthKind) -> Double? {
        guard !entries.isEmpty else { return nil }
        switch kind.aggregation {
        case .sum: return entries.reduce(0) { $0 + $1.value }
        case .average: return entries.reduce(0) { $0 + $1.value } / Double(entries.count)
        case .latest: return entries.max { $0.date < $1.date }?.value
        }
    }

    /// One value per day that has data, oldest first. `entries` must already be of `kind`.
    static func daily(_ entries: [HealthEntry], _ kind: HealthKind, days: Int, now: Date = .now,
                      calendar: Calendar = .ptBR) -> [DayValue] {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return Dictionary(grouping: entries.filter { $0.date >= start && $0.date < end }) { calendar.startOfDay(for: $0.date) }
            .compactMap { day, items in
                aggregate(items, kind).map {
                    DayValue(day: day, value: $0, value2: items.max { $0.date < $1.date }?.value2)
                }
            }
            .sorted { $0.day < $1.day }
    }

    /// Summed metrics: today's total. Others: the most recent entry.
    static func current(_ entries: [HealthEntry], _ kind: HealthKind, now: Date = .now,
                        calendar: Calendar = .ptBR) -> (value: Double, value2: Double?, date: Date)? {
        if kind.aggregation == .sum {
            let today = entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
            return aggregate(today, kind).map { ($0, nil, now) }
        }
        return entries.max { $0.date < $1.date }.map { ($0.value, $0.value2, $0.date) }
    }

    /// Mean of the daily values over the last `days` days (today included).
    static func average(_ entries: [HealthEntry], _ kind: HealthKind, days: Int = 7, now: Date = .now,
                        calendar: Calendar = .ptBR) -> Double? {
        let values = daily(entries, kind, days: days, now: now, calendar: calendar).map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Last 7 days' average minus the 7 days before. Nil when either week has no data.
    static func weeklyChange(_ entries: [HealthEntry], _ kind: HealthKind, now: Date = .now,
                             calendar: Calendar = .ptBR) -> Double? {
        guard let recent = average(entries, kind, days: 7, now: now, calendar: calendar),
              let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let previous = average(entries, kind, days: 7, now: weekAgo, calendar: calendar)
        else { return nil }
        return recent - previous
    }

    static func format(_ v: Double, _ kind: HealthKind) -> String {
        v.formatted(.number.precision(.fractionLength(0...kind.decimals)).locale(.ptBR))
    }

    static func format(_ v: Double, _ v2: Double?, _ kind: HealthKind) -> String {
        if kind.hasSecondValue, let v2 { return "\(format(v, kind))/\(format(v2, kind))" }
        return format(v, kind)
    }
}

@MainActor
enum HealthStore {
    static func setTarget(_ value: Double?, for kind: HealthKind, in ctx: ModelContext) throws {
        let raw = kind.rawValue
        let existing = try ctx.fetch(FetchDescriptor<HealthTarget>(predicate: #Predicate<HealthTarget> { $0.kindRaw == raw }))
        guard let value, value > 0 else {
            for t in existing { ctx.delete(t) }
            return
        }
        if let t = existing.first {
            t.value = value
        } else {
            ctx.insert(HealthTarget(kind: kind, value: value))
        }
    }
}
