import { addDays, isSameDay, startOfDay } from '../lib/dates'
import type { HealthEntry, HealthKind } from './types'

export type Aggregation = 'sum' | 'average' | 'latest'

export interface HealthMeta {
  label: string
  unit: string
  aggregation: Aggregation
  decimals: number
  /** Summed metrics can have a daily target. */
  hasSecond?: boolean
}

export const HEALTH: Record<HealthKind, HealthMeta> = {
  passos: { label: 'Passos', unit: 'passos', aggregation: 'sum', decimals: 0 },
  agua: { label: 'Água', unit: 'ml', aggregation: 'sum', decimals: 0 },
  sono: { label: 'Sono', unit: 'h', aggregation: 'sum', decimals: 1 },
  exercicio: { label: 'Exercício', unit: 'min', aggregation: 'sum', decimals: 0 },
  peso: { label: 'Peso', unit: 'kg', aggregation: 'latest', decimals: 1 },
  frequencia: { label: 'Frequência cardíaca', unit: 'bpm', aggregation: 'average', decimals: 0 },
  pressao: { label: 'Pressão arterial', unit: 'mmHg', aggregation: 'latest', decimals: 0, hasSecond: true },
  cintura: { label: 'Cintura', unit: 'cm', aggregation: 'latest', decimals: 1 },
}

export const HEALTH_KINDS = Object.keys(HEALTH) as HealthKind[]

export const supportsTarget = (k: HealthKind): boolean => HEALTH[k].aggregation === 'sum'

export function aggregate(entries: HealthEntry[], kind: HealthKind): number | undefined {
  if (entries.length === 0) return undefined
  switch (HEALTH[kind].aggregation) {
    case 'sum':
      return entries.reduce((s, e) => s + e.value, 0)
    case 'average':
      return entries.reduce((s, e) => s + e.value, 0) / entries.length
    case 'latest':
      return entries.reduce((a, b) => (b.date > a.date ? b : a)).value
  }
}

export interface DayValue {
  day: Date
  value: number
  value2?: number
}

/** One value per day that has data, oldest first. `entries` must already be of `kind`. */
export function daily(entries: HealthEntry[], kind: HealthKind, days: number, now: Date = new Date()): DayValue[] {
  const start = addDays(startOfDay(now), -(days - 1))
  const end = addDays(startOfDay(now), 1)
  const byDay = new Map<number, HealthEntry[]>()
  for (const e of entries) {
    if (e.date < start || e.date >= end) continue
    const key = startOfDay(e.date).getTime()
    byDay.set(key, [...(byDay.get(key) ?? []), e])
  }
  return [...byDay]
    .flatMap(([key, items]) => {
      const value = aggregate(items, kind)
      if (value === undefined) return []
      const latest = items.reduce((a, b) => (b.date > a.date ? b : a))
      return [{ day: new Date(key), value, value2: latest.value2 }]
    })
    .sort((a, b) => +a.day - +b.day)
}

/** Summed metrics: today's total. Others: the most recent entry. */
export function current(entries: HealthEntry[], kind: HealthKind, now: Date = new Date()) {
  if (HEALTH[kind].aggregation === 'sum') {
    const today = entries.filter((e) => isSameDay(e.date, now))
    const value = aggregate(today, kind)
    return value === undefined ? undefined : { value, value2: undefined, date: now }
  }
  if (entries.length === 0) return undefined
  const latest = entries.reduce((a, b) => (b.date > a.date ? b : a))
  return { value: latest.value, value2: latest.value2, date: latest.date }
}

/** Mean of the daily values over the last `days` days (today included). */
export function average(entries: HealthEntry[], kind: HealthKind, days = 7, now: Date = new Date()): number | undefined {
  const values = daily(entries, kind, days, now).map((d) => d.value)
  return values.length === 0 ? undefined : values.reduce((a, b) => a + b, 0) / values.length
}

/** Last 7 days' average minus the 7 days before. Undefined when either week has no data. */
export function weeklyChange(entries: HealthEntry[], kind: HealthKind, now: Date = new Date()): number | undefined {
  const recent = average(entries, kind, 7, now)
  const previous = average(entries, kind, 7, addDays(now, -7))
  return recent === undefined || previous === undefined ? undefined : recent - previous
}

export function formatValue(v: number, kind: HealthKind, v2?: number): string {
  const f = (n: number) => n.toLocaleString('pt-BR', { maximumFractionDigits: HEALTH[kind].decimals })
  return HEALTH[kind].hasSecond && v2 !== undefined ? `${f(v)}/${f(v2)}` : f(v)
}
