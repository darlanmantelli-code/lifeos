import { describe, expect, it } from 'vitest'
import { formatMoney, parseMoney, parseStatementAmount } from '../lib/money'
import { addMonths, toISO } from '../lib/dates'
import * as fin from './finance'
import * as routine from './routine'
import * as health from './health'
import * as shop from './shopping'
import { parseStatement, suggestCategory } from './statements'
import type { Account, Category, CheckIn, Habit, ShoppingItem, Task, Transaction } from './types'

const noon = (m: number, d: number, y = 2026) => new Date(y, m - 1, d, 12)
const txn = (p: Partial<Transaction>): Transaction => ({
  date: noon(1, 1), amountCents: 0, kind: 'despesa', title: '', note: '', isFixed: false, source: 'manual',
  isRecurring: false, createdAt: noon(1, 1), ...p,
})
const account = (p: Partial<Account>): Account => ({
  id: 1, name: 'Conta', kind: 'corrente', initialBalanceCents: 0, archived: false, createdAt: noon(1, 1), ...p,
})
const plain = (s: string) => s.replace(/ /g, ' ')

describe('money', () => {
  it('formats BRL', () => expect(plain(formatMoney(123456))).toBe('R$ 1.234,56'))
  it('parses Brazilian input', () => {
    expect(parseMoney('75')).toBe(7500)
    expect(parseMoney('75,5')).toBe(7550)
    expect(parseMoney('1.234,56')).toBe(123456)
    expect(parseMoney('R$ 1.234,56')).toBe(123456)
    expect(parseMoney('-10,00')).toBe(-1000)
    expect(parseMoney(',99')).toBe(99)
    expect(parseMoney('')).toBeNull()
    expect(parseMoney('abc')).toBeNull()
    expect(parseMoney('1,2,3')).toBeNull()
  })
  it('round-trips', () => {
    for (const c of [0, 1, 99, 100, 7500, 123456, 99_999_999]) expect(parseMoney(plain(formatMoney(c)))).toBe(c)
  })
  it('parses statement amounts with either decimal mark', () => {
    expect(parseStatementAmount('1.234,56')).toBe(123456)
    expect(parseStatementAmount('-50,00')).toBe(-5000)
    expect(parseStatementAmount('R$ 12,90')).toBe(1290)
    expect(parseStatementAmount('12.5')).toBe(1250)
    expect(parseStatementAmount('-1234.56')).toBe(-123456)
    expect(parseStatementAmount('1,234.56')).toBe(123456)
    expect(parseStatementAmount('1.234')).toBe(123400)
    expect(parseStatementAmount('(30,00)')).toBe(-3000)
    expect(parseStatementAmount('abc')).toBeNull()
  })
})

