import { useState } from 'react'
import { Card, CheckButton, Confirm, Empty, Field, Icon, Modal, Seg } from '../components/ui'
import { clearBought, deleteList, newItem, newList, saveItemPrice } from '../data/actions'
import { useDb } from '../data/DbContext'
import { useItems, useLists, usePrices } from '../data/hooks'
import { SHOPPING_CATEGORIES, estimate, groupItems, lineTotal } from '../domain/shopping'
import type { Priority, ShoppingItem } from '../domain/types'
import { fmtDate } from '../lib/dates'
import { formatMoney, parseMoney } from '../lib/money'
import { PRIORITY_LABEL } from '../domain/routine'
import { TransactionForm } from './finance/TransactionForm'

export function Shopping() {
  const { db } = useDb()
  const lists = useLists()
  const items = useItems()
  const [selected, setSelected] = useState<number | undefined>()
  const [newListOpen, setNewListOpen] = useState<boolean | undefined>() // value = isWishlist
  const [editing, setEditing] = useState<ShoppingItem | undefined>()
  const [newName, setNewName] = useState('')
  const [expense, setExpense] = useState<{ title: string; amountCents?: number } | undefined>()
  const [removing, setRemoving] = useState<boolean>(false)
  const [clearing, setClearing] = useState(false)

  const list = lists.find((l) => l.id === selected) ?? lists[0]
  const mine = items.filter((i) => i.listId === list?.id)
  const pending = mine.filter((i) => !i.bought)
  const bought = mine.filter((i) => i.bought).sort((a, b) => +(b.boughtAt ?? 0) - +(a.boughtAt ?? 0))
  const est = estimate(pending)

  async function add(e: React.FormEvent) {
    e.preventDefault()
    const name = newName.trim()
    if (!name || !list) return
    await db.items.add(newItem(name, list.id!))
    setNewName('')
  }

  const row = (i: ShoppingItem) => {
    const line = lineTotal(i)
    const detail = [i.quantity !== 1 || i.unit ? `${i.quantity.toLocaleString('pt-BR')} ${i.unit}`.trim() : '', i.store, list?.isWishlist && i.priority === 2 ? 'Prioridade alta' : ''].filter(Boolean).join(' · ')
    return (
      <li key={i.id}>
        <CheckButton checked={i.bought} label={i.bought ? `Desmarcar ${i.name}` : `Marcar ${i.name}`} onClick={() => db.items.update(i.id!, { bought: !i.bought, boughtAt: i.bought ? undefined : new Date() })} />
        <button className="grow btn ghost" style={{ justifyContent: 'flex-start', textAlign: 'left', padding: 0 }} onClick={() => setEditing(i)}>
          <span className="grow"><div style={{ textDecoration: i.bought ? 'line-through' : undefined }}>{i.name}</div>{detail && <div className="muted small">{detail}</div>}</span>
        </button>
        {line !== undefined && <span className="num muted">{formatMoney(line)}</span>}
        {line !== undefined && <button className="icon-btn" aria-label={`Lançar despesa de ${i.name}`} title="Lançar como despesa" onClick={() => setExpense({ title: i.name, amountCents: line })}><Icon name="wallet" size={18} /></button>}
        <button className="icon-btn" aria-label={`Apagar ${i.name}`} onClick={() => db.items.delete(i.id!)}><Icon name="trash" size={18} /></button>
      </li>
    )
  }

  return (
    <>
      <div className="page-head">
        <div><h1>Compras</h1><p className="sub">Listas de compras e de desejos. Os preços são os que você informa, não consultados em lojas.</p></div>
        <div className="row wrap">
          <button className="btn" onClick={() => setNewListOpen(false)}><Icon name="plus" size={18} /> Lista de compras</button>
          <button className="btn" onClick={() => setNewListOpen(true)}><Icon name="star" size={18} /> Lista de desejos</button>
        </div>
      </div>

      {lists.length === 0 ? <Card><Empty icon="cart">Crie uma lista de compras ou uma lista de desejos.</Empty></Card> : (
        <div className="stack">
          <Seg label="Listas" value={String(list?.id)} options={lists.map((l) => [String(l.id), `${l.isWishlist ? '★ ' : ''}${l.name}`] as const)} onChange={(v) => setSelected(Number(v))} />
          {list && (
            <>
              <form className="row" onSubmit={add}>
                <input className="input" placeholder={list.isWishlist ? 'Adicionar desejo' : 'Adicionar item'} value={newName} onChange={(e) => setNewName(e.target.value)} aria-label="Novo item" />
                <button className="btn primary" type="submit" disabled={!newName.trim()}>Adicionar</button>
              </form>
              {groupItems(pending).map((g) => <Card key={g.category} title={g.category || 'Sem categoria'}><ul className="list">{g.items.map(row)}</ul></Card>)}
              {pending.length === 0 && <p className="muted">Nenhum item pendente.</p>}
              {bought.length > 0 && (
                <Card title={list.isWishlist ? 'Conquistados' : 'Comprados'} action={
                  <div className="row">
                    <button className="btn small" onClick={() => setExpense({ title: list.name, amountCents: bought.reduce((s, i) => s + (lineTotal(i) ?? 0), 0) || undefined })}>Lançar compra</button>
                    <button className="btn small danger" onClick={() => setClearing(true)}>Limpar marcados</button>
                  </div>
                }><ul className="list">{bought.map(row)}</ul></Card>
              )}
              <Card>
                <div className="row between"><span>Total estimado (pendentes)</span><b className="num">{formatMoney(est.cents)}</b></div>
                <p className="muted small">{est.missing > 0 ? `${est.missing} item(ns) sem preço ficaram fora do total. ` : ''}Preços informados por você, não consultados em lojas.</p>
              </Card>
              <div><button className="btn danger" onClick={() => setRemoving(true)}>Apagar lista “{list.name}”</button></div>
            </>
          )}
        </div>
      )}

      <Modal open={newListOpen !== undefined} title={newListOpen ? 'Nova lista de desejos' : 'Nova lista de compras'} onClose={() => setNewListOpen(undefined)}>
        {newListOpen !== undefined && <ListNameBody wish={newListOpen} onClose={() => setNewListOpen(undefined)} onCreate={async (name) => { const id = await db.lists.add(newList(name, newListOpen)); setSelected(id) }} />}
      </Modal>
      <ItemDialog item={editing} wishlist={!!list?.isWishlist} onClose={() => setEditing(undefined)} />
      <TransactionForm open={!!expense} initialKind="despesa" prefill={expense} onClose={() => setExpense(undefined)} />
      <Confirm open={removing} title="Apagar lista?" text="Todos os itens e o histórico de preços da lista serão apagados." confirmLabel="Apagar" onConfirm={() => list && deleteList(db, list.id!)} onClose={() => setRemoving(false)} />
      <Confirm open={clearing} title={`Remover ${bought.length} item(ns) marcado(s)?`} text="Esta ação não pode ser desfeita." confirmLabel="Remover" onConfirm={() => list && clearBought(db, list.id!)} onClose={() => setClearing(false)} />
    </>
  )
}

