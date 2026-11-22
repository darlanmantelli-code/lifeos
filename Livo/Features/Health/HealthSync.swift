import Foundation
import SwiftData
import HealthKit

/// Read-only import from Apple Health. Each sync replaces the imported days in the window with fresh daily
/// values (source "healthkit"); manual entries are never touched.
@MainActor
enum HealthSync {
    static let source = "healthkit"
    static let autoKey = "health.autoSync"
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private struct QuantitySpec {
        let kind: HealthKind
        let id: HKQuantityTypeIdentifier
        let unit: HKUnit
        let aggregation: HealthAggregation
    }

    private static var specs: [QuantitySpec] {
        [QuantitySpec(kind: .passos, id: .stepCount, unit: .count(), aggregation: .sum),
         QuantitySpec(kind: .agua, id: .dietaryWater, unit: .literUnit(with: .milli), aggregation: .sum),
         QuantitySpec(kind: .exercicio, id: .appleExerciseTime, unit: .minute(), aggregation: .sum),
         QuantitySpec(kind: .peso, id: .bodyMass, unit: .gramUnit(with: .kilo), aggregation: .latest),
         QuantitySpec(kind: .frequencia, id: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), aggregation: .average),
         QuantitySpec(kind: .cintura, id: .waistCircumference, unit: .meterUnit(with: .centi), aggregation: .latest)]
    }

    private static var readTypes: Set<HKObjectType> {
        Set(specs.map { HKQuantityType($0.id) as HKObjectType } + [HKCategoryType(.sleepAnalysis)])
    }

    /// Shows the system permission sheet the first time; later calls return immediately.
    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Imports the last `days` days. Returns how many daily values were written.
    @discardableResult
    static func sync(days: Int = 30, into ctx: ModelContext, now: Date = .now, calendar: Calendar = .ptBR) async throws -> Int {
        guard isAvailable else { return 0 }
        try await requestAccess()
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        var daily: [HealthKind: [Date: Double]] = [:]

        for spec in specs {
            let options: HKStatisticsOptions = switch spec.aggregation {
            case .sum: .cumulativeSum
            case .average: .discreteAverage
            case .latest: .mostRecent
            }
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(spec.id), predicate: predicate),
                options: options, anchorDate: start, intervalComponents: DateComponents(day: 1))
            // A type the user didn't allow just returns no data (HealthKit hides read denials).
            guard let collection = try? await descriptor.result(for: store) else { continue }
            for stats in collection.statistics() {
                let quantity: HKQuantity? = switch spec.aggregation {
                case .sum: stats.sumQuantity()
                case .average: stats.averageQuantity()
                case .latest: stats.mostRecentQuantity()
                }
                if let quantity { daily[spec.kind, default: [:]][calendar.startOfDay(for: stats.startDate)] = quantity.doubleValue(for: spec.unit) }
            }
        }

        let sleep = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
                                            sortDescriptors: [])
        if let samples = try? await sleep.result(for: store) {
            let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
            for s in samples where asleep.contains(s.value) {
                // A night counts for the day you wake up.
                daily[.sono, default: [:]][calendar.startOfDay(for: s.endDate), default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
            }
        }

        return try apply(daily, from: start, in: ctx, calendar: calendar)
    }

    /// Replaces imported entries from `start` on with `daily` (one entry per kind per day, dated at noon).
    @discardableResult
    static func apply(_ daily: [HealthKind: [Date: Double]], from start: Date, in ctx: ModelContext,
                      calendar: Calendar = .ptBR) throws -> Int {
        let src = source
        let old = try ctx.fetch(FetchDescriptor<HealthEntry>(predicate: #Predicate<HealthEntry> { $0.sourceRaw == src && $0.date >= start }))
        for e in old { ctx.delete(e) }
        var count = 0
        for (kind, days) in daily {
            for (day, value) in days where value > 0 && day >= calendar.startOfDay(for: start) {
                let e = HealthEntry(kind: kind, value: value, date: calendar.date(byAdding: .hour, value: 12, to: day)!)
                e.sourceRaw = source
                ctx.insert(e)
                count += 1
            }
        }
        try ctx.save()
        return count
    }
}
