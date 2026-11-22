import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { LivoMark, BrandLockup, BRAND } from '../brand/Logo'
import { Card, CheckButton, Empty, Icon, Progress, Seg } from '../components/ui'
import { addHealth, tapCheckIn, toggleTask } from '../data/actions'
import { useDb } from '../data/DbContext'
import { useAccounts, useBudgets, useCategories, useCheckIns, useGoalSteps, useGoals, useHabits, useHealth, useHealthTargets, useItems, useTasks, useTransactions } from '../data/hooks'
import { balance, budgetLines, nextDue, summarize, upcomingPayments, type DashAlert } from '../domain/finance'
import { HEALTH, current, formatValue } from '../domain/health'
import { dueLabel, goalProgress, isComplete, isOverdue, sortTasks, countIn, period, PERIOD_LABEL, streak } from '../domain/routine'
import { estimate } from '../domain/shopping'
import { addDays, fmtLongDate, inInterval, periodInterval, startOfDay, type PeriodKind } from '../lib/dates'
import { formatMoney } from '../lib/money'

const PERIODS: ReadonlyArray<readonly [PeriodKind, string]> = [['dia', 'Dia'], ['semana', 'Semana'], ['mes', 'Mês']]
const UNTIL: Record<PeriodKind, string> = { dia: 'até o fim do dia', semana: 'até o fim da semana', mes: 'até o fim do mês' }

function greeting(now: Date): string {
  const h = now.getHours()
  return h >= 5 && h < 12 ? 'Bom dia' : h >= 12 && h < 18 ? 'Boa tarde' : 'Boa noite'
}

