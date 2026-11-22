import { useState } from 'react'
import { Card, CheckButton, Confirm, Empty, Field, Icon, Modal, Progress, Seg } from '../components/ui'
import { deleteGoal, deleteHabit, newGoal, newHabit, newTask, tapCheckIn, toggleTask } from '../data/actions'
import { useDb } from '../data/DbContext'
import { useCheckIns, useGoalSteps, useGoals, useHabits, useTasks } from '../data/hooks'
import { PERIOD_LABEL, PRIORITY_LABEL, FREQUENCY_LABEL, bestStreak, countIn, dueLabel, goalProgress, isForToday, isOverdue, period, sortTasks, streak } from '../domain/routine'
import type { Goal, GoalHorizon, Habit, HabitFrequency, Priority, Task } from '../domain/types'
import { fmtDate, fromDateInput, toDateInput } from '../lib/dates'

type Tab = 'hoje' | 'tarefas' | 'habitos' | 'metas'
const TABS: ReadonlyArray<readonly [Tab, string]> = [['hoje', 'Hoje'], ['tarefas', 'Tarefas'], ['habitos', 'Hábitos'], ['metas', 'Metas']]
const HORIZONS: ReadonlyArray<readonly [GoalHorizon, string]> = [['curto', 'Curto prazo'], ['medio', 'Médio prazo'], ['longo', 'Longo prazo']]

