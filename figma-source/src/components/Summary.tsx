import { useEffect, useState } from 'react'
import { LEADERBOARD, fmtTime, type Mode, type Result } from '../data'

type Props = { mode: Mode; result: Result; onAgain: () => void; onHub: () => void }

export default function Summary({ mode, result, onAgain, onHub }: Props) {
  const [count, setCount] = useState(10)
  const [auto, setAuto] = useState(true)
  const board = LEADERBOARD[mode.id]
  const rank = board.filter((r) => r.score > result.score).length + 1
  const best = board.find((r) => r.tag === '#0423')?.score ?? 0
  const pb = result.score > best

  useEffect(() => {
    if (!auto) return
    if (count <= 0) return onAgain()
    const t = setTimeout(() => setCount((c) => c - 1), 1000)
    return () => clearTimeout(t)
  }, [count, auto, onAgain])

  const Stat = ({ label, value, unit }: { label: string; value: string; unit?: string }) => (
    <div className="border-t border-line pt-2">
      <div className="font-mono text-[10px] tracking-widest text-dim">{label}</div>
      <div className="font-display text-4xl leading-none tabular-nums">
        {value}
        {unit && <span className="ml-1 text-xl text-dim">{unit}</span>}
      </div>
    </div>
  )

  return (
    <div className="no-scrollbar flex h-full flex-col overflow-y-auto px-5 pt-16 pb-5">
      <div className="font-mono text-[10px] tracking-widest" style={{ color: mode.color }}>
        {mode.code} / {mode.game.toUpperCase()} · SESSION COMPLETE
      </div>
      <h1 className="mt-1 font-display text-[44px] leading-[0.9] uppercase">
        Work
        <br />
        done.
      </h1>

      <div className="mt-4 flex items-end gap-3">
        <div className="font-display text-[112px] leading-[0.8] tabular-nums" style={{ color: mode.color }}>
          {result.reps}
        </div>
        <div className="pb-2 font-display text-2xl leading-none uppercase">
          valid
          <br />
          {mode.exercise}
        </div>
      </div>

      <div className="mt-5 grid grid-cols-2 gap-x-4 gap-y-4">
        <Stat label="ACTIVE TIME" value={fmtTime(result.seconds)} />
        <Stat label="SCORE" value={result.score.toLocaleString()} />
        <Stat label="TRACKING LATENCY" value={String(result.latency)} unit="ms" />
        <Stat label="GLOBAL RANK" value={`#${rank}`} />
      </div>

      <div className={`mt-5 flex items-center gap-3 px-4 py-3 ${pb ? 'bg-volt text-ink' : 'border border-line'}`}>
        <span className="font-display text-2xl">{pb ? '★' : '✓'}</span>
        <div className="leading-tight">
          <div className="font-display text-xl uppercase">{pb ? 'New personal best!' : 'Score submitted'}</div>
          <div className={`font-mono text-[10px] ${pb ? 'text-ink/70' : 'text-dim'}`}>
            {pb ? `BEAT ${best.toLocaleString()} · ` : `PB ${best.toLocaleString()} · `}POSTED TO LEADERBOARD
          </div>
        </div>
      </div>

      <div className="mt-auto flex flex-col gap-3 pt-5">
        <button onClick={onAgain} className="relative overflow-hidden bg-white py-4 font-display text-3xl text-ink uppercase">
          {auto && <span className="absolute inset-y-0 left-0 bg-volt transition-all duration-1000 ease-linear" style={{ width: `${(1 - count / 10) * 100}%` }} />}
          <span className="relative">Play again {auto && `· ${count}`}</span>
        </button>
        <div className="flex gap-3">
          <button onClick={onHub} className="flex-1 border border-line py-3 font-display text-lg uppercase hover:bg-white/5">
            Return to hub
          </button>
          {auto && (
            <button onClick={() => setAuto(false)} className="border border-line px-4 font-mono text-[10px] text-dim hover:text-white">
              CANCEL AUTO
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
