import { Check, ClipboardList, FileText, UserSearch, CalendarCheck } from 'lucide-react'
import type { OnboardingState } from '@/types/agent'
import { cn } from '@/lib/utils'

interface OnboardingProgressProps {
  state: OnboardingState
}

const STEPS = [
  { key: 'intake', label: 'Intake', icon: ClipboardList },
  { key: 'documents', label: 'Documents', icon: FileText },
  { key: 'therapist', label: 'Therapist', icon: UserSearch },
  { key: 'schedule', label: 'Schedule', icon: CalendarCheck },
] as const

export default function OnboardingProgress({ state }: OnboardingProgressProps) {
  const currentIdx = STEPS.findIndex((s) => s.key === state.step)

  return (
    <div className="shrink-0 border-b border-teal-100/80 bg-white/60 backdrop-blur-sm">
      <div className="mx-auto flex max-w-3xl items-center justify-between px-6 py-3">
        {STEPS.map((step, idx) => {
          const isComplete = idx < currentIdx || state.step === 'complete'
          const isCurrent = idx === currentIdx && state.step !== 'complete'
          const Icon = step.icon

          return (
            <div key={step.key} className="flex items-center flex-1">
              <div className="flex items-center gap-2">
                <div
                  className={cn(
                    'flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold transition-all duration-300',
                    isComplete && 'bg-teal-600 text-white shadow-sm shadow-teal-200',
                    isCurrent && 'bg-teal-100 text-teal-700 ring-2 ring-teal-400/50',
                    !isComplete && !isCurrent && 'bg-slate-100 text-slate-400'
                  )}
                >
                  {isComplete ? (
                    <Check className="h-3.5 w-3.5" />
                  ) : (
                    <Icon className="h-3.5 w-3.5" />
                  )}
                </div>
                <span
                  className={cn(
                    'hidden text-xs font-medium sm:block',
                    isCurrent ? 'text-teal-800' : isComplete ? 'text-teal-600' : 'text-slate-400'
                  )}
                >
                  {step.label}
                </span>
              </div>
              {idx < STEPS.length - 1 && (
                <div
                  className={cn(
                    'mx-3 h-px flex-1 transition-colors duration-300',
                    idx < currentIdx ? 'bg-teal-400' : 'bg-slate-200'
                  )}
                />
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