export function Routine({ initialTab = 'hoje' }: { initialTab?: Tab }) {
  const { db } = useDb()
  const [tab, setTab] = useState<Tab>(initialTab)
  const tasks = useTasks()
  const habits = useHabits().filter((h) => !h.archived)
  const checkIns = useCheckIns()
  const goals = useGoals()
  const steps = useGoalSteps()
  const [taskForm, setTaskForm] = useState<Task | 'new' | undefined>()
  const [habitForm, setHabitForm] = useState<Habit | 'new' | undefined>()
  const [goalForm, setGoalForm] = useState<Goal | 'new' | undefined>()
  const [goalOpen, setGoalOpen] = useState<Goal | undefined>()
  const [removing, setRemoving] = useState<{ text: string; run: () => void } | undefined>()

  const taskRow = (t: Task) => (
    <li key={t.id}>
      <CheckButton checked={t.done} label={t.done ? `Marcar ${t.title} como pendente` : `Concluir ${t.title}`} onClick={() => toggleTask(db, t)} />
      <button className="grow btn ghost" style={{ justifyContent: 'flex-start', textAlign: 'left', padding: 0 }} onClick={() => setTaskForm(t)}>
        <span className="grow">
          <div style={{ textDecoration: t.done ? 'line-through' : undefined, opacity: t.done ? 0.6 : 1 }}>{t.title}</div>
          <div className={`small ${isOverdue(t) ? 'expense' : 'muted'}`}>
            {[t.due ? dueLabel(t.due) : '', t.priority === 2 ? 'Prioridade alta' : '', goals.find((g) => g.id === t.goalId)?.title ?? ''].filter(Boolean).join(' · ')}
          </div>
        </span>
      </button>
      <button className="icon-btn" aria-label={`Apagar ${t.title}`} onClick={() => setRemoving({ text: `Apagar a tarefa “${t.title}”?`, run: () => db.tasks.delete(t.id!) })}><Icon name="trash" size={18} /></button>
    </li>
  )

  const habitRow = (h: Habit, detail = false) => {
    const count = countIn(h.id!, checkIns, period(new Date(), h.frequency))
    const done = count >= Math.max(h.target, 1)
    const s = streak(h, checkIns)
    return (
      <li key={h.id}>
        <CheckButton checked={done} label={done ? `${h.name} concluído, desfazer` : `Registrar ${h.name}`} onClick={() => tapCheckIn(db, h)} />
        <button className="grow btn ghost" style={{ justifyContent: 'flex-start', textAlign: 'left', padding: 0 }} onClick={() => detail && setHabitForm(h)}>
          <span className="grow">
            <div>{h.name}</div>
            <div className="muted small">{count}/{h.target} {PERIOD_LABEL[h.frequency]}{s > 0 ? ` · sequência de ${s}` : ''}{detail ? ` · melhor: ${bestStreak(h, checkIns)}` : ''}</div>
          </span>
        </button>
        {detail && <button className="icon-btn" aria-label={`Apagar ${h.name}`} onClick={() => setRemoving({ text: `Apagar o hábito “${h.name}” e todo o histórico de registros?`, run: () => deleteHabit(db, h.id!) })}><Icon name="trash" size={18} /></button>}
      </li>
    )
  }

  const pending = sortTasks(tasks.filter((t) => !t.done))
  const doneTasks = tasks.filter((t) => t.done).sort((a, b) => +(b.doneAt ?? 0) - +(a.doneAt ?? 0)).slice(0, 30)

  return (
    <>
      <div className="page-head">
        <div><h1>Rotina</h1><p className="sub">Tarefas, hábitos e metas.</p></div>
        <div className="row wrap">
          <Seg label="Seção" value={tab} options={TABS} onChange={setTab} />
          <button className="btn primary" onClick={() => (tab === 'habitos' ? setHabitForm('new') : tab === 'metas' ? setGoalForm('new') : setTaskForm('new'))}>
            <Icon name="plus" size={18} /> {tab === 'habitos' ? 'Novo hábito' : tab === 'metas' ? 'Nova meta' : 'Nova tarefa'}
          </button>
        </div>
      </div>

      {tab === 'hoje' && (
        <div className="grid cols-2">
          <Card title="Hábitos" icon="repeat">
            {habits.length === 0 ? <Empty icon="repeat">Crie seu primeiro hábito.</Empty> : <ul className="list">{habits.map((h) => habitRow(h))}</ul>}
          </Card>
          <Card title="Tarefas para hoje" icon="tasks">
            {(() => { const due = sortTasks(tasks.filter((t) => isForToday(t))); return due.length === 0 ? <p className="muted">Nada com prazo para hoje.</p> : <ul className="list">{due.map(taskRow)}</ul> })()}
          </Card>
        </div>
      )}

      {tab === 'tarefas' && (
        <div className="stack">
          <Card title="Pendentes">{pending.length === 0 ? <p className="muted">Nenhuma tarefa pendente.</p> : <ul className="list">{pending.map(taskRow)}</ul>}</Card>
          {doneTasks.length > 0 && <Card title="Concluídas"><ul className="list">{doneTasks.map(taskRow)}</ul></Card>}
        </div>
      )}

      {tab === 'habitos' && <Card>{habits.length === 0 ? <Empty icon="repeat">Nenhum hábito ativo.</Empty> : <ul className="list">{habits.map((h) => habitRow(h, true))}</ul>}</Card>}

      {tab === 'metas' && (
        goals.length === 0 ? <Card><Empty icon="target">Nenhuma meta ainda.</Empty></Card> : (
          <div className="stack">
            {HORIZONS.map(([horizon, label]) => {
              const list = goals.filter((g) => g.horizon === horizon).sort((a, b) => Number(a.completed) - Number(b.completed) || b.priority - a.priority)
              return list.length === 0 ? null : (
                <Card key={horizon} title={label} icon="target">
                  <ul className="list">
                    {list.map((g) => {
                      const p = goalProgress(g, steps, tasks)
                      return (
                        <li key={g.id}>
                          <button className="grow btn ghost" style={{ justifyContent: 'flex-start', textAlign: 'left', padding: 0 }} onClick={() => setGoalOpen(g)}>
                            <span className="grow stack" style={{ gap: 6 }}>
                              <span className="row between"><b style={{ textDecoration: g.completed ? 'line-through' : undefined }}>{g.title}</b><span className="muted small num">{Math.round(p * 100)}%</span></span>
                              <Progress value={p} />
                              {g.deadline && <span className="muted small">Prazo: {fmtDate(g.deadline)}</span>}
                            </span>
                          </button>
                        </li>
                      )
                    })}
                  </ul>
                </Card>
              )
            })}
          </div>
        )
      )}

      <TaskForm open={taskForm !== undefined} editing={taskForm === 'new' ? undefined : taskForm} onClose={() => setTaskForm(undefined)} />
      <HabitForm open={habitForm !== undefined} editing={habitForm === 'new' ? undefined : habitForm} onClose={() => setHabitForm(undefined)} />
      <GoalForm open={goalForm !== undefined} editing={goalForm === 'new' ? undefined : goalForm} onClose={() => setGoalForm(undefined)} />
      <GoalDetail goal={goalOpen} onClose={() => setGoalOpen(undefined)} onEdit={(g) => { setGoalOpen(undefined); setGoalForm(g) }} onDelete={(g) => { setGoalOpen(undefined); setRemoving({ text: `Apagar a meta “${g.title}”? As etapas serão apagadas; as tarefas ligadas continuam, sem meta.`, run: () => deleteGoal(db, g.id!) }) }} />
      <Confirm open={!!removing} title="Apagar?" text={removing?.text ?? ''} confirmLabel="Apagar" onConfirm={() => removing?.run()} onClose={() => setRemoving(undefined)} />
    </>
  )
}

