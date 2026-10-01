import { useCallback, useState } from 'react'
import { MODES, type ModeId, type Result, type Settings as S } from './data'
import Hub from './components/Hub'
import Calibrate from './components/Calibrate'
import Play from './components/Play'
import Summary from './components/Summary'
import Leaderboard from './components/Leaderboard'
import Settings from './components/Settings'

type Screen = 'hub' | 'calibrate' | 'play' | 'summary' | 'leaderboard' | 'settings'

export default function App() {
  const [screen, setScreen] = useState<Screen>('hub')
  const [modeId, setModeId] = useState<ModeId>('dino')
  const [result, setResult] = useState<Result | null>(null)
  const [run, setRun] = useState(0)
  const [locked, setLocked] = useState<Record<ModeId, boolean>>({ dino: false, lane: false, flappy: true })
  const [settings, setSettings] = useState<S>({ accel: 'GPU', jack: 150, lunge: 100, arm: 120 })
  const mode = MODES.find((m) => m.id === modeId)!

  const onReady = useCallback(() => setScreen('play'), [])
  const onEnd = useCallback((r: Result) => {
    setResult(r)
    setScreen('summary')
  }, [])
  const again = useCallback(() => {
    setRun((n) => n + 1)
    setScreen('calibrate')
  }, [])

  return (
    <div className="flex min-h-screen items-center justify-center gap-12 p-0 sm:p-6">
      <aside className="hidden max-w-xs lg:block">
        <div className="font-display text-6xl leading-[0.9] uppercase">
          Fit<span className="text-volt">Arcade</span>
        </div>
        <p className="mt-4 text-white/60">Your body is the controller. Prop the phone up, step back 2–3 m, and every rep drives the game.</p>
        <div className="mt-6 font-mono text-[10px] tracking-widest text-dim">SCREEN · {screen.toUpperCase()}</div>
      </aside>
      <main className="relative h-[100dvh] w-full overflow-hidden bg-ink sm:h-[min(844px,calc(100dvh-3rem))] sm:w-[390px] sm:rounded-[36px] sm:border-[10px] sm:border-[#1c1c1f] sm:shadow-[0_40px_120px_-20px_rgba(212,255,58,0.15)]">
        {screen === 'hub' && (
          <Hub
            locked={locked}
            onPick={(m) => {
              setModeId(m)
              again()
            }}
            onNav={setScreen}
          />
        )}
        {screen === 'calibrate' && <Calibrate key={run} mode={mode} onReady={onReady} onBack={() => setScreen('hub')} />}
        {screen === 'play' && <Play key={run} mode={mode} onEnd={onEnd} />}
        {screen === 'summary' && result && <Summary mode={mode} result={result} onAgain={again} onHub={() => setScreen('hub')} />}
        {screen === 'leaderboard' && <Leaderboard onBack={() => setScreen('hub')} />}
        {screen === 'settings' && (
          <Settings
            settings={settings}
            onChange={setSettings}
            locked={locked}
            onLock={(id) => setLocked((l) => ({ ...l, [id]: !l[id] }))}
            onBack={() => setScreen('hub')}
          />
        )}
      </main>
    </div>
  )
}
