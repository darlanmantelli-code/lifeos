import Foundation
import SwiftData
import SwiftUI

/// Demo mode: in-memory store filled with clearly fictitious records, never mixed with real data.
/// Enabled with the launch argument `-demo YES` (CI screenshots); a user toggle comes with the privacy stage.
enum DemoMode {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demo") }
}

struct DemoBanner: View {
    var body: some View {
        Label("Modo demonstração · dados fictícios", systemImage: "theatermasks")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
enum DemoData {
    static func seed(_ ctx: ModelContext, now: Date = .now) {
        let cal = Calendar.ptBR
        func daysAgo(_ n: Int, hour: Int = 12) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -n, to: now)!)!
        }
        let monthStart = MonthKey.interval(of: now).start
        func inMonth(_ day: Int) -> Date { cal.date(byAdding: .day, value: day - 1, to: monthStart)! }

        // Finanças
        FinanceStore.seedCategoriesIfNeeded(ctx)
        let cats = (try? ctx.fetch(FetchDescriptor<FinanceCategory>())) ?? []
        func cat(_ name: String) -> FinanceCategory? { cats.first { $0.name == name } }

        let conta = Account(name: "Conta Demo", kind: .corrente, initialBalanceCents: 520_000)
        let poupanca = Account(name: "Reserva Demo", kind: .poupanca, initialBalanceCents: 1_250_000)
        let cartao = Account(name: "Cartão Demo", kind: .cartao)
        [conta, poupanca, cartao].forEach { ctx.insert($0) }
        cartao.creditLimitCents = 800_000
        cartao.closingDay = 5
        cartao.dueDay = 12

        let entries: [(TxnKind, Int64, String, Date, Account, String?, Repetition)] = [
            (.receita, 850_000, "Salário (exemplo)", inMonth(5), conta, "Salário", .unica),
            (.despesa, 220_000, "Aluguel (exemplo)", inMonth(6), conta, "Moradia", .unica),
            (.despesa, 64_000, "Supermercado", inMonth(8), cartao, "Alimentação", .unica),
            (.despesa, 38_500, "Feira e padaria", inMonth(12), conta, "Alimentação", .unica),
            (.despesa, 25_000, "Combustível", inMonth(10), cartao, "Transporte", .unica),
            (.despesa, 5_590, "Streaming", inMonth(9), cartao, "Assinaturas", .recorrente),
            (.despesa, 480_000, "Notebook", inMonth(3), cartao, "Compras", .parcelada(10)),
            (.despesa, 9_000, "Cinema", inMonth(14), cartao, "Lazer", .unica),
            (.despesa, 18_000, "Academia", inMonth(2), conta, "Saúde", .recorrente),
        ]
        for (kind, cents, title, date, account, category, rep) in entries where date <= now || rep != .unica {
            FinanceStore.insert(TransactionDraft(kind: kind, amountCents: cents, title: title, date: date, account: account,
                                                 category: category.flatMap(cat), isFixed: rep == .recorrente, repetition: rep), in: ctx)
        }
        let key = MonthKey.of(now)
        for (name, limit) in [("Alimentação", Int64(120_000)), ("Lazer", 30_000), ("Transporte", 40_000)] {
            if let c = cat(name) { FinanceStore.setBudget(limit, for: c, from: key, in: ctx) }
        }

        // Rotina
        let habits: [(String, String, HabitFrequency, Int, [Int])] = [
            ("Ler 20 minutos", "book", .diaria, 1, [1, 2, 3, 4, 5, 7, 8]),
            ("Beber 2 L de água", "drop", .diaria, 1, [0, 1, 2, 4]),
            ("Treinar", "dumbbell", .semanal, 3, [1, 3, 8, 10, 12]),
            ("Meditar", "brain.head.profile", .diaria, 1, []),
        ]
        for (name, icon, freq, target, days) in habits {
            let h = Habit(name: name, frequency: freq, targetPerPeriod: target, icon: icon)
            ctx.insert(h)
            for d in days {
                let c = HabitCheckIn(date: daysAgo(d, hour: 8))
                ctx.insert(c)
                c.habit = h
            }
        }