function ListNameBody({ wish, onClose, onCreate }: { wish: boolean; onClose: () => void; onCreate: (name: string) => void }) {
  const [name, setName] = useState(wish ? 'Desejos' : '')
  return (
    <form className="form" onSubmit={(e) => { e.preventDefault(); if (name.trim()) { onCreate(name.trim()); onClose() } }}>
      <Field label="Nome"><input className="input" autoFocus value={name} onChange={(e) => setName(e.target.value)} /></Field>
      <div className="dlg-actions"><button type="button" className="btn" onClick={onClose}>Cancelar</button><button type="submit" className="btn primary" disabled={!name.trim()}>Criar</button></div>
    </form>
  )
}

function ItemDialog({ item, wishlist, onClose }: { item?: ShoppingItem; wishlist: boolean; onClose: () => void }) {
  return (
    <Modal open={!!item} title="Item" onClose={onClose}>
      {item && <ItemBody item={item} wishlist={wishlist} onClose={onClose} />}
    </Modal>
  )
}

function ItemBody({ item, wishlist, onClose }: { item: ShoppingItem; wishlist: boolean; onClose: () => void }) {
  const { db } = useDb()
  const history = usePrices().filter((p) => p.itemId === item.id).sort((a, b) => +b.observedAt - +a.observedAt)
  const [name, setName] = useState(item.name)
  const [quantity, setQuantity] = useState(item.quantity === 1 ? '' : String(item.quantity).replace('.', ','))
  const [unit, setUnit] = useState(item.unit)
  const [category, setCategory] = useState(item.category)
  const [price, setPrice] = useState(item.priceCents !== undefined ? formatMoney(item.priceCents).replace(/[^\d,.-]/g, '') : '')
  const [store, setStore] = useState(item.store)
  const [link, setLink] = useState(item.link)
  const [note, setNote] = useState(item.note)
  const [priority, setPriority] = useState<Priority>(item.priority)
  const qty = quantity.trim() === '' ? 1 : Number(quantity.replace(',', '.'))
  const cents = price.trim() === '' ? undefined : parseMoney(price)
  const valid = name.trim() && Number.isFinite(qty) && qty > 0 && cents !== null

  async function save(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    await db.items.update(item.id!, { name: name.trim(), quantity: qty, unit, category, link, note, priority })
    await saveItemPrice(db, { ...item, priceCents: item.priceCents }, cents ?? undefined, store)
    onClose()
  }
  return (
    <form className="form" onSubmit={save}>
      <Field label="Nome"><input className="input" autoFocus value={name} onChange={(e) => setName(e.target.value)} /></Field>
      <div className="two">
        <Field label="Quantidade"><input className="input" inputMode="decimal" placeholder="1" value={quantity} onChange={(e) => setQuantity(e.target.value)} /></Field>
        <Field label="Unidade (kg, un, pct)"><input className="input" value={unit} onChange={(e) => setUnit(e.target.value)} /></Field>
      </div>
      <Field label="Categoria">
        <select className="input" value={category} onChange={(e) => setCategory(e.target.value)}>
          <option value="">Sem categoria</option>
          {SHOPPING_CATEGORIES.map((c) => <option key={c}>{c}</option>)}
        </select>
      </Field>
      <div className="two">
        <Field label="Preço unitário (R$)"><input className="input" inputMode="decimal" placeholder="0,00" value={price} onChange={(e) => setPrice(e.target.value)} /></Field>
        <Field label="Loja"><input className="input" value={store} onChange={(e) => setStore(e.target.value)} /></Field>
      </div>
      <p className="muted small">Preço informado por você. Cada alteração fica registrada no histórico com a data.</p>
      {wishlist && (
        <div className="two">
          <Field label="Prioridade"><select className="input" value={priority} onChange={(e) => setPriority(Number(e.target.value) as Priority)}>{([0, 1, 2] as const).map((p) => <option key={p} value={p}>{PRIORITY_LABEL[p]}</option>)}</select></Field>
          <Field label="Link do produto"><input className="input" type="url" value={link} onChange={(e) => setLink(e.target.value)} /></Field>
        </div>
      )}
      {wishlist && /^https?:\/\//.test(link) && <a href={link} target="_blank" rel="noopener noreferrer">Abrir link</a>}
      <Field label="Observação"><textarea className="input" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      {history.length > 0 && (
        <div><h3 style={{ marginBottom: 6 }}>Histórico de preços</h3>
          <ul className="list">{history.map((p) => <li key={p.id}><span className="grow"><b className="num">{formatMoney(p.priceCents)}</b><div className="muted small">{[p.store, fmtDate(p.observedAt), 'informado por você'].filter(Boolean).join(' · ')}</div></span></li>)}</ul>
        </div>
      )}
      <div className="dlg-actions"><button type="button" className="btn" onClick={onClose}>Cancelar</button><button type="submit" className="btn primary" disabled={!valid}>Salvar</button></div>
    </form>
  )
}
