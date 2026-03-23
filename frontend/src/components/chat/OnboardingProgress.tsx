import { Check } from 'lucide-react'
import type { OnboardingState } from '@/types/agent'
import { cn } from '@/lib/utils'

interface OnboardingProgressProps {
  state: OnboardingState
}

const STEPS = [
  { key: 'intake', label: 'Intake' },
  { key: 'documents', label: 'Documents' },
  { key: 'therapist', label: 'Therapist' },
  { key: 'schedule', label: 'Schedule' },
] as const

export default function OnboardingProgress({ state }: OnboardingProgressProps) {
  const currentIdx = STEPS.findIndex((s) => s.key === state.step)

  return (
    <div className="flex items-center gap-1 px-4 py-2 bg-teal-50 border-b border-teal-100">
      {STEPS.map((step, idx) => {
        const isComplete = idx < currentIdx || state.step === 'complete'
        const isCurrent = idx === currentIdx && state.step !== 'complete'

        return (
          <div key={step.key} className="flex items-center gap-1 flex-1">
            <div
              className={cn(
                'flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-bold',
                isComplete && 'bg-teal-600 text-white',
                isCurrent && 'bg-teal-200 text-teal-800 ring-2 ring-teal-400',
                !isComplete && !isCurrent && 'bg-slate-200 text-slate-400'
              )}
            >
              {isComplete ? <Check className="h-3 w-3" /> : idx + 1}
            </div>
            <span
              className={cn(
                'text-[10px] font-medium truncate',
                isCurrent ? 'text-teal-800' : isComplete ? 'text-teal-600' : 'text-slate-400'
              )}
            >
              {step.label}
            </span>
            {idx < STEPS.length - 1 && (
              <div
                className={cn(
                  'h-px flex-1 mx-1',
                  idx < currentIdx ? 'bg-teal-400' : 'bg-slate-200'
                )}
              />
            )}
          </div>
        )
      })}
    </div>
  )
}
