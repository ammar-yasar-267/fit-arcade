import { useEffect, useRef, useState } from 'react'
import { fmtTime, type Mode, type Result } from '../data'
import Skeleton from './Skeleton'

const DURATION = 32 // simulated session length (s)

type Flash = { id: number; ok: boolean }

export default function Play({ mode, onEnd }: { mode: Mode; onEnd: (r: Result) => void }) {
  const [, force] = useState(0)
  const [paused, setPaused] = useState(false)
  const [flash, setFlash] = useState<Flash | null>(null)
  const s = useRef({ started: false, t: 0, reps: 0, score: 0, lastRep: -9, lane: 1, y: 50, vy: 0, nextRep: 2.6, wall: 0 })
  const pausedRef = useRef(false)
  pausedRef.current = paused

  useEffect(() => {
    let raf = 0
    let prev = performance.now()
    const loop = (now: number) => {
      const dt = Math.min(0.05, (now - prev) / 1000)
      prev = now
      const g = s.current
      if (!pausedRef.current) {
        g.wall += dt
        if (g.started) {
          g.t += dt
          g.score += dt * (40 + g.t * 4)
          if (mode.id === 'flappy') {
            g.vy += 60 * dt
            g.y = Math.max(8, Math.min(88, g.y + g.vy * dt))
          }
        }
        if (g.wall >= g.nextRep) {
          const ok = Math.random() > 0.15
          if (!g.started) g.started = true
          if (ok) {
            g.reps += 1
            g.score += 120
            g.lastRep = g.t
            if (mode.id === 'lane') g.lane = g.lane === 0 ? 2 : g.lane === 2 ? 0 : Math.random() > 0.5 ? 0 : 2
            if (mode.id === 'flappy') g.vy = -38
          }
          setFlash({ id: g.wall, ok })
          g.nextRep = g.wall + 0.9 + Math.random() * 0.6
        }
        if (g.t >= DURATION) {
          onEnd({ reps: g.reps, seconds: Math.round(g.t), score: Math.round(g.score), latency: 38 + Math.round(Math.random() * 14) })
          return
        }
      }
      force((n) => n + 1)
      raf = requestAnimationFrame(loop)
    }
    raf = requestAnimationFrame(loop)
    return () => cancelAnimationFrame(raf)
  }, [mode.id, onEnd])

  const g = s.current
  const since = g.t - g.lastRep
  const repPhase = g.started ? Math.max(0, 1 - since / 0.6) : (Math.sin(g.wall * 2) + 1) / 6

  return (
    <div className="relative h-full overflow-hidden bg-ink select-none" onClick={() => setPaused(true)}>
      {/* GAME CANVAS */}
      <div className="absolute inset-0">
        {mode.id === 'dino' && <Dino t={g.t} jump={g.started ? Math.max(0, Math.sin(Math.min(1, since / 0.6) * Math.PI)) : 0} />}
        {mode.id === 'lane' && <Lanes t={g.t} lane={g.lane} />}
        {mode.id === 'flappy' && <Flappy t={g.t} y={g.y} />}
      </div>

      {/* HUD */}
      <div className="absolute inset-x-0 top-0 bg-gradient-to-b from-ink via-ink/80 to-transparent px-5 pt-14 pb-10">
        <div className="flex items-start justify-between">
          <div>
            <div className="font-mono text-[10px] tracking-widest text-dim">REPS</div>
            <div className="font-display text-[92px] leading-[0.85] tabular-nums" style={{ color: mode.color }}>
              {g.reps}
            </div>
          </div>
          <div className="text-right">
            <div className="font-mono text-[10px] tracking-widest text-dim">TIME</div>
            <div className="font-display text-5xl leading-none tabular-nums">{fmtTime(g.t)}</div>
            <div className="mt-3 font-mono text-[10px] tracking-widest text-dim">SCORE</div>
            <div className="font-display text-4xl leading-none tabular-nums">{Math.round(g.score).toLocaleString()}</div>
          </div>
        </div>
        <div className="mt-2 h-1.5 bg-white/10">
          <div className="h-full" style={{ width: `${(g.t / DURATION) * 100}%`, background: mode.color }} />
        </div>
      </div>

      {/* Rep feedback: full-bleed edge glow + badge */}
      {flash && (
        <div key={flash.id} className="pointer-events-none absolute inset-0">
          <div className="absolute inset-0 animate-pop" style={{ boxShadow: `inset 0 0 0 10px ${flash.ok ? '#d4ff3a' : '#ff3b2f'}` }} />
          <div className="absolute inset-x-0 top-[44%] flex justify-center">
            <div
              className="animate-pop px-5 py-2 font-display text-5xl uppercase text-ink"
              style={{ background: flash.ok ? '#d4ff3a' : '#ff3b2f' }}
            >
              {flash.ok ? '+1 Rep' : 'Go deeper'}
            </div>
          </div>
        </div>
      )}

      {/* PIP camera */}
      <div className="absolute right-3 bottom-3 h-36 w-24 overflow-hidden border-2 border-white/80 bg-[radial-gradient(ellipse_at_50%_30%,#33363d,#111)]">
        <Skeleton mode={mode.id} phase={repPhase} color={mode.color} className="h-full w-full p-2" />
        <div className="absolute top-1 left-1 flex items-center gap-1 font-mono text-[8px]">
          <span className="h-1.5 w-1.5 rounded-full bg-volt" /> IN FRAME
        </div>
      </div>

      {/* Primed state */}
      {!g.started && (
        <div className="absolute inset-0 grid place-items-center bg-ink/70">
          <div className="text-center">
            <div className="font-mono text-xs tracking-[0.3em] text-dim">READY · STEP BACK</div>
            <div className="mt-2 font-display text-[64px] leading-[0.9] uppercase">
              First rep
              <br />
              <span style={{ color: mode.color }}>starts it</span>
            </div>
            <div className="mt-4 animate-bob text-xl font-bold uppercase">Do 1 {mode.exercise.replace(/s$/, '')}</div>
          </div>
        </div>
      )}

      {!paused && g.started && (
        <div className="absolute top-9 inset-x-0 text-center font-mono text-[9px] text-white/40">TAP ANYWHERE TO PAUSE</div>
      )}

      {paused && (
        <div className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-4 bg-ink/90 stripes" onClick={(e) => e.stopPropagation()}>
          <div className="font-display text-[80px] leading-none uppercase">Paused</div>
          <div className="font-mono text-xs text-dim">TIMERS FROZEN · {g.reps} REPS · {fmtTime(g.t)}</div>
          <button onClick={() => setPaused(false)} className="mt-4 w-56 bg-volt py-4 font-display text-2xl text-ink uppercase">
            Resume
          </button>
          <button
            onClick={() => onEnd({ reps: g.reps, seconds: Math.round(g.t), score: Math.round(g.score), latency: 42 })}
            className="w-56 border border-white/40 py-3 font-display text-xl uppercase"
          >
            End workout
          </button>
        </div>
      )}
    </div>
  )
}

