import { useState } from 'react'
import { Field, Modal } from '../../components/ui'
import { addTransactions } from '../../data/actions'
import { useDb } from '../../data/DbContext'
import { useAccounts, useCategories } from '../../data/hooks'
import type { Repetition } from '../../domain/finance'
import type { Transaction, TxnKind } from '../../domain/types'
import { fromDateInput, toDateInput } from '../../lib/dates'
import { formatMoney, parseMoney } from '../../lib/money'

const KINDS: ReadonlyArray<[TxnKind, string]> = [['despesa', 'Despesa'], ['receita', 'Receita'], ['transferencia', 'Transferência']]

export interface FormProps {
  open: boolean
  onClose: () => void
  editing?: Transaction
  initialKind?: TxnKind
  prefill?: { title: string; amountCents?: number }
}

export function TransactionForm(props: FormProps) {
  return (
    <Modal open={props.open} title={props.editing ? 'Editar lançamento' : 'Novo lançamento'} onClose={props.onClose}>
      <Body {...props} />
    </Modal>
  )
}

function Body({ onClose, editing, initialKind, prefill }: FormProps) {
  const { db } = useDb()
  const accounts = useAccounts().filter((a) => !a.archived)
  const categories = useCategories()
  const [kind, setKind] = useState<TxnKind>(editing?.kind ?? initialKind ?? 'despesa')
  const [amount, setAmount] = useState(editing ? formatMoney(editing.amountCents).replace(/[^\d,.-]/g, '') : prefill?.amountCents ? String(prefill.amountCents / 100).replace('.', ',') : '')
  const [title, setTitle] = useState(editing?.title ?? prefill?.title ?? '')
  const [note, setNote] = useState(editing?.note ?? '')
  const [date, setDate] = useState(toDateInput(editing?.date ?? new Date()))
  const [accountId, setAccountId] = useState<number | undefined>(editing?.accountId)
  const [toAccountId, setToAccountId] = useState<number | undefined>(editing?.toAccountId)
  const [categoryId, setCategoryId] = useState<number | undefined>(editing?.categoryId)
  const [isFixed, setIsFixed] = useState(editing?.isFixed ?? false)
  const [repetition, setRepetition] = useState<'unica' | 'parcelada' | 'recorrente'>('unica')
  const [installments, setInstallments] = useState(2)
  const [error, setError] = useState('')

  const cents = parseMoney(amount)
  const account = accountId ?? accounts[0]?.id
  const wanted = kind === 'receita' ? 'receita' : 'despesa'
  const options = categories
    .filter((c) => c.kind === wanted)
    .map((c) => ({ id: c.id!, label: c.parentId ? `${categories.find((p) => p.id === c.parentId)?.name} › ${c.name}` : c.name }))
    .sort((a, b) => a.label.localeCompare(b.label, 'pt-BR'))

  async function save(e: React.FormEvent) {
    e.preventDefault()
    const when = fromDateInput(date)
    if (!cents || cents <= 0) return setError('Informe um valor maior que zero.')
    if (!when) return setError('Informe uma data válida.')
    if (account === undefined) return setError('Cadastre uma conta antes de lançar.')
    if (kind === 'transferencia' && (toAccountId === undefined || toAccountId === account)) return setError('Escolha uma conta de destino diferente da origem.')
    const finalTitle = title.trim() || (kind === 'transferencia' ? 'Transferência' : (options.find((o) => o.id === categoryId)?.label ?? KINDS.find(([k]) => k === kind)![1]))
    const transfer = kind === 'transferencia'
    if (editing) {
      await db.transactions.update(editing.id!, {
        kind, amountCents: cents, title: finalTitle, note, date: when, accountId: account, isFixed,
        toAccountId: transfer ? toAccountId : undefined, categoryId: transfer ? undefined : categoryId,
      })
    } else {
      const rep: Repetition = repetition === 'parcelada' ? { type: 'parcelada', count: installments } : { type: repetition }
      await addTransactions(db, { kind, amountCents: cents, title: finalTitle, note, date: when, accountId: account, toAccountId, categoryId, isFixed, repetition: rep })
    }
    onClose()
  }

  return (
    <form className="form" onSubmit={save}>
      <div className="seg" role="group" aria-label="Tipo">
        {KINDS.map(([k, label]) => (
          <button key={k} type="button" aria-pressed={kind === k} onClick={() => { setKind(k); setCategoryId(undefined) }}>{label}</button>
        ))}
      </div>
      <Field label="Valor (R$)">
        <input className="input num" inputMode="decimal" autoFocus placeholder="0,00" value={amount} onChange={(e) => setAmount(e.target.value)} style={{ fontSize: 24, fontWeight: 800 }} />
      </Field>
      <Field label="Descrição"><input className="input" value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
      <div className="two">
        <Field label="Data"><input className="input" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
        <Field label={kind === 'transferencia' ? 'De' : 'Conta'}>
          <select className="input" value={account ?? ''} onChange={(e) => setAccountId(Number(e.target.value))}>
            {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </Field>
      </div>
      {kind === 'transferencia' ? (
        <Field label="Para">
          <select className="input" value={toAccountId ?? ''} onChange={(e) => setToAccountId(Number(e.target.value))}>
            <option value="">Selecione</option>
            {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </Field>
      ) : (
        <div className="two">
          <Field label="Categoria">
            <select className="input" value={categoryId ?? ''} onChange={(e) => setCategoryId(e.target.value ? Number(e.target.value) : undefined)}>
              <option value="">Sem categoria</option>
              {options.map((o) => <option key={o.id} value={o.id}>{o.label}</option>)}
            </select>
          </Field>
          <label className="field"><span>{kind === 'receita' ? 'Receita fixa' : 'Despesa fixa'}</span>
            <input type="checkbox" checked={isFixed} onChange={(e) => setIsFixed(e.target.checked)} style={{ width: 24, height: 24 }} />
          </label>
        </div>
      )}
      {!editing && (
        <div className="stack" style={{ gap: 8 }}>
          <div className="seg" role="group" aria-label="Repetição">
            {([['unica', 'Única'], ['parcelada', 'Parcelada'], ['recorrente', 'Mensal']] as const).map(([k, label]) => (
              <button key={k} type="button" aria-pressed={repetition === k} onClick={() => setRepetition(k)}>{label}</button>
            ))}
          </div>
          {repetition === 'parcelada' && (
            <Field label="Parcelas"><input className="input" type="number" min={2} max={48} value={installments} onChange={(e) => setInstallments(Math.max(2, Math.min(48, Number(e.target.value) || 2)))} /></Field>
          )}
          {repetition === 'parcelada' && <p className="muted small">O valor informado é o total da compra, dividido em parcelas mensais.</p>}
          {repetition === 'recorrente' && <p className="muted small">Cria o lançamento todo mês pelos próximos 12 meses.</p>}
        </div>
      )}
      <Field label="Observação"><textarea className="input" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      {error && <p className="err" role="alert">{error}</p>}
      <div className="dlg-actions">
        <button type="button" className="btn" onClick={onClose}>Cancelar</button>
        <button type="submit" className="btn primary">Salvar</button>
      </div>
    </form>
  )
}
