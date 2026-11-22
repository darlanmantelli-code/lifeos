import SwiftUI
import SwiftData
import Charts

/// Projection, monthly evolution and unusual-spending alerts. Shown as estimates, labelled as such.
struct InsightsView: View {
    @Query(filter: #Predicate<Account> { $0.archived == false }) private var accounts: [Account]
    @Query(sort: \FinanceTransaction.date) private var transactions: [FinanceTransaction]

    var body: some View {
        let points = FinanceInsights.projection(accounts: accounts, transactions: transactions)
        let months = FinanceInsights.monthly(transactions)
        let unusual = FinanceInsights.unusualExpenses(transactions)
        List {
            Section {
                Chart(points) { p in
                    LineMark(x: .value("Dia", p.day), y: .value("Saldo", Double(p.cents) / 100))
                        .foregroundStyle(Color.lifeAccent)
                        .interpolationMethod(.stepEnd)
                    AreaMark(x: .value("Dia", p.day), y: .value("Saldo", Double(p.cents) / 100))
                        .foregroundStyle(Color.lifeAccent.opacity(0.12))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 200)
                .padding(.vertical, Spacing.s)
                .accessibilityLabel("Projeção de saldo para os próximos 90 dias")
                ForEach([30, 60, 90], id: \.self) { d in
                    LabeledContent("Em \(d) dias") {
                        Text(FinanceInsights.projected(points, afterDays: d).map(Money.format) ?? "—").monospacedDigit()
                    }
                }
            } header: {
                Text("Projeção de saldo")
            } footer: {
                Text("Estimativa: saldo de hoje mais os lançamentos previstos já cadastrados. Não considera gastos que você ainda não lançou.")
            }

            Section {
                Chart(months) { m in
                    BarMark(x: .value("Mês", m.month, unit: .month), y: .value("Receitas", Double(m.income) / 100))
                        .foregroundStyle(Color.lifeIncome)
                        .position(by: .value("Tipo", "Receitas"))
                    BarMark(x: .value("Mês", m.month, unit: .month), y: .value("Despesas", Double(m.expense) / 100))
                        .foregroundStyle(Color.lifeExpense)
                        .position(by: .value("Tipo", "Despesas"))
                }
                .frame(height: 200)
                .padding(.vertical, Spacing.s)
            } header: {
                Text("Evolução dos últimos 6 meses")
            }

            Section {
                if unusual.isEmpty {
                    Label("Nenhum gasto fora do padrão nesta semana.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                }
                ForEach(unusual, id: \.title) { u in
                    VStack(alignment: .leading, spacing: 2) {
                        Label("\(u.title) · \(Money.format(u.cents))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.lifeExpense)
                        Text("Bem acima do habitual em \(u.category) (mediana de \(Money.format(u.typicalCents))). Sugestão, não um diagnóstico.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Gastos incomuns")
            }
        }
        .navigationTitle("Análise")
        .brandScreen()
    }
}
