import { useState } from 'react'
import { Bars, LineChart } from '../components/charts'
import { Field, Icon, Modal, Progress } from '../components/ui'
import { addHealth, setHealthTarget } from '../data/actions'
import { useDb } from '../data/DbContext'
import { useHealth, useHealthTargets } from '../data/hooks'
import { HEALTH, HEALTH_KINDS, average, current, daily, formatValue, supportsTarget, weeklyChange } from '../domain/health'
import type { HealthEntry, HealthKind } from '../domain/types'
import { fmtDate, fmtTime, fromDateInput, toDateInput } from '../lib/dates'

const DISCLAIMER =
  'Registros pessoais para acompanhamento. O livo não faz diagnósticos nem recomendações clínicas; para isso, procure um profissional de saúde.'

export function Health() {
  const entries = useHealth()
  const targets = useHealthTargets()
  const [detail, setDetail] = useState<HealthKind | undefined>()
  const [adding, setAdding] = useState<HealthKind | undefined>()

  return (
    <>
      <div className="page-head">
        <div><h1>Saúde</h1><p className="sub">Seus registros manuais, gráficos e metas diárias.</p></div>
        <button className="btn primary" onClick={() => setAdding('agua')}><Icon name="plus" size={18} /> Novo registro</button>
      </div>
      <div className="grid cols-3">
        {HEALTH_KINDS.map((k) => {
          const mine = entries.filter((e) => e.kind === k)
          const now = current(mine, k)
          const target = targets.find((t) => t.kind === k)?.value
          return (
            <button key={k} className="card" style={{ textAlign: 'left' }} onClick={() => setDetail(k)} aria-label={`${HEALTH[k].label}: abrir detalhes`}>
              <div className="muted small" style={{ fontWeight: 800 }}>{HEALTH[k].label}</div>
              {now ? (
                <>
                  <div className="num" style={{ fontSize: 26, fontWeight: 900 }}>{formatValue(now.value, k, now.value2)} <span className="muted small">{HEALTH[k].unit}</span></div>
                  <div className="muted small">{HEALTH[k].aggregation === 'sum' ? 'hoje' : fmtDate(now.date)}</div>
                </>
              ) : <div className="muted" style={{ marginTop: 6 }}>Sem registros</div>}
              {supportsTarget(k) && target !== undefined && <div style={{ marginTop: 8 }}><Progress value={(now?.value ?? 0) / target} /></div>}
            </button>
          )
        })}
      </div>
      <p className="muted small" style={{ marginTop: 20 }}>{DISCLAIMER}</p>
      <Modal open={!!detail} title={detail ? HEALTH[detail].label : ''} onClose={() => setDetail(undefined)}>
        {detail && <Detail kind={detail} onAdd={() => { setAdding(detail); setDetail(undefined) }} />}
      </Modal>
      <Modal open={!!adding} title="Novo registro" onClose={() => setAdding(undefined)}>
        {adding && <EntryBody initial={adding} onClose={() => setAdding(undefined)} />}
      </Modal>
    </>
  )
}

