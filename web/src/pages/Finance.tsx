import { useMemo, useState } from 'react'
import { Card, Confirm, Empty, Icon, Progress, Seg } from '../components/ui'
import { Donut } from '../components/charts'
import { deleteTransaction } from '../data/actions'
import { useDb } from '../data/DbContext'
import { useAccounts, useBudgets, useCategories, useTransactions } from '../data/hooks'
import { balance, budgetLines, expensesByRootCategory, summarize } from '../domain/finance'
import type { Transaction } from '../domain/types'
import { addMonths, fmtLongDate, fmtMonthYear, inInterval, monthInterval, startOfDay } from '../lib/dates'
import { formatMoney } from '../lib/money'
import { AccountsPanel } from './finance/AccountsPanel'
import { BudgetsPanel } from './finance/BudgetsPanel'
import { CategoriesPanel } from './finance/CategoriesPanel'
import { ImportPanel } from './finance/ImportPanel'
import { InsightsPanel } from './finance/InsightsPanel'
import { TransactionForm } from './finance/TransactionForm'

type Tab = 'lancamentos' | 'contas' | 'categorias' | 'orcamentos' | 'analise' | 'importar'
const TABS: ReadonlyArray<readonly [Tab, string]> = [
  ['lancamentos', 'Lançamentos'], ['contas', 'Contas'], ['categorias', 'Categorias'],
  ['orcamentos', 'Orçamentos'], ['analise', 'Análise'], ['importar', 'Importar'],
]

export function Finance() {
  const [tab, setTab] = useState<Tab>('lancamentos')
  return (
    <>
      <div className="page-head">
        <div><h1>Finanças</h1><p className="sub">Contas, lançamentos, orçamentos e projeções.</p></div>
        <Seg label="Seção" value={tab} options={TABS} onChange={setTab} />
      </div>
      {tab === 'lancamentos' && <Overview />}
      {tab === 'contas' && <AccountsPanel />}
      {tab === 'categorias' && <CategoriesPanel />}
      {tab === 'orcamentos' && <BudgetsPanel />}
      {tab === 'analise' && <InsightsPanel />}
      {tab === 'importar' && <ImportPanel />}
    </>
  )
}

