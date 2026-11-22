import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Card, Empty, Icon } from '../components/ui'
import { useDb } from '../data/DbContext'
import { useCategories, useGoals, useHabits, useItems, useLists, useTasks, useTransactions } from '../data/hooks'
import { useLive } from '../data/DbContext'
import { isEmpty, searchAll } from '../domain/search'
import type { Study } from '../domain/types'
import { fmtDate } from '../lib/dates'
import { formatMoney } from '../lib/money'

const NO_STUDIES = [] as Study[]

/** Global search across transactions, tasks, goals, habits, shopping and studies. */
export function Search() {
  useDb()
  const [query, setQuery] = useState('')
  const transactions = useTransactions()
  const categories = useCategories()
  const tasks = useTasks()
  const goals = useGoals()
  const habits = useHabits()
  const items = useItems()
  const lists = useLists()
  const studies = useLive((db) => db.studies.toArray(), NO_STUDIES)
  const searching = query.trim() !== ''
  const r = searching ? searchAll({ transactions, categories, tasks, goals, habits, items, lists, studies }, query) : undefined

  return (
    <>
      <div className="page-head"><div><h1>Buscar</h1><p className="sub">Lançamentos, tarefas, metas, hábitos, compras e estudos.</p></div></div>
      <div className="row" style={{ marginBottom: 18 }}>
        <Icon name="search" />
        <input className="input" autoFocus type="search" placeholder="Buscar…" aria-label="Buscar" value={query} onChange={(e) => setQuery(e.target.value)} />
      </div>
      {r && isEmpty(r) && <Card><Empty icon="search">Nada encontrado para “{query.trim()}”.</Empty></Card>}
      {r && !isEmpty(r) && (
        <div className="stack">
          {r.transactions.length > 0 && (
            <Card title="Lançamentos" icon="wallet" action={<Link to="/financas" className="small">Abrir Finanças</Link>}>
              <ul className="list">{r.transactions.map((t) => (
                <li key={t.id}><span className="grow"><div>{t.title}</div><div className="muted small">{fmtDate(t.date)}</div></span><b className={`num ${t.kind === 'receita' ? 'income' : ''}`}>{formatMoney(t.amountCents)}</b></li>
              ))}</ul>
            </Card>
          )}
          {r.tasks.length > 0 && <Card title="Tarefas" icon="tasks" action={<Link to="/rotina" className="small">Abrir Rotina</Link>}><ul className="list">{r.tasks.map((t) => <li key={t.id}><span className="grow" style={{ textDecoration: t.done ? 'line-through' : undefined }}>{t.title}</span></li>)}</ul></Card>}
          {r.goals.length > 0 && <Card title="Metas" icon="target"><ul className="list">{r.goals.map((g) => <li key={g.id}><span className="grow">{g.title}</span></li>)}</ul></Card>}
          {r.habits.length > 0 && <Card title="Hábitos" icon="repeat"><ul className="list">{r.habits.map((h) => <li key={h.id}><span className="grow">{h.name}</span></li>)}</ul></Card>}
          {r.items.length > 0 && <Card title="Compras" icon="cart" action={<Link to="/compras" className="small">Abrir Compras</Link>}><ul className="list">{r.items.map((i) => <li key={i.id}><span className="grow"><div style={{ textDecoration: i.bought ? 'line-through' : undefined }}>{i.name}</div><div className="muted small">{i.listName}</div></span></li>)}</ul></Card>}
          {r.studies.length > 0 && <Card title="Estudos" icon="book" action={<Link to="/estudos" className="small">Abrir Estudos</Link>}><ul className="list">{r.studies.map((s) => <li key={s.id}><span className="grow">{s.title}</span></li>)}</ul></Card>}
        </div>
      )}
    </>
  )
}