function Ground({ t, speed }: { t: number; speed: number }) {
  return (
    <div
      className="absolute inset-x-0 bottom-0 h-[26%] border-t-4 border-volt bg-[#111214]"
      style={{
        backgroundImage: 'repeating-linear-gradient(90deg, #2a2a2e 0 3px, transparent 3px 40px)',
        backgroundPositionX: `${-t * speed}px`,
      }}
    />
  )
}

function Dino({ t, jump }: { t: number; jump: number }) {
  const speed = 180 + t * 6
  const obs = [0, 0.45, 0.8].map((o, i) => ({ x: 1.1 - ((t * speed) / 420 + o) % 1.4, tall: i % 2 === 0 }))
  return (
    <div className="absolute inset-0 bg-[linear-gradient(#0b0b0c,#1a1c10)]">
      <div className="absolute top-[40%] right-10 h-16 w-16 rounded-full bg-volt/15" />
      <Ground t={t} speed={speed} />
      {obs.map((o, i) => (
        <div key={i} className="absolute bottom-[26%] bg-signal" style={{ left: `${o.x * 100}%`, width: 18, height: o.tall ? 56 : 34 }}>
          <div className="absolute -left-2 top-3 h-4 w-2 bg-signal" />
        </div>
      ))}
      <div
        className="absolute left-[18%] bottom-[26%] grid h-16 w-14 place-items-center bg-volt font-display text-3xl text-ink"
        style={{ transform: `translateY(${-jump * 130}px)` }}
      >
        ▲
      </div>
    </div>
  )
}

function Lanes({ t, lane }: { t: number; lane: number }) {
  const items = [0, 0.33, 0.66].map((o, i) => ({ y: ((t * 0.45 + o) % 1.2) - 0.1, lane: (i * 2 + Math.floor(t * 0.45 + o)) % 3, coin: i === 1 }))
  return (
    <div className="absolute inset-0 grid grid-cols-3 bg-[#07141a]">
      {[0, 1, 2].map((l) => (
        <div
          key={l}
          className="relative border-x border-cyan/15"
          style={{ backgroundImage: 'repeating-linear-gradient(180deg, rgba(58,224,255,.12) 0 30px, transparent 30px 70px)', backgroundPositionY: `${t * 240}px` }}
        />
      ))}
      {items.map((it, i) => (
        <div
          key={i}
          className={`absolute grid h-12 w-12 -translate-x-1/2 place-items-center font-display text-xl text-ink ${it.coin ? 'rounded-full bg-volt' : 'bg-signal'}`}
          style={{ left: `${(it.lane + 0.5) * 33.33}%`, top: `${it.y * 100}%` }}
        >
          {it.coin ? '+' : '✕'}
        </div>
      ))}
      <div
        className="absolute bottom-[14%] h-20 w-16 -translate-x-1/2 bg-cyan transition-[left] duration-200 [clip-path:polygon(50%_0,100%_100%,0_100%)]"
        style={{ left: `${(lane + 0.5) * 33.33}%` }}
      />
      <div className="absolute bottom-3 left-0 right-28 flex justify-between px-4 font-display text-base text-cyan/60 uppercase">
        <span>◀ Lunge L</span>
        <span>Lunge R ▶</span>
      </div>
    </div>
  )
}

function Flappy({ t, y }: { t: number; y: number }) {
  const pipes = [0, 0.55].map((o, i) => ({ x: 1.1 - ((t * 0.22 + o) % 1.3), gap: 38 + ((i * 23 + Math.floor(t * 0.22 + o) * 17) % 30) }))
  return (
    <div className="absolute inset-0 bg-[linear-gradient(#1a0e05,#0b0b0c)]">
      {pipes.map((p, i) => (
        <div key={i} className="absolute inset-y-0 w-14" style={{ left: `${p.x * 100}%` }}>
          <div className="absolute inset-x-0 top-0 bg-flame" style={{ height: `${p.gap}%` }} />
          <div className="absolute inset-x-0 bottom-0 bg-flame" style={{ top: `${p.gap + 26}%` }} />
        </div>
      ))}
      <div className="absolute left-[20%] h-12 w-12 -translate-y-1/2 rounded-full border-4 border-ink bg-volt" style={{ top: `${y}%` }}>
        <div className="absolute top-2 right-2 h-2.5 w-2.5 rounded-full bg-ink" />
      </div>
      <div className="absolute bottom-10 left-4 font-display text-base text-flame/70 uppercase">▲ Raise arms to rise</div>
    </div>
  )
}
