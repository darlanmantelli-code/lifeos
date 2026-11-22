import Foundation
import SwiftData

/// Full export of the user's data as versioned JSON (LGPD portability + backup), restore, and wipe.
/// Relationships are written as integer ids local to the file.
struct Backup: Codable {
    static let currentVersion = 1

    var app = "livo"
    var versao = Backup.currentVersion
    var exportadoEm = Date()

    struct AccountDTO: Codable { var id: Int; var name: String; var kind: String; var initialBalanceCents: Int64
        var creditLimitCents: Int64?; var closingDay: Int?; var dueDay: Int?; var archived: Bool; var createdAt: Date }
    struct CategoryDTO: Codable { var id: Int; var name: String; var kind: String; var icon: String; var parentId: Int? }
    struct TransactionDTO: Codable { var date: Date; var amountCents: Int64; var kind: String; var title: String; var note: String
        var isFixed: Bool; var source: String; var groupID: UUID?; var installmentIndex: Int?; var installmentCount: Int?
        var isRecurring: Bool; var createdAt: Date; var accountId: Int?; var toAccountId: Int?; var categoryId: Int? }
    struct BudgetDTO: Codable { var month: String; var limitCents: Int64; var categoryId: Int? }
    struct GoalDTO: Codable { var id: Int; var title: String; var notes: String; var horizon: String; var deadline: Date?
        var priority: Int; var targetValue: Double?; var currentValue: Double?; var unit: String; var completed: Bool; var createdAt: Date }
    struct GoalStepDTO: Codable { var title: String; var done: Bool; var order: Int; var goalId: Int? }
    struct TaskDTO: Codable { var title: String; var notes: String; var due: Date?; var priority: Int; var done: Bool
        var doneAt: Date?; var createdAt: Date; var goalId: Int? }
    struct HabitDTO: Codable { var id: Int; var name: String; var icon: String; var frequency: String; var target: Int
        var archived: Bool; var createdAt: Date }
    struct CheckInDTO: Codable { var date: Date; var habitId: Int? }
    struct ListDTO: Codable { var id: Int; var name: String; var icon: String; var isWishlist: Bool; var createdAt: Date }
    struct ItemDTO: Codable { var id: Int; var name: String; var quantity: Double; var unit: String; var category: String
        var priceCents: Int64?; var store: String; var link: String; var note: String; var bought: Bool; var boughtAt: Date?
        var priority: Int; var createdAt: Date; var listId: Int? }
    struct PriceDTO: Codable { var priceCents: Int64; var store: String; var observedAt: Date; var source: String; var itemId: Int? }
    struct HealthDTO: Codable { var kind: String; var value: Double; var value2: Double?; var date: Date; var note: String
        var source: String; var createdAt: Date }
    struct TargetDTO: Codable { var kind: String; var value: Double }
    struct LogDTO: Codable { var date: Date; var tool: String; var summary: String; var status: String }
    struct RuleDTO: Codable { var trigger: String; var action: String; var parameter: Int; var enabled: Bool; var createdAt: Date; var firedKeys: String }
    struct RunDTO: Codable { var date: Date; var ruleLabel: String; var message: String; var ok: Bool }
    struct StudyDTO: Codable { var id: Int; var title: String; var kind: String; var progress: Int; var notes: String
        var reviewStage: Int?; var nextReview: Date?; var archived: Bool; var createdAt: Date }
    struct FocusDTO: Codable { var start: Date; var minutes: Int; var studyId: Int? }

    var contas: [AccountDTO] = []
    var categorias: [CategoryDTO] = []
    var lancamentos: [TransactionDTO] = []
    var orcamentos: [BudgetDTO] = []
    var metas: [GoalDTO] = []
    var etapas: [GoalStepDTO] = []
    var tarefas: [TaskDTO] = []
    var habitos: [HabitDTO] = []
    var registrosHabitos: [CheckInDTO] = []
    var listas: [ListDTO] = []
    var itens: [ItemDTO] = []
    var precos: [PriceDTO] = []
    var saude: [HealthDTO] = []
    var metasSaude: [TargetDTO] = []
    var historicoIA: [LogDTO] = []
    // Added after version 1 shipped: optional so older files still decode.
    var automacoes: [RuleDTO]? = []
    var execucoesAutomacoes: [RunDTO]? = []
    var estudos: [StudyDTO]? = []
    var sessoesFoco: [FocusDTO]? = []

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Assigns stable integer ids to models while exporting.
private struct IdMap {
    private var ids: [PersistentIdentifier: Int] = [:]
    mutating func id(_ m: (any PersistentModel)?) -> Int? {
        guard let m else { return nil }
        if let existing = ids[m.persistentModelID] { return existing }
        let new = ids.count + 1
        ids[m.persistentModelID] = new
        return new
    }
}

@MainActor
enum BackupStore {
    struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func all<T: PersistentModel>(_ ctx: ModelContext, _: T.Type) throws -> [T] {
        try ctx.fetch(FetchDescriptor<T>())
    }