describe('finance', () => {
  it('splits installments keeping the total', () => {
    expect(fin.splitInstallments(1000, 3)).toEqual([334, 333, 333])
    expect(fin.splitInstallments(99_999, 7).reduce((a, b) => a + b, 0)).toBe(99_999)
    expect(fin.splitInstallments(1000, 0)).toEqual([])
  })
  it('clamps month-end dates', () => {
    expect(fin.monthlyDates(noon(1, 31), 3).map((d) => d.getDate())).toEqual([31, 28, 31])
    expect(addMonths(noon(1, 31), 1).getMonth()).toBe(1)
  })
  it('picks the invoice by closing day', () => {
    expect(fin.invoiceKey(noon(3, 4), 5)).toBe('2026-03')
    expect(fin.invoiceKey(noon(3, 5), 5)).toBe('2026-04')
    expect(fin.invoiceKey(noon(12, 20), 5)).toBe('2027-01')
  })
  it('computes balances, installments and transfers', () => {
    const conta = account({ id: 1, initialBalanceCents: 100_000 })
    const cartao = account({ id: 2, kind: 'cartao', closingDay: 5 })
    const yesterday = new Date(Date.now() - 86_400_000)
    const rows = [
      ...fin.expandDraft({ kind: 'receita', amountCents: 50_000, title: 'Salário', date: yesterday, accountId: 1 }),
      ...fin.expandDraft({ kind: 'despesa', amountCents: 30_000, title: 'TV', date: yesterday, accountId: 2, repetition: { type: 'parcelada', count: 3 } }),
      ...fin.expandDraft({ kind: 'transferencia', amountCents: 10_000, title: 'Fatura', date: yesterday, accountId: 1, toAccountId: 2 }),
    ]
    const parcelas = rows.filter((t) => t.installmentCount)
    expect(parcelas.map((t) => t.installmentIndex)).toEqual([1, 2, 3])
    expect(new Set(parcelas.map((t) => t.groupID)).size).toBe(1)
    // Only the first installment is in the past; the rest are planned.
    expect(fin.balance(conta, rows)).toBe(100_000 + 50_000 - 10_000)
    expect(fin.balance(cartao, rows)).toBe(-10_000 + 10_000)
    expect(fin.summarize([parcelas[0]]).expense).toBe(10_000)
  })
  it('expands recurring entries over the horizon', () => {
    const rows = fin.expandDraft({ kind: 'despesa', amountCents: 5_000, title: 'Streaming', date: noon(1, 10), accountId: 1, repetition: { type: 'recorrente' } })
    expect(rows).toHaveLength(fin.RECURRING_HORIZON)
    expect(rows.every((t) => t.isRecurring)).toBe(true)
    expect(rows.at(-1)!.date.getMonth()).toBe(11)
  })
  it('carries budgets forward until changed', () => {
    const budgets = [
      { month: '2026-01', limitCents: 80_000, categoryId: 1 },
      { month: '2026-04', limitCents: 0, categoryId: 1 },
    ]
    expect(fin.effectiveLimit(budgets, '2025-12')).toBeUndefined()
    expect(fin.effectiveLimit(budgets, '2026-03')).toBe(80_000)
    expect(fin.effectiveLimit(budgets, '2026-05')).toBeUndefined()
  })
  it('groups expenses by root category', () => {
    const cats: Category[] = [
      { id: 1, name: 'Alimentação', kind: 'despesa', icon: '' },
      { id: 2, name: 'Mercado', kind: 'despesa', icon: '', parentId: 1 },
    ]
    const totals = fin.expensesByRootCategory([txn({ amountCents: 100, categoryId: 2 }), txn({ amountCents: 50, categoryId: 1 }), txn({ amountCents: 7 })], cats)
    expect(totals).toEqual([{ name: 'Alimentação', cents: 150 }, { name: 'Sem categoria', cents: 7 }])
  })
  it('projects the balance with planned entries and ignores own-account transfers', () => {
    const now = noon(6, 1)
    const conta = account({ id: 1, initialBalanceCents: 100_000 })
    const reserva = account({ id: 2, name: 'Reserva' })
    const rows = [
      ...fin.expandDraft({ kind: 'despesa', amountCents: 30_000, title: 'Aluguel', date: noon(6, 10), accountId: 1, repetition: { type: 'recorrente' } }),
      ...fin.expandDraft({ kind: 'transferencia', amountCents: 20_000, title: 'Guardar', date: noon(6, 15), accountId: 1, toAccountId: 2 }),
    ]
    const points = fin.projection([conta, reserva], rows, 90, now)
    expect(points[0].cents).toBe(100_000)
    expect(points[30].cents).toBe(70_000)
    expect(points[90].cents).toBe(10_000)
  })
  it('flags only outlier expenses', () => {
    const cats: Category[] = [{ id: 1, name: 'Alimentação', kind: 'despesa', icon: '' }]
    const rows = [6_000, 7_000, 8_000, 9_000].map((v, i) => txn({ amountCents: v, title: `Rotina ${i}`, date: noon(4, 1 + i), categoryId: 1 }))
    rows.push(txn({ amountCents: 60_000, title: 'Churrasco', date: noon(6, 1), categoryId: 1 }), txn({ amountCents: 8_000, title: 'Feira', date: noon(6, 1), categoryId: 1 }))
    expect(fin.unusualExpenses(rows, cats, noon(6, 2)).map((u) => u.title)).toEqual(['Churrasco'])
  })
  it('builds six monthly totals ending this month', () => {
    const m = fin.monthlyTotals([], 6, noon(6, 15))
    expect(m).toHaveLength(6)
    expect(m.at(-1)!.month.getMonth()).toBe(5)
  })
})

