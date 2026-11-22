import { addMonths, inInterval, monthInterval, monthKey, startOfDay, addDays } from '../lib/dates'
import type { Account, Budget, Category, Transaction, TxnKind, TxnSource } from './types'

/** Recurring entries are created this many months ahead. */
export const RECURRING_HORIZON = 12

/** Splits a total into installments; the remainder cents go to the first one so the sum is exact. */
export function splitInstallments(totalCents: number, count: number): number[] {
  if (count <= 0) return []
  const base = Math.trunc(totalCents / count)
  const rest = totalCents - base * count
  return Array.from({ length: count }, (_, i) => (i === 0 ? base + rest : base))
}

export const monthlyDates = (start: Date, count: number): Date[] =>
  Array.from({ length: count }, (_, i) => addMonths(start, i))

export type Repetition = { type: 'unica' } | { type: 'parcelada'; count: number } | { type: 'recorrente' }

export interface TransactionDraft {
  kind: TxnKind
  amountCents: number
  title: string
  note?: string
  date: Date
  accountId: number
  toAccountId?: number
  categoryId?: number
  isFixed?: boolean
  repetition?: Repetition
  source?: TxnSource
  externalID?: string
}

/** Turns a draft into the rows to store: one, N installments, or a year of monthly entries. */
export function expandDraft(d: TransactionDraft, now: Date = new Date()): Transaction[] {
  const rep = d.repetition ?? { type: 'unica' }
  const amounts =
    rep.type === 'parcelada'
      ? splitInstallments(d.amountCents, Math.max(rep.count, 1))
      : rep.type === 'recorrente'
        ? Array.from({ length: RECURRING_HORIZON }, () => d.amountCents)
        : [d.amountCents]
  const dates = monthlyDates(d.date, amounts.length)
  const groupID = amounts.length > 1 ? crypto.randomUUID() : undefined
  const transfer = d.kind === 'transferencia'
  return amounts.map((amountCents, i) => ({
    date: dates[i],
    amountCents,
    kind: d.kind,
    title: d.title,
    note: d.note ?? '',
    isFixed: d.isFixed ?? false,
    source: d.source ?? 'manual',
    groupID,
    installmentIndex: rep.type === 'parcelada' ? i + 1 : undefined,
    installmentCount: rep.type === 'parcelada' ? amounts.length : undefined,
    isRecurring: rep.type === 'recorrente',
    createdAt: now,
    accountId: d.accountId,
    toAccountId: transfer ? d.toAccountId : undefined,
    categoryId: transfer ? undefined : d.categoryId,
    externalID: i === 0 ? d.externalID : undefined,
  }))
}

/** Signed effect of one transaction on one account's balance. */
export function effect(t: Transaction, accountId: number): number {
  switch (t.kind) {
    case 'receita':
      return t.accountId === accountId ? t.amountCents : 0
    case 'despesa':
      return t.accountId === accountId ? -t.amountCents : 0
    case 'transferencia':
      return (t.toAccountId === accountId ? t.amountCents : 0) - (t.accountId === accountId ? t.amountCents : 0)
  }
}

/** Balance on `at`: future-dated entries are planned and not counted. Credit cards go negative as purchases add up. */
export function balance(account: Account, txns: Transaction[], at: Date = new Date()): number {
  const id = account.id!
  return txns
    .filter((t) => t.date <= at && (t.accountId === id || t.toAccountId === id))
    .reduce((sum, t) => sum + effect(t, id), account.initialBalanceCents)
}

/** Invoice ("yyyy-MM" of its closing month) a card purchase falls into: on/after the closing day goes to the next one. */
export function invoiceKey(date: Date, closingDay: number): string {
  return monthKey(date.getDate() >= closingDay ? addMonths(date, 1) : date)
}

/** Purchases minus refunds in one invoice. Payments (transfers into the card) are not counted. */
export function invoiceTotal(card: Account, txns: Transaction[], key: string): number {
  const closing = card.closingDay ?? 1
  return txns
    .filter((t) => t.accountId === card.id && invoiceKey(t.date, closing) === key)
    .reduce((total, t) => (t.kind === 'despesa' ? total + t.amountCents : t.kind === 'receita' ? total - t.amountCents : total), 0)
}

