import PageHeader from './PageHeader'
import { useState } from 'react'
import { LEADERBOARD, MODES, type ModeId } from '../data'

export default function Leaderboard({ onBack }: { onBack: () => void }) {
  const [tab, setTab] = useState<ModeId>('dino')
  const mode = MODES.find((m) => m.id === tab)!
  const rows = LEADERBOARD[tab]
  const podium = [rows[1], rows[0], rows[2]]

  return (
    <div className="flex h-full flex-col px-5 pt-16 pb-5">
      <PageHeader title="Leaderboard" onBack={onBack} />

      <div className="mt-4 grid grid-cols-3 border border-line">
        {MODES.map((m) => (
          <button
            key={m.id}
            onClick={() => setTab(m.id)}
            className="py-2.5 text-[12px] font-bold uppercase tracking-wide transition"
            style={tab === m.id ? { background: m.color, color: '#0b0b0c' } : { color: '#8a8a92' }}
          >
            {m.exercise}
          </button>
        ))}
      </div>

      <div className="mt-6 grid grid-cols-3 items-end gap-2">
        {podium.map((r, i) => {
          const place = [2, 1, 3][i]
          return (
            <div key={r.tag} className="flex flex-col items-center">
              <div className="grid h-12 w-12 place-items-center border-2 font-display text-lg" style={{ borderColor: mode.color }}>
                {r.badge}
              </div>
              <div className="mt-1 w-full truncate text-center text-xs font-bold">{r.name}</div>
              <div className="font-mono text-[10px] text-dim">{r.score.toLocaleString()}</div>
              <div
                className="mt-2 grid w-full place-items-start px-2 pt-1 font-display text-4xl text-ink"
                style={{ height: [70, 100, 50][i], background: place === 1 ? mode.color : place === 2 ? '#e8e8e8' : '#8a8a92' }}
              >
                {place}
              </div>
            </div>
          )
        })}
      </div>

      <div className="no-scrollbar mt-5 flex-1 overflow-y-auto">
        <div className="grid grid-cols-[36px_1fr_auto] border-b border-line pb-1 font-mono text-[10px] tracking-widest text-dim">
          <span>#</span>
          <span>PLAYER</span>
          <span>SCORE / DATE</span>
        </div>
        {rows.map((r, i) => {
          const me = r.tag === '#0423'
          return (
            <div
              key={r.tag}
              className={`grid grid-cols-[36px_1fr_auto] items-center border-b border-line py-2.5 ${me ? 'bg-white/5' : ''}`}
            >
              <span className="font-display text-2xl" style={{ color: i < 3 ? mode.color : undefined }}>
                {i + 1}
              </span>
              <span className="flex items-center gap-2">
                <span className="grid h-8 w-8 place-items-center bg-panel font-mono text-[10px] font-bold">{r.badge}</span>
                <span className="leading-tight">
                  <span className="block text-sm font-bold">
                    {r.name} {me && <span className="ml-1 bg-volt px-1 text-[9px] text-ink">YOU</span>}
                  </span>
                  <span className="font-mono text-[10px] text-dim">{r.tag}</span>
                </span>
              </span>
              <span className="text-right leading-tight">
                <span className="block font-display text-xl tabular-nums">{r.score.toLocaleString()}</span>
                <span className="font-mono text-[10px] text-dim">{r.date}</span>
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
