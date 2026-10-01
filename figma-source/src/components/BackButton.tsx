export default function BackButton({ onClick, label = 'Back to hub' }: { onClick: () => void; label?: string }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      className="group grid h-10 w-10 shrink-0 place-items-center border border-line bg-ink/60 transition hover:border-volt hover:bg-volt active:scale-95"
    >
      <svg viewBox="0 0 24 24" className="h-5 w-5 text-white transition group-hover:text-ink" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="square">
        <path d="M14.5 5.5L8 12l6.5 6.5" />
      </svg>
    </button>
  )
}
