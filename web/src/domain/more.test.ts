import { describe, expect, it } from 'vitest'
import { isEmpty, matches, searchAll, type SearchData } from './search'
import * as study from './study'
import type { Study, Transaction } from './types'

const noon = (m: number, d: number) => new Date(2026, m - 1, d, 12)
const empty: SearchData = { transactions: [], categories: [], tasks: [], goals: [], habits: [], items: [], lists: [], studies: [] }

describe('search', () => {
  it('ignores case and accents', () => {
    expect(matches('Alimentação', 'alimentacao')).toBe(true)
    expect(matches('Tênis de corrida', 'TENIS')).toBe(true)
    expect(matches('Mercado', '  ')).toBe(false)
  })
  it('finds across modules, newest transactions first, with list names for items', () => {
    const txn = (title: string, d: number, categoryId?: number): Transaction => ({
      id: d, date: noon(5, d), amountCents: 1, kind: 'despesa', title, note: '', isFixed: false, source: 'manual', isRecurring: false, createdAt: noon(5, 1), categoryId,
    })
    const data: SearchData = {
      ...empty,
      categories: [{ id: 1, name: 'Alimentação', kind: 'despesa', icon: '' }],
      transactions: [txn('Padaria', 2, 1), txn('Cinema', 3), txn('Feira', 9, 1)],
      lists: [{ id: 1, name: 'Mercado', icon: '', isWishlist: false, createdAt: noon(1, 1) }],
      items: [{ id: 1, name: 'Café alimentação', listId: 1, quantity: 1, unit: '', category: '', store: '', link: '', note: '', bought: false, priority: 1, createdAt: noon(1, 1) }],
      tasks: [{ id: 1, title: 'Comprar passagem', notes: '', priority: 1, done: false, createdAt: noon(1, 1) }],
    }
    const r = searchAll(data, 'alimentacao')
    expect(r.transactions.map((t) => t.title)).toEqual(['Feira', 'Padaria']) // by category name, newest first
    expect(r.items[0].listName).toBe('Mercado')
    expect(r.tasks).toHaveLength(0)
    expect(isEmpty(searchAll(data, 'zzz'))).toBe(true)
    expect(searchAll(data, 'passagem').tasks).toHaveLength(1)
  })
})

describe('study', () => {
  const s = (p: Partial<Study> = {}): Study => ({ id: 1, title: 'Swift', kind: 'curso', progress: 0, notes: '', archived: false, createdAt: noon(1, 1), ...p })

  it('advances spaced reviews and caps at the last interval', () => {
    let cur = s()
    cur = { ...cur, ...study.markReviewed(cur, noon(3, 1)) }
    expect(cur.nextReview!.getDate()).toBe(2) // +1 day
    expect(study.isReviewDue(cur, noon(3, 1))).toBe(false)
    expect(study.isReviewDue(cur, new Date(2026, 2, 2, 8))).toBe(true)
    cur = { ...cur, ...study.markReviewed(cur, noon(3, 2)) }
    expect(cur.nextReview!.getDate()).toBe(5) // +3 days
    for (let i = 0; i < 10; i++) cur = { ...cur, ...study.markReviewed(cur, noon(3, 5)) }
    expect(cur.reviewStage).toBe(study.REVIEW_INTERVALS.length - 1)
    expect({ ...cur, ...study.stopReviews() }.nextReview).toBeUndefined()
    expect(study.isReviewDue(s({ nextReview: noon(1, 1), archived: true }), noon(3, 1))).toBe(false)
  })

  it('sums focus minutes per study and since a date', () => {
    const sessions = [
      { start: noon(3, 1), minutes: 25, studyId: 1 }, { start: noon(3, 3), minutes: 25, studyId: 1 },
      { start: noon(3, 10), minutes: 50, studyId: 1 }, { start: noon(3, 10), minutes: 30, studyId: 2 },
    ]
    expect(study.totalMinutes(sessions, 1)).toBe(100)
    expect(study.minutesSince(sessions, noon(3, 2))).toBe(105)
  })

  it('keeps pomodoro time from the wall clock', () => {
    const t0 = Date.UTC(2026, 2, 1, 9)
    const st = study.startPhase('focus', 25, t0, 1)
    expect(study.remainingMs(st, t0 + 60_000)).toBe(24 * 60_000)
    expect(study.isFinished(st, t0 + 24 * 60_000)).toBe(false)
    expect(study.isFinished(st, t0 + 26 * 60_000)).toBe(true) // tab was in the background
    expect(study.clock(24 * 60_000 + 5_000)).toBe('24:05')
    expect(study.minutesSpent(st, t0 + 10 * 60_000 + 30_000)).toBe(10)
    expect(study.isFinished(study.IDLE, t0)).toBe(false)
  })
})
