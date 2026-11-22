import 'fake-indexeddb/auto'
import { beforeEach, describe, expect, it } from 'vitest'
import { LivoDB } from './db'
import { BackupError, SECTION_NAMES, exportBackup, parseBackup, restoreBackup, wipe } from './backup'
import { seedDemo } from './demo'
import * as actions from './actions'

let db: LivoDB
let n = 0
beforeEach(() => {
  db = new LivoDB(`test-${n++}`)
})

/** Required keys of each iOS Backup DTO (non-optional Swift properties): a file missing one fails to import on iOS. */
const IOS_REQUIRED: Record<string, string[]> = {
  contas: ['id', 'name', 'kind', 'initialBalanceCents', 'archived', 'createdAt'],
  categorias: ['id', 'name', 'kind', 'icon'],
  lancamentos: ['date', 'amountCents', 'kind', 'title', 'note', 'isFixed', 'source', 'isRecurring', 'createdAt'],
  orcamentos: ['month', 'limitCents'],
  metas: ['id', 'title', 'notes', 'horizon', 'priority', 'unit', 'completed', 'createdAt'],
  etapas: ['title', 'done', 'order'],
  tarefas: ['title', 'notes', 'priority', 'done', 'createdAt'],
  habitos: ['id', 'name', 'icon', 'frequency', 'target', 'archived', 'createdAt'],
  registrosHabitos: ['date'],
  listas: ['id', 'name', 'icon', 'isWishlist', 'createdAt'],
  itens: ['id', 'name', 'quantity', 'unit', 'category', 'store', 'link', 'note', 'bought', 'priority', 'createdAt'],
  precos: ['priceCents', 'store', 'observedAt', 'source'],
  saude: ['kind', 'value', 'date', 'note', 'source', 'createdAt'],
  metasSaude: ['kind', 'value'],
}

describe('backup', () => {
  it('exports every section the iOS app reads, with all its required fields', async () => {
    await seedDemo(db)
    const file = await exportBackup(db)
    expect(file.app).toBe('livo')
    expect(file.versao).toBe(1)
    for (const s of SECTION_NAMES) expect(Array.isArray(file[s]), s).toBe(true)
    for (const [section, keys] of Object.entries(IOS_REQUIRED)) {
      const rows = file[section] as Record<string, unknown>[]
      expect(rows.length, section).toBeGreaterThan(0)
      for (const row of rows) for (const k of keys) expect(row[k], `${section}.${k}`).not.toBeUndefined()
    }
  })

  it('writes dates as ISO UTC without milliseconds and omits web-only and undefined fields', async () => {
    await seedDemo(db)
    const file = await exportBackup(db)
    const json = JSON.stringify(file)
    expect(json).not.toMatch(/\d{2}:\d{2}:\d{2}\.\d{3}Z/)
    expect(json).not.toContain('externalID')
    const tx = (file.lancamentos as Record<string, unknown>[])[0]
    expect(tx.date).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
    expect('id' in tx).toBe(false) // transactions carry no id in the DTO
    expect(Object.values(tx).includes(null)).toBe(false)
  })

  it('round-trips everything: export, wipe, restore', async () => {
    await seedDemo(db)
    const counts = async () => Promise.all(db.allTables.map((t) => t.count()))
    const before = await counts()
    const file = await exportBackup(db)
    await wipe(db)
    expect((await counts()).every((c) => c === 0)).toBe(true)
    await restoreBackup(db, parseBackup(JSON.stringify(file)))
    expect(await counts()).toEqual(before)
    // references survive: every transaction still points at an existing account
    const accounts = new Set((await db.accounts.toArray()).map((a) => a.id))
    expect((await db.transactions.toArray()).every((t) => accounts.has(t.accountId!))).toBe(true)
    const tenis = (await db.items.toArray()).find((i) => i.name === 'Tênis de corrida')!
    expect(await db.prices.where('itemId').equals(tenis.id!).count()).toBe(2)
    // dates come back as Dates
    expect((await db.transactions.toArray())[0].date).toBeInstanceOf(Date)
  })

  it('imports a file in the shape the iOS app writes (ids on some sections, null-free, older version without new sections)', async () => {
    const ios = {
      app: 'livo', versao: 1, exportadoEm: '2026-11-22T15:00:00Z',
      contas: [{ id: 7, name: 'Nubank', kind: 'corrente', initialBalanceCents: 1000, archived: false, createdAt: '2026-01-01T12:00:00Z' }],
      categorias: [{ id: 3, name: 'Mercado', kind: 'despesa', icon: 'tag' }],
      lancamentos: [{ date: '2026-11-05T15:00:00Z', amountCents: 7550, kind: 'despesa', title: 'Posto', note: '', isFixed: false, source: 'importacao', isRecurring: false, createdAt: '2026-11-05T15:00:00Z', accountId: 7, categoryId: 3 }],
      orcamentos: [], metas: [], etapas: [], tarefas: [], habitos: [], registrosHabitos: [], listas: [], itens: [], precos: [], saude: [], metasSaude: [], historicoIA: [],
    }
    await restoreBackup(db, parseBackup(JSON.stringify(ios)))
    const t = (await db.transactions.toArray())[0]
    expect(t).toMatchObject({ amountCents: 7550, accountId: 7, categoryId: 3, source: 'importacao' })
    expect(await db.accounts.get(7)).toMatchObject({ name: 'Nubank' })
    // new ids continue after the restored ones
    expect(await db.accounts.add(actions.newAccount({ name: 'Outra', kind: 'carteira' }))).toBeGreaterThan(7)
  })

  it('rejects foreign, newer and malformed files without touching existing data', async () => {
    await db.accounts.add(actions.newAccount({ name: 'Mantida', kind: 'corrente' }))
    expect(() => parseBackup('não é json')).toThrow(BackupError)
    expect(() => parseBackup('{"foo":1}')).toThrow(BackupError)
    expect(() => parseBackup('{"app":"livo","versao":2}')).toThrow(/mais nova/)
    expect(() => parseBackup('{"app":"livo","versao":1,"contas":"x"}')).toThrow(BackupError)
    const bad = parseBackup('{"app":"livo","versao":1,"lancamentos":[{"date":"ontem"}]}')
    await expect(restoreBackup(db, bad)).rejects.toThrow(BackupError)
    expect(await db.accounts.count()).toBe(1)
  })
})

