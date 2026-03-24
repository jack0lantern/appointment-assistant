import type { SuggestedAction } from '@/types/agent'
import { Sparkles } from 'lucide-react'

interface QuickActionsProps {
  actions: SuggestedAction[]
  onSelect: (payload: string) => void
  disabled?: boolean
}

export default function QuickActions({ actions, onSelect, disabled }: QuickActionsProps) {
  if (actions.length === 0) return null

  return (
    <div className="flex flex-wrap items-center gap-2 px-3 py-2">
      <Sparkles className="h-3.5 w-3.5 text-teal-400" />
      {actions.map((action) => (
        <button
          key={action.label}
          onClick={() => onSelect(action.payload ?? action.label)}
          disabled={disabled}
          className="rounded-full border border-teal-200/80 bg-white px-3.5 py-1.5 text-xs font-medium
                     text-teal-700 shadow-sm transition-all hover:bg-teal-50 hover:border-teal-300 hover:shadow
                     disabled:opacity-50 disabled:cursor-not-allowed disabled:shadow-none"
        >
          {action.label}
        </button>
      ))}
    </div>
  )
}