function Detail({ kind, onAdd }: { kind: HealthKind; onAdd: () => void }) {
  const { db } = useDb()
  const meta = HEALTH[kind]
  const entries = useHealth().filter((e) => e.kind === kind).sort((a, b) => +b.date - +a.date)
  const target = useHealthTargets().find((t) => t.kind === kind)?.value
  const [targetText, setTargetText] = useState(target?.toString() ?? '')
  const series = daily(entries, kind, 30)
  const avg = average(entries, kind)
  const change = weeklyChange(entries, kind)
  const fmt = (n: number) => `${n.toLocaleString('pt-BR', { maximumFractionDigits: meta.decimals })} ${meta.unit}`
  return (
    <div className="stack">
      {series.length === 0 ? <p className="muted">Sem registros nos últimos 30 dias.</p> : meta.aggregation === 'sum'
        ? <Bars data={series.map((d) => ({ x: d.day, y: d.value }))} label={`${meta.label} nos últimos 30 dias`} target={target} />
        : <LineChart points={series.map((d) => ({ x: d.day, y: d.value }))} label={`${meta.label} nos últimos 30 dias`} format={(n) => n.toFixed(meta.decimals)} />}
      <ul className="list">
        <li><span className="grow">Média diária (7 dias)</span><b className="num">{avg === undefined ? '—' : fmt(avg)}</b></li>
        <li><span className="grow">Variação vs. semana anterior</span><b className="num">{change === undefined ? '—' : `${change > 0 ? '+' : ''}${fmt(change)}`}</b></li>
      </ul>
      {supportsTarget(kind) && (
        <form className="row" onSubmit={(e) => { e.preventDefault(); const v = Number(targetText.replace(/\./g, '').replace(',', '.')); void setHealthTarget(db, kind, Number.isFinite(v) && v > 0 ? v : undefined) }}>
          <Field label={`Meta diária (${meta.unit})`}><input className="input" inputMode="decimal" value={targetText} onChange={(e) => setTargetText(e.target.value)} placeholder="Sem meta" /></Field>
          <button className="btn" type="submit" style={{ alignSelf: 'end' }}>Salvar meta</button>
        </form>
      )}
      <div className="row between"><h3>Registros</h3><button className="btn small primary" onClick={onAdd}>Novo registro</button></div>
      <ul className="list" style={{ maxHeight: 240, overflow: 'auto' }}>
        {entries.length === 0 && <li className="muted">Nenhum registro ainda.</li>}
        {entries.slice(0, 100).map((e: HealthEntry) => (
          <li key={e.id}>
            <span className="grow"><b className="num">{formatValue(e.value, kind, e.value2)} {meta.unit}</b>{e.note && <div className="muted small">{e.note}</div>}</span>
            <span className="muted small">{fmtDate(e.date)} {fmtTime(e.date)}</span>
            <button className="icon-btn" aria-label="Apagar registro" onClick={() => db.health.delete(e.id!)}><Icon name="trash" size={16} /></button>
          </li>
        ))}
      </ul>
      <p className="muted small">{DISCLAIMER}</p>
    </div>
  )
}

export function HealthEntryForm({ open, onClose, initial = 'agua' }: { open: boolean; onClose: () => void; initial?: HealthKind }) {
  return <Modal open={open} title="Novo registro" onClose={onClose}><EntryBody initial={initial} onClose={onClose} /></Modal>
}

function EntryBody({ initial, onClose }: { initial: HealthKind; onClose: () => void }) {
  const { db } = useDb()
  const [kind, setKind] = useState<HealthKind>(initial)
  const [value, setValue] = useState('')
  const [value2, setValue2] = useState('')
  const [date, setDate] = useState(() => toDateInput(new Date()))
  const [note, setNote] = useState('')
  const meta = HEALTH[kind]
  const num = (s: string) => { const v = Number(s.replace(/\./g, '').replace(',', '.')); return Number.isFinite(v) && v > 0 ? v : undefined }
  const v = num(value)
  const v2 = num(value2)
  const valid = v !== undefined && (!meta.hasSecond || v2 !== undefined)

  async function save(e: React.FormEvent) {
    e.preventDefault()
    const day = fromDateInput(date)
    if (!valid || !day) return
    const now = new Date()
    const when = new Date(day.getFullYear(), day.getMonth(), day.getDate(), now.getHours(), now.getMinutes())
    await addHealth(db, kind, v!, when, meta.hasSecond ? v2 : undefined, note)
    onClose()
  }
  return (
    <form className="form" onSubmit={save}>
      <Field label="Tipo">
        <select className="input" value={kind} onChange={(e) => setKind(e.target.value as HealthKind)}>
          {HEALTH_KINDS.map((k) => <option key={k} value={k}>{HEALTH[k].label}</option>)}
        </select>
      </Field>
      <Field label={meta.hasSecond ? `Sistólica (${meta.unit})` : `Valor (${meta.unit})`}><input className="input" autoFocus inputMode="decimal" value={value} onChange={(e) => setValue(e.target.value)} /></Field>
      {meta.hasSecond && <Field label={`Diastólica (${meta.unit})`}><input className="input" inputMode="decimal" value={value2} onChange={(e) => setValue2(e.target.value)} /></Field>}
      {kind === 'agua' && <div className="row">{[200, 300, 500].map((ml) => <button key={ml} type="button" className="btn small" onClick={() => setValue(String(ml))}>{ml} ml</button>)}</div>}
      <Field label="Data"><input className="input" type="date" value={date} max={toDateInput(new Date())} onChange={(e) => setDate(e.target.value)} /></Field>
      <Field label="Observação"><input className="input" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      <div className="dlg-actions"><button type="button" className="btn" onClick={onClose}>Cancelar</button><button type="submit" className="btn primary" disabled={!valid}>Salvar</button></div>
    </form>
  )
}