describe('actions', () => {
  it('creates installments and deletes this and future ones', async () => {
    const id = await db.accounts.add(actions.newAccount({ name: 'C', kind: 'corrente' }))
    await actions.addTransactions(db, { kind: 'despesa', amountCents: 30_000, title: 'TV', date: new Date(2026, 0, 10, 12), accountId: id, repetition: { type: 'parcelada', count: 3 } })
    const rows = (await db.transactions.toArray()).sort((a, b) => +a.date - +b.date)
    expect(rows.map((r) => r.amountCents)).toEqual([10_000, 10_000, 10_000])
    await actions.deleteTransaction(db, rows[1], true)
    expect(await db.transactions.count()).toBe(1)
  })

  it('archives an account that has transactions and deletes an unused one', async () => {
    const a = await db.accounts.add(actions.newAccount({ name: 'A', kind: 'corrente' }))
    const b = await db.accounts.add(actions.newAccount({ name: 'B', kind: 'corrente' }))
    await actions.addTransactions(db, { kind: 'despesa', amountCents: 100, title: 'x', date: new Date(), accountId: a })
    expect(await actions.deleteAccount(db, a)).toBe('archived')
    expect(await actions.deleteAccount(db, b)).toBe('deleted')
    expect((await db.accounts.get(a))?.archived).toBe(true)
  })

  it('moves habit check-ins up to the target and undoes the last one at target', async () => {
    const id = await db.habits.add(actions.newHabit('Ler'))
    const habit = (await db.habits.get(id))!
    const at = new Date(2026, 3, 1, 9)
    await actions.tapCheckIn(db, habit, at)
    expect(await db.checkIns.count()).toBe(1)
    await actions.tapCheckIn(db, habit, new Date(2026, 3, 1, 18))
    expect(await db.checkIns.count()).toBe(0)
  })

  it('cascades category and goal deletes without losing transactions or tasks', async () => {
    await actions.ensureDefaults(db)
    const cat = (await db.categories.toArray())[0].id!
    const sub = await actions.addCategory(db, { name: 'Sub', kind: 'despesa', parentId: cat })
    const acc = await db.accounts.add(actions.newAccount({ name: 'C', kind: 'corrente' }))
    await actions.addTransactions(db, { kind: 'despesa', amountCents: 100, title: 'x', date: new Date(), accountId: acc, categoryId: sub })
    await actions.setBudget(db, cat, '2026-01', 5000)
    await actions.deleteCategory(db, cat)
    expect(await db.categories.get(sub)).toBeUndefined()
    expect(await db.budgets.count()).toBe(0)
    expect((await db.transactions.toArray())[0].categoryId).toBeUndefined()

    const goal = await db.goals.add(actions.newGoal('G'))
    await db.goalSteps.add({ title: 's', done: false, order: 0, goalId: goal })
    await db.tasks.add(actions.newTask('t', { goalId: goal }))
    await actions.deleteGoal(db, goal)
    expect(await db.goalSteps.count()).toBe(0)
    expect((await db.tasks.toArray())[0].goalId).toBeUndefined()
  })

  it('keeps price history only on change and removes it with the list', async () => {
    const list = await db.lists.add(actions.newList('Mercado', false))
    const id = await db.items.add(actions.newItem('Café', list))
    await actions.saveItemPrice(db, (await db.items.get(id))!, 1890, 'A')
    await actions.saveItemPrice(db, (await db.items.get(id))!, 1890, 'A')
    await actions.saveItemPrice(db, (await db.items.get(id))!, 2090, 'B')
    expect(await db.prices.count()).toBe(2)
    await actions.deleteList(db, list)
    expect(await db.items.count()).toBe(0)
    expect(await db.prices.count()).toBe(0)
  })

  it('sets and removes health targets', async () => {
    await actions.setHealthTarget(db, 'agua', 2000)
    await actions.setHealthTarget(db, 'agua', 2500)
    expect((await db.healthTargets.toArray()).map((t) => t.value)).toEqual([2500])
    await actions.setHealthTarget(db, 'agua', undefined)
    expect(await db.healthTargets.count()).toBe(0)
  })
})
