import { useLive } from './DbContext'
import type {
  Account, Budget, Category, CheckIn, Goal, GoalStep, Habit, HealthEntry, HealthTarget, PricePoint, ShoppingItem,
  ShoppingList, Task, Transaction,
} from '../domain/types'

// One shared empty array per type so "still loading" never changes identity between renders.
const E = [] as never[]

export const useAccounts = () => useLive((db) => db.accounts.toArray(), E as Account[])
export const useCategories = () => useLive((db) => db.categories.toArray(), E as Category[])
export const useTransactions = () => useLive((db) => db.transactions.orderBy('date').reverse().toArray(), E as Transaction[])
export const useBudgets = () => useLive((db) => db.budgets.toArray(), E as Budget[])
export const useTasks = () => useLive((db) => db.tasks.toArray(), E as Task[])
export const useHabits = () => useLive((db) => db.habits.toArray(), E as Habit[])
export const useCheckIns = () => useLive((db) => db.checkIns.toArray(), E as CheckIn[])
export const useGoals = () => useLive((db) => db.goals.toArray(), E as Goal[])
export const useGoalSteps = () => useLive((db) => db.goalSteps.toArray(), E as GoalStep[])
export const useLists = () => useLive((db) => db.lists.toArray(), E as ShoppingList[])
export const useItems = () => useLive((db) => db.items.toArray(), E as ShoppingItem[])
export const usePrices = () => useLive((db) => db.prices.toArray(), E as PricePoint[])
export const useHealth = () => useLive((db) => db.health.toArray(), E as HealthEntry[])
export const useHealthTargets = () => useLive((db) => db.healthTargets.toArray(), E as HealthTarget[])
