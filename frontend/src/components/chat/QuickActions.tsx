import type { SuggestedAction } from '@/types/agent'

interface QuickActionsProps {
  actions: SuggestedAction[]
  onSelect: (payload: string) => void
  disabled?: boolean
}

export default function QuickActions({ actions, onSelect, disabled }: QuickActionsProps) {
  if (actions.length === 0) return null

  return (
    <div className="flex flex-wrap gap-2 px-3 py-2">
      {actions.map((action) => (
        <button
          key={action.label}
          onClick={() => onSelect(action.payload ?? action.label)}
          disabled={disabled}
          className="rounded-full border border-teal-200 bg-teal-50 px-3 py-1.5 text-xs font-medium
                     text-teal-700 transition-colors hover:bg-teal-100 hover:border-teal-300
                     disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {action.label}
        </button>
      ))}
    </div>
  )
}
