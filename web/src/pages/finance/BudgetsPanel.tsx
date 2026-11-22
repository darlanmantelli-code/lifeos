import { useState } from 'react'
import { Card, Field, Modal, Progress } from '../../components/ui'
import { setBudget } from '../../data/actions'
import { useDb } from '../../data/DbContext'
import { useBudgets, useCategories, useTransactions } from '../../data/hooks'
import { budgetLines, effectiveLimit, spentIn } from '../../domain/finance'
import type { Category } from '../../domain/types'
import { fmtMonthYear, inInterval, monthInterval, monthKey } from '../../lib/dates'
import { formatMoney, parseMoney } from '../../lib/money'

export function BudgetsPanel() {
  const { db } = useDb()
  const categories = useCategories()
  const budgets = useBudgets()
  const txns = useTransactions()
  const [editing, setEditing] = useState<Category | undefined>()
  const now = new Date()
  const key = monthKey(now)
  const monthTxns = txns.filter((t) => inInterval(t.date, monthInterval(now)) && t.date <= now)
  const roots = categories.filter((c) => c.parentId === undefined && c.kind === 'despesa')
  const lines = budgetLines(now, categories, budgets, txns, now)

  return (
    <div className="stack">
      <p className="muted">
        O limite vale a partir de {fmtMonthYear(now)} e segue nos meses seguintes até ser alterado. Informe 0 para remover.
      </p>
      <Card>
        <ul className="list">
          {roots.map((c) => {
            const limit = effectiveLimit(budgets.filter((b) => b.categoryId === c.id), key)
            const spent = spentIn(c, monthTxns, categories)
            return (
              <li key={c.id}>
                <span className="grow">
                  <div>{c.name}</div>
                  {limit !== undefined && <Progress value={spent / limit} over={spent > limit} />}
                </span>
                <span className="num" style={{ textAlign: 'right' }}>
                  <div>{limit === undefined ? <span className="muted">Sem limite</span> : formatMoney(limit)}</div>
                  <div className="muted small">Gasto: {formatMoney(spent)}</div>
                </span>
                <button className="btn small" onClick={() => setEditing(c)}>Definir</button>
              </li>
            )
          })}
        </ul>
      </Card>
      {lines.length === 0 && <p className="muted small">Defina um limite para acompanhar o orçamento na visão geral.</p>}
      <Modal open={!!editing} title={`Limite mensal — ${editing?.name ?? ''}`} onClose={() => setEditing(undefined)}>
        {editing && <LimitBody category={editing} current={effectiveLimit(budgets.filter((b) => b.categoryId === editing.id), key)} onClose={() => setEditing(undefined)}
          onSave={(cents) => setBudget(db, editing.id!, key, cents)} />}
      </Modal>
    </div>
  )
}

function LimitBody({ current, onClose, onSave }: { category: Category; current?: number; onClose: () => void; onSave: (cents: number) => void }) {
  const [text, setText] = useState(current ? formatMoney(current).replace(/[^\d,.-]/g, '') : '')
  const cents = text.trim() === '' ? 0 : parseMoney(text)
  return (
    <form className="form" onSubmit={(e) => { e.preventDefault(); if (cents !== null && cents >= 0) { onSave(cents); onClose() } }}>
      <Field label="Limite (R$)"><input className="input" autoFocus inputMode="decimal" placeholder="0,00" value={text} onChange={(e) => setText(e.target.value)} /></Field>
      <div className="dlg-actions">
        <button type="button" className="btn" onClick={onClose}>Cancelar</button>
        <button type="submit" className="btn primary" disabled={cents === null || cents < 0}>Salvar</button>
      </div>
    </form>
  )
}
