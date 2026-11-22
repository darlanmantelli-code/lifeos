import { toISO } from '../lib/dates'
import type { LivoDB } from './db'

/**
 * JSON backup, identical in shape to the iOS app's export (Settings > Seus dados), so files move both ways.
 * Section names are Portuguese; dates are ISO 8601 UTC without milliseconds; ids that other rows point to
 * (accounts, categories, goals, habits, lists, items, studies) are kept as-is.
 */
export const BACKUP_VERSION = 1

type Row = Record<string, unknown> & { id?: number }

/** section name -> table name + date fields + whether the DTO carries an `id`. */
const SECTIONS = [
  { section: 'contas', table: 'accounts', dates: ['createdAt'], withId: true },
  { section: 'categorias', table: 'categories', dates: [], withId: true },
  { section: 'lancamentos', table: 'transactions', dates: ['date', 'createdAt'], withId: false },
  { section: 'orcamentos', table: 'budgets', dates: [], withId: false },
  { section: 'metas', table: 'goals', dates: ['deadline', 'createdAt'], withId: true },
  { section: 'etapas', table: 'goalSteps', dates: [], withId: false },
  { section: 'tarefas', table: 'tasks', dates: ['due', 'doneAt', 'createdAt'], withId: false },
  { section: 'habitos', table: 'habits', dates: ['createdAt'], withId: true },
  { section: 'registrosHabitos', table: 'checkIns', dates: ['date'], withId: false },
  { section: 'listas', table: 'lists', dates: ['createdAt'], withId: true },
  { section: 'itens', table: 'items', dates: ['boughtAt', 'createdAt'], withId: true },
  { section: 'precos', table: 'prices', dates: ['observedAt'], withId: false },
  { section: 'saude', table: 'health', dates: ['date', 'createdAt'], withId: false },
  { section: 'metasSaude', table: 'healthTargets', dates: [], withId: false },
  { section: 'historicoIA', table: 'aiLog', dates: ['date'], withId: false },
  { section: 'automacoes', table: 'rules', dates: ['createdAt'], withId: false },
  { section: 'execucoesAutomacoes', table: 'runs', dates: ['date'], withId: false },
  { section: 'estudos', table: 'studies', dates: ['nextReview', 'createdAt'], withId: true },
  { section: 'sessoesFoco', table: 'focus', dates: ['start'], withId: false },
] as const

/** Fields that exist only in the web app. */
const WEB_ONLY: Record<string, string[]> = { transactions: ['externalID'] }

export class BackupError extends Error {}

export type BackupFile = { app: 'livo'; versao: number; exportadoEm: string } & Record<string, unknown>

const table = (db: LivoDB, name: string) => (db as unknown as Record<string, { toArray(): Promise<Row[]> }>)[name]

export async function exportBackup(db: LivoDB, now: Date = new Date()): Promise<BackupFile> {
  const file: BackupFile = { app: 'livo', versao: BACKUP_VERSION, exportadoEm: toISO(now) }
  for (const s of SECTIONS) {
    const rows = await table(db, s.table).toArray()
    file[s.section] = rows.map((row) => {
      const out: Row = {}
      for (const [k, v] of Object.entries(row)) {
        if (v === undefined || (k === 'id' && !s.withId) || WEB_ONLY[s.table]?.includes(k)) continue
        out[k] = (s.dates as readonly string[]).includes(k) && v instanceof Date ? toISO(v) : v
      }
      return out
    })
  }
  return file
}

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

/** Validates before anything is touched. Missing sections are treated as empty (older files lack some). */
export function parseBackup(text: string): BackupFile {
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch {
    throw new BackupError('O arquivo não é um backup válido do livo.')
  }
  if (!isRecord(data) || data.app !== 'livo') throw new BackupError('O arquivo não é um backup do livo.')
  if (typeof data.versao !== 'number' || data.versao > BACKUP_VERSION) {
    throw new BackupError('Backup feito por uma versão mais nova do livo. Atualize o app.')
  }
  for (const s of SECTIONS) {
    const v = data[s.section]
    if (v !== undefined && v !== null && !Array.isArray(v)) throw new BackupError(`Seção "${s.section}" inválida.`)
  }
  return data as BackupFile
}

function reviveDates(row: Row, dates: readonly string[]): Row {
  const out: Row = { ...row }
  for (const f of dates) {
    const v = out[f]
    if (typeof v === 'string') {
      const d = new Date(v)
      if (Number.isNaN(d.getTime())) throw new BackupError(`Data inválida em "${f}": ${v}`)
      out[f] = d
    } else if (v === null) delete out[f]
  }
  for (const [k, v] of Object.entries(out)) if (v === null) delete out[k]
  return out
}

/** Replaces everything in `db` with the file's contents, in one transaction (all or nothing). */
export async function restoreBackup(db: LivoDB, file: BackupFile): Promise<void> {
  const prepared = SECTIONS.map((s) => ({
    s,
    rows: ((file[s.section] as Row[] | undefined | null) ?? []).map((r) => reviveDates(r, s.dates)),
  }))
  await db.transaction('rw', db.allTables, async () => {
    for (const t of db.allTables) await t.clear()
    for (const { s, rows } of prepared) {
      if (rows.length) await db.table(s.table).bulkAdd(rows)
    }
  })
}

export async function wipe(db: LivoDB): Promise<void> {
  await db.transaction('rw', db.allTables, async () => {
    for (const t of db.allTables) await t.clear()
  })
}

/** Section keys a valid iOS file must be able to decode (used by tests to guard the contract). */
export const SECTION_NAMES = SECTIONS.map((s) => s.section)
