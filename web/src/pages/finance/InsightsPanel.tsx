import { Card, Icon } from '../../components/ui'
import { LineChart, MonthlyBars } from '../../components/charts'
import { useAccounts, useCategories, useTransactions } from '../../data/hooks'
import { monthlyTotals, projection, unusualExpenses } from '../../domain/finance'
import { formatMoney } from '../../lib/money'

/** Estimates computed from the user's own records. Every number here is a calculation, labelled as such. */
export function InsightsPanel() {
  const accounts = useAccounts()
  const categories = useCategories()
  const txns = useTransactions()
  const points = projection(accounts, txns)
  const months = monthlyTotals(txns)
  const unusual = unusualExpenses(txns, categories)

  return (
    <div className="stack">
      <Card title="Projeção de saldo" icon="chart">
        <LineChart points={points.map((p) => ({ x: p.day, y: p.cents }))} format={formatMoney} label="Projeção de saldo para os próximos 90 dias" />
        <ul className="list">
          {[30, 60, 90].map((d) => (
            <li key={d}><span className="grow">Em {d} dias</span><b className="num">{points[d] ? formatMoney(points[d].cents) : '—'}</b></li>
          ))}
        </ul>
        <p className="muted small">Estimativa: saldo de hoje mais os lançamentos previstos já cadastrados. Não considera gastos que você ainda não lançou.</p>
      </Card>
      <Card title="Evolução dos últimos 6 meses" icon="chart">
        <MonthlyBars data={months} label="Receitas e despesas por mês" />
        <div className="legend"><span><i style={{ background: 'var(--growth)' }} />Receitas</span><span><i style={{ background: 'var(--expense)' }} />Despesas</span></div>
      </Card>
      <Card title="Gastos incomuns" icon="alert">
        {unusual.length === 0 && <p className="muted">Nenhum gasto fora do padrão nesta semana.</p>}
        <ul className="list">
          {unusual.map((u) => (
            <li key={u.title}>
              <Icon name="alert" size={20} />
              <span className="grow">
                <div className="expense">{u.title} · {formatMoney(u.cents)}</div>
                <div className="muted small">Bem acima do habitual em {u.category} (mediana de {formatMoney(u.typicalCents)}). Sugestão, não um diagnóstico.</div>
              </span>
            </li>
          ))}
        </ul>
      </Card>
    </div>
  )
}
