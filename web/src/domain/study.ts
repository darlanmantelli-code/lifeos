import { addDays, startOfDay } from '../lib/dates'
import type { FocusSession, Study } from './types'

/** Spaced review: days until the next review after each successful one. */
export const REVIEW_INTERVALS = [1, 3, 7, 14, 30, 60] as const

export const STUDY_KINDS = [['curso', 'Curso'], ['livro', 'Livro'], ['assunto', 'Assunto']] as const

export const totalMinutes = (sessions: FocusSession[], studyId: number): number =>
  sessions.filter((s) => s.studyId === studyId).reduce((sum, s) => sum + s.minutes, 0)

export const minutesSince = (sessions: FocusSession[], start: Date): number =>
  sessions.filter((s) => s.start >= start).reduce((sum, s) => sum + s.minutes, 0)

export function isReviewDue(s: Study, now: Date = new Date()): boolean {
  return !s.archived && s.nextReview !== undefined && startOfDay(s.nextReview) <= startOfDay(now)
}

/** Starts reviews (first one tomorrow) or advances to the next interval, capped at the last one. */
export function markReviewed(s: Study, now: Date = new Date()): Pick<Study, 'reviewStage' | 'nextReview'> {
  const stage = s.reviewStage === undefined ? 0 : Math.min(s.reviewStage + 1, REVIEW_INTERVALS.length - 1)
  return { reviewStage: stage, nextReview: addDays(startOfDay(now), REVIEW_INTERVALS[stage]) }
}

export const stopReviews = (): Pick<Study, 'reviewStage' | 'nextReview'> => ({ reviewStage: undefined, nextReview: undefined })

// ---- Pomodoro: derived from wall-clock dates, so it stays right while the tab is in the background ----

export type PomodoroPhase = 'idle' | 'focus' | 'pause'

export interface PomodoroState {
  phase: PomodoroPhase
  startedAt?: number
  endsAt?: number
  studyId?: number
}

export const IDLE: PomodoroState = { phase: 'idle' }

export const startPhase = (phase: Exclude<PomodoroPhase, 'idle'>, minutes: number, now: number, studyId?: number): PomodoroState => ({
  phase, startedAt: now, endsAt: now + minutes * 60_000, studyId,
})

export const remainingMs = (s: PomodoroState, now: number): number => (s.endsAt === undefined ? 0 : Math.max(0, s.endsAt - now))

export const isFinished = (s: PomodoroState, now: number): boolean => s.phase !== 'idle' && remainingMs(s, now) === 0

export function clock(ms: number): string {
  const total = Math.ceil(ms / 1000)
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`
}

/** Whole minutes spent in a focus block stopped early; 0 if under a minute. */
export const minutesSpent = (s: PomodoroState, now: number): number =>
  s.phase === 'focus' && s.startedAt !== undefined ? Math.floor((now - s.startedAt) / 60_000) : 0