// ---------- forms ----------

export function TaskForm({ open, editing, onClose, presetGoalId }: { open: boolean; editing?: Task; onClose: () => void; presetGoalId?: number }) {
  return <Modal open={open} title={editing ? 'Editar tarefa' : 'Nova tarefa'} onClose={onClose}><TaskBody editing={editing} onClose={onClose} presetGoalId={presetGoalId} /></Modal>
}

function TaskBody({ editing, onClose, presetGoalId }: { editing?: Task; onClose: () => void; presetGoalId?: number }) {
  const { db } = useDb()
  const goals = useGoals().filter((g) => !g.completed)
  const [title, setTitle] = useState(editing?.title ?? '')
  const [notes, setNotes] = useState(editing?.notes ?? '')
  const [due, setDue] = useState(editing?.due ? toDateInput(editing.due) : '')
  const [priority, setPriority] = useState<Priority>(editing?.priority ?? 1)
  const [goalId, setGoalId] = useState<number | undefined>(editing?.goalId ?? presetGoalId)

  async function save(e: React.FormEvent) {
    e.preventDefault()
    const d = due ? fromDateInput(due) : null
    const dueDate = d ? new Date(d.getFullYear(), d.getMonth(), d.getDate()) : undefined
    if (editing) await db.tasks.update(editing.id!, { title: title.trim(), notes, due: dueDate, priority, goalId })
    else await db.tasks.add(newTask(title.trim(), { notes, due: dueDate, priority, goalId }))
    onClose()
  }
  return (
    <form className="form" onSubmit={save}>
      <Field label="O que precisa ser feito?"><input className="input" autoFocus value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
      <div className="two">
        <Field label="Prazo"><input className="input" type="date" value={due} onChange={(e) => setDue(e.target.value)} /></Field>
        <Field label="Prioridade">
          <select className="input" value={priority} onChange={(e) => setPriority(Number(e.target.value) as Priority)}>
            {([0, 1, 2] as const).map((p) => <option key={p} value={p}>{PRIORITY_LABEL[p]}</option>)}
          </select>
        </Field>
      </div>
      <Field label="Meta">
        <select className="input" value={goalId ?? ''} onChange={(e) => setGoalId(e.target.value ? Number(e.target.value) : undefined)}>
          <option value="">Nenhuma</option>
          {goals.map((g) => <option key={g.id} value={g.id}>{g.title}</option>)}
        </select>
      </Field>
      <Field label="Notas"><textarea className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
      <div className="dlg-actions">
        <button type="button" className="btn" onClick={onClose}>Cancelar</button>
        <button type="submit" className="btn primary" disabled={!title.trim()}>Salvar</button>
      </div>
    </form>
  )
}

export function HabitForm({ open, editing, onClose }: { open: boolean; editing?: Habit; onClose: () => void }) {
  return <Modal open={open} title={editing ? 'Editar hábito' : 'Novo hábito'} onClose={onClose}><HabitBody editing={editing} onClose={onClose} /></Modal>
}