        let reserva = Goal(title: "Reserva de emergência", horizon: .medio)
        reserva.targetValue = 30_000
        reserva.currentValue = 12_500
        reserva.unit = "R$"
        reserva.priority = .alta
        reserva.deadline = cal.date(byAdding: .month, value: 8, to: now)
        let livros = Goal(title: "Ler 12 livros no ano", horizon: .longo)
        livros.targetValue = 12
        livros.currentValue = 7
        livros.unit = "livros"
        let viagem = Goal(title: "Viagem de férias", horizon: .curto)
        viagem.deadline = cal.date(byAdding: .month, value: 2, to: now)
        [reserva, livros, viagem].forEach { ctx.insert($0) }
        for (i, (title, done)) in [("Definir destino", true), ("Pesquisar passagens", true), ("Reservar hotel", false), ("Montar roteiro", false)].enumerated() {
            let s = GoalStep(title: title, order: i)
            ctx.insert(s)
            s.goal = viagem
            s.done = done
        }

        let tasks: [(String, Int?, Priority, Goal?)] = [
            ("Pagar conta de luz", 0, .alta, nil),
            ("Revisar orçamento do mês", 0, .media, reserva),
            ("Renovar documento", -2, .alta, nil),
            ("Comprar passagens", 1, .media, viagem),
            ("Organizar fotos", nil, .baixa, nil),
        ]
        for (title, offset, priority, goal) in tasks {
            let t = TaskItem(title: title, due: offset.map { cal.startOfDay(for: daysAgo(-$0)) }, priority: priority)
            ctx.insert(t)
            t.goal = goal
        }

        // Compras
        let mercado = ShoppingList(name: "Mercado", isWishlist: false)
        let desejos = ShoppingList(name: "Desejos", isWishlist: true)
        ctx.insert(mercado)
        ctx.insert(desejos)
        let groceries: [(String, String, Double, String, Int64?)] = [
            ("Banana", "Hortifruti", 1.5, "kg", 699), ("Tomate", "Hortifruti", 1, "kg", 899),
            ("Arroz", "Mercearia", 1, "pct", 2_490), ("Café", "Mercearia", 2, "pct", 1_890),
            ("Leite", "Laticínios", 6, "L", 549), ("Detergente", "Limpeza", 2, "un", nil),
        ]
        for (name, category, qty, unit, price) in groceries {
            let i = ShoppingItem(name: name)
            ctx.insert(i)
            i.list = mercado
            i.category = category
            i.quantity = qty
            i.unit = unit
            ShoppingStore.setPrice(price, store: "Mercado Exemplo", for: i, at: daysAgo(3), in: ctx)
        }
        let tenis = ShoppingItem(name: "Tênis de corrida")
        ctx.insert(tenis)
        tenis.list = desejos
        tenis.priority = .alta
        ShoppingStore.setPrice(59_990, store: "Loja Exemplo", for: tenis, at: daysAgo(20), in: ctx)
        ShoppingStore.setPrice(52_990, store: "Loja Exemplo", for: tenis, at: daysAgo(2), in: ctx)

        // Saúde
        for d in 0..<21 {
            let wobble = Double((d * 37) % 11) / 10 // deterministic variation
            let records: [(HealthKind, Double, Double?)] = [
                (.passos, 6_000 + 400 * Double((d * 7) % 9), nil),
                (.agua, d == 0 ? 1_200 : 1_600 + 100 * Double(d % 6), nil),
                (.sono, 6.2 + wobble, nil),
                (.exercicio, d % 2 == 0 ? 40 : 0, nil),
                (.peso, 81.0 + Double(d) * 0.06, nil), // slowly decreasing toward today
            ]
            for (kind, value, v2) in records where value > 0 {
                ctx.insert(HealthEntry(kind: kind, value: value, value2: v2, date: daysAgo(d, hour: kind == .sono ? 7 : 19)))
            }
            if d % 3 == 0 {
                ctx.insert(HealthEntry(kind: .pressao, value: 118 + Double(d % 5), value2: 78 + Double(d % 3), date: daysAgo(d, hour: 9)))
            }
        }
        ctx.insert(HealthTarget(kind: .agua, value: 2_000))
        ctx.insert(HealthTarget(kind: .passos, value: 8_000))
        ctx.insert(HealthTarget(kind: .sono, value: 8))

        try? ctx.save()
    }
}
