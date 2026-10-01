import type { ModeId } from '../data'

type Props = { mode: ModeId; phase: number; color?: string; missing?: string | null; className?: string }

// Stylised pose skeleton. phase 0..1 animates the current exercise.
export default function Skeleton({ mode, phase, color = '#d4ff3a', missing, className }: Props) {
  const t = Math.sin(phase * Math.PI)
  let lh = { x: 30, y: 62 }
  let rh = { x: 70, y: 62 }
  let lf = { x: 42, y: 118 }
  let rf = { x: 58, y: 118 }
  let lk = { x: 44, y: 100 }
  let rk = { x: 56, y: 100 }
  let hipX = 50
  if (mode === 'dino') {
    lh = { x: 30 - t * 6, y: 62 - t * 44 }
    rh = { x: 70 + t * 6, y: 62 - t * 44 }
    lf = { x: 42 - t * 12, y: 118 }
    rf = { x: 58 + t * 12, y: 118 }
    lk = { x: 44 - t * 6, y: 100 }
    rk = { x: 56 + t * 6, y: 100 }
  } else if (mode === 'lane') {
    hipX = 50 - t * 10
    lf = { x: 30 - t * 6, y: 118 }
    rf = { x: 64, y: 118 }
    lk = { x: 34 - t * 6, y: 98 + t * 4 }
    rk = { x: 58, y: 100 }
  } else {
    lh = { x: 30 - t * 4, y: 62 - t * 48 }
    rh = { x: 70 + t * 4, y: 62 - t * 48 }
  }
  const dim = (limb: string) => (missing === limb ? '#ff3b2f' : color)
  const dash = (limb: string) => (missing === limb ? '3 3' : undefined)
  const J = ({ x, y, c = color }: { x: number; y: number; c?: string }) => (
    <circle cx={x} cy={y} r={2.6} fill="#0b0b0c" stroke={c} strokeWidth={1.6} />
  )
  return (
    <svg viewBox="0 0 100 130" className={className} fill="none" strokeLinecap="round">
      <circle cx={hipX} cy={20} r={8} stroke={color} strokeWidth={2} />
      <g stroke={color} strokeWidth={2.4}>
        <line x1={hipX} y1={30} x2={hipX} y2={76} />
        <line x1={hipX - 12} y1={40} x2={hipX + 12} y2={40} />
        <line x1={hipX - 8} y1={76} x2={hipX + 8} y2={76} />
      </g>
      <g stroke={dim('ARMS')} strokeWidth={2.4} strokeDasharray={dash('ARMS')}>
        <polyline points={`${hipX - 12},40 ${(hipX - 12 + lh.x) / 2},${(40 + lh.y) / 2 + 4} ${lh.x},${lh.y}`} />
        <polyline points={`${hipX + 12},40 ${(hipX + 12 + rh.x) / 2},${(40 + rh.y) / 2 + 4} ${rh.x},${rh.y}`} />
      </g>
      <g stroke={dim('KNEES')} strokeWidth={2.4} strokeDasharray={dash('KNEES')}>
        <line x1={hipX - 8} y1={76} x2={lk.x} y2={lk.y} />
        <line x1={hipX + 8} y1={76} x2={rk.x} y2={rk.y} />
      </g>
      <g stroke={dim('FEET')} strokeWidth={2.4} strokeDasharray={dash('FEET')}>
        <line x1={lk.x} y1={lk.y} x2={lf.x} y2={lf.y} />
        <line x1={rk.x} y1={rk.y} x2={rf.x} y2={rf.y} />
      </g>
      {[lh, rh].map((p, i) => <J key={'h' + i} {...p} c={dim('ARMS')} />)}
      {[lk, rk].map((p, i) => <J key={'k' + i} {...p} c={dim('KNEES')} />)}
      {[lf, rf].map((p, i) => <J key={'f' + i} {...p} c={dim('FEET')} />)}
      <J x={hipX - 12} y={40} />
      <J x={hipX + 12} y={40} />
    </svg>
  )
}
