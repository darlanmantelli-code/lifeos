import Foundation
import SwiftData

enum Priority: Int, CaseIterable, Identifiable {
    case baixa, media, alta
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .baixa: "Baixa"
        case .media: "Média"
        case .alta: "Alta"
        }
    }
}

enum HabitFrequency: String, CaseIterable, Identifiable {
    case diaria, semanal, mensal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .diaria: "Diário"
        case .semanal: "Semanal"
        case .mensal: "Mensal"
        }
    }
    /// "2/3 nesta semana"
    var currentPeriodLabel: String {
        switch self {
        case .diaria: "hoje"
        case .semanal: "nesta semana"
        case .mensal: "neste mês"
        }
    }
    var perPeriodLabel: String {
        switch self {
        case .diaria: "por dia"
        case .semanal: "por semana"
        case .mensal: "por mês"
        }
    }
}

enum GoalHorizon: String, CaseIterable, Identifiable {
    case curto, medio, longo
    var id: String { rawValue }
    var label: String {
        switch self {
        case .curto: "Curto prazo"
        case .medio: "Médio prazo"
        case .longo: "Longo prazo"
        }
    }
}

@Model
final class TaskItem {
    var title: String = ""
    var notes: String = ""
    /// Day only (start of day).
    var due: Date?
    var priorityRaw: Int = Priority.media.rawValue
    var done: Bool = false
    var doneAt: Date?
    var createdAt: Date = Date()
    var goal: Goal?

    init(title: String, due: Date? = nil, priority: Priority = .media) {
        self.title = title
        self.due = due
        self.priorityRaw = priority.rawValue
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .media }
        set { priorityRaw = newValue.rawValue }
    }
}

@Model
final class Habit {
    var name: String = ""
    var icon: String = "checkmark.circle"
    var frequencyRaw: String = HabitFrequency.diaria.rawValue
    var targetPerPeriod: Int = 1
    var archived: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \HabitCheckIn.habit)
    var checkIns: [HabitCheckIn]? = []

    init(name: String, frequency: HabitFrequency = .diaria, targetPerPeriod: Int = 1, icon: String = "checkmark.circle") {
        self.name = name
        self.frequencyRaw = frequency.rawValue
        self.targetPerPeriod = targetPerPeriod
        self.icon = icon
    }

    var frequency: HabitFrequency {
        get { HabitFrequency(rawValue: frequencyRaw) ?? .diaria }
        set { frequencyRaw = newValue.rawValue }
    }

    var target: Int { max(targetPerPeriod, 1) }
}

@Model
final class HabitCheckIn {
    var date: Date = Date()
    var habit: Habit?

    init(date: Date) { self.date = date }
}

@Model
final class Goal {
    var title: String = ""
    var notes: String = ""
    var horizonRaw: String = GoalHorizon.curto.rawValue
    var deadline: Date?
    var priorityRaw: Int = Priority.media.rawValue
    /// Optional numeric target (e.g. 10 kg, 50 livros). Without it, progress comes from steps and tasks.
    var targetValue: Double?
    var currentValue: Double?
    var unit: String = ""
    var completed: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \GoalStep.goal)
    var steps: [GoalStep]? = []
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.goal)
    var tasks: [TaskItem]? = []

    init(title: String, horizon: GoalHorizon = .curto) {
        self.title = title
        self.horizonRaw = horizon.rawValue
    }

    var horizon: GoalHorizon {
        get { GoalHorizon(rawValue: horizonRaw) ?? .curto }
        set { horizonRaw = newValue.rawValue }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .media }
        set { priorityRaw = newValue.rawValue }
    }
}

@Model
final class GoalStep {
    var title: String = ""
    var done: Bool = false
    var order: Int = 0
    var goal: Goal?

    init(title: String, order: Int) {
        self.title = title
        self.order = order
    }
}
