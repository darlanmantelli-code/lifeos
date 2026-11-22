import { useState } from 'react'
import { Card, Confirm, Empty, Field, Icon, Modal } from '../../components/ui'
import { deleteAccount, newAccount } from '../../data/actions'
import { useDb } from '../../data/DbContext'
import { useAccounts, useTransactions } from '../../data/hooks'
import { balance, invoiceKey, invoiceTotal } from '../../domain/finance'
import type { Account, AccountKind } from '../../domain/types'
import { formatMoney, parseMoney } from '../../lib/money'

const KINDS: ReadonlyArray<[AccountKind, string]> = [
  ['corrente', 'Conta corrente'], ['poupanca', 'Poupança'], ['carteira', 'Carteira'], ['cartao', 'Cartão de crédito'], ['investimento', 'Investimento'],
]
const kindLabel = (k: AccountKind) => KINDS.find(([v]) => v === k)![1]

export function AccountsPanel() {
  const { db } = useDb()
  const accounts = useAccounts()
  const txns = useTransactions()
  const [editing, setEditing] = useState<Account | 'new' | undefined>()
  const [removing, setRemoving] = useState<Account | undefined>()
  const active = accounts.filter((a) => !a.archived)
  const archived = accounts.filter((a) => a.archived)

  const row = (a: Account) => {
    const bal = balance(a, txns)
    const closing = a.closingDay
    return (
      <li key={a.id}>
        <span className="dot"><Icon name="wallet" size={18} /></span>
        <button className="grow btn ghost" style={{ justifyContent: 'flex-start', textAlign: 'left', padding: 0 }} onClick={() => setEditing(a)}>
          <span className="grow">
            <div>{a.name}</div>
            <div className="muted small">{kindLabel(a.kind)}</div>
            {a.kind === 'cartao' && closing !== undefined && (
              <div className="muted small num">
                Fatura atual: {formatMoney(invoiceTotal(a, txns, invoiceKey(new Date(), closing)))}
                {a.creditLimitCents !== undefined && ` · Limite disponível: ${formatMoney(a.creditLimitCents + bal)}`}
              </div>
            )}
          </span>
        </button>
        <b className={`num ${bal < 0 ? 'expense' : ''}`}>{formatMoney(bal)}</b>
        <button className="icon-btn" aria-label={`Remover ${a.name}`} onClick={() => setRemoving(a)}><Icon name="trash" size={18} /></button>
      </li>
    )
  }

  return (
    <div className="stack">
      <div className="row between">
        <p className="muted">Contas com lançamentos são arquivadas em vez de apagadas, para preservar o histórico.</p>
        <button className="btn primary" onClick={() => setEditing('new')}><Icon name="plus" size={18} /> Nova conta</button>
      </div>
      <Card>
        {active.length === 0 ? <Empty icon="wallet">Nenhuma conta ainda.</Empty> : <ul className="list">{active.map(row)}</ul>}
      </Card>
      {archived.length > 0 && (
        <Card title="Arquivadas">
          <ul className="list">
            {archived.map((a) => (
              <li key={a.id}>
                <span className="grow">{a.name}</span>
                <button className="btn small" onClick={() => db.accounts.update(a.id!, { archived: false })}>Reativar</button>
              </li>
            ))}
          </ul>
        </Card>
      )}
      <AccountForm open={editing !== undefined} editing={editing === 'new' ? undefined : editing} onClose={() => setEditing(undefined)} />
      <Confirm open={!!removing} title={`Remover ${removing?.name ?? ''}?`}
        text="Se a conta tiver lançamentos ela será arquivada; sem lançamentos, será apagada."
        confirmLabel="Remover" onConfirm={() => removing && deleteAccount(db, removing.id!)} onClose={() => setRemoving(undefined)} />
    </div>
  )
}

function AccountForm({ open, editing, onClose }: { open: boolean; editing?: Account; onClose: () => void }) {
  return (
    <Modal open={open} title={editing ? 'Editar conta' : 'Nova conta'} onClose={onClose}>
      <FormBody editing={editing} onClose={onClose} />
    </Modal>
  )
}

function FormBody({ editing, onClose }: { editing?: Account; onClose: () => void }) {
  const { db } = useDb()
  const [name, setName] = useState(editing?.name ?? '')
  const [kind, setKind] = useState<AccountKind>(editing?.kind ?? 'corrente')
  const [initial, setInitial] = useState(editing && editing.initialBalanceCents !== 0 ? formatMoney(editing.initialBalanceCents).replace(/[^\d,.-]/g, '') : '')
  const [limit, setLimit] = useState(editing?.creditLimitCents !== undefined ? formatMoney(editing.creditLimitCents).replace(/[^\d,.-]/g, '') : '')
  const [closing, setClosing] = useState(editing?.closingDay ?? 1)
  const [due, setDue] = useState(editing?.dueDay ?? 10)
  const [error, setError] = useState('')

  async function save(e: React.FormEvent) {
    e.preventDefault()
    const initialCents = initial.trim() === '' ? 0 : parseMoney(initial)
    const limitCents = limit.trim() === '' ? undefined : parseMoney(limit)
    if (!name.trim()) return setError('Informe o nome da conta.')
    if (initialCents === null || (limit.trim() !== '' && limitCents === null)) return setError('Informe valores válidos.')
    const card = kind === 'cartao'
    const patch = {
      name: name.trim(), kind, initialBalanceCents: initialCents,
      creditLimitCents: card ? (limitCents ?? undefined) : undefined, closingDay: card ? closing : undefined, dueDay: card ? due : undefined,
    }
    if (editing) await db.accounts.update(editing.id!, patch)
    else await db.accounts.add(newAccount(patch))
    onClose()
  }

  return (
    <form className="form" onSubmit={save}>
      <Field label="Nome (ex.: Nubank, Itaú)"><input className="input" autoFocus value={name} onChange={(e) => setName(e.target.value)} /></Field>
      <Field label="Tipo">
        <select className="input" value={kind} onChange={(e) => setKind(e.target.value as AccountKind)}>
          {KINDS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </Field>
      {kind === 'cartao' && (
        <>
          <Field label="Limite (R$)"><input className="input" inputMode="decimal" value={limit} onChange={(e) => setLimit(e.target.value)} /></Field>
          <div className="two">
            <Field label="Dia de fechamento"><input className="input" type="number" min={1} max={28} value={closing} onChange={(e) => setClosing(Number(e.target.value))} /></Field>
            <Field label="Dia de vencimento"><input className="input" type="number" min={1} max={28} value={due} onChange={(e) => setDue(Number(e.target.value))} /></Field>
          </div>
        </>
      )}
      <Field label="Saldo inicial (R$)"><input className="input" inputMode="decimal" placeholder="0,00" value={initial} onChange={(e) => setInitial(e.target.value)} /></Field>
      <p className="muted small">{kind === 'cartao' ? 'Para um cartão, informe a fatura em aberto como valor negativo (ex.: -350,00).' : 'Use valor negativo para saldo devedor.'}</p>
      {error && <p className="err" role="alert">{error}</p>}
      <div className="dlg-actions">
        <button type="button" className="btn" onClick={onClose}>Cancelar</button>
        <button type="submit" className="btn primary">Salvar</button>
      </div>
    </form>
  )
}
