import { formatMoney } from '../lib/money'

/** Series colors from the brand: blue, mint, graphite-blue family, then warm accents for the long tail. */
export const SERIES = ['#0462d0', '#2bd08f', '#6ba9ff', '#a4e8db', '#26364a', '#f59e0b', '#d92d3a', '#8b5cf6', '#14b8a6', '#94a3b8']

export function Donut({ data, label }: { data: { name: string; cents: number }[]; label: string }) {
  const total = data.reduce((s, d) => s + d.cents, 0)
  if (total <= 0) return null
  const R = 70
  const C = 2 * Math.PI * R
  let offset = 0
  return (
    <div>
      <svg className="chart" viewBox="0 0 200 200" width="100%" style={{ maxWidth: 240, display: 'block', margin: '0 auto' }} role="img" aria-label={label}>
        <g transform="rotate(-90 100 100)">
          {data.map((d, i) => {
            const len = (d.cents / total) * C
            const el = (
              <circle key={d.name} cx="100" cy="100" r={R} fill="none" stroke={SERIES[i % SERIES.length]} strokeWidth="30"
                strokeDasharray={`${Math.max(len - 1.5, 0)} ${C}`} strokeDashoffset={-offset} />
            )
            offset += len
            return el
          })}
        </g>
        <text x="100" y="96" textAnchor="middle" style={{ fontSize: 12 }}>Total</text>
        <text x="100" y="116" textAnchor="middle" style={{ fontSize: 15, fontWeight: 800, fill: 'var(--ink)' }}>{formatMoney(total)}</text>
      </svg>
      <div className="legend">
        {data.map((d, i) => (
          <span key={d.name}><i style={{ background: SERIES[i % SERIES.length] }} />{d.name} · {formatMoney(d.cents)}</span>
        ))}
      </div>
    </div>
  )
}

export interface Point { x: Date; y: number }

/** Step line with a filled area. y values are plain numbers (cents or any unit); `format` renders the axis. */
export function LineChart({ points, label, format, color = 'var(--accent)', height = 200 }: {
  points: Point[]; label: string; format: (n: number) => string; color?: string; height?: number
}) {
  if (points.length < 2) return null
  const W = 600
  const pad = { l: 8, r: 8, t: 12, b: 22 }
  const ys = points.map((p) => p.y)
  const min = Math.min(0, ...ys)
  const max = Math.max(...ys, min + 1)
  const sx = (i: number) => pad.l + (i / (points.length - 1)) * (W - pad.l - pad.r)
  const sy = (v: number) => pad.t + (1 - (v - min) / (max - min)) * (height - pad.t - pad.b)
  const line = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${sx(i).toFixed(1)} ${sy(p.y).toFixed(1)}`).join('')
  const area = `${line}L${sx(points.length - 1)} ${sy(min)}L${sx(0)} ${sy(min)}Z`
  const ticks = [0, Math.floor((points.length - 1) / 2), points.length - 1]
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${height}`} width="100%" role="img" aria-label={label}>
      <line x1={pad.l} x2={W - pad.r} y1={sy(0)} y2={sy(0)} stroke="var(--hair)" />
      <path d={area} fill={color} opacity="0.12" />
      <path d={line} fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round" />
      <text x={pad.l} y={pad.t + 8}>{format(max)}</text>
      {ticks.map((i) => (
        <text key={i} x={sx(i)} y={height - 5} textAnchor={i === 0 ? 'start' : i === points.length - 1 ? 'end' : 'middle'}>
          {points[i].x.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }).replace('.', '')}
        </text>
      ))}
    </svg>
  )
}

export function Bars({ data, label, color = 'var(--growth)', height = 180, target }: {
  data: { x: Date; y: number }[]; label: string; color?: string; height?: number; target?: number
}) {
  if (data.length === 0) return null
  const W = 600
  const pad = { l: 8, r: 8, t: 12, b: 22 }
  const max = Math.max(...data.map((d) => d.y), target ?? 0, 1)
  const slot = (W - pad.l - pad.r) / data.length
  const bw = Math.min(slot * 0.7, 28)
  const sy = (v: number) => pad.t + (1 - v / max) * (height - pad.t - pad.b)
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${height}`} width="100%" role="img" aria-label={label}>
      <line x1={pad.l} x2={W - pad.r} y1={sy(0)} y2={sy(0)} stroke="var(--hair)" />
      {target !== undefined && <line x1={pad.l} x2={W - pad.r} y1={sy(target)} y2={sy(target)} stroke="var(--muted)" strokeDasharray="5 4" />}
      {data.map((d, i) => (
        <rect key={i} x={pad.l + i * slot + (slot - bw) / 2} y={sy(d.y)} width={bw} height={sy(0) - sy(d.y)} rx="4" fill={color} />
      ))}
      {[0, data.length - 1].map((i) => (
        <text key={i} x={pad.l + i * slot + slot / 2} y={height - 5} textAnchor={i === 0 ? 'start' : 'end'}>
          {data[i].x.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }).replace('.', '')}
        </text>
      ))}
    </svg>
  )
}

/** Income vs expense per month. */
export function MonthlyBars({ data, label }: { data: { month: Date; income: number; expense: number }[]; label: string }) {
  const W = 600
  const height = 200
  const pad = { l: 8, r: 8, t: 14, b: 24 }
  const max = Math.max(...data.flatMap((d) => [d.income, d.expense]), 1)
  const slot = (W - pad.l - pad.r) / data.length
  const bw = Math.min(slot * 0.32, 30)
  const sy = (v: number) => pad.t + (1 - v / max) * (height - pad.t - pad.b)
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${height}`} width="100%" role="img" aria-label={label}>
      <line x1={pad.l} x2={W - pad.r} y1={sy(0)} y2={sy(0)} stroke="var(--hair)" />
      {data.map((d, i) => {
        const cx = pad.l + i * slot + slot / 2
        return (
          <g key={i}>
            <rect x={cx - bw - 2} y={sy(d.income)} width={bw} height={sy(0) - sy(d.income)} rx="4" fill="var(--growth)" />
            <rect x={cx + 2} y={sy(d.expense)} width={bw} height={sy(0) - sy(d.expense)} rx="4" fill="var(--expense)" />
            <text x={cx} y={height - 6} textAnchor="middle">{d.month.toLocaleDateString('pt-BR', { month: 'short' }).replace('.', '')}</text>
          </g>
        )
      })}
    </svg>
  )
}
