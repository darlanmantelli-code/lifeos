/** Calendar helpers. Everything uses the local calendar; weeks start on Sunday (as in pt-BR on iOS). */

export const startOfDay = (d: Date): Date => new Date(d.getFullYear(), d.getMonth(), d.getDate())

export const addDays = (d: Date, n: number): Date =>
  new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds())

/** Adds months, clamping to the end of the month (Jan 31 + 1 month = Feb 28). */
export function addMonths(d: Date, n: number): Date {
  const target = new Date(d.getFullYear(), d.getMonth() + n, 1, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds())
  const lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate()
  target.setDate(Math.min(d.getDate(), lastDay))
  return target
}

export const isSameDay = (a: Date, b: Date): boolean =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()

export const monthStart = (d: Date): Date => new Date(d.getFullYear(), d.getMonth(), 1)

/** "2026-11" */
export const monthKey = (d: Date): string => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`

export type Interval = readonly [start: Date, end: Date]

export const monthInterval = (d: Date): Interval => [monthStart(d), addMonths(monthStart(d), 1)]

export function weekInterval(d: Date): Interval {
  const start = addDays(startOfDay(d), -startOfDay(d).getDay())
  return [start, addDays(start, 7)]
}

export const dayInterval = (d: Date): Interval => [startOfDay(d), addDays(startOfDay(d), 1)]

export type PeriodKind = 'dia' | 'semana' | 'mes'

export function periodInterval(kind: PeriodKind, d: Date): Interval {
  return kind === 'dia' ? dayInterval(d) : kind === 'semana' ? weekInterval(d) : monthInterval(d)
}

export const inInterval = (d: Date, [start, end]: Interval): boolean => d >= start && d < end

/** ISO 8601 in UTC without milliseconds: the format the iOS backup reads. */
export const toISO = (d: Date): string => d.toISOString().replace(/\.\d{3}Z$/, 'Z')

const dayMonth = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short' })
const longDate = new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })
const monthYear = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric' })
const dateOnly = new Intl.DateTimeFormat('pt-BR')
const timeOnly = new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' })

export const firstUpper = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1)
export const fmtDayMonth = (d: Date): string => dayMonth.format(d).replace('.', '')
export const fmtLongDate = (d: Date): string => firstUpper(longDate.format(d))
export const fmtMonthYear = (d: Date): string => firstUpper(monthYear.format(d))
export const fmtDate = (d: Date): string => dateOnly.format(d)
export const fmtTime = (d: Date): string => timeOnly.format(d)

/** Value for <input type="date"> in local time. */
export const toDateInput = (d: Date): string =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

/** Reads an <input type="date"> value as local noon (so time-zone shifts never change the day). */
export function fromDateInput(value: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12) : null
}
