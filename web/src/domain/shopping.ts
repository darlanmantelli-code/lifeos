import type { PricePoint, ShoppingItem } from './types'

export const SHOPPING_CATEGORIES = [
  'Hortifruti', 'Açougue', 'Padaria', 'Laticínios', 'Mercearia', 'Bebidas',
  'Limpeza', 'Higiene', 'Casa', 'Eletrônicos', 'Vestuário', 'Outros',
] as const

/** Unit price x quantity, rounded to the cent. Undefined without a price. */
export function lineTotal(i: ShoppingItem): number | undefined {
  return i.priceCents === undefined ? undefined : Math.round(i.priceCents * i.quantity)
}

export function estimate(items: ShoppingItem[]): { cents: number; missing: number } {
  let cents = 0
  let missing = 0
  for (const i of items) {
    const line = lineTotal(i)
    if (line === undefined) missing += 1
    else cents += line
  }
  return { cents, missing }
}

/** Categories alphabetically, uncategorized last; items by name. */
export function groupItems(items: ShoppingItem[]): { category: string; items: ShoppingItem[] }[] {
  const groups = new Map<string, ShoppingItem[]>()
  for (const i of items) groups.set(i.category, [...(groups.get(i.category) ?? []), i])
  return [...groups]
    .map(([category, list]) => ({ category, items: list.sort((a, b) => a.name.localeCompare(b.name, 'pt-BR')) }))
    .sort((a, b) => {
      if ((a.category === '') !== (b.category === '')) return a.category === '' ? 1 : -1
      return a.category.localeCompare(b.category, 'pt-BR')
    })
}

/** A price history entry is recorded only when the price actually changes. */
export function priceChange(
  item: ShoppingItem,
  cents: number | undefined,
  store: string,
  at: Date = new Date(),
): { priceCents: number | undefined; point?: Omit<PricePoint, 'id'> } {
  if (cents === undefined) return { priceCents: undefined }
  if (cents === item.priceCents) return { priceCents: cents }
  return { priceCents: cents, point: { priceCents: cents, store, observedAt: at, source: 'manual', itemId: item.id } }
}