    static func export(_ ctx: ModelContext) throws -> Data {
        var m = IdMap()
        var b = Backup()
        for a in try all(ctx, Account.self) {
            b.contas.append(.init(id: m.id(a)!, name: a.name, kind: a.kindRaw, initialBalanceCents: a.initialBalanceCents,
                                  creditLimitCents: a.creditLimitCents, closingDay: a.closingDay, dueDay: a.dueDay,
                                  archived: a.archived, createdAt: a.createdAt))
        }
        for c in try all(ctx, FinanceCategory.self) {
            b.categorias.append(.init(id: m.id(c)!, name: c.name, kind: c.kindRaw, icon: c.icon, parentId: m.id(c.parent)))
        }
        for t in try all(ctx, FinanceTransaction.self) {
            b.lancamentos.append(.init(date: t.date, amountCents: t.amountCents, kind: t.kindRaw, title: t.title, note: t.note,
                                       isFixed: t.isFixed, source: t.sourceRaw, groupID: t.groupID,
                                       installmentIndex: t.installmentIndex, installmentCount: t.installmentCount,
                                       isRecurring: t.isRecurring, createdAt: t.createdAt, accountId: m.id(t.account),
                                       toAccountId: m.id(t.toAccount), categoryId: m.id(t.category)))
        }
        for x in try all(ctx, Budget.self) {
            b.orcamentos.append(.init(month: x.month, limitCents: x.limitCents, categoryId: m.id(x.category)))
        }
        for g in try all(ctx, Goal.self) {
            b.metas.append(.init(id: m.id(g)!, title: g.title, notes: g.notes, horizon: g.horizonRaw, deadline: g.deadline,
                                 priority: g.priorityRaw, targetValue: g.targetValue, currentValue: g.currentValue,
                                 unit: g.unit, completed: g.completed, createdAt: g.createdAt))
        }
        for s in try all(ctx, GoalStep.self) {
            b.etapas.append(.init(title: s.title, done: s.done, order: s.order, goalId: m.id(s.goal)))
        }
        for t in try all(ctx, TaskItem.self) {
            b.tarefas.append(.init(title: t.title, notes: t.notes, due: t.due, priority: t.priorityRaw, done: t.done,
                                   doneAt: t.doneAt, createdAt: t.createdAt, goalId: m.id(t.goal)))
        }
        for h in try all(ctx, Habit.self) {
            b.habitos.append(.init(id: m.id(h)!, name: h.name, icon: h.icon, frequency: h.frequencyRaw,
                                   target: h.targetPerPeriod, archived: h.archived, createdAt: h.createdAt))
        }
        for c in try all(ctx, HabitCheckIn.self) {
            b.registrosHabitos.append(.init(date: c.date, habitId: m.id(c.habit)))
        }
        for l in try all(ctx, ShoppingList.self) {
            b.listas.append(.init(id: m.id(l)!, name: l.name, icon: l.icon, isWishlist: l.isWishlist, createdAt: l.createdAt))
        }
        for i in try all(ctx, ShoppingItem.self) {
            b.itens.append(.init(id: m.id(i)!, name: i.name, quantity: i.quantity, unit: i.unit, category: i.category,
                                 priceCents: i.priceCents, store: i.store, link: i.link, note: i.note, bought: i.bought,
                                 boughtAt: i.boughtAt, priority: i.priorityRaw, createdAt: i.createdAt, listId: m.id(i.list)))
        }
        for p in try all(ctx, PricePoint.self) {
            b.precos.append(.init(priceCents: p.priceCents, store: p.store, observedAt: p.observedAt, source: p.sourceRaw, itemId: m.id(p.item)))
        }
        for e in try all(ctx, HealthEntry.self) {
            b.saude.append(.init(kind: e.kindRaw, value: e.value, value2: e.value2, date: e.date, note: e.note,
                                 source: e.sourceRaw, createdAt: e.createdAt))
        }
        for t in try all(ctx, HealthTarget.self) { b.metasSaude.append(.init(kind: t.kindRaw, value: t.value)) }
        for l in try all(ctx, AIActionLog.self) {
            b.historicoIA.append(.init(date: l.date, tool: l.tool, summary: l.summary, status: l.status))
        }
        b.automacoes = try all(ctx, AutomationRule.self).map {
            .init(trigger: $0.triggerRaw, action: $0.actionRaw, parameter: $0.parameter, enabled: $0.enabled, createdAt: $0.createdAt, firedKeys: $0.firedKeys)
        }
        b.execucoesAutomacoes = try all(ctx, AutomationRun.self).map { .init(date: $0.date, ruleLabel: $0.ruleLabel, message: $0.message, ok: $0.ok) }
        b.estudos = try all(ctx, StudyItem.self).map {
            .init(id: m.id($0)!, title: $0.title, kind: $0.kindRaw, progress: $0.progress, notes: $0.notes,
                  reviewStage: $0.reviewStage, nextReview: $0.nextReview, archived: $0.archived, createdAt: $0.createdAt)
        }
        b.sessoesFoco = try all(ctx, FocusSession.self).map { .init(start: $0.start, minutes: $0.minutes, studyId: m.id($0.study)) }
        return try Backup.encoder().encode(b)
    }

