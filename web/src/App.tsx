import { useState } from 'react'
import { NavLink, Route, Routes, useLocation, useNavigate } from 'react-router-dom'
import { BrandLockup } from './brand/Logo'
import { Field, Icon, Modal, type IconName } from './components/ui'
import { newItem, newList } from './data/actions'
import { useDb } from './data/DbContext'
import { useLists } from './data/hooks'
import type { TxnKind } from './domain/types'
import { Finance } from './pages/Finance'
import { Health, HealthEntryForm } from './pages/Health'
import { Home } from './pages/Home'
import { Routine, HabitForm, TaskForm } from './pages/Routine'
import { Search } from './pages/Search'
import { Settings } from './pages/Settings'
import { Studies } from './pages/Studies'
import { Shopping } from './pages/Shopping'
import { TransactionForm } from './pages/finance/TransactionForm'

const NAV: ReadonlyArray<{ to: string; label: string; icon: IconName }> = [
  { to: '/', label: 'Início', icon: 'home' },
  { to: '/financas', label: 'Finanças', icon: 'wallet' },
  { to: '/rotina', label: 'Rotina', icon: 'tasks' },
  { to: '/compras', label: 'Compras', icon: 'cart' },
  { to: '/saude', label: 'Saúde', icon: 'heart' },
  { to: '/estudos', label: 'Estudos', icon: 'book' },
  { to: '/busca', label: 'Buscar', icon: 'search' },
  { to: '/config', label: 'Configurações', icon: 'settings' },
]

type Adding = { type: 'txn'; kind: TxnKind } | { type: 'task' } | { type: 'habit' } | { type: 'item' } | { type: 'health' } | undefined

export function App() {
  const { demo } = useDb()
  const [menu, setMenu] = useState(false)
  const [more, setMore] = useState(false)
  const [adding, setAdding] = useState<Adding>()
  const navigate = useNavigate()
  const { pathname } = useLocation()

  return (
    <>
      {demo && <div className="demo-banner" role="status">Modo demonstração · dados fictícios</div>}
      <div className="app">
        <aside className="side" aria-label="Navegação principal">
          <div className="lockup"><BrandLockup height={30} /></div>
          {NAV.map((n) => (
            <NavLink key={n.to} to={n.to} end={n.to === '/'} className="nav-link"><Icon name={n.icon} />{n.label}</NavLink>
          ))}
          <div className="spacer" />
          <button className="btn primary" onClick={() => setMenu(true)}><Icon name="plus" size={18} /> Adicionar</button>
        </aside>

        <main className="main" id="conteudo">
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/financas" element={<Finance />} />
            <Route path="/rotina" element={<Routine />} />
            <Route path="/compras" element={<Shopping />} />
            <Route path="/saude" element={<Health />} />
            <Route path="/estudos" element={<Studies />} />
            <Route path="/busca" element={<Search />} />
            <Route path="/config" element={<Settings />} />
            <Route path="*" element={<Home />} />
          </Routes>
        </main>
      </div>

      <nav className="tabbar" aria-label="Navegação principal">
        <NavLink to="/" end className="tab"><Icon name="home" /><span>Início</span></NavLink>
        <NavLink to="/financas" className="tab"><Icon name="wallet" /><span>Finanças</span></NavLink>
        <button className="tab add" onClick={() => setMenu(true)} aria-label="Adicionar"><span className="plus"><Icon name="plus" /></span><span>Adicionar</span></button>
        <NavLink to="/rotina" className="tab"><Icon name="tasks" /><span>Rotina</span></NavLink>
        <button className="tab" aria-current={['/compras', '/saude', '/estudos', '/busca', '/config'].includes(pathname) ? 'page' : undefined} onClick={() => setMore(true)}><Icon name="more" /><span>Mais</span></button>
      </nav>

      <Modal open={more} title="Mais" onClose={() => setMore(false)}>
        <ul className="list">
          {NAV.filter((n) => ['/compras', '/saude', '/estudos', '/busca', '/config'].includes(n.to)).map((n) => (
            <li key={n.to}><button className="btn ghost grow" style={{ justifyContent: 'flex-start' }} onClick={() => { setMore(false); navigate(n.to) }}><Icon name={n.icon} />{n.label}</button></li>
          ))}
        </ul>
      </Modal>

      <Modal open={menu} title="Adicionar" onClose={() => setMenu(false)}>
        <div className="stack" style={{ gap: 6 }}>
          {([
            ['Despesa', { type: 'txn', kind: 'despesa' }], ['Receita', { type: 'txn', kind: 'receita' }], ['Transferência', { type: 'txn', kind: 'transferencia' }],
            ['Tarefa', { type: 'task' }], ['Novo hábito', { type: 'habit' }], ['Item de compra', { type: 'item' }], ['Registro de saúde', { type: 'health' }],
          ] as const).map(([label, value]) => (
            <button key={label} className="btn" style={{ justifyContent: 'flex-start' }} onClick={() => { setMenu(false); setAdding(value as Adding) }}>{label}</button>
          ))}
          <button className="btn" style={{ justifyContent: 'flex-start' }} onClick={() => { setMenu(false); navigate('/rotina') }}>Registrar hábito (Rotina)</button>
        </div>
      </Modal>

      <TransactionForm open={adding?.type === 'txn'} initialKind={adding?.type === 'txn' ? adding.kind : undefined} onClose={() => setAdding(undefined)} />
      <TaskForm open={adding?.type === 'task'} onClose={() => setAdding(undefined)} />
      <HabitForm open={adding?.type === 'habit'} onClose={() => setAdding(undefined)} />
      <HealthEntryForm open={adding?.type === 'health'} onClose={() => setAdding(undefined)} />
      <QuickItem open={adding?.type === 'item'} onClose={() => setAdding(undefined)} />
    </>
  )
}

function QuickItem({ open, onClose }: { open: boolean; onClose: () => void }) {
  return <Modal open={open} title="Item de compra" onClose={onClose}><QuickItemBody onClose={onClose} /></Modal>
}

function QuickItemBody({ onClose }: { onClose: () => void }) {
  const { db } = useDb()
  const lists = useLists()
  const [name, setName] = useState('')
  const [listId, setListId] = useState<number | undefined>()
  const chosen = listId ?? lists.find((l) => !l.isWishlist)?.id ?? lists[0]?.id

  async function save(e: React.FormEvent) {
    e.preventDefault()
    const id = chosen ?? (await db.lists.add(newList('Mercado', false)))
    await db.items.add(newItem(name.trim(), id))
    onClose()
  }
  return (
    <form className="form" onSubmit={save}>
      <Field label="Item"><input className="input" autoFocus value={name} onChange={(e) => setName(e.target.value)} /></Field>
      <Field label="Lista">
        <select className="input" value={chosen ?? ''} onChange={(e) => setListId(Number(e.target.value))}>
          {lists.length === 0 && <option value="">Nova lista “Mercado”</option>}
          {lists.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
        </select>
      </Field>
      <div className="dlg-actions"><button type="button" className="btn" onClick={onClose}>Cancelar</button><button type="submit" className="btn primary" disabled={!name.trim()}>Salvar</button></div>
    </form>
  )
}
