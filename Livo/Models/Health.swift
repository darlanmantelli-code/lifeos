import Foundation
import SwiftData

enum HealthAggregation { case sum, average, latest }

enum HealthKind: String, CaseIterable, Identifiable {
    case passos, agua, sono, exercicio, peso, frequencia, pressao, cintura
    var id: String { rawValue }

    var label: String {
        switch self {
        case .passos: "Passos"
        case .agua: "Água"
        case .sono: "Sono"
        case .exercicio: "Exercício"
        case .peso: "Peso"
        case .frequencia: "Frequência cardíaca"
        case .pressao: "Pressão arterial"
        case .cintura: "Cintura"
        }
    }

    var unit: String {
        switch self {
        case .passos: "passos"
        case .agua: "ml"
        case .sono: "h"
        case .exercicio: "min"
        case .peso: "kg"
        case .frequencia: "bpm"
        case .pressao: "mmHg"
        case .cintura: "cm"
        }
    }

    var icon: String {
        switch self {
        case .passos: "figure.walk"
        case .agua: "drop.fill"
        case .sono: "bed.double.fill"
        case .exercicio: "flame.fill"
        case .peso: "scalemass.fill"
        case .frequencia: "heart.fill"
        case .pressao: "waveform.path.ecg"
        case .cintura: "ruler"
        }
    }

    /// How several entries on the same day combine.
    var aggregation: HealthAggregation {
        switch self {
        case .passos, .agua, .sono, .exercicio: .sum
        case .frequencia: .average
        case .peso, .pressao, .cintura: .latest
        }
    }

    var decimals: Int {
        switch self {
        case .sono, .peso, .cintura: 1
        default: 0
        }
    }

    var hasSecondValue: Bool { self == .pressao }
    var supportsDailyTarget: Bool { aggregation == .sum }
}

/// Manual entry. `sourceRaw` is "manual" until the HealthKit integration writes "healthkit".
@Model
final class HealthEntry {
    var kindRaw: String = HealthKind.agua.rawValue
    var value: Double = 0
    /// Diastolic pressure for `.pressao`.
    var value2: Double?
    var date: Date = Date()
    var note: String = ""
    var sourceRaw: String = "manual"
    var createdAt: Date = Date()

    init(kind: HealthKind, value: Double, value2: Double? = nil, date: Date) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.value2 = value2
        self.date = date
    }

    var kind: HealthKind { HealthKind(rawValue: kindRaw) ?? .agua }
}

/// Daily target for summed metrics (e.g. 2000 ml de água, 8000 passos).
@Model
final class HealthTarget {
    var kindRaw: String = HealthKind.agua.rawValue
    var value: Double = 0

    init(kind: HealthKind, value: Double) {
        self.kindRaw = kind.rawValue
        self.value = value
    }
}