describe('routine', () => {
  const habit = (p: Partial<Habit> = {}): Habit => ({ id: 1, name: 'H', icon: '', frequency: 'diaria', target: 1, archived: false, createdAt: noon(1, 1), ...p })
  const checks = (days: number[], month = 3): CheckIn[] => days.map((d) => ({ date: noon(month, d), habitId: 1 }))

  it('keeps a daily streak alive while today is in progress', () => {
    const c = checks([8, 9])
    expect(routine.streak(habit(), c, noon(3, 10))).toBe(2)
    expect(routine.streak(habit(), c, noon(3, 9))).toBe(2)
    expect(routine.streak(habit(), c, noon(3, 11))).toBe(0)
  })
  it('finds the best streak', () => {
    const c = checks([1, 2, 3, 5, 6])
    expect(routine.bestStreak(habit(), c, noon(3, 6))).toBe(3)
    expect(routine.streak(habit(), c, noon(3, 6))).toBe(2)
  })
  it('counts weekly targets (weeks start on Sunday)', () => {
    const h = habit({ frequency: 'semanal', target: 2 })
    const c = checks([9, 11, 16]) // Mar 8-14 2026 has two; Mar 15-21 has one
    expect(routine.isComplete(h, c, noon(3, 12))).toBe(true)
    expect(routine.isComplete(h, c, noon(3, 17))).toBe(false)
    expect(routine.streak(h, c, noon(3, 17))).toBe(1)
  })
  it('measures goal progress from steps and tasks, or numeric target', () => {
    const goal = { id: 1, title: 'G', notes: '', horizon: 'curto' as const, priority: 1 as const, unit: '', completed: false, createdAt: noon(1, 1) }
    const steps = [true, false, false].map((done, i) => ({ id: i, title: 's', done, order: i, goalId: 1 }))
    const tasks: Task[] = [{ id: 1, title: 't', notes: '', priority: 1, done: true, createdAt: noon(1, 1), goalId: 1 }]
    expect(routine.goalProgress(goal, steps, tasks)).toBeCloseTo(0.5)
    expect(routine.goalProgress({ ...goal, targetValue: 10, currentValue: 2.5 }, steps, tasks)).toBeCloseTo(0.25)
    expect(routine.goalProgress({ ...goal, completed: true }, steps, tasks)).toBe(1)
  })
  it('orders tasks and finds today/overdue', () => {
    const now = noon(5, 10)
    const mk = (title: string, due: Date | undefined, priority: 0 | 1 | 2 = 1): Task => ({ title, notes: '', due, priority, done: false, createdAt: noon(1, 1) })
    const undated = mk('Sem data', undefined, 2)
    const late = mk('Atrasada', new Date(2026, 4, 8))
    const todayLow = mk('Hoje baixa', new Date(2026, 4, 10), 0)
    const todayHigh = mk('Hoje alta', new Date(2026, 4, 10), 2)
    const later = mk('Depois', new Date(2026, 4, 20))
    expect(routine.sortTasks([undated, later, todayLow, late, todayHigh]).map((t) => t.title)).toEqual(['Atrasada', 'Hoje alta', 'Hoje baixa', 'Depois', 'Sem data'])
    expect(routine.isOverdue(late, now)).toBe(true)
    expect(routine.isForToday(todayLow, now)).toBe(true)
    expect(routine.isForToday(later, now)).toBe(false)
    expect(routine.isForToday(undated, now)).toBe(false)
  })
})

describe('health', () => {
  const e = (kind: 'agua' | 'peso', value: number, d: number, h: number) => ({ kind, value, date: new Date(2026, 5, d, h), note: '', source: 'manual', createdAt: noon(1, 1) })
  it('sums per day and reports today', () => {
    const water = [e('agua', 300, 10, 8), e('agua', 500, 10, 14), e('agua', 1000, 9, 9), e('agua', 999, 1, 9)]
    const now = new Date(2026, 5, 10, 20)
    expect(health.daily(water, 'agua', 7, now).map((d) => d.value)).toEqual([1000, 800])
    expect(health.current(water, 'agua', now)?.value).toBe(800)
    expect(health.current(water, 'agua', new Date(2026, 5, 11, 12))).toBeUndefined()
  })
  it('uses the latest weight per day and the weekly change', () => {
    const w = [e('peso', 80, 1, 7), e('peso', 80.4, 2, 7), e('peso', 79, 8, 7), e('peso', 78.6, 9, 7), e('peso', 78.8, 9, 20)]
    const now = new Date(2026, 5, 9, 21)
    expect(health.current(w, 'peso', now)?.value).toBe(78.8)
    expect(health.weeklyChange(w, 'peso', now)!).toBeCloseTo(-1.3, 4)
  })
  it('formats pressure', () => expect(health.formatValue(120, 'pressao', 80)).toBe('120/80'))
})

