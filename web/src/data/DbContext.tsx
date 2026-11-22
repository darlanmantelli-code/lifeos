import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import { DEMO_DB, LivoDB, REAL_DB } from './db'
import { ensureDefaults } from './actions'
import { seedDemo } from './demo'
import { wipe } from './backup'

interface Ctx {
  db: LivoDB
  demo: boolean
  setDemo: (on: boolean) => void
}

const DbCtx = createContext<Ctx | null>(null)
let opening: Promise<unknown> = Promise.resolve()
const DEMO_KEY = 'livo.demo'

/** Opens the real database, or a fresh in-browser demo database when demo mode is on. They never mix. */
export function DbProvider({ children }: { children: ReactNode }) {
  const [demo, setDemoState] = useState(() => localStorage.getItem(DEMO_KEY) === '1')
  const [db, setDb] = useState<LivoDB | null>(null)
  const previous = useRef<LivoDB | null>(null)

  useEffect(() => {
    let cancelled = false
    // Openings run one at a time: React runs effects twice in development, and two overlapping demo seeds
    // would write the fictitious data twice. A cancelled opening is skipped before it touches the database.
    const job = opening.then(async () => {
      if (cancelled) return
      const next = new LivoDB(demo ? DEMO_DB : REAL_DB)
      if (demo) {
        await wipe(next)
        await seedDemo(next)
      } else {
        await ensureDefaults(next)
      }
      if (cancelled) return next.close()
      previous.current?.close()
      previous.current = next
      setDb(next)
    })
    opening = job.catch(() => undefined)
    return () => {
      cancelled = true
    }
  }, [demo])

  useEffect(() => {
    // Ask the browser not to evict the data under storage pressure. Best effort; no prompt is shown.
    void navigator.storage?.persist?.()
  }, [])

  const setDemo = (on: boolean) => {
    localStorage.setItem(DEMO_KEY, on ? '1' : '0')
    setDb(null)
    setDemoState(on)
  }

  if (!db) return <div style={{ padding: 40, textAlign: 'center' }} role="status">Carregando…</div>
  return <DbCtx.Provider value={{ db, demo, setDemo }}>{children}</DbCtx.Provider>
}

export function useDb(): Ctx {
  const ctx = useContext(DbCtx)
  if (!ctx) throw new Error('useDb outside DbProvider')
  return ctx
}

/** Live query on the current database. Returns `fallback` while loading, then re-renders on every change. */
export function useLive<T>(query: (db: LivoDB) => Promise<T>, fallback: T, deps: unknown[] = []): T {
  const { db } = useDb()
  return useLiveQuery(() => query(db), [db, ...deps], fallback) as T
}