    /// Writes the export to a temporary file named for sharing.
    static func exportFile(_ ctx: ModelContext) throws -> URL {
        let day = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appending(path: "livo-backup-\(day).json")
        try export(ctx).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func wipe(_ ctx: ModelContext) throws {
        ReceiptStore.deleteAll()
        // Children first, then parents (cascades would do it, explicit is clearer).
        try ctx.delete(model: PricePoint.self)
        try ctx.delete(model: ShoppingItem.self)
        try ctx.delete(model: ShoppingList.self)
        try ctx.delete(model: HabitCheckIn.self)
        try ctx.delete(model: Habit.self)
        try ctx.delete(model: GoalStep.self)
        try ctx.delete(model: TaskItem.self)
        try ctx.delete(model: Goal.self)
        try ctx.delete(model: Budget.self)
        try ctx.delete(model: FinanceTransaction.self)
        try ctx.delete(model: FinanceCategory.self)
        try ctx.delete(model: Account.self)
        try ctx.delete(model: HealthEntry.self)
        try ctx.delete(model: HealthTarget.self)
        try ctx.delete(model: AIActionLog.self)
        try ctx.delete(model: AutomationRun.self)
        try ctx.delete(model: AutomationRule.self)
        try ctx.delete(model: FocusSession.self)
        try ctx.delete(model: StudyItem.self)
        try ctx.save()
    }

    /// Replaces everything with the backup's contents. Decodes fully before touching the store.
    static func restore(_ data: Data, into ctx: ModelContext) throws {
        let b: Backup
        do { b = try Backup.decoder().decode(Backup.self, from: data) } catch {
            throw ImportError(message: "Arquivo não é um backup válido do livo.")
        }
        guard b.app == "livo" else { throw ImportError(message: "Arquivo não é um backup do livo.") }
        guard b.versao <= Backup.currentVersion else {
            throw ImportError(message: "Backup feito por uma versão mais nova do app. Atualize o livo.")
        }
        try wipe(ctx)

        var accounts: [Int: Account] = [:], categories: [Int: FinanceCategory] = [:], goals: [Int: Goal] = [:]
        var habits: [Int: Habit] = [:], lists: [Int: ShoppingList] = [:], items: [Int: ShoppingItem] = [:]

        for d in b.contas {
            let a = Account(name: d.name, kind: AccountKind(rawValue: d.kind) ?? .corrente, initialBalanceCents: d.initialBalanceCents)
            ctx.insert(a)
            a.creditLimitCents = d.creditLimitCents; a.closingDay = d.closingDay; a.dueDay = d.dueDay
            a.archived = d.archived; a.createdAt = d.createdAt
            accounts[d.id] = a
        }
        for d in b.categorias {
            let c = FinanceCategory(name: d.name, kind: CategoryKind(rawValue: d.kind) ?? .despesa, icon: d.icon)
            ctx.insert(c)
            categories[d.id] = c
        }
        for d in b.categorias { categories[d.id]?.parent = d.parentId.flatMap { categories[$0] } }
        for d in b.lancamentos {
            let t = FinanceTransaction(kind: TxnKind(rawValue: d.kind) ?? .despesa, amountCents: d.amountCents, title: d.title, date: d.date)
            ctx.insert(t)
            t.note = d.note; t.isFixed = d.isFixed; t.sourceRaw = d.source; t.groupID = d.groupID
            t.installmentIndex = d.installmentIndex; t.installmentCount = d.installmentCount
            t.isRecurring = d.isRecurring; t.createdAt = d.createdAt
            t.account = d.accountId.flatMap { accounts[$0] }
            t.toAccount = d.toAccountId.flatMap { accounts[$0] }
            t.category = d.categoryId.flatMap { categories[$0] }
        }
        for d in b.orcamentos {
            let x = Budget(month: d.month, limitCents: d.limitCents)
            ctx.insert(x)
            x.category = d.categoryId.flatMap { categories[$0] }
        }
        for d in b.metas {
            let g = Goal(title: d.title, horizon: GoalHorizon(rawValue: d.horizon) ?? .curto)
            ctx.insert(g)
            g.notes = d.notes; g.deadline = d.deadline; g.priorityRaw = d.priority; g.targetValue = d.targetValue
            g.currentValue = d.currentValue; g.unit = d.unit; g.completed = d.completed; g.createdAt = d.createdAt
            goals[d.id] = g
        }
        for d in b.etapas {
            let s = GoalStep(title: d.title, order: d.order)
            ctx.insert(s)
            s.done = d.done
            s.goal = d.goalId.flatMap { goals[$0] }
        }
        for d in b.tarefas {
            let t = TaskItem(title: d.title, due: d.due, priority: Priority(rawValue: d.priority) ?? .media)
            ctx.insert(t)
            t.notes = d.notes; t.done = d.done; t.doneAt = d.doneAt; t.createdAt = d.createdAt
            t.goal = d.goalId.flatMap { goals[$0] }
        }
        for d in b.habitos {
            let h = Habit(name: d.name, frequency: HabitFrequency(rawValue: d.frequency) ?? .diaria, targetPerPeriod: d.target, icon: d.icon)
            ctx.insert(h)
            h.archived = d.archived; h.createdAt = d.createdAt
            habits[d.id] = h
        }
        for d in b.registrosHabitos {
            let c = HabitCheckIn(date: d.date)
            ctx.insert(c)
            c.habit = d.habitId.flatMap { habits[$0] }
        }
        for d in b.listas {
            let l = ShoppingList(name: d.name, isWishlist: d.isWishlist)
            ctx.insert(l)
            l.icon = d.icon; l.createdAt = d.createdAt
            lists[d.id] = l
        }
        for d in b.itens {
            let i = ShoppingItem(name: d.name)
            ctx.insert(i)
            i.quantity = d.quantity; i.unit = d.unit; i.category = d.category; i.priceCents = d.priceCents
            i.store = d.store; i.link = d.link; i.note = d.note; i.bought = d.bought; i.boughtAt = d.boughtAt
            i.priorityRaw = d.priority; i.createdAt = d.createdAt
            i.list = d.listId.flatMap { lists[$0] }
            items[d.id] = i
        }
        for d in b.precos {
            let p = PricePoint(priceCents: d.priceCents, store: d.store, observedAt: d.observedAt)
            ctx.insert(p)
            p.sourceRaw = d.source
            p.item = d.itemId.flatMap { items[$0] }
        }
        for d in b.saude {
            let e = HealthEntry(kind: HealthKind(rawValue: d.kind) ?? .agua, value: d.value, value2: d.value2, date: d.date)
            ctx.insert(e)
            e.note = d.note; e.sourceRaw = d.source; e.createdAt = d.createdAt
        }
        for d in b.metasSaude { ctx.insert(HealthTarget(kind: HealthKind(rawValue: d.kind) ?? .agua, value: d.value)) }
        for d in b.historicoIA {
            let l = AIActionLog(tool: d.tool, summary: d.summary, status: d.status)
            ctx.insert(l)
            l.date = d.date
        }
        for d in b.automacoes ?? [] {
            let r = AutomationRule(trigger: AutomationTrigger(rawValue: d.trigger) ?? .faturaProxima,
                                   action: AutomationAction(rawValue: d.action) ?? .notificacao)
            ctx.insert(r)
            r.parameter = d.parameter; r.enabled = d.enabled; r.createdAt = d.createdAt; r.firedKeys = d.firedKeys
        }
        for d in b.execucoesAutomacoes ?? [] {
            let r = AutomationRun(ruleLabel: d.ruleLabel, message: d.message, ok: d.ok)
            ctx.insert(r)
            r.date = d.date
        }
        var studies: [Int: StudyItem] = [:]
        for d in b.estudos ?? [] {
            let s = StudyItem(title: d.title, kind: StudyKind(rawValue: d.kind) ?? .curso)
            ctx.insert(s)
            s.progress = d.progress; s.notes = d.notes; s.reviewStage = d.reviewStage; s.nextReview = d.nextReview
            s.archived = d.archived; s.createdAt = d.createdAt
            studies[d.id] = s
        }
        for d in b.sessoesFoco ?? [] {
            let f = FocusSession(start: d.start, minutes: d.minutes)
            ctx.insert(f)
            f.study = d.studyId.flatMap { studies[$0] }
        }
        try ctx.save()
    }
}
