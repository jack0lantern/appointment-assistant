import type { TherapistSearchResult } from '@/types/agent'
import { ChevronRight } from 'lucide-react'

interface TherapistCardProps {
  therapist: TherapistSearchResult
  onSelect: (displayLabel: string) => void
}

export default function TherapistCard({ therapist, onSelect }: TherapistCardProps) {
  const initials = therapist.name.split(' ').map((n) => n[0]).join('')

  return (
    <button
      onClick={() => onSelect(therapist.display_label)}
      className="group w-full rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm
                 transition-all hover:border-teal-300 hover:shadow-md focus:outline-none
                 focus:ring-2 focus:ring-teal-400 focus:ring-offset-2"
    >
      <div className="flex items-start gap-3">
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-teal-500 to-teal-600 text-white font-semibold text-sm shadow-sm">
          {initials}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between">
            <p className="font-semibold text-slate-900 text-sm">{therapist.name}</p>
            <ChevronRight className="h-4 w-4 text-slate-300 transition-colors group-hover:text-teal-500" />
          </div>
          <p className="text-xs text-slate-500">{therapist.license_type}</p>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {therapist.specialties.slice(0, 3).map((s) => (
              <span
                key={s}
                className="rounded-full bg-teal-50 px-2.5 py-0.5 text-[11px] font-medium text-teal-700 border border-teal-100"
              >
                {s}
              </span>
            ))}
            {therapist.specialties.length > 3 && (
              <span className="rounded-full bg-slate-50 px-2 py-0.5 text-[11px] text-slate-500">
                +{therapist.specialties.length - 3} more
              </span>
            )}
          </div>
          {therapist.bio && (
            <p className="mt-2 text-xs leading-relaxed text-slate-600 line-clamp-2">{therapist.bio}</p>
          )}
        </div>
      </div>
    </button>
  )
}