export function Home() {
  const { db } = useDb()
  const [kind, setKind] = useState<PeriodKind>(() => (localStorage.getItem('livo.period') as PeriodKind) || 'dia')
  const now = new Date()
  const accounts = useAccounts().filter((a) => !a.archived)
  const categories = useCategories()
  const budgets = useBudgets()
  const txns = useTransactions()
  const tasks = useTasks()
  const habits = useHabits().filter((h) => !h.archived)
  const checkIns = useCheckIns()
  const goals = useGoals().filter((g) => !g.completed)
  const steps = useGoalSteps()
  const health = useHealth()
  const targets = useHealthTargets()
  const items = useItems()

  const interval = periodInterval(kind, now)
  const summary = summarize(txns.filter((t) => inInterval(t.date, interval)))
  const consolidated = accounts.reduce((s, a) => s + balance(a, txns), 0)

  const alerts = useMemo(() => buildAlerts(accounts, txns, categories, budgets, tasks, now), [accounts, txns, categories, budgets, tasks]) // eslint-disable-line react-hooks/exhaustive-deps
  const periodTasks = sortTasks(tasks.filter((t) => !t.done && (t.due ?? new Date(8.64e15)) < interval[1])).slice(0, 5)
  const pendingHabits = habits.filter((h) => !isComplete(h, checkIns, now))
  const payments = upcomingPayments(txns, interval[1], now)
  const topGoals = [...goals].sort((a, b) => b.priority - a.priority || +(a.deadline ?? 8.64e15) - +(b.deadline ?? 8.64e15)).slice(0, 3)
  const shopping = items.filter((i) => !i.bought)
  const waterNow = current(health.filter((e) => e.kind === 'agua'), 'agua')?.value

  return (
    <div className="stack" style={{ gap: 20 }}>
      <div className="page-head" style={{ marginBottom: 0 }}>
        <div><p className="muted" style={{ fontWeight: 700 }}>{fmtLongDate(now)}</p><h1>{greeting(now)}</h1></div>
        <Seg label="Período" value={kind} options={PERIODS} onChange={(k) => { setKind(k); localStorage.setItem('livo.period', k) }} />
      </div>

      <section className="hero" aria-label="Resumo financeiro">
        <LivoMark mono="#fff" className="mark-bg" />
        {accounts.length === 0 ? (
          <p>Cadastre uma conta em <Link to="/financas" style={{ color: '#fff' }}>Finanças</Link> para ver seu saldo aqui.</p>
        ) : (
          <>
            <div className="label">Saldo consolidado</div>
            <div className="big num" style={consolidated < 0 ? { color: '#ffb4b8' } : undefined}>{formatMoney(consolidated)}</div>
            <div className="stats">
              <div className="stat in"><span className="label">Receitas</span><b className="num">{formatMoney(summary.income)}</b></div>
              <div className="stat out"><span className="label">Despesas</span><b className="num">{formatMoney(summary.expense)}</b></div>
            </div>
            <div className="foot">{PERIODS.find(([k]) => k === kind)![1]} atual · inclui lançamentos previstos</div>
          </>
        )}
      </section>

      <div className="grid cols-2">
        <Card title="Alertas" icon="alert">
          {alerts.length === 0 && <p className="muted">Tudo em dia.</p>}
          {alerts.map((a) => <div key={a.id} className={`alert ${a.tone}`}><Icon name="alert" size={18} />{a.text}</div>)}
        </Card>

        <Card title="Tarefas prioritárias" icon="tasks" action={<Link to="/rotina" className="small">Ver todas</Link>}>
          {periodTasks.length === 0 ? <p className="muted">Nenhuma tarefa com prazo {UNTIL[kind]}.</p> : (
            <ul className="list">
              {periodTasks.map((t) => (
                <li key={t.id}>
                  <CheckButton checked={t.done} label={`Concluir ${t.title}`} onClick={() => toggleTask(db, t)} />
                  <span className="grow"><div>{t.title}</div><div className={`small ${isOverdue(t) ? 'expense' : 'muted'}`}>{[t.due ? dueLabel(t.due) : '', t.priority === 2 ? 'Prioridade alta' : ''].filter(Boolean).join(' · ')}</div></span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card title="Hábitos pendentes" icon="repeat">
          {habits.length === 0 ? <Empty icon="repeat">Crie hábitos na aba Rotina.</Empty> : pendingHabits.length === 0 ? <p className="muted">Todos os hábitos do período feitos.</p> : (
            <ul className="list">
              {pendingHabits.map((h) => (
                <li key={h.id}>
                  <CheckButton checked={false} label={`Registrar ${h.name}`} onClick={() => tapCheckIn(db, h)} />
                  <span className="grow"><div>{h.name}</div><div className="muted small">{countIn(h.id!, checkIns, period(now, h.frequency))}/{h.target} {PERIOD_LABEL[h.frequency]}{streak(h, checkIns) > 0 ? ` · sequência de ${streak(h, checkIns)}` : ''}</div></span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card title="Pagamentos programados" icon="calendar">
          {payments.length === 0 ? <p className="muted">Nada programado {UNTIL[kind]}.</p> : (
            <>
              <ul className="list">
                {payments.slice(0, 5).map((t) => (
                  <li key={t.id}><span className="grow"><div>{t.title}</div><div className="muted small">{t.date.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: 'short' })}</div></span><b className="num">{formatMoney(t.amountCents)}</b></li>
                ))}
              </ul>
              {payments.length > 1 && <div className="row between" style={{ marginTop: 8 }}><b>Total</b><b className="num">{formatMoney(payments.reduce((s, t) => s + t.amountCents, 0))}</b></div>}
            </>
          )}
        </Card>

        <Card title="Metas" icon="target">
          {topGoals.length === 0 ? <p className="muted">Nenhuma meta ativa.</p> : (
            <div className="stack">
              {topGoals.map((g) => { const p = goalProgress(g, steps, tasks); return (
                <div key={g.id} className="stack" style={{ gap: 6 }}><div className="row between"><b>{g.title}</b><span className="muted small num">{Math.round(p * 100)}%</span></div><Progress value={p} /></div>
              ) })}
            </div>
          )}
        </Card>

        <Card title="Saúde hoje" icon="heart" action={<Link to="/saude" className="small">Ver saúde</Link>}>
          <div className="grid" style={{ gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            {(['passos', 'agua', 'sono', 'exercicio'] as const).map((k) => {
              const v = current(health.filter((e) => e.kind === k), k)?.value
              const target = targets.find((t) => t.kind === k)?.value
              return (
                <div key={k} className="stack" style={{ gap: 4 }}>
                  <span className="muted small">{HEALTH[k].label}</span>
                  <b className="num">{v === undefined ? '—' : `${formatValue(v, k)} ${HEALTH[k].unit}`}</b>
                  {target !== undefined && <Progress value={(v ?? 0) / target} />}
                </div>
              )
            })}
          </div>
          <button className="btn small" style={{ marginTop: 12 }} onClick={() => addHealth(db, 'agua', 250, new Date())}>+ 250 ml de água{waterNow ? ` (hoje: ${waterNow} ml)` : ''}</button>
        </Card>

        <Card title="Compras" icon="cart" action={<Link to="/compras" className="small">Ver compras</Link>}>
          {shopping.length === 0 ? <p className="muted">Nenhum item pendente.</p> : (
            <ul className="list">
              <li><span className="grow">Itens pendentes</span><b>{shopping.length}</b></li>
              {estimate(shopping).cents > 0 && <li><span className="grow">Estimativa (informada por você)</span><b className="num">{formatMoney(estimate(shopping).cents)}</b></li>}
            </ul>
          )}
        </Card>
      </div>

      <footer style={{ textAlign: 'center', padding: '16px 0 4px' }} className="stack">
        <div style={{ display: 'grid', placeItems: 'center' }}><BrandLockup height={24} /></div>
        <p className="muted small">{BRAND.headline} {BRAND.tagline}</p>
      </footer>
    </div>
  )
}

function buildAlerts(accounts: ReturnType<typeof useAccounts>, txns: ReturnType<typeof useTransactions>, categories: ReturnType<typeof useCategories>, budgets: ReturnType<typeof useBudgets>, tasks: ReturnType<typeof useTasks>, now: Date): DashAlert[] {
  const out: DashAlert[] = []
  for (const l of budgetLines(now, categories, budgets, txns, now)) {
    if (l.spent > l.limit) out.push({ id: `b-${l.category.id}`, tone: 'critical', text: `Orçamento de ${l.category.name} estourado: ${formatMoney(l.spent)} de ${formatMoney(l.limit)}` })
    else if (l.spent * 10 >= l.limit * 8) out.push({ id: `b-${l.category.id}`, tone: 'warning', text: `${l.category.name} já usou ${Math.round((l.spent / l.limit) * 100)}% do orçamento do mês` })
  }
  for (const a of accounts) {
    if (a.kind === 'cartao' && a.dueDay !== undefined) {
      const days = Math.round((+nextDue(a.dueDay, now) - +startOfDay(now)) / 86_400_000)
      if (days <= 5) out.push({ id: `c-${a.id}`, tone: days <= 1 ? 'critical' : 'warning', text: `Fatura do ${a.name} ${days === 0 ? 'vence hoje' : days === 1 ? 'vence amanhã' : `vence em ${days} dias`}` })
    } else if (a.kind !== 'cartao' && balance(a, txns, now) < 0) {
      out.push({ id: `n-${a.id}`, tone: 'critical', text: `${a.name} está com saldo negativo` })
    }
  }
  const overdue = tasks.filter((t) => isOverdue(t, now)).length
  if (overdue > 0) out.push({ id: 'overdue', tone: 'warning', text: overdue === 1 ? '1 tarefa atrasada' : `${overdue} tarefas atrasadas` })
  return out.sort((a, b) => Number(b.tone === 'critical') - Number(a.tone === 'critical'))
}

export { addDays }
