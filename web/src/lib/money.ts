/** Money is stored as integer cents everywhere, never floats. */

const brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })

export function formatMoney(cents: number): string {
  return brl.format(cents / 100)
}

/**
 * Parses Brazilian input: "75", "75,5", "1.234,56", "R$ 1.234,56", "-10,00".
 * "." is a thousands separator and "," the decimal separator. Returns null when it isn't a number.
 */
export function parseMoney(text: string): number | null {
  const s = text.replace('R$', '').replace(/\s/g, '')
  if (!s || (s.match(/,/g) ?? []).length > 1) return null
  const negative = s.startsWith('-')
  const body = (negative ? s.slice(1) : s).replace(/\./g, '').replace(',', '.')
  if (!/^\d*\.?\d*$/.test(body) || body === '' || body === '.') return null
  return toCents(body, negative)
}

/** Decimal string ("1234.5") to cents, rounding half up on the third decimal digit. */
function toCents(decimal: string, negative: boolean): number {
  const [int, frac = ''] = decimal.split('.')
  let cents = parseInt(int || '0', 10) * 100 + parseInt((frac + '00').slice(0, 2), 10)
  if (frac.length > 2 && parseInt(frac[2], 10) >= 5) cents += 1
  return negative ? -cents : cents
}

/**
 * Parses amounts from bank files, where either "." or "," can be the decimal mark:
 * "1.234,56", "-50,00", "R$ 12,90", "12.5", "-1234.56", "1,234.56", "(30,00)", "1.234" (thousands).
 */
export function parseStatementAmount(raw: string): number | null {
  let s = raw.replace('R$', '').replace(/\s/g, '')
  let negative = false
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true
    s = s.slice(1, -1)
  }
  if (s.startsWith('-')) {
    negative = !negative
    s = s.slice(1)
  } else if (s.startsWith('+')) {
    s = s.slice(1)
  }
  if (s.endsWith('-')) {
    negative = !negative
    s = s.slice(0, -1)
  }
  const lastComma = s.lastIndexOf(',')
  const lastDot = s.lastIndexOf('.')
  let decimal: string | null = null
  if (lastComma >= 0 && lastDot >= 0) decimal = lastComma > lastDot ? ',' : '.'
  else if (lastComma >= 0) decimal = ','
  else if (lastDot >= 0) decimal = s.length - lastDot - 1 <= 2 ? '.' : null // "1.234" = thousands
  let normalized = ''
  for (const ch of s) {
    if (/\d/.test(ch)) normalized += ch
    else if (ch === decimal) normalized += '.'
  }
  if (!/^\d*\.?\d*$/.test(normalized) || normalized === '' || normalized === '.') return null
  return toCents(normalized, negative)
}