export interface Summary {
  income: number
  expense: number
  net: number
}

/** Transfers move money between own accounts: neither income nor expense. */
export function summarize(txns: Transaction[]): Summary {
  let income = 0
  let expense = 0
  for (const t of txns) {
    if (t.kind === 'receita') income += t.amountCents
    else if (t.kind === 'despesa') expense += t.amountCents
  }
  return { income, expense, net: income - expense }
}

export interface CategoryTotal {
  name: string
  cents: number
}

export function expensesByRootCategory(txns: Transaction[], categories: Category[]): CategoryTotal[] {
  const byId = new Map(categories.map((c) => [c.id!, c]))
  const totals = new Map<string, number>()
  for (const t of txns) {
    if (t.kind !== 'despesa') continue
    const cat = t.categoryId !== undefined ? byId.get(t.categoryId) : undefined
    const root = cat?.parentId !== undefined ? (byId.get(cat.parentId) ?? cat) : cat
    const name = root?.name ?? 'Sem categoria'
    totals.set(name, (totals.get(name) ?? 0) + t.amountCents)
  }
  return [...totals].map(([name, cents]) => ({ name, cents })).sort((a, b) => b.cents - a.cents)
}

/** Expenses in a category including its subcategories. */
export function spentIn(category: Category, txns: Transaction[], categories: Category[]): number {
  const ids = new Set([category.id!, ...categories.filter((c) => c.parentId === category.id).map((c) => c.id!)])
  return txns
    .filter((t) => t.kind === 'despesa' && t.categoryId !== undefined && ids.has(t.categoryId))
    .reduce((sum, t) => sum + t.amountCents, 0)
}

/** The limit that applies in month `key`: the latest budget starting on or before it; 0 means none. */
export function effectiveLimit(budgets: Budget[], key: string): number | undefined {
  const latest = budgets.filter((b) => b.month <= key).sort((a, b) => (a.month < b.month ? -1 : 1)).at(-1)
  return latest && latest.limitCents > 0 ? latest.limitCents : undefined
}

export interface BudgetLine {
  category: Category
  spent: number
  limit: number
}

/** Budgets for the month of `date`, using only what was spent up to `upTo`. */
export function budgetLines(
  date: Date,
  categories: Category[],
  budgets: Budget[],
  txns: Transaction[],
  upTo?: Date,
): BudgetLine[] {
  const interval = monthInterval(date)
  const key = monthKey(date)
  const inMonth = txns.filter((t) => inInterval(t.date, interval) && (!upTo || t.date <= upTo))
  return categories
    .filter((c) => c.parentId === undefined && c.kind === 'despesa')
    .flatMap((c) => {
      const limit = effectiveLimit(budgets.filter((b) => b.categoryId === c.id), key)
      return limit === undefined ? [] : [{ category: c, spent: spentIn(c, inMonth, categories), limit }]
    })
}

// ---- Analysis ----

export interface BalancePoint {
  day: Date
  cents: number
}

/** Consolidated balance today plus planned (future-dated) entries, day by day. Own-account transfers net to zero. */
export function projection(accounts: Account[], txns: Transaction[], days = 90, now: Date = new Date()): BalancePoint[] {
  const active = accounts.filter((a) => !a.archived)
  const ids = new Set(active.map((a) => a.id!))
  let running = active.reduce((sum, a) => sum + balance(a, txns, now), 0)
  const end = addDays(now, days)
  const byDay = new Map<number, number>()
  for (const t of txns) {
    if (!(t.date > now && t.date <= end)) continue
    const from = t.accountId !== undefined && ids.has(t.accountId)
    const to = t.toAccountId !== undefined && ids.has(t.toAccountId)
    const delta =
      t.kind === 'receita' ? (from ? t.amountCents : 0)
      : t.kind === 'despesa' ? (from ? -t.amountCents : 0)
      : (to ? t.amountCents : 0) - (from ? t.amountCents : 0)
    const key = startOfDay(t.date).getTime()
    byDay.set(key, (byDay.get(key) ?? 0) + delta)
  }
  const today = startOfDay(now)
  const points: BalancePoint[] = [{ day: today, cents: running }]
  for (let i = 1; i <= days; i++) {
    const day = addDays(today, i)
    running += byDay.get(day.getTime()) ?? 0
    points.push({ day, cents: running })
  }
  return points
}