function HabitBody({ editing, onClose }: { editing?: Habit; onClose: () => void }) {
  const { db } = useDb()
  const [name, setName] = useState(editing?.name ?? '')
  const [frequency, setFrequency] = useState<HabitFrequency>(editing?.frequency ?? 'diaria')
  const [target, setTarget] = useState(editing?.target ?? 1)
  async function save(e: React.FormEvent) {
    e.preventDefault()
    if (editing) await db.habits.update(editing.id!, { name: name.trim(), frequency, target })
    else await db.habits.add(newHabit(name.trim(), { frequency, target }))
    onClose()
  }
  return (
    <form className="form" onSubmit={save}>
      <Field label="Nome (ex.: Beber água, Ler 20 min)"><input className="input" autoFocus value={name} onChange={(e) => setName(e.target.value)} /></Field>
      <div className="two">
        <Field label="Frequência">
          <select className="input" value={frequency} onChange={(e) => setFrequency(e.target.value as HabitFrequency)}>
            {(['diaria', 'semanal', 'mensal'] as const).map((f) => <option key={f} value={f}>{FREQUENCY_LABEL[f]}</option>)}
          </select>
        </Field>
        <Field label="Vezes por período"><input className="input" type="number" min={1} max={30} value={target} onChange={(e) => setTarget(Math.max(1, Number(e.target.value) || 1))} /></Field>
      </div>
      <div className="dlg-actions">
        <button type="button" className="btn" onClick={onClose}>Cancelar</button>
        <button type="submit" className="btn primary" disabled={!name.trim()}>Salvar</button>
      </div>
    </form>
  )
}

function GoalForm({ open, editing, onClose }: { open: boolean; editing?: Goal; onClose: () => void }) {
  return <Modal open={open} title={editing ? 'Editar meta' : 'Nova meta'} onClose={onClose}><GoalBody editing={editing} onClose={onClose} /></Modal>
}

