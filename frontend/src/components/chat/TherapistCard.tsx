import type { TherapistSearchResult } from '@/types/agent'

interface TherapistCardProps {
  therapist: TherapistSearchResult
  onSelect: (displayLabel: string) => void
}

export default function TherapistCard({ therapist, onSelect }: TherapistCardProps) {
  return (
    <button
      onClick={() => onSelect(therapist.display_label)}
      className="w-full rounded-xl border border-slate-200 bg-white p-3 text-left
                 transition-all hover:border-teal-300 hover:shadow-md"
    >
      <div className="flex items-start gap-3">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-teal-100 text-teal-700 font-semibold text-sm">
          {therapist.name.split(' ').map((n) => n[0]).join('')}
        </div>
        <div className="min-w-0 flex-1">
          <p className="font-medium text-slate-900 text-sm">{therapist.name}</p>
          <p className="text-xs text-slate-500">{therapist.license_type}</p>
          <div className="mt-1.5 flex flex-wrap gap-1">
            {therapist.specialties.slice(0, 3).map((s) => (
              <span
                key={s}
                className="rounded-full bg-teal-50 px-2 py-0.5 text-[10px] font-medium text-teal-700"
              >
                {s}
              </span>
            ))}
          </div>
          {therapist.bio && (
            <p className="mt-1.5 text-xs text-slate-600 line-clamp-2">{therapist.bio}</p>
          )}
        </div>
      </div>
    </button>
  )
}