export interface MonthTotals {
  month: Date
  income: number
  expense: number
}

/** Income and expense per month for the last `months` months (current included), oldest first. */
export function monthlyTotals(txns: Transaction[], months = 6, now: Date = new Date()): MonthTotals[] {
  const thisMonth = new Date(now.getFullYear(), now.getMonth(), 1)
  return Array.from({ length: months }, (_, k) => {
    const start = addMonths(thisMonth, -(months - 1 - k))
    const end = addMonths(start, 1)
    const s = summarize(txns.filter((t) => t.date >= start && t.date < end && t.date <= now))
    return { month: start, income: s.income, expense: s.expense }
  })
}

export interface UnusualExpense {
  title: string
  category: string
  cents: number
  typicalCents: number
}

/**
 * Expenses from the last 7 days far above what the user usually spends in that category:
 * more than 2.5x the median of the previous 90 days, with at least 3 past entries and above R$ 50.
 */
export function unusualExpenses(txns: Transaction[], categories: Category[], now: Date = new Date()): UnusualExpense[] {
  const weekAgo = addDays(now, -7)
  const historyStart = addDays(now, -97)
  const names = new Map(categories.map((c) => [c.id!, c.name]))
  const expenses = txns.filter((t) => t.kind === 'despesa' && t.date <= now)
  return expenses
    .filter((t) => t.date >= weekAgo && t.amountCents > 5_000 && t.categoryId !== undefined)
    .flatMap((t) => {
      const past = expenses
        .filter((p) => p.categoryId === t.categoryId && p.date >= historyStart && p.date < weekAgo)
        .map((p) => p.amountCents)
        .sort((a, b) => a - b)
      if (past.length < 3) return []
      const median = past[Math.floor(past.length / 2)]
      if (median <= 0 || t.amountCents * 10 <= median * 25) return []
      return [{ title: t.title, category: names.get(t.categoryId!) ?? '', cents: t.amountCents, typicalCents: median }]
    })
}

// ---- Alerts and upcoming ----

export interface DashAlert {
  id: string
  text: string
  tone: 'warning' | 'critical'
}

/** Next calendar date with day-of-month `day` on or after today. */
export function nextDue(day: number, now: Date): Date {
  const today = startOfDay(now)
  const candidate = new Date(today.getFullYear(), today.getMonth(), day)
  return candidate >= today ? candidate : addMonths(candidate, 1)
}

export function upcomingPayments(txns: Transaction[], until: Date, now: Date = new Date()): Transaction[] {
  return txns.filter((t) => t.kind === 'despesa' && t.date > now && t.date < until).sort((a, b) => +a.date - +b.date)
}

export const defaultCategories: ReadonlyArray<Omit<Category, 'id'>> = [
  ...(
    [
      ['Alimentação', 'utensils'], ['Moradia', 'home'], ['Transporte', 'car'], ['Saúde', 'heart-pulse'],
      ['Educação', 'book'], ['Lazer', 'gamepad'], ['Compras', 'bag'], ['Assinaturas', 'repeat'],
      ['Impostos e taxas', 'file'], ['Outros', 'dots'],
    ] as const
  ).map(([name, icon]) => ({ name, icon, kind: 'despesa' as const })),
  ...(
    [['Salário', 'briefcase'], ['Rendimentos', 'trend'], ['Outras receitas', 'plus']] as const
  ).map(([name, icon]) => ({ name, icon, kind: 'receita' as const })),
]