function GoalBody({ editing, onClose }: { editing?: Goal; onClose: () => void }) {
  const { db } = useDb()
  const [title, setTitle] = useState(editing?.title ?? '')
  const [notes, setNotes] = useState(editing?.notes ?? '')
  const [horizon, setHorizon] = useState<GoalHorizon>(editing?.horizon ?? 'curto')
  const [priority, setPriority] = useState<Priority>(editing?.priority ?? 1)
  const [deadline, setDeadline] = useState(editing?.deadline ? toDateInput(editing.deadline) : '')
  const [numeric, setNumeric] = useState(editing?.targetValue !== undefined)
  const [target, setTarget] = useState(editing?.targetValue?.toString() ?? '')
  const [current, setCurrent] = useState(editing?.currentValue?.toString() ?? '')
  const [unit, setUnit] = useState(editing?.unit ?? '')
  const num = (s: string) => { const v = Number(s.replace(/\./g, '').replace(',', '.')); return Number.isFinite(v) ? v : undefined }

  async function save(e: React.FormEvent) {
    e.preventDefault()
    const patch = {
      title: title.trim(), notes, horizon, priority, deadline: deadline ? fromDateInput(deadline) ?? undefined : undefined,
      targetValue: numeric ? num(target) : undefined, currentValue: numeric ? (num(current) ?? 0) : undefined, unit: numeric ? unit : '',
    }
    if (editing) await db.goals.update(editing.id!, patch)
    else await db.goals.add(newGoal(patch.title, patch))
    onClose()
  }
  return (
    <form className="form" onSubmit={save}>
      <Field label="Objetivo (ex.: Correr 10 km)"><input className="input" autoFocus value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
      <div className="two">
        <Field label="Horizonte"><select className="input" value={horizon} onChange={(e) => setHorizon(e.target.value as GoalHorizon)}>{HORIZONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></Field>
        <Field label="Prioridade"><select className="input" value={priority} onChange={(e) => setPriority(Number(e.target.value) as Priority)}>{([0, 1, 2] as const).map((p) => <option key={p} value={p}>{PRIORITY_LABEL[p]}</option>)}</select></Field>
      </div>
      <Field label="Prazo"><input className="input" type="date" value={deadline} onChange={(e) => setDeadline(e.target.value)} /></Field>
      <label className="row"><input type="checkbox" checked={numeric} onChange={(e) => setNumeric(e.target.checked)} style={{ width: 20, height: 20 }} /> <span>Meta numérica</span></label>
      {numeric ? (
        <div className="two">
          <Field label="Alvo"><input className="input" inputMode="decimal" value={target} onChange={(e) => setTarget(e.target.value)} /></Field>
          <Field label="Atual"><input className="input" inputMode="decimal" value={current} onChange={(e) => setCurrent(e.target.value)} /></Field>
          <Field label="Unidade (km, livros, R$)"><input className="input" value={unit} onChange={(e) => setUnit(e.target.value)} /></Field>
        </div>
      ) : <p className="muted small">Sem meta numérica, o progresso vem das etapas e tarefas concluídas.</p>}
      <Field label="Notas"><textarea className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
      <div className="dlg-actions">
        <button type="button" className="btn" onClick={onClose}>Cancelar</button>
        <button type="submit" className="btn primary" disabled={!title.trim() || (numeric && !((num(target) ?? 0) > 0))}>Salvar</button>
      </div>
    </form>
  )
}

function GoalDetail({ goal, onClose, onEdit, onDelete }: { goal?: Goal; onClose: () => void; onEdit: (g: Goal) => void; onDelete: (g: Goal) => void }) {
  return (
    <Modal open={!!goal} title={goal?.title ?? ''} onClose={onClose}>
      {goal && <DetailBody goalId={goal.id!} onEdit={onEdit} onDelete={onDelete} />}
    </Modal>
  )
}

function DetailBody({ goalId, onEdit, onDelete }: { goalId: number; onEdit: (g: Goal) => void; onDelete: (g: Goal) => void }) {
  const { db } = useDb()
  const goal = useGoals().find((g) => g.id === goalId)
  const steps = useGoalSteps().filter((s) => s.goalId === goalId).sort((a, b) => a.order - b.order)
  const tasks = useTasks()
  const [newStep, setNewStep] = useState('')
  if (!goal) return null
  const progress = goalProgress(goal, steps, tasks)
  const linked = sortTasks(tasks.filter((t) => t.goalId === goalId))
  return (
    <div className="stack">
      <div><div className="num" style={{ fontSize: 30, fontWeight: 900 }}>{Math.round(progress * 100)}%</div><Progress value={progress} /></div>
      {goal.targetValue !== undefined && <p className="muted">{goal.currentValue ?? 0} de {goal.targetValue} {goal.unit}</p>}
      <div>
        <h3 style={{ marginBottom: 6 }}>Etapas</h3>
        <ul className="list">
          {steps.map((s) => (
            <li key={s.id}>
              <CheckButton checked={s.done} label={s.title} onClick={() => db.goalSteps.update(s.id!, { done: !s.done })} />
              <span className="grow" style={{ textDecoration: s.done ? 'line-through' : undefined }}>{s.title}</span>
              <button className="icon-btn" aria-label={`Apagar etapa ${s.title}`} onClick={() => db.goalSteps.delete(s.id!)}><Icon name="trash" size={16} /></button>
            </li>
          ))}
        </ul>
        <form className="row" onSubmit={(e) => { e.preventDefault(); const t = newStep.trim(); if (t) { void db.goalSteps.add({ title: t, done: false, order: (steps.at(-1)?.order ?? -1) + 1, goalId }); setNewStep('') } }}>
          <input className="input" placeholder="Nova etapa" value={newStep} onChange={(e) => setNewStep(e.target.value)} aria-label="Nova etapa" />
          <button className="btn" type="submit">Adicionar</button>
        </form>
      </div>
      {linked.length > 0 && <div><h3 style={{ marginBottom: 6 }}>Tarefas ligadas</h3><ul className="list">{linked.map((t) => <li key={t.id}><CheckButton checked={t.done} label={t.title} onClick={() => toggleTask(db, t)} /><span className="grow">{t.title}</span></li>)}</ul></div>}
      <div className="dlg-actions">
        <button className="btn" onClick={() => db.goals.update(goalId, { completed: !goal.completed })}>{goal.completed ? 'Reabrir meta' : 'Marcar como concluída'}</button>
        <button className="btn" onClick={() => onEdit(goal)}>Editar</button>
        <button className="btn danger" onClick={() => onDelete(goal)}>Apagar</button>
      </div>
    </div>
  )
}
