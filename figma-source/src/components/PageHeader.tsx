import BackButton from './BackButton'

export default function PageHeader({ title, onBack }: { title: string; onBack: () => void }) {
  return (
    <header className="shrink-0">
      <div className="flex items-center gap-3">
        <BackButton onClick={onBack} />
        <span className="font-mono text-[11px] tracking-widest text-dim">
          HUB <span className="text-white/25">/</span> <span className="text-white">{title.toUpperCase()}</span>
        </span>
      </div>
      <h1 className="mt-5 font-display text-[56px] leading-[0.9] uppercase">{title}</h1>
    </header>
  )
}
