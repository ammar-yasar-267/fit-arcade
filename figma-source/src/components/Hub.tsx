import { useEffect, useState } from 'react'
import Skeleton from './Skeleton'
import { LEADERBOARD, MODES, PLAYER, type ModeId } from '../data'

type Props = {
  locked: Record<ModeId, boolean>
  onPick: (m: ModeId) => void
  onNav: (s: 'leaderboard' | 'settings') => void
}

const WEEK = [
  { d: 'M', reps: 84 },
  { d: 'T', reps: 120 },
  { d: 'W', reps: 0 },
  { d: 'T', reps: 96 },
  { d: 'F', reps: 142 },
  { d: 'S', reps: 60 },
  { d: 'S', reps: 110 },
]

export default function Hub({ locked, onPick, onNav }: Props) {
  const [sel, setSel] = useState<ModeId>(MODES.find((m) => !locked[m.id])?.id ?? 'dino')
  const [phase, setPhase] = useState(0)
  useEffect(() => {
    const id = setInterval(() => setPhase((p) => (p + 0.04) % 1), 40)
    return () => clearInterval(id)
  }, [])
  const max = Math.max(...WEEK.map((w) => w.reps))

  return (
    <div className="flex h-full flex-col px-5 pt-16 pb-5">
      {/* Identity bar */}
      <header className="flex shrink-0 items-center gap-3">
        <div className="grid h-11 w-11 shrink-0 place-items-center bg-volt font-display text-lg text-ink [clip-path:polygon(50%_0,100%_25%,100%_75%,50%_100%,0_75%,0_25%)]">
          {PLAYER.badge}
        </div>
        <div className="min-w-0 flex-1">
          <div className="truncate font-display text-xl leading-none tracking-wide">{PLAYER.name}</div>
          <div className="mt-1 font-mono text-[10px] text-dim">
            {PLAYER.tag} · LVL {PLAYER.level}
          </div>
        </div>
        <button onClick={() => onNav('leaderboard')} aria-label="Leaderboard" className="group grid h-10 w-10 place-items-center border border-line transition hover:border-volt hover:bg-volt active:scale-95">
          <svg viewBox="0 0 24 24" className="h-5 w-5 text-white transition group-hover:text-ink" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="square"><path d="M9 20V8h6v12M3 20v-7h6M15 20v-9h6v9M2 20h20" /></svg>
        </button>
        <button onClick={() => onNav('settings')} aria-label="Tracking settings" className="group grid h-10 w-10 place-items-center border border-line transition hover:border-volt hover:bg-volt active:scale-95">
          <svg viewBox="0 0 24 24" className="h-5 w-5 text-white transition group-hover:text-ink" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="square"><path d="M4 7h9M17 7h3M4 17h3M11 17h9" /><rect x="13" y="5" width="4" height="4" /><rect x="7" y="15" width="4" height="4" /></svg>
        </button>
      </header>

      {/* Week strip */}
      <div className="mt-6 flex shrink-0 items-end gap-5 bg-panel px-4 py-3.5 ring-1 ring-line">
        <div className="shrink-0">
          <div className="font-mono text-[11px] tracking-widest text-dim">THIS WEEK</div>
          <div className="font-display text-5xl leading-none tabular-nums">
            612<span className="ml-1 text-lg text-dim">REPS</span>
          </div>
        </div>
        <div className="flex h-16 flex-1 items-end gap-2">
          {WEEK.map((w, i) => (
            <div key={i} className="flex flex-1 flex-col items-center gap-1">
              <div
                className="w-full"
                style={{ height: `${Math.max(3, (w.reps / max) * 46)}px`, background: i === 6 ? '#d4ff3a' : w.reps ? '#3a3a3e' : '#1f1f22' }}
              />
              <span className={`font-mono text-[10px] ${i === 6 ? 'text-volt' : 'text-dim'}`}>{w.d}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Daily challenge */}
      <button
        onClick={() => !locked.lane && onPick('lane')}
        className="group mt-3 flex shrink-0 items-center gap-3 bg-panel py-3 pr-3 pl-4 text-left ring-1 ring-line transition hover:ring-volt/60 active:scale-[0.99]"
      >
        <span className="min-w-0 flex-1">
          <span className="font-mono text-[10px] tracking-widest text-dim">
            DAILY CHALLENGE · <span className="text-white/60">7H LEFT</span>
          </span>
          <span className="mt-1 block font-display text-[22px] leading-none uppercase">40 Side lunges</span>
          <span className="mt-1.5 block text-xs font-semibold leading-none text-white/50">
            Under 2:00 <span className="px-1 text-white/20">·</span>
            <span className="text-volt">+500 XP</span>
          </span>
        </span>
        <span className="relative grid h-14 w-14 shrink-0 place-items-center">
          <svg viewBox="0 0 64 64" className="absolute inset-0 -rotate-90">
            <circle cx="32" cy="32" r="28" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="4" />
            <circle cx="32" cy="32" r="28" fill="none" stroke="#d4ff3a" strokeWidth="4" strokeDasharray={`${0.35 * 175.9} 175.9`} />
          </svg>
          <span className="absolute inset-0 flex items-center justify-center font-display text-lg leading-none">
            14<span className="text-xs text-dim">/40</span>
          </span>
        </span>
        <span className="grid h-14 w-9 shrink-0 place-items-center bg-volt text-ink transition group-hover:brightness-110 group-active:scale-95">
          <svg viewBox="0 0 24 24" className="h-4 w-4 translate-x-px" fill="currentColor">
            <path d="M7 4.5v15L19.5 12z" />
          </svg>
        </span>
      </button>

      {/* Game list: every mode visible, selected one expands with a live move preview */}
      <div className="mt-10 flex items-center gap-3">
        <span className="font-display text-2xl leading-none uppercase">Games</span>
        <span className="h-px flex-1 bg-line" />
        <span className="font-mono text-[10px] tracking-widest text-dim">PICK ONE · {MODES.length} MODES</span>
      </div>
      <div className="no-scrollbar flex min-h-0 flex-1 flex-col overflow-y-auto">
        {MODES.map((m) => {
          const active = m.id === sel
          const lk = locked[m.id]
          const rows = LEADERBOARD[m.id]
          const i = rows.findIndex((r) => r.tag === PLAYER.tag)
          return (
            <div key={m.id} className="border-b border-line">
              <button onClick={() => setSel(m.id)} className="flex w-full items-center gap-3 py-3.5 text-left">
                <span className="w-1.5 self-stretch transition-opacity" style={{ background: lk ? '#ff3b2f' : m.color, opacity: active ? 1 : 0.35 }} />
                <span className="min-w-0 flex-1">
                  <span className={`block truncate font-display text-[28px] leading-none uppercase transition-colors ${lk ? 'text-white/30' : active ? '' : 'text-white/60'}`}>{m.exercise}</span>
                  <span className="mt-1 block font-mono text-[10px] tracking-wider" style={{ color: lk ? '#ff3b2f' : active ? m.color : '#8a8a92' }}>
                    {lk ? 'BACK SOON' : m.game.toUpperCase()}
                  </span>
                </span>
                {!lk && (
                  <span className="flex gap-4 text-right leading-none">
                    <span>
                      <span className="block font-mono text-[9px] tracking-widest text-dim">RANK</span>
                      <span className={`font-display text-lg tabular-nums ${active ? '' : 'text-white/50'}`}>{i >= 0 ? `#${i + 1}` : '—'}</span>
                    </span>
                    <span>
                      <span className="block font-mono text-[9px] tracking-widest text-dim">BEST</span>
                      <span className={`font-display text-lg tabular-nums ${active ? '' : 'text-white/50'}`}>{rows[i]?.score.toLocaleString() ?? '—'}</span>
                    </span>
                  </span>
                )}
              </button>
              <div className={`grid transition-all duration-300 ${active ? 'grid-rows-[1fr] pb-4' : 'grid-rows-[0fr]'}`}>
                <div className="overflow-hidden">
                  <div className="flex items-stretch gap-3 pl-[18px]">
                    <div className="relative h-[88px] w-[72px] shrink-0 border border-line bg-[radial-gradient(ellipse_at_50%_30%,#2a2d33,#0b0b0c)]">
                      <Skeleton mode={m.id} phase={lk ? 0 : phase} color={lk ? '#555' : m.color} className="h-full w-full p-1.5" />
                    </div>
                    <div className="flex min-w-0 flex-1 flex-col">
                      <span className="text-sm font-semibold text-white/70">{m.action}</span>
                      <button
                        disabled={lk}
                        onClick={() => onPick(m.id)}
                        className="mt-auto flex items-center justify-center gap-2 px-3 py-2.5 transition hover:brightness-110 active:scale-[0.98] disabled:cursor-not-allowed"
                        style={{ background: lk ? '#2a2a2e' : m.color, color: lk ? '#8a8a92' : '#0b0b0c' }}
                      >
                        {!lk && (
                          <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="currentColor">
                            <path d="M7 4.5v15L19.5 12z" />
                          </svg>
                        )}
                        <span className="font-display text-xl leading-none uppercase tracking-wide">{lk ? 'Under maintenance' : 'Start'}</span>
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )
        })}
        <div className="mt-auto flex items-center gap-3 pt-8 pb-1">
          <span className="h-px flex-1 bg-line" />
          <span className="font-display text-xl leading-none tracking-wider uppercase">
            Fit<span className="text-volt">Arcade</span>
          </span>
          <span className="h-px flex-1 bg-line" />
        </div>
      </div>

    </div>
  )
}
