import BackButton from './BackButton'
import { useEffect, useState } from 'react'
import type { Mode } from '../data'
import Skeleton from './Skeleton'

type Stage = 'close' | 'missing' | 'ready'

export default function Calibrate({ mode, onReady, onBack }: { mode: Mode; onReady: () => void; onBack: () => void }) {
  const [stage, setStage] = useState<Stage>('close')
  const [lock, setLock] = useState(0)

  // Simulated framing sequence: too close → missing limb → ready → 1s lock-in
  useEffect(() => {
    const a = setTimeout(() => setStage('missing'), 1800)
    const b = setTimeout(() => setStage('ready'), 3800)
    return () => {
      clearTimeout(a)
      clearTimeout(b)
    }
  }, [])

  useEffect(() => {
    if (stage !== 'ready') return
    const start = performance.now()
    let raf = 0
    const tick = () => {
      const p = Math.min(1, (performance.now() - start) / 1000)
      setLock(p)
      if (p < 1) raf = requestAnimationFrame(tick)
      else setTimeout(onReady, 350)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [stage, onReady])

  const cfg = {
    close: { c: '#ff3b2f', big: 'Step back', sub: 'Body cut off — move 2–3 m away' },
    missing: { c: '#ff8a1f', big: `Show ${mode.limb.toLowerCase()}`, sub: `${mode.exercise} needs your ${mode.limb.toLowerCase()} in frame` },
    ready: { c: '#d4ff3a', big: 'Hold still', sub: 'Locking in…' },
  }[stage]

  return (
    <div className="relative h-full overflow-hidden bg-[radial-gradient(ellipse_at_50%_30%,#2a2d33,#0b0b0c_70%)]">
      <div className="absolute inset-0 stripes opacity-40" />
      {/* frame guide */}
      <div
        className="absolute inset-x-8 top-32 bottom-[260px] border-2 transition-colors duration-300"
        style={{ borderColor: cfg.c, boxShadow: `inset 0 0 60px ${cfg.c}33` }}
      >
        {['top-0 left-0', 'top-0 right-0 rotate-90', 'bottom-0 right-0 rotate-180', 'bottom-0 left-0 -rotate-90'].map((p) => (
          <span key={p} className={`absolute ${p} h-6 w-6 border-t-[6px] border-l-[6px]`} style={{ borderColor: cfg.c }} />
        ))}
        <div
          className="absolute inset-0 flex items-center justify-center transition-transform duration-700"
          style={{ transform: stage === 'close' ? 'scale(1.9) translateY(12%)' : 'scale(1)' }}
        >
          <Skeleton mode={mode.id} phase={0} color={stage === 'ready' ? '#d4ff3a' : '#ffffff'} missing={stage === 'missing' ? mode.limb : null} className="h-[88%]" />
        </div>
      </div>

      <div className="absolute inset-x-0 top-0 flex items-center justify-between px-5 pt-16 pb-4">
        <BackButton onClick={onBack} />
        <span className="flex items-center gap-2 font-mono text-[10px] tracking-widest">
          <span className="h-2 w-2 animate-pulse rounded-full bg-signal" /> CAM LIVE · {mode.game.toUpperCase()}
        </span>
      </div>

      <div className="absolute inset-x-0 bottom-0 p-5">
        <div className="font-mono text-[11px] tracking-widest" style={{ color: cfg.c }}>
          FRAMING {stage === 'close' ? '1' : stage === 'missing' ? '2' : '3'}/3
        </div>
        <div className="font-display text-[52px] leading-[0.95] uppercase" style={{ color: cfg.c }}>
          {cfg.big}
        </div>
        <div className="mt-1 text-lg font-semibold text-white/80">{cfg.sub}</div>
        <div className="mt-4 h-3 w-full bg-white/10">
          <div className="h-full bg-volt" style={{ width: `${lock * 100}%` }} />
        </div>
        <div className="mt-2 font-mono text-[10px] text-dim">HANDS-FREE · AUTO-STARTS WHEN FRAMED FOR 1s</div>
      </div>
    </div>
  )
}
