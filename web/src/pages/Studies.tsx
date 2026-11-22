import { useEffect, useRef, useState } from 'react'
import { Card, Confirm, Empty, Field, Icon, Modal, Progress } from '../components/ui'
import { useDb, useLive } from '../data/DbContext'
import { IDLE, STUDY_KINDS, clock, isFinished, isReviewDue, markReviewed, minutesSince, minutesSpent, remainingMs, startPhase, stopReviews, totalMinutes, type PomodoroState } from '../domain/study'
import type { FocusSession, Study } from '../domain/types'
import { fmtDate, weekInterval } from '../lib/dates'

const E_STUDIES = [] as Study[]
const E_FOCUS = [] as FocusSession[]
const TIMER_KEY = 'livo.pomodoro'

export function Studies() {
  const { db } = useDb()
  const studies = useLive((d) => d.studies.toArray(), E_STUDIES)
  const sessions = useLive((d) => d.focus.toArray(), E_FOCUS)
  const [editing, setEditing] = useState<Study | 'new' | undefined>()
  const [open, setOpen] = useState<Study | undefined>()
  const active = studies.filter((s) => !s.archived)
  const due = active.filter((s) => isReviewDue(s))
  const week = minutesSince(sessions, weekInterval(new Date())[0])

  return (
    <>
      <div className="page-head">
        <div><h1>Estudos</h1><p className="sub">Cursos, livros e assuntos, com revisões espaçadas e foco (Pomodoro).</p></div>
        <button className="btn primary" onClick={() => setEditing('new')}><Icon name="plus" size={18} /> Novo estudo</button>
      </div>
      <div className="grid cols-2">
        <Pomodoro studies={active} />
        <div className="stack">
          <Card title="Revisões para hoje" icon="repeat">
            {due.length === 0 ? <p className="muted">Nenhuma revisão pendente.</p> : (
              <ul className="list">{due.map((s) => (
                <li key={s.id}><span className="grow">{s.title}</span><button className="btn small" onClick={() => db.studies.update(s.id!, markReviewed(s))}>Revisei</button></li>
              ))}</ul>
            )}
          </Card>
          <Card><div className="row between"><span>Foco nesta semana</span><b className="num">{week} min</b></div></Card>
        </div>
      </div>
      <div className="stack" style={{ marginTop: 16 }}>
        {active.length === 0 ? <Card><Empty icon="book">Cadastre cursos, livros ou assuntos para acompanhar progresso, tempo e revisões.</Empty></Card> : STUDY_KINDS.map(([kind, label]) => {
          const list = active.filter((s) => s.kind === kind)
          return list.length === 0 ? null : (
            <Card key={kind} title={`${label}s`} icon="book">
              <ul className="list">{list.map((s) => (
                <li key={s.id}>
                  <button className="grow btn ghost" style={{ justifyContent: 'flex-start', textAlign: 'left', padding: 0 }} onClick={() => setOpen(s)}>
                    <span className="grow stack" style={{ gap: 6 }}>
                      <span className="row between"><b>{s.title}</b><span className="muted small num">{s.progress}%</span></span>
                      <Progress value={s.progress / 100} />
                      <span className="muted small">{totalMinutes(sessions, s.id!)} min de foco{s.nextReview ? ` · revisão em ${fmtDate(s.nextReview)}` : ''}</span>
                    </span>
                  </button>
                </li>
              ))}</ul>
            </Card>
          )
        })}
      </div>
      <StudyForm open={editing !== undefined} onClose={() => setEditing(undefined)} />
      <Modal open={!!open} title={open?.title ?? ''} onClose={() => setOpen(undefined)}>{open && <Detail id={open.id!} minutes={totalMinutes(sessions, open.id!)} onClose={() => setOpen(undefined)} />}</Modal>
    </>
  )
}

function StudyForm({ open, onClose }: { open: boolean; onClose: () => void }) {
  return <Modal open={open} title="Novo estudo" onClose={onClose}><FormBody onClose={onClose} /></Modal>
}

