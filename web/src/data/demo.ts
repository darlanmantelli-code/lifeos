import { addDays, addMonths, monthKey, monthStart } from '../lib/dates'
import type { HabitFrequency } from '../domain/types'
import { addHealth, addTransactions, ensureDefaults, newGoal, newHabit, newItem, newList, newTask, saveItemPrice, setBudget, setHealthTarget } from './actions'
import { newAccount } from './actions'
import type { LivoDB } from './db'

/** Clearly fictitious records for demo mode. Mirrors the iOS demo data. Never mixed with real data. */
export async function seedDemo(db: LivoDB, now: Date = new Date()): Promise<void> {
  const noonDaysAgo = (n: number, hour = 12) => {
    const d = addDays(now, -n)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), hour)
  }
  const first = monthStart(now)
  const inMonth = (day: number) => new Date(first.getFullYear(), first.getMonth(), day, 12)

  await ensureDefaults(db)
  const cats = await db.categories.toArray()
  const cat = (name: string) => cats.find((c) => c.name === name)?.id

  const conta = await db.accounts.add(newAccount({ name: 'Conta Demo', kind: 'corrente', initialBalanceCents: 520_000 }))
  await db.accounts.add(newAccount({ name: 'Reserva Demo', kind: 'poupanca', initialBalanceCents: 1_250_000 }))
  const cartao = await db.accounts.add(newAccount({ name: 'Cartão Demo', kind: 'cartao', creditLimitCents: 800_000, closingDay: 5, dueDay: 12 }))

  type Entry = [kind: 'despesa' | 'receita', cents: number, title: string, day: number, account: number, category: string, rep?: 'parcelada' | 'recorrente']
  const entries: Entry[] = [
    ['receita', 850_000, 'Salário (exemplo)', 5, conta, 'Salário'],
    ['despesa', 220_000, 'Aluguel (exemplo)', 6, conta, 'Moradia'],
    ['despesa', 64_000, 'Supermercado', 8, cartao, 'Alimentação'],
    ['despesa', 38_500, 'Feira e padaria', 12, conta, 'Alimentação'],
    ['despesa', 25_000, 'Combustível', 10, cartao, 'Transporte'],
    ['despesa', 5_590, 'Streaming', 9, cartao, 'Assinaturas', 'recorrente'],
    ['despesa', 480_000, 'Notebook', 3, cartao, 'Compras', 'parcelada'],
    ['despesa', 9_000, 'Cinema', 14, cartao, 'Lazer'],
    ['despesa', 18_000, 'Academia', 2, conta, 'Saúde', 'recorrente'],
  ]
  for (const [kind, cents, title, day, accountId, category, rep] of entries) {
    const date = inMonth(day)
    if (date > now && !rep) continue
    await addTransactions(db, {
      kind, amountCents: cents, title, date, accountId, categoryId: cat(category), isFixed: rep === 'recorrente',
      repetition: rep === 'parcelada' ? { type: 'parcelada', count: 10 } : rep === 'recorrente' ? { type: 'recorrente' } : { type: 'unica' },
    })
  }
  const key = monthKey(now)
  for (const [name, limit] of [['Alimentação', 120_000], ['Lazer', 30_000], ['Transporte', 40_000]] as const) {
    const id = cat(name)
    if (id !== undefined) await setBudget(db, id, key, limit)
  }

  const habits: [string, string, HabitFrequency, number, number[]][] = [
    ['Ler 20 minutos', 'book', 'diaria', 1, [1, 2, 3, 4, 5, 7, 8]],
    ['Beber 2 L de água', 'drop', 'diaria', 1, [0, 1, 2, 4]],
    ['Treinar', 'dumbbell', 'semanal', 3, [1, 3, 8, 10, 12]],
    ['Meditar', 'brain', 'diaria', 1, []],
  ]
  for (const [name, icon, frequency, target, days] of habits) {
    const habitId = await db.habits.add(newHabit(name, { icon, frequency, target }))
    await db.checkIns.bulkAdd(days.map((d) => ({ habitId, date: noonDaysAgo(d, 8) })))
  }

  const reserva = await db.goals.add(newGoal('Reserva de emergência', { horizon: 'medio', targetValue: 30_000, currentValue: 12_500, unit: 'R$', priority: 2, deadline: addMonths(now, 8) }))
  await db.goals.add(newGoal('Ler 12 livros no ano', { horizon: 'longo', targetValue: 12, currentValue: 7, unit: 'livros' }))
  const viagem = await db.goals.add(newGoal('Viagem de férias', { horizon: 'curto', deadline: addMonths(now, 2) }))
  const steps: [string, boolean][] = [['Definir destino', true], ['Pesquisar passagens', true], ['Reservar hotel', false], ['Montar roteiro', false]]
  await db.goalSteps.bulkAdd(steps.map(([title, done], order) => ({ title, done, order, goalId: viagem })))

  const day = (offset: number) => new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset)
  await db.tasks.bulkAdd([
    newTask('Pagar conta de luz', { due: day(0), priority: 2 }),
    newTask('Revisar orçamento do mês', { due: day(0), goalId: reserva }),
    newTask('Renovar documento', { due: day(-2), priority: 2 }),
    newTask('Comprar passagens', { due: day(1), goalId: viagem }),
    newTask('Organizar fotos', { priority: 0 }),
  ])

  const mercado = await db.lists.add(newList('Mercado', false))
  const desejos = await db.lists.add(newList('Desejos', true))
  const groceries: [string, string, number, string, number | undefined][] = [
    ['Banana', 'Hortifruti', 1.5, 'kg', 699], ['Tomate', 'Hortifruti', 1, 'kg', 899], ['Arroz', 'Mercearia', 1, 'pct', 2490],
    ['Café', 'Mercearia', 2, 'pct', 1890], ['Leite', 'Laticínios', 6, 'L', 549], ['Detergente', 'Limpeza', 2, 'un', undefined],
  ]
  for (const [name, category, quantity, unit, price] of groceries) {
    const id = await db.items.add(newItem(name, mercado, { category, quantity, unit }))
    await saveItemPrice(db, (await db.items.get(id))!, price, 'Mercado Exemplo')
  }
  const tenisId = await db.items.add(newItem('Tênis de corrida', desejos, { priority: 2 }))
  await saveItemPrice(db, (await db.items.get(tenisId))!, 59_990, 'Loja Exemplo')
  await saveItemPrice(db, (await db.items.get(tenisId))!, 52_990, 'Loja Exemplo')

  for (let d = 0; d < 21; d++) {
    const at = (h: number) => noonDaysAgo(d, h)
    await addHealth(db, 'passos', 6000 + 400 * ((d * 7) % 9), at(19))
    await addHealth(db, 'agua', d === 0 ? 1200 : 1600 + 100 * (d % 6), at(19))
    await addHealth(db, 'sono', 6.2 + ((d * 37) % 11) / 10, at(7))
    if (d % 2 === 0) await addHealth(db, 'exercicio', 40, at(19))
    await addHealth(db, 'peso', Number((81 + d * 0.06).toFixed(2)), at(19))
    if (d % 3 === 0) await addHealth(db, 'pressao', 118 + (d % 5), at(9), 78 + (d % 3))
  }
  await setHealthTarget(db, 'agua', 2000)
  await setHealthTarget(db, 'passos', 8000)
  await setHealthTarget(db, 'sono', 8)
}