function Overview() {
  const { db } = useDb()
  const accounts = useAccounts()
  const categories = useCategories()
  const budgets = useBudgets()
  const txns = useTransactions()
  const [month, setMonth] = useState(() => new Date())
  const [editing, setEditing] = useState<Transaction | undefined>()
  const [creating, setCreating] = useState(false)
  const [removing, setRemoving] = useState<Transaction | undefined>()

  const interval = monthInterval(month)
  const inMonth = useMemo(() => txns.filter((t) => inInterval(t.date, interval)), [txns, month]) // eslint-disable-line react-hooks/exhaustive-deps
  const summary = summarize(inMonth)
  const active = accounts.filter((a) => !a.archived)
  const consolidated = active.reduce((s, a) => s + balance(a, txns), 0)
  const byCategory = expensesByRootCategory(inMonth, categories)
  const lines = budgetLines(month, categories, budgets, txns)
  const accountName = (id?: number) => accounts.find((a) => a.id === id)?.name ?? 'Sem conta'
  const categoryIcon = (t: Transaction) => (t.kind === 'transferencia' ? '⇄' : (categories.find((c) => c.id === t.categoryId)?.name ?? '•').charAt(0).toUpperCase())

  const days = useMemo(() => {
    const groups = new Map<number, Transaction[]>()
    for (const t of inMonth) groups.set(startOfDay(t.date).getTime(), [...(groups.get(startOfDay(t.date).getTime()) ?? []), t])
    return [...groups].sort((a, b) => b[0] - a[0])
  }, [inMonth])

  if (active.length === 0) {
    return <Card><Empty icon="wallet">Cadastre sua primeira conta ou cartão na aba <b>Contas</b> para começar a lançar receitas e despesas.</Empty></Card>
  }

  return (
    <div className="stack">
      <div className="row between wrap">
        <div className="row">
          <button className="icon-btn" aria-label="Mês anterior" onClick={() => setMonth(addMonths(month, -1))}><Icon name="chevL" /></button>
          <h2 style={{ minWidth: 150, textAlign: 'center' }}>{fmtMonthYear(month)}</h2>
          <button className="icon-btn" aria-label="Próximo mês" onClick={() => setMonth(addMonths(month, 1))}><Icon name="chevR" /></button>
        </div>
        <button className="btn primary" onClick={() => setCreating(true)}><Icon name="plus" size={18} /> Novo lançamento</button>
      </div>

      <div className="grid cols-3">
        <div className="card"><div className="muted small">Saldo consolidado hoje</div><div className="num" style={{ fontSize: 24, fontWeight: 900 }}>{formatMoney(consolidated)}</div></div>
        <div className="card"><div className="muted small">Receitas</div><div className="num income" style={{ fontSize: 24, fontWeight: 900 }}>{formatMoney(summary.income)}</div></div>
        <div className="card"><div className="muted small">Despesas</div><div className="num expense" style={{ fontSize: 24, fontWeight: 900 }}>{formatMoney(summary.expense)}</div></div>
      </div>

      <div className="grid cols-2">
        {byCategory.length > 0 && <Card title="Para onde foi o dinheiro" icon="chart"><Donut data={byCategory} label="Despesas por categoria" /></Card>}
        {lines.length > 0 && (
          <Card title="Orçamentos do mês" icon="target">
            <div className="stack">
              {lines.map((b) => (
                <div key={b.category.id} className="stack" style={{ gap: 6 }}>
                  <div className="row between"><b>{b.category.name}</b><span className="muted small num">{formatMoney(b.spent)} de {formatMoney(b.limit)}</span></div>
                  <Progress value={b.spent / b.limit} over={b.spent > b.limit} />
                </div>
              ))}
            </div>
          </Card>
        )}
      </div>

      <Card title="Lançamentos" icon="wallet">
        {days.length === 0 && <p className="muted">Nenhum lançamento neste mês.</p>}
        {days.map(([day, items]) => (
          <div key={day}>
            <div className="day-head">{fmtLongDate(new Date(day))}</div>
            <ul className="list">
              {items.map((t) => {
                const sub = [t.kind === 'transferencia' ? `${accountName(t.accountId)} → ${accountName(t.toAccountId)}` : accountName(t.accountId),
                  t.installmentIndex ? `${t.installmentIndex}/${t.installmentCount}` : '', t.isRecurring ? 'recorrente' : '', t.date > new Date() ? 'previsto' : ''].filter(Boolean).join(' · ')
                return (
                  <li key={t.id} style={{ opacity: t.date > new Date() ? 0.65 : 1 }}>
                    <span className="dot" aria-hidden="true">{categoryIcon(t)}</span>
                    <button className="grow btn ghost" style={{ justifyContent: 'flex-start', textAlign: 'left', padding: 0 }} onClick={() => setEditing(t)}>
                      <span className="grow"><div>{t.title}</div><div className="muted small">{sub}</div></span>
                    </button>
                    <span className={`num ${t.kind === 'receita' ? 'income' : ''}`} style={{ fontWeight: 800 }}>
                      {t.kind === 'receita' ? '+' : t.kind === 'despesa' ? '−' : ''}{formatMoney(t.amountCents)}
                    </span>
                    <button className="icon-btn" aria-label={`Apagar ${t.title}`} onClick={() => setRemoving(t)}><Icon name="trash" size={18} /></button>
                  </li>
                )
              })}
            </ul>
          </div>
        ))}
      </Card>

      <TransactionForm open={creating} onClose={() => setCreating(false)} />
      <TransactionForm open={!!editing} editing={editing} onClose={() => setEditing(undefined)} />
      <DeleteDialog t={removing} onClose={() => setRemoving(undefined)} onDelete={(t, future) => deleteTransaction(db, t, future)} />
    </div>
  )
}

function DeleteDialog({ t, onClose, onDelete }: { t?: Transaction; onClose: () => void; onDelete: (t: Transaction, includingFuture: boolean) => void }) {
  if (t?.groupID) {
    return (
      <Confirm open title="Apagar lançamento?" text={`“${t.title}” faz parte de uma série. Apagar só este ou também os próximos? Não pode ser desfeito.`}
        confirmLabel="Apagar este e os próximos" onConfirm={() => onDelete(t, true)} onClose={onClose} />
    )
  }
  return (
    <Confirm open={!!t} title="Apagar lançamento?" text="Esta ação não pode ser desfeita." confirmLabel="Apagar"
      onConfirm={() => t && onDelete(t, false)} onClose={onClose} />
  )
}