function FormBody({ onClose }: { onClose: () => void }) {
  const { db } = useDb()
  const [title, setTitle] = useState('')
  const [kind, setKind] = useState('curso')
  const [reviews, setReviews] = useState(true)
  async function save(e: React.FormEvent) {
    e.preventDefault()
    const base: Study = { title: title.trim(), kind, progress: 0, notes: '', archived: false, createdAt: new Date() }
    await db.studies.add(reviews ? { ...base, ...markReviewed(base) } : base)
    onClose()
  }
  return (
    <form className="form" onSubmit={save}>
      <Field label="Título"><input className="input" autoFocus value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
      <Field label="Tipo"><select className="input" value={kind} onChange={(e) => setKind(e.target.value)}>{STUDY_KINDS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></Field>
      <label className="row"><input type="checkbox" checked={reviews} onChange={(e) => setReviews(e.target.checked)} style={{ width: 20, height: 20 }} /><span>Programar revisões espaçadas</span></label>
      <div className="dlg-actions"><button type="button" className="btn" onClick={onClose}>Cancelar</button><button type="submit" className="btn primary" disabled={!title.trim()}>Salvar</button></div>
    </form>
  )
}

function Detail({ id, minutes, onClose }: { id: number; minutes: number; onClose: () => void }) {
  const { db } = useDb()
  const s = useLive((d) => d.studies.get(id), undefined as Study | undefined, [id])
  const [confirm, setConfirm] = useState(false)
  if (!s) return null
  return (
    <div className="stack">
      <Field label={`Progresso: ${s.progress}%`}>
        <input type="range" min={0} max={100} step={5} value={s.progress} onChange={(e) => db.studies.update(id, { progress: Number(e.target.value) })} />
      </Field>
      <Progress value={s.progress / 100} />
      <p className="muted">Tempo de foco: <b className="num">{minutes} min</b></p>
      <div>
        <h3 style={{ marginBottom: 6 }}>Revisões</h3>
        {s.nextReview ? (
          <div className="row wrap">
            <span className="grow">Próxima: <b>{fmtDate(s.nextReview)}</b></span>
            <button className="btn small" onClick={() => db.studies.update(id, markReviewed(s))}>Revisei agora</button>
            <button className="btn small danger" onClick={() => db.studies.update(id, stopReviews())}>Parar</button>
          </div>
        ) : <button className="btn small" onClick={() => db.studies.update(id, markReviewed(s))}>Programar revisões</button>}
        <p className="muted small" style={{ marginTop: 6 }}>Intervalos crescentes: 1, 3, 7, 14, 30 e 60 dias.</p>
      </div>
      <Field label="Notas"><textarea className="input" rows={3} value={s.notes} onChange={(e) => db.studies.update(id, { notes: e.target.value })} placeholder="Resumo, capítulos, links…" /></Field>
      <div className="dlg-actions">
        <button className="btn" onClick={() => { void db.studies.update(id, { archived: true }); onClose() }}>Arquivar</button>
        <button className="btn danger" onClick={() => setConfirm(true)}>Apagar</button>
      </div>
      <Confirm open={confirm} title={`Apagar ${s.title}?`} text="As sessões de foco continuam registradas, sem vínculo." confirmLabel="Apagar"
        onConfirm={async () => { await db.focus.where('studyId').equals(id).modify({ studyId: undefined }); await db.studies.delete(id); onClose() }} onClose={() => setConfirm(false)} />
    </div>
  )
}

// ---- Pomodoro ----

function loadTimer(): PomodoroState {
  try {
    const raw = localStorage.getItem(TIMER_KEY)
    return raw ? (JSON.parse(raw) as PomodoroState) : IDLE
  } catch {
    return IDLE
  }
}

function Pomodoro({ studies }: { studies: Study[] }) {
  const { db } = useDb()
  const [timer, setTimerState] = useState<PomodoroState>(loadTimer)
  const [now, setNow] = useState(() => Date.now())
  const [focusMin, setFocusMin] = useState(() => Number(localStorage.getItem('livo.pomodoro.focus')) || 25)
  const [pauseMin, setPauseMin] = useState(() => Number(localStorage.getItem('livo.pomodoro.pause')) || 5)
  const [studyId, setStudyId] = useState<number | undefined>()
  const [completed, setCompleted] = useState(0)
  const handled = useRef<number | undefined>(undefined)

  const setTimer = (s: PomodoroState) => { setTimerState(s); localStorage.setItem(TIMER_KEY, JSON.stringify(s)) }

  useEffect(() => {
    if (timer.phase === 'idle') return
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [timer.phase])

  useEffect(() => {
    document.title = timer.phase === 'idle' ? 'livo' : `${clock(remainingMs(timer, now))} · ${timer.phase === 'focus' ? 'Foco' : 'Pausa'} · livo`
    return () => { document.title = 'livo' }
  })

  useEffect(() => {
    if (!isFinished(timer, now) || handled.current === timer.endsAt) return
    handled.current = timer.endsAt
    if (timer.phase === 'focus' && timer.startedAt !== undefined) {
      void db.focus.add({ start: new Date(timer.startedAt), minutes: focusMin, studyId: timer.studyId })
      setCompleted((c) => c + 1)
      notify('Bloco de foco concluído', `Hora de uma pausa de ${pauseMin} min.`)
      setTimer(startPhase('pause', pauseMin, Date.now()))
    } else {
      notify('Pausa encerrada', 'Pronto para o próximo bloco?')
      setTimer(IDLE)
    }
  }) // eslint-disable-line react-hooks/exhaustive-deps

  function notify(title: string, body: string) {
    if ('Notification' in window && Notification.permission === 'granted') new Notification(title, { body, icon: './icons/icon-192.png' })
  }

  async function start() {
    localStorage.setItem('livo.pomodoro.focus', String(focusMin))
    localStorage.setItem('livo.pomodoro.pause', String(pauseMin))
    if ('Notification' in window && Notification.permission === 'default') await Notification.requestPermission()
    setNow(Date.now())
    setTimer(startPhase('focus', focusMin, Date.now(), studyId))
  }

  function stop() {
    const spent = minutesSpent(timer, Date.now())
    // A focus block stopped midway still counts the whole minutes already spent.
    if (spent >= 1 && timer.startedAt !== undefined) void db.focus.add({ start: new Date(timer.startedAt), minutes: spent, studyId: timer.studyId })
    setTimer(IDLE)
  }

  const idle = timer.phase === 'idle'
  return (
    <Card title="Foco (Pomodoro)" icon="timer">
      <div className="stack" style={{ alignItems: 'center', textAlign: 'center' }}>
        <div className="badge">{idle ? 'Pronto para focar' : timer.phase === 'focus' ? 'Foco' : 'Pausa'}</div>
        <div className="num" role="timer" aria-live="off" style={{ fontSize: 64, fontWeight: 900, letterSpacing: '-0.02em' }}>{clock(idle ? focusMin * 60_000 : remainingMs(timer, now))}</div>
        {idle ? (
          <>
            <button className="btn primary" onClick={start}>Iniciar foco</button>
            <div className="row wrap" style={{ justifyContent: 'center' }}>
              <Field label="Foco (min)"><input className="input" type="number" min={5} max={90} step={5} value={focusMin} onChange={(e) => setFocusMin(Math.max(5, Math.min(90, Number(e.target.value) || 25)))} style={{ width: 90 }} /></Field>
              <Field label="Pausa (min)"><input className="input" type="number" min={1} max={30} value={pauseMin} onChange={(e) => setPauseMin(Math.max(1, Math.min(30, Number(e.target.value) || 5)))} style={{ width: 90 }} /></Field>
              <Field label="Estudo">
                <select className="input" value={studyId ?? ''} onChange={(e) => setStudyId(e.target.value ? Number(e.target.value) : undefined)}>
                  <option value="">Sem vínculo</option>
                  {studies.map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}
                </select>
              </Field>
            </div>
          </>
        ) : <button className="btn danger" onClick={stop}>Parar</button>}
        <p className="muted small">Blocos concluídos nesta sessão: {completed}. O tempo segue o relógio, mesmo com a aba em segundo plano.</p>
      </div>
    </Card>
  )
}
