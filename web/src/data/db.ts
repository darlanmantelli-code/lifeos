import Dexie, { type Table } from 'dexie'
import type {
  Account, AiLog, AutomationRule, AutomationRun, Budget, Category, CheckIn, FocusSession, Goal, GoalStep, HealthEntry,
  HealthTarget, Habit, PricePoint, ShoppingItem, ShoppingList, Study, Task, Transaction,
} from '../domain/types'

/** Local IndexedDB store. The real data lives in `livo`; demo mode uses a separate `livo-demo` database. */
export class LivoDB extends Dexie {
  accounts!: Table<Account, number>
  categories!: Table<Category, number>
  transactions!: Table<Transaction, number>
  budgets!: Table<Budget, number>
  goals!: Table<Goal, number>
  goalSteps!: Table<GoalStep, number>
  tasks!: Table<Task, number>
  habits!: Table<Habit, number>
  checkIns!: Table<CheckIn, number>
  lists!: Table<ShoppingList, number>
  items!: Table<ShoppingItem, number>
  prices!: Table<PricePoint, number>
  health!: Table<HealthEntry, number>
  healthTargets!: Table<HealthTarget, number>
  aiLog!: Table<AiLog, number>
  rules!: Table<AutomationRule, number>
  runs!: Table<AutomationRun, number>
  studies!: Table<Study, number>
  focus!: Table<FocusSession, number>

  constructor(name: string) {
    super(name)
    this.version(1).stores({
      accounts: '++id',
      categories: '++id, parentId',
      transactions: '++id, date, accountId, categoryId, groupID, externalID',
      budgets: '++id, categoryId, month',
      goals: '++id',
      goalSteps: '++id, goalId',
      tasks: '++id, goalId, due, done',
      habits: '++id',
      checkIns: '++id, habitId, date',
      lists: '++id',
      items: '++id, listId',
      prices: '++id, itemId',
      health: '++id, kind, date',
      healthTargets: '++id, kind',
      aiLog: '++id',
      rules: '++id',
      runs: '++id',
      studies: '++id',
      focus: '++id, studyId',
    })
  }

  /** Every table, for wipe/export. */
  get allTables(): Table[] {
    return this.tables
  }
}

export const REAL_DB = 'livo'
export const DEMO_DB = 'livo-demo'
