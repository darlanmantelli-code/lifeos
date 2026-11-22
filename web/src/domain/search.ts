import { normalize } from './statements'
import type { Category, Goal, Habit, ShoppingItem, ShoppingList, Study, Task, Transaction } from './types'

/** Case- and accent-insensitive: "alimentacao" finds "Alimentação". */
export function matches(text: string, query: string): boolean {
  const q = normalize(query)
  return q !== '' && normalize(text).includes(q)
}

export interface SearchData {
  transactions: Transaction[]
  categories: Category[]
  tasks: Task[]
  goals: Goal[]
  habits: Habit[]
  items: ShoppingItem[]
  lists: ShoppingList[]
  studies: Study[]
}

export interface SearchResults {
  transactions: Transaction[]
  tasks: Task[]
  goals: Goal[]
  habits: Habit[]
  items: (ShoppingItem & { listName: string })[]
  studies: Study[]
}

/** Searches every module's text fields. Transactions are capped (newest first) so a broad query stays fast. */
export function searchAll(d: SearchData, query: string, limit = 20): SearchResults {
  const catName = new Map(d.categories.map((c) => [c.id!, c.name]))
  const listName = new Map(d.lists.map((l) => [l.id!, l.name]))
  const m = (...texts: (string | undefined)[]) => texts.some((t) => t !== undefined && matches(t, query))
  return {
    transactions: d.transactions
      .filter((t) => m(t.title, t.note, t.categoryId !== undefined ? catName.get(t.categoryId) : undefined))
      .sort((a, b) => +b.date - +a.date)
      .slice(0, limit),
    tasks: d.tasks.filter((t) => m(t.title, t.notes)),
    goals: d.goals.filter((g) => m(g.title, g.notes)),
    habits: d.habits.filter((h) => m(h.name)),
    items: d.items.filter((i) => i.listId !== undefined && m(i.name, i.store, i.note)).map((i) => ({ ...i, listName: listName.get(i.listId!) ?? '' })),
    studies: d.studies.filter((s) => m(s.title, s.notes)),
  }
}

export const isEmpty = (r: SearchResults): boolean => Object.values(r).every((list) => list.length === 0)
