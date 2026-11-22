import { useMemo, useState } from 'react'
import { Card, Empty, Field } from '../../components/ui'
import { addTransactions } from '../../data/actions'
import { useDb } from '../../data/DbContext'
import { useAccounts, useCategories, useTransactions } from '../../data/hooks'
import { parseStatement, StatementError, suggestCategory, type StatementLine } from '../../domain/statements'
import { fmtDate } from '../../lib/dates'
import { formatMoney } from '../../lib/money'

interface Candidate { line: StatementLine; include: boolean; categoryId?: number; duplicate: boolean }

/** Import a bank statement (OFX or CSV) into one account, with a preview before anything is saved. */
export function ImportPanel() {
  const { db } = useDb()
  const accounts = useAccounts().filter((a) => !a.archived)
  const categories = useCategories()
  const history = useTransactions()
  const [accountId, setAccountId] = useState<number | undefined>()
  const [positiveIsExpense, setPositiveIsExpense] = useState(false)
  const [lines, setLines] = useState<StatementLine[]>([])
  const [fileName, setFileName] = useState('')
  const [error, setError] = useState('')
  const [done, setDone] = useState('')
  const [overrides, setOverrides] = useState<Record<string, { include?: boolean; categoryId?: number | null }>>({})

  const account = accountId ?? accounts[0]?.id
  const isExpense = (l: StatementLine) => (positiveIsExpense ? l.amountCents > 0 : l.amountCents < 0)

  const candidates: Candidate[] = useMemo(() => {
    const existing = new Set(history.filter((t) => t.accountId === account && t.externalID).map((t) => t.externalID!))
    return lines.map((line) => {
      const dup = existing.has(line.id)
      const o = overrides[line.id]
      const suggested = suggestCategory(line.description, !isExpense(line), categories, history)?.id
      return {
        line, duplicate: dup,
        include: o?.include ?? (!dup && line.amountCents !== 0),
        categoryId: o && 'categoryId' in o ? (o.categoryId ?? undefined) : suggested,
      }
    })
  }, [lines, overrides, account, history, categories, positiveIsExpense]) // eslint-disable-line react-hooks/exhaustive-deps

  const selected = candidates.filter((c) => c.include)

  async function load(file: File) {
    setError(''); setDone(''); setOverrides({})
    try {
      setLines(parseStatement(await file.text()))
      setFileName(file.name)
    } catch (e) {
      setLines([]); setFileName('')
      setError(e instanceof StatementError ? e.message : 'Não foi possível ler o arquivo.')
    }
  }

  async function commit() {
    if (account === undefined) return
    for (const c of selected) {
      await addTransactions(db, {
        kind: isExpense(c.line) ? 'despesa' : 'receita', amountCents: Math.abs(c.line.amountCents), title: c.line.description,
        date: c.line.date, accountId: account, categoryId: c.categoryId, source: 'importacao', externalID: c.line.id,
      })
    }
    setDone(`${selected.length} lançamento(s) importado(s).`)
    setLines([]); setFileName('')
  }

  if (accounts.length === 0) return <Card><Empty icon="upload">Cadastre uma conta para importar um extrato.</Empty></Card>

  return (
    <div className="stack">
      <Card title="Importar extrato" icon="upload">
        <div className="form">
          <div className="two">
            <Field label="Conta">
              <select className="input" value={account ?? ''} onChange={(e) => setAccountId(Number(e.target.value))}>
                {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
              </select>
            </Field>
            <Field label="Arquivo OFX ou CSV">
              <input className="input" type="file" accept=".ofx,.csv,.txt,text/csv" onChange={(e) => { const f = e.target.files?.[0]; if (f) void load(f); e.target.value = '' }} />
            </Field>
          </div>
          <label className="row"><input type="checkbox" checked={positiveIsExpense} onChange={(e) => setPositiveIsExpense(e.target.checked)} style={{ width: 20, height: 20 }} />
            <span>Valores positivos são despesas (faturas de cartão)</span></label>
          <p className="muted small">Nada é gravado antes de você confirmar. Lançamentos já importados nesta conta aparecem como duplicados e vêm desmarcados.</p>
          {error && <p className="err" role="alert">{error}</p>}
          {done && <p className="note-box" role="status">{done}</p>}
        </div>
      </Card>
      {candidates.length > 0 && (
        <Card title={`${fileName} · ${selected.length} de ${candidates.length} selecionados`}>
          <div className="scroll-x">
            <table className="t">
              <thead><tr><th /><th>Data</th><th>Descrição</th><th>Categoria</th><th style={{ textAlign: 'right' }}>Valor</th></tr></thead>
              <tbody>
                {candidates.map((c) => {
                  const wanted = isExpense(c.line) ? 'despesa' : 'receita'
                  return (
                    <tr key={c.line.id} style={{ opacity: c.include ? 1 : 0.55 }}>
                      <td><input type="checkbox" aria-label={`Importar ${c.line.description}`} checked={c.include} onChange={(e) => setOverrides({ ...overrides, [c.line.id]: { ...overrides[c.line.id], include: e.target.checked } })} /></td>
                      <td className="num">{fmtDate(c.line.date)}{c.duplicate && <div className="small" style={{ color: 'var(--warn)' }}>duplicado</div>}</td>
                      <td>{c.line.description}</td>
                      <td>
                        <select className="input" style={{ padding: '6px 8px' }} value={c.categoryId ?? ''} aria-label={`Categoria de ${c.line.description}`}
                          onChange={(e) => setOverrides({ ...overrides, [c.line.id]: { ...overrides[c.line.id], categoryId: e.target.value ? Number(e.target.value) : null } })}>
                          <option value="">Sem categoria</option>
                          {categories.filter((k) => k.kind === wanted).map((k) => <option key={k.id} value={k.id}>{k.parentId ? '— ' : ''}{k.name}</option>)}
                        </select>
                      </td>
                      <td className={`num ${isExpense(c.line) ? '' : 'income'}`} style={{ textAlign: 'right', fontWeight: 800 }}>{isExpense(c.line) ? '−' : '+'}{formatMoney(Math.abs(c.line.amountCents))}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <div className="dlg-actions" style={{ marginTop: 14 }}>
            <button className="btn" onClick={() => { setLines([]); setFileName('') }}>Cancelar</button>
            <button className="btn primary" disabled={selected.length === 0} onClick={commit}>Importar {selected.length}</button>
          </div>
        </Card>
      )}
    </div>
  )
}
