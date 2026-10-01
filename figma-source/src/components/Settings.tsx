import PageHeader from './PageHeader'
import type { ModeId, Settings as S } from '../data'
import { MODES } from '../data'

type Props = {
  settings: S
  onChange: (s: S) => void
  locked: Record<ModeId, boolean>
  onLock: (id: ModeId) => void
  onBack: () => void
}

const SLIDERS: { key: 'jack' | 'lunge' | 'arm'; label: string; hint: string; min: number; max: number; color: string }[] = [
  { key: 'jack', label: 'Jack arm spread', hint: 'Hands-over-head angle to count a jack', min: 120, max: 180, color: '#d4ff3a' },
  { key: 'lunge', label: 'Lunge knee depth', hint: 'Knee bend required for a side lunge', min: 60, max: 140, color: '#3ae0ff' },
  { key: 'arm', label: 'Arm raise reach', hint: 'Shoulder angle required for a raise', min: 70, max: 170, color: '#ff8a1f' },
]

export default function Settings({ settings, onChange, locked, onLock, onBack }: Props) {
  return (
    <div className="no-scrollbar flex h-full flex-col overflow-y-auto px-5 pt-16 pb-5">
      <PageHeader title="Tracking" onBack={onBack} />

      <section className="mt-6">
        <div className="font-mono text-[10px] tracking-widest text-dim">HARDWARE ACCELERATION</div>
        <div className="mt-2 grid grid-cols-2 border border-line p-1">
          {(['CPU', 'GPU'] as const).map((a) => (
            <button
              key={a}
              onClick={() => onChange({ ...settings, accel: a })}
              className={`py-3 font-display text-2xl transition ${settings.accel === a ? 'bg-volt text-ink' : 'text-dim hover:text-white'}`}
            >
              {a}
            </button>
          ))}
        </div>
        <p className="mt-2 text-sm text-white/60">
          {settings.accel === 'GPU' ? 'Faster pose inference (~40 ms). Uses more battery.' : 'Most compatible. Expect ~70 ms latency on older phones.'}
        </p>
      </section>

      <section className="mt-7">
        <div className="font-mono text-[10px] tracking-widest text-dim">EXERCISE SENSITIVITY</div>
        {SLIDERS.map((s) => (
          <div key={s.key} className="mt-4 border-t border-line pt-3">
            <div className="flex items-end justify-between">
              <div>
                <div className="text-base font-bold uppercase">{s.label}</div>
                <div className="text-xs text-white/50">{s.hint}</div>
              </div>
              <div className="font-display text-4xl tabular-nums" style={{ color: s.color }}>
                {settings[s.key]}°
              </div>
            </div>
            <input
              type="range"
              min={s.min}
              max={s.max}
              value={settings[s.key]}
              onChange={(e) => onChange({ ...settings, [s.key]: Number(e.target.value) })}
              className="mt-2 w-full"
              style={{ accentColor: s.color }}
            />
            <div className="flex justify-between font-mono text-[9px] text-dim">
              <span>EASIER · {s.min}°</span>
              <span>{s.max}° · STRICTER</span>
            </div>
          </div>
        ))}
      </section>

      <section className="mt-7">
        <div className="font-mono text-[10px] tracking-widest text-dim">REMOTE GAME LOCKS (DEMO)</div>
        {MODES.map((m) => (
          <button key={m.id} onClick={() => onLock(m.id)} className="mt-2 flex w-full items-center justify-between border border-line px-3 py-2.5">
            <span className="font-bold uppercase">{m.game}</span>
            <span className={`font-mono text-[10px] ${locked[m.id] ? 'text-signal' : 'text-volt'}`}>{locked[m.id] ? '● MAINTENANCE' : '● LIVE'}</span>
          </button>
        ))}
      </section>
    </div>
  )
}
