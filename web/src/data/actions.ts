import { period } from '../domain/routine'
import { defaultCategories, expandDraft, type TransactionDraft } from '../domain/finance'
import { priceChange } from '../domain/shopping'
import { inInterval, startOfDay } from '../lib/dates'
import type {
  Account, Category, Goal, Habit, HealthKind, Priority, ShoppingItem, ShoppingList, Task, Transaction,
} from '../domain/types'
import type { LivoDB } from './db'

/** All writes go through here, so every row is created with the fields the backup format requires. */

export async function ensureDefaults(db: LivoDB): Promise<void> {
  if ((await db.categories.count()) === 0) await db.categories.bulkAdd(defaultCategories.map((c) => ({ ...c })))
}

// ---- Finance ----

export async function addTransactions(db: LivoDB, draft: TransactionDraft): Promise<number[]> {
  const rows = expandDraft(draft)
  return (await db.transactions.bulkAdd(rows, { allKeys: true })) as number[]
}

export async function deleteTransaction(db: LivoDB, t: Transaction, includingFuture: boolean): Promise<void> {
  if (!includingFuture || !t.groupID) {
    await db.transactions.delete(t.id!)
    return
  }
  const group = await db.transactions.where('groupID').equals(t.groupID).toArray()
  await db.transactions.bulkDelete(group.filter((x) => x.date >= t.date).map((x) => x.id!))
}

export async function setBudget(db: LivoDB, categoryId: number, month: string, limitCents: number): Promise<void> {
  const existing = (await db.budgets.where('categoryId').equals(categoryId).toArray()).find((b) => b.month === month)
  if (existing) await db.budgets.update(existing.id!, { limitCents })
  else await db.budgets.add({ categoryId, month, limitCents })
}

export const newAccount = (p: Partial<Account> & Pick<Account, 'name' | 'kind'>): Account => ({
  initialBalanceCents: 0, archived: false, createdAt: new Date(), ...p,
})

export async function deleteAccount(db: LivoDB, id: number): Promise<'deleted' | 'archived'> {
  const used = await db.transactions.filter((t) => t.accountId === id || t.toAccountId === id).count()
  if (used > 0) {
    await db.accounts.update(id, { archived: true })
    return 'archived'
  }
  await db.accounts.delete(id)
  return 'deleted'
}

export async function addCategory(db: LivoDB, c: Pick<Category, 'name' | 'kind'> & { parentId?: number; icon?: string }): Promise<number> {
  return db.categories.add({ name: c.name, kind: c.kind, icon: c.icon ?? 'tag', parentId: c.parentId })
}

/** Deletes the category, its subcategories and budgets; transactions keep existing without a category. */
export async function deleteCategory(db: LivoDB, id: number): Promise<void> {
  const ids = [id, ...(await db.categories.where('parentId').equals(id).primaryKeys())]
  await db.transaction('rw', db.categories, db.budgets, db.transactions, async () => {
    for (const cid of ids) {
      await db.budgets.where('categoryId').equals(cid).delete()
      await db.transactions.where('categoryId').equals(cid).modify({ categoryId: undefined })
    }
    await db.categories.bulkDelete(ids)
  })
}

// ---- Routine ----

export const newTask = (title: string, p: Partial<Task> = {}): Task => ({
  title, notes: '', priority: 1, done: false, createdAt: new Date(), ...p,
})

export async function toggleTask(db: LivoDB, t: Task): Promise<void> {
  await db.tasks.update(t.id!, { done: !t.done, doneAt: t.done ? undefined : new Date() })
}

export const newHabit = (name: string, p: Partial<Habit> = {}): Habit => ({
  name, icon: 'check', frequency: 'diaria', target: 1, archived: false, createdAt: new Date(), ...p,
})

/** A tap adds a check-in until the period target is met; tapping a complete habit undoes the last one. */
export async function tapCheckIn(db: LivoDB, habit: Habit, at: Date = new Date()): Promise<void> {
  const interval = period(at, habit.frequency)
  const inPeriod = (await db.checkIns.where('habitId').equals(habit.id!).toArray())
    .filter((c) => inInterval(c.date, interval))
    .sort((a, b) => +a.date - +b.date)
  if (inPeriod.length >= Math.max(habit.target, 1)) await db.checkIns.delete(inPeriod.at(-1)!.id!)
  else await db.checkIns.add({ habitId: habit.id!, date: at })
}

export async function deleteHabit(db: LivoDB, id: number): Promise<void> {
  await db.transaction('rw', db.habits, db.checkIns, async () => {
    await db.checkIns.where('habitId').equals(id).delete()
    await db.habits.delete(id)
  })
}

export const newGoal = (title: string, p: Partial<Goal> = {}): Goal => ({
  title, notes: '', horizon: 'curto', priority: 1 as Priority, unit: '', completed: false, createdAt: new Date(), ...p,
})

/** Deletes the goal and its steps; linked tasks stay, without a goal. */
export async function deleteGoal(db: LivoDB, id: number): Promise<void> {
  await db.transaction('rw', db.goals, db.goalSteps, db.tasks, async () => {
    await db.goalSteps.where('goalId').equals(id).delete()
    await db.tasks.where('goalId').equals(id).modify({ goalId: undefined })
    await db.goals.delete(id)
  })
}

// ---- Shopping ----

export const newList = (name: string, isWishlist: boolean): ShoppingList => ({
  name, isWishlist, icon: isWishlist ? 'star' : 'cart', createdAt: new Date(),
})

export const newItem = (name: string, listId: number, p: Partial<ShoppingItem> = {}): ShoppingItem => ({
  name, listId, quantity: 1, unit: '', category: '', store: '', link: '', note: '', bought: false, priority: 1, createdAt: new Date(), ...p,
})

/** Saves the item and, when the price changed, adds one history point. */
export async function saveItemPrice(db: LivoDB, item: ShoppingItem, cents: number | undefined, store: string): Promise<void> {
  const { priceCents, point } = priceChange(item, cents, store)
  await db.transaction('rw', db.items, db.prices, async () => {
    await db.items.update(item.id!, { priceCents, store })
    if (point) await db.prices.add(point)
  })
}

export async function deleteList(db: LivoDB, id: number): Promise<void> {
  const itemIds = (await db.items.where('listId').equals(id).primaryKeys()) as number[]
  await db.transaction('rw', db.lists, db.items, db.prices, async () => {
    await db.prices.where('itemId').anyOf(itemIds).delete()
    await db.items.bulkDelete(itemIds)
    await db.lists.delete(id)
  })
}

export async function clearBought(db: LivoDB, listId: number): Promise<void> {
  const ids = (await db.items.where('listId').equals(listId).filter((i) => i.bought).primaryKeys()) as number[]
  await db.transaction('rw', db.items, db.prices, async () => {
    await db.prices.where('itemId').anyOf(ids).delete()
    await db.items.bulkDelete(ids)
  })
}

// ---- Health ----

export async function addHealth(db: LivoDB, kind: HealthKind, value: number, date: Date, value2?: number, note = ''): Promise<void> {
  await db.health.add({ kind, value, value2, date, note, source: 'manual', createdAt: new Date() })
}

export async function setHealthTarget(db: LivoDB, kind: HealthKind, value: number | undefined): Promise<void> {
  const existing = await db.healthTargets.where('kind').equals(kind).toArray()
  if (value === undefined || value <= 0) {
    await db.healthTargets.bulkDelete(existing.map((t) => t.id!))
  } else if (existing[0]) {
    await db.healthTargets.update(existing[0].id!, { value })
  } else {
    await db.healthTargets.add({ kind, value })
  }
}

export const today = (): Date => startOfDay(new Date())
