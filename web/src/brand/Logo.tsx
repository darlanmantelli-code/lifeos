import { useId } from 'react'
import geometry from './geometry.json'

const W = 1000
const leafPath = (() => {
  const pts: string[] = []
  for (let i = 0; i < geometry.leaf.length; i += 2) {
    pts.push(`${(geometry.leaf[i] * W).toFixed(1)} ${(geometry.leaf[i + 1] * W).toFixed(1)}`)
  }
  return `M${pts.join('L')}Z`
})()

const [x1, y1] = geometry.capsule.p1.map((v) => v * W)
const [x2, y2] = geometry.capsule.p2.map((v) => v * W)
const barWidth = geometry.capsule.r * 2 * W
const HEIGHT = geometry.h * W

/** The livo mark: a blue bar and a mint leaf. Vector, so it stays sharp at any size and in both appearances. */
export function LivoMark({ height, mono, className }: { height?: number; mono?: string; className?: string }) {
  const id = useId()
  return (
    <svg
      viewBox={`0 0 ${W} ${HEIGHT}`}
      height={height}
      width={height ? (height * W) / HEIGHT : undefined}
      className={className}
      role="img"
      aria-label="livo"
    >
      {!mono && (
        <defs>
          <linearGradient id={`${id}-b`} gradientUnits="userSpaceOnUse" x1={x1} y1={y1} x2={x2} y2={y2}>
            <stop offset="0" style={{ stopColor: 'var(--mark-blue-top)' }} />
            <stop offset="1" style={{ stopColor: 'var(--mark-blue-bottom)' }} />
          </linearGradient>
          <linearGradient id={`${id}-m`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" style={{ stopColor: 'var(--mark-mint-a)' }} />
            <stop offset="1" style={{ stopColor: 'var(--mark-mint-b)' }} />
          </linearGradient>
        </defs>
      )}
      <path d={leafPath} fill={mono ?? `url(#${id}-m)`} />
      <line x1={x1} y1={y1} x2={x2} y2={y2} strokeWidth={barWidth} strokeLinecap="round" stroke={mono ?? `url(#${id}-b)`} />
    </svg>
  )
}

/** "livo" in heavy rounded type, close to the logo's letterforms. */
export function Wordmark({ size = 30 }: { size?: number }) {
  return (
    <span aria-hidden="true" style={{ fontSize: size, fontWeight: 900, letterSpacing: '-0.015em', color: 'var(--wordmark)', lineHeight: 1 }}>
      livo
    </span>
  )
}

export function BrandLockup({ height = 28 }: { height?: number }) {
  return (
    <span className="row" style={{ gap: height * 0.3 }} aria-label="livo">
      <LivoMark height={height} />
      <Wordmark size={height * 1.15} />
    </span>
  )
}

export const BRAND = { headline: 'Vida inteligente.', tagline: 'Sua vida mais simples.' } as const