describe('shopping', () => {
  const item = (p: Partial<ShoppingItem>): ShoppingItem => ({ id: 1, name: 'x', quantity: 1, unit: '', category: '', store: '', link: '', note: '', bought: false, priority: 1, createdAt: noon(1, 1), ...p })
  it('estimates totals and groups by category', () => {
    const items = [item({ name: 'Banana', category: 'Hortifruti', quantity: 1.5, priceCents: 799 }), item({ name: 'Arroz', category: 'Mercearia', priceCents: 2500 }), item({ name: 'Sabão' })]
    expect(shop.lineTotal(items[0])).toBe(1199)
    expect(shop.estimate(items)).toEqual({ cents: 3699, missing: 1 })
    expect(shop.groupItems(items).map((g) => g.category)).toEqual(['Hortifruti', 'Mercearia', ''])
  })
  it('records price history only on change', () => {
    const i = item({ priceCents: 1890 })
    expect(shop.priceChange(i, 1890, 'A').point).toBeUndefined()
    expect(shop.priceChange(i, 2090, 'B').point?.priceCents).toBe(2090)
  })
})

describe('statements', () => {
  it('reads OFX (SGML)', () => {
    const ofx = `OFXHEADER:100
<OFX><STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261105120000[-3:BRT]
<TRNAMT>-75.50
<FITID>abc123
<MEMO>POSTO IPIRANGA
</STMTTRN>
<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20261106<TRNAMT>8500.00<FITID>sal1<NAME>SALARIO EMPRESA</STMTTRN></OFX>`
    const lines = parseStatement(ofx)
    expect(lines.map((l) => l.amountCents)).toEqual([-7550, 850000])
    expect(lines[0]).toMatchObject({ id: 'abc123', description: 'POSTO IPIRANGA' })
    expect(lines[0].date.getDate()).toBe(5)
    expect(lines[1].description).toBe('SALARIO EMPRESA')
  })
  it('reads Brazilian bank CSV with quoted fields', () => {
    const lines = parseStatement('Data;Histórico;Valor\n05/11/2026;"Padaria; centro";-12,50\n06/11/26;Salário;8.500,00\n\n')
    expect(lines.map((l) => l.amountCents)).toEqual([-1250, 850000])
    expect(lines[0].description).toBe('Padaria; centro')
    expect(lines[1].date.getDate()).toBe(6)
  })
  it('reads Nubank card CSV and rejects unknown headers', () => {
    expect(parseStatement('date,title,amount\n2026-11-01,Uber *Trip,23.9\n2026-11-02,Netflix.com,55.90\n').map((l) => l.amountCents)).toEqual([2390, 5590])
    expect(() => parseStatement('a;b;c\n1;2;3')).toThrow()
  })
  it('suggests categories from history first, then keywords', () => {
    const cats: Category[] = [
      { id: 1, name: 'Lazer', kind: 'despesa', icon: '' },
      { id: 2, name: 'Transporte', kind: 'despesa', icon: '' },
    ]
    const history = [txn({ title: 'Bar do Zé', categoryId: 1 })]
    expect(suggestCategory('uber *trip', false, cats, history)?.name).toBe('Transporte')
    expect(suggestCategory('bar do ze', false, cats, history)?.name).toBe('Lazer')
    expect(suggestCategory('Loja X', false, cats, history)).toBeUndefined()
  })
})

describe('dates', () => {
  it('writes ISO without milliseconds (the iOS backup format)', () => {
    expect(toISO(new Date(Date.UTC(2026, 10, 22, 15, 30, 5, 123)))).toBe('2026-11-22T15:30:05Z')
  })
})
