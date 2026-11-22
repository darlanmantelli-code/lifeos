import { addDays, addMonths, inInterval, isSameDay, startOfDay, weekInterval, type Interval } from '../lib/dates'
import type { CheckIn, Goal, GoalStep, Habit, HabitFrequency, Priority, Task } from './types'

export function period(date: Date, frequency: HabitFrequency): Interval {
  if (frequency === 'diaria') return [startOfDay(date), addDays(startOfDay(date), 1)]
  if (frequency === 'semanal') return weekInterval(date)
  const start = new Date(date.getFullYear(), date.getMonth(), 1)
  return [start, addMonths(start, 1)]
}

const periodStartKey = (d: Date, f: HabitFrequency): number => period(d, f)[0].getTime()

export function countIn(habitId: number, checkIns: CheckIn[], interval: Interval): number {
  return checkIns.filter((c) => c.habitId === habitId && inInterval(c.date, interval)).length
}

export function isComplete(habit: Habit, checkIns: CheckIn[], at: Date = new Date()): boolean {
  return countIn(habit.id!, checkIns, period(at, habit.frequency)) >= Math.max(habit.target, 1)
}

function countsByPeriod(habit: Habit, checkIns: CheckIn[]): Map<number, number> {
  const counts = new Map<number, number>()
  for (const c of checkIns) {
    if (c.habitId !== habit.id) continue
    const key = periodStartKey(c.date, habit.frequency)
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }
  return counts
}

/**
 * Consecutive complete periods up to `now`. The current period counts once complete;
 * while still in progress it does not break the streak.
 */
export function streak(habit: Habit, checkIns: CheckIn[], now: Date = new Date()): number {
  const counts = countsByPeriod(habit, checkIns)
  const target = Math.max(habit.target, 1)
  let [start] = period(now, habit.frequency)
  let result = (counts.get(start.getTime()) ?? 0) >= target ? 1 : 0
  for (;;) {
    ;[start] = period(new Date(start.getTime() - 1), habit.frequency)
    if ((counts.get(start.getTime()) ?? 0) < target) break
    result += 1
  }
  return result
}

export function bestStreak(habit: Habit, checkIns: CheckIn[], now: Date = new Date()): number {
  const mine = checkIns.filter((c) => c.habitId === habit.id)
  if (mine.length === 0) return 0
  const counts = countsByPeriod(habit, checkIns)
  const target = Math.max(habit.target, 1)
  const first = new Date(Math.min(...mine.map((c) => c.date.getTime())))
  const [, end] = period(now, habit.frequency)
  let [start, next] = period(first, habit.frequency)
  let best = 0
  let current = 0
  while (start < end) {
    if ((counts.get(start.getTime()) ?? 0) >= target) {
      current += 1
      best = Math.max(best, current)
    } else {
      current = 0
    }
    ;[start, next] = period(next, habit.frequency)
  }
  return best
}

/** 0...1. A numeric target wins; otherwise done steps + done linked tasks over the total. */
export function goalProgress(goal: Goal, steps: GoalStep[], tasks: Task[]): number {
  if (goal.completed) return 1
  if (goal.targetValue !== undefined && goal.targetValue > 0) {
    return Math.min(Math.max((goal.currentValue ?? 0) / goal.targetValue, 0), 1)
  }
  const items = [...steps.filter((s) => s.goalId === goal.id).map((s) => s.done), ...tasks.filter((t) => t.goalId === goal.id).map((t) => t.done)]
  return items.length === 0 ? 0 : items.filter(Boolean).length / items.length
}

/** Dated before undated; earlier day first; then higher priority; then oldest. */
export function sortTasks(tasks: Task[]): Task[] {
  return [...tasks].sort((a, b) => {
    if (a.due && !b.due) return -1
    if (!a.due && b.due) return 1
    if (a.due && b.due && !isSameDay(a.due, b.due)) return +a.due - +b.due
    if (a.priority !== b.priority) return b.priority - a.priority
    return +a.createdAt - +b.createdAt
  })
}

export function isOverdue(t: Task, now: Date = new Date()): boolean {
  return !t.done && t.due !== undefined && t.due < startOfDay(now)
}

/** Pending tasks due today or overdue. */
export function isForToday(t: Task, now: Date = new Date()): boolean {
  return !t.done && t.due !== undefined && (isOverdue(t, now) || isSameDay(t.due, now))
}

export function dueLabel(due: Date, now: Date = new Date()): string {
  if (isSameDay(due, now)) return 'Hoje'
  if (isSameDay(due, addDays(now, 1))) return 'Amanhã'
  const text = due.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }).replace('.', '')
  return due < startOfDay(now) ? `Atrasada · ${text}` : text
}

export const PRIORITY_LABEL: Record<Priority, string> = { 0: 'Baixa', 1: 'Média', 2: 'Alta' }
export const FREQUENCY_LABEL: Record<HabitFrequency, string> = { diaria: 'Diário', semanal: 'Semanal', mensal: 'Mensal' }
export const PERIOD_LABEL: Record<HabitFrequency, string> = { diaria: 'hoje', semanal: 'nesta semana', mensal: 'neste mês' }
