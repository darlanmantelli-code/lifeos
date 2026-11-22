import { parseStatementAmount } from '../lib/money'
import type { Category, Transaction } from './types'

/** One line of a bank statement, before it becomes a transaction. */
export interface StatementLine {
  id: string
  date: Date
  /** Signed: negative = money out. */
  amountCents: number
  description: string
}

/** Lowercase, without accents or extra spaces: "Histórico " becomes "historico". */
export const normalize = (s: string): string =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().split(/\s+/).filter(Boolean).join(' ')

const localNoon = (y: number, m: number, d: number): Date => new Date(y, m - 1, d, 12)

export const syntheticId = (date: Date, cents: number, desc: string): string =>
  `${Math.floor(date.getTime() / 86_400_000)}|${cents}|${normalize(desc)}`

export class StatementError extends Error {}

export function parseStatement(text: string): StatementLine[] {
  const lines = text.toUpperCase().includes('<STMTTRN>') ? parseOFX(text) : parseCSV(text)
  if (lines.length === 0) throw new StatementError('Nenhum lançamento encontrado no arquivo.')
  return lines
}

// ---- OFX (1.x SGML with unclosed tags, and 2.x XML) ----

/** "20261105", "20261105120000[-3:BRT]". */
export function ofxDate(s: string): Date | null {
  const digits = /^\d+/.exec(s)?.[0] ?? ''
  if (digits.length < 8) return null
  return localNoon(Number(digits.slice(0, 4)), Number(digits.slice(4, 6)), Number(digits.slice(6, 8)))
}

export function parseOFX(text: string): StatementLine[] {
  return text
    .split('<STMTTRN>')
    .slice(1)
    .flatMap((raw) => {
      const block = raw.split('</STMTTRN>')[0]
      const tag = (name: string): string | undefined => {
        const m = new RegExp(`<${name}>([^<\\r\\n]*)`, 'i').exec(block)
        const v = m?.[1].trim()
        return v ? v : undefined
      }
      const dateRaw = tag('DTPOSTED')
      const amountRaw = tag('TRNAMT')
      const date = dateRaw ? ofxDate(dateRaw) : null
      const cents = amountRaw ? parseStatementAmount(amountRaw) : null
      if (!date || cents === null) return []
      const description = tag('MEMO') ?? tag('NAME') ?? 'Lançamento'
      return [{ id: tag('FITID') ?? syntheticId(date, cents, description), date, amountCents: cents, description }]
    })
}

// ---- CSV ----

/** Handles quoted fields: "Padaria; centro";-12,50 */
export function splitCSV(line: string, delimiter: string): string[] {
  const fields: string[] = []
  let current = ''
  let quoted = false
  for (const ch of line) {
    if (ch === '"') quoted = !quoted
    else if (ch === delimiter && !quoted) {
      fields.push(current)
      current = ''
    } else current += ch
  }
  fields.push(current)
  return fields.map((f) => f.trim())
}

/** dd/MM/yyyy, dd/MM/yy, dd-MM-yyyy or ISO yyyy-MM-dd. */
export function csvDate(s: string): Date | null {
  const parts = s.trim().split(/[/\-T ]/).filter(Boolean)
  if (parts.length < 3) return null
  const [a, b, c] = parts.slice(0, 3).map(Number)
  if ([a, b, c].some(Number.isNaN)) return null
  const [y, m, d] = parts[0].length === 4 ? [a, b, c] : [c < 100 ? 2000 + c : c, b, a]
  if (m < 1 || m > 12 || d < 1 || d > 31) return null
  return localNoon(y, m, d)
}

export function parseCSV(text: string): StatementLine[] {
  const rows = text.split(/\r?\n/).filter((r) => r.trim() !== '')
  if (rows.length === 0) throw new StatementError('Nenhum lançamento encontrado no arquivo.')
  const headerLine = rows[0]
  const count = (ch: string) => headerLine.split(ch).length - 1
  const delimiter = count(';') >= count(',') ? ';' : ','
  const header = splitCSV(headerLine, delimiter).map(normalize)
  const column = (names: string[]) => header.findIndex((h) => names.some((n) => h === n || h.startsWith(n)))
  const dateCol = column(['data', 'date', 'dt'])
  const descCol = column(['descricao', 'historico', 'lancamento', 'title', 'estabelecimento', 'description', 'memo'])
  const valueCol = column(['valor', 'quantia', 'amount', 'value', 'montante'])
  if (dateCol < 0 || descCol < 0 || valueCol < 0) {
    throw new StatementError(`Não encontrei as colunas de data, descrição e valor. Cabeçalho: ${headerLine}`)
  }
  return rows.slice(1).flatMap((row) => {
    const f = splitCSV(row, delimiter)
    if (f.length <= Math.max(dateCol, descCol, valueCol)) return []
    const date = csvDate(f[dateCol])
    const cents = parseStatementAmount(f[valueCol])
    if (!date || cents === null) return []
    const description = f[descCol].trim() || 'Lançamento'
    return [{ id: syntheticId(date, cents, description), date, amountCents: cents, description }]
  })
}

// ---- Category suggestion ----

const KEYWORDS: ReadonlyArray<readonly [string, readonly string[]]> = [
  ['Transporte', ['posto', 'combust', 'ipiranga', 'shell', 'uber', '99app', '99 ', 'estaciona', 'pedagio', 'sem parar', 'metro', 'onibus']],
  ['Alimentação', ['ifood', 'restaurante', 'padaria', 'mercado', 'supermerc', 'acougue', 'lanchonete', 'pizzaria', 'hortifruti', 'atacad', 'rappi']],
  ['Assinaturas', ['netflix', 'spotify', 'disney', 'prime video', 'amazon prime', 'youtube', 'hbo', 'max.com', 'icloud', 'apple.com', 'google one']],
  ['Saúde', ['farmacia', 'drogaria', 'droga', 'raia', 'pague menos', 'hospital', 'clinica', 'laborat', 'academia', 'smart fit']],
  ['Moradia', ['aluguel', 'condominio', 'energia', 'enel', 'cemig', 'copel', 'sabesp', 'agua', 'gas ', 'internet', 'vivo', 'claro', 'tim ']],
  ['Educação', ['escola', 'faculdade', 'curso', 'udemy', 'alura', 'livraria']],
  ['Lazer', ['cinema', 'ingresso', 'show', 'steam', 'playstation', 'xbox', 'bar ']],
  ['Impostos e taxas', ['iof', 'tarifa', 'anuidade', 'juros', 'imposto', 'iptu', 'ipva', 'darf']],
  ['Salário', ['salario', 'folha', 'pagamento de salario']],
  ['Rendimentos', ['rendimento', 'dividendo', 'juros sobre capital', 'resgate']],
]

/** A category the user already used for the same description wins over keywords. */
export function suggestCategory(
  description: string,
  isIncome: boolean,
  categories: Category[],
  history: Transaction[],
): Category | undefined {
  const wanted = isIncome ? 'receita' : 'despesa'
  const byId = new Map(categories.map((c) => [c.id!, c]))
  const key = normalize(description)
  for (const t of history) {
    const cat = t.categoryId !== undefined ? byId.get(t.categoryId) : undefined
    if (cat?.kind === wanted && normalize(t.title) === key) return cat
  }
  const padded = `${key} `
  for (const [name, words] of KEYWORDS) {
    if (words.some((w) => padded.includes(w))) {
      const match = categories.find((c) => c.parentId === undefined && c.kind === wanted && c.name === name)
      if (match) return match
    }
  }
  return undefined
}
