import Foundation
import SwiftData

enum AutomationTrigger: String, CaseIterable, Identifiable {
    case faturaProxima, orcamentoPercentual, metaAlcancada, tarefaAtrasada, resumoSemanal, compromisso
    var id: String { rawValue }

    var label: String {
        switch self {
        case .faturaProxima: "Fatura perto do vencimento"
        case .orcamentoPercentual: "Orçamento atingiu um percentual"
        case .metaAlcancada: "Meta alcançada"
        case .tarefaAtrasada: "Tarefa ficou atrasada"
        case .resumoSemanal: "Resumo semanal no domingo"
        case .compromisso: "Compromisso nas próximas 24 h"
        }
    }

    var icon: String {
        switch self {
        case .faturaProxima: "creditcard"
        case .orcamentoPercentual: "chart.bar"
        case .metaAlcancada: "flag.checkered"
        case .tarefaAtrasada: "clock.badge.exclamationmark"
        case .resumoSemanal: "calendar"
        case .compromisso: "calendar.badge.clock"
        }
    }

    /// Meaning and range of the rule's numeric parameter.
    var parameter: (label: String, range: ClosedRange<Int>, defaultValue: Int)? {
        switch self {
        case .faturaProxima: ("Dias antes do vencimento", 1...10, 3)
        case .orcamentoPercentual: ("Percentual do orçamento", 50...100, 80)
        case .resumoSemanal: ("A partir das (hora)", 6...22, 18)
        case .metaAlcancada, .tarefaAtrasada, .compromisso: nil
        }
    }
}

enum AutomationAction: String, CaseIterable, Identifiable {
    case notificacao, tarefa
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notificacao: "Enviar notificação"
        case .tarefa: "Criar tarefa"
        }
    }
}

@Model
final class AutomationRule {
    var triggerRaw: String = AutomationTrigger.faturaProxima.rawValue
    var actionRaw: String = AutomationAction.notificacao.rawValue
    var parameter: Int = 0
    var enabled: Bool = true
    var createdAt: Date = Date()
    /// Occurrences already handled (e.g. "Cartão X|2026-11"), so each fires once. Newline-separated, capped.
    var firedKeys: String = ""

    init(trigger: AutomationTrigger, action: AutomationAction = .notificacao) {
        self.triggerRaw = trigger.rawValue
        self.actionRaw = action.rawValue
        self.parameter = trigger.parameter?.defaultValue ?? 0
    }

    var trigger: AutomationTrigger { AutomationTrigger(rawValue: triggerRaw) ?? .faturaProxima }
    var action: AutomationAction {
        get { AutomationAction(rawValue: actionRaw) ?? .notificacao }
        set { actionRaw = newValue.rawValue }
    }

    func hasFired(_ key: String) -> Bool { firedKeys.split(separator: "\n").contains { $0 == key } }

    func markFired(_ key: String) {
        // ponytail: keeps the last 200 keys; old occurrences can't recur, so dropping them is safe.
        let keys = (firedKeys.split(separator: "\n").map(String.init) + [key]).suffix(200)
        firedKeys = keys.joined(separator: "\n")
    }
}

@Model
final class AutomationRun {
    var date: Date = Date()
    var ruleLabel: String = ""
    var message: String = ""
    var ok: Bool = true

    init(ruleLabel: String, message: String, ok: Bool) {
        self.ruleLabel = ruleLabel
        self.message = message
        self.ok = ok
    }
}
