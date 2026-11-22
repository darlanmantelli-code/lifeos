/**
 * Data model. Field names and raw values match the iOS app's JSON backup, so a file exported from either side
 * can be imported on the other. Dates are `Date` here and ISO 8601 strings in the backup file.
 */

export type AccountKind = 'corrente' | 'poupanca' | 'carteira' | 'cartao' | 'investimento'
export type TxnKind = 'despesa' | 'receita' | 'transferencia'
export type TxnSource = 'manual' | 'importacao' | 'ia'
export type CategoryKind = 'despesa' | 'receita'
/** 0 baixa, 1 média, 2 alta (same integers as the iOS app). */
export type Priority = 0 | 1 | 2
export type HabitFrequency = 'diaria' | 'semanal' | 'mensal'
export type GoalHorizon = 'curto' | 'medio' | 'longo'
export type HealthKind = 'passos' | 'agua' | 'sono' | 'exercicio' | 'peso' | 'frequencia' | 'pressao' | 'cintura'

export interface Account {
  id?: number
  name: string
  kind: AccountKind
  initialBalanceCents: number
  creditLimitCents?: number
  closingDay?: number
  dueDay?: number
  archived: boolean
  createdAt: Date
}

export interface Category {
  id?: number
  name: string
  kind: CategoryKind
  icon: string
  parentId?: number
}

export interface Transaction {
  id?: number
  date: Date
  /** Always positive; `kind` gives the direction. */
  amountCents: number
  kind: TxnKind
  title: string
  note: string
  isFixed: boolean
  source: TxnSource
  /** Shared by all occurrences of one installment purchase or recurring entry. */
  groupID?: string
  installmentIndex?: number
  installmentCount?: number
  isRecurring: boolean
  createdAt: Date
  accountId?: number
  toAccountId?: number
  categoryId?: number
  /** Bank id (OFX FITID or a hash for CSV) used to skip duplicates on re-import. Web-only, not in the backup. */
  externalID?: string
}

/** Limit applies from `month` ("yyyy-MM") until a later budget for the same category replaces it. 0 = none. */
export interface Budget {
  id?: number
  month: string
  limitCents: number
  categoryId?: number
}

export interface Goal {
  id?: number
  title: string
  notes: string
  horizon: GoalHorizon
  deadline?: Date
  priority: Priority
  targetValue?: number
  currentValue?: number
  unit: string
  completed: boolean
  createdAt: Date
}

export interface GoalStep {
  id?: number
  title: string
  done: boolean
  order: number
  goalId?: number
}

export interface Task {
  id?: number
  title: string
  notes: string
  /** Day only (local midnight). */
  due?: Date
  priority: Priority
  done: boolean
  doneAt?: Date
  createdAt: Date
  goalId?: number
}

export interface Habit {
  id?: number
  name: string
  icon: string
  frequency: HabitFrequency
  /** Check-ins needed per period. */
  target: number
  archived: boolean
  createdAt: Date
}

export interface CheckIn {
  id?: number
  date: Date
  habitId?: number
}

export interface ShoppingList {
  id?: number
  name: string
  icon: string
  isWishlist: boolean
  createdAt: Date
}

export interface ShoppingItem {
  id?: number
  name: string
  quantity: number
  unit: string
  category: string
  /** Unit price typed by the user, never fetched from a store. */
  priceCents?: number
  store: string
  link: string
  note: string
  bought: boolean
  boughtAt?: Date
  priority: Priority
  createdAt: Date
  listId?: number
}

export interface PricePoint {
  id?: number
  priceCents: number
  store: string
  observedAt: Date
  source: string
  itemId?: number
}

export interface HealthEntry {
  id?: number
  kind: HealthKind
  value: number
  /** Diastolic pressure for `pressao`. */
  value2?: number
  date: Date
  note: string
  source: string
  createdAt: Date
}

export interface HealthTarget {
  id?: number
  kind: HealthKind
  value: number
}

// Carried through import/export untouched (the iOS app owns these; the web app has no screens for them yet).
export interface AiLog { id?: number; date: Date; tool: string; summary: string; status: string }
export interface AutomationRule {
  id?: number; trigger: string; action: string; parameter: number; enabled: boolean; createdAt: Date; firedKeys: string
}
export interface AutomationRun { id?: number; date: Date; ruleLabel: string; message: string; ok: boolean }
export interface Study {
  id?: number; title: string; kind: string; progress: number; notes: string
  reviewStage?: number; nextReview?: Date; archived: boolean; createdAt: Date
}
export interface FocusSession { id?: number; start: Date; minutes: number; studyId?: number }
