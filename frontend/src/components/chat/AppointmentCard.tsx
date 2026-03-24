import type { AppointmentResult } from '@/types/agent'
import { Calendar, Clock, XCircle } from 'lucide-react'

interface AppointmentCardProps {
  appointment: AppointmentResult
  onSelect: (cancelPayload: string) => void
}

export default function AppointmentCard({ appointment, onSelect }: AppointmentCardProps) {
  return (
    <button
      onClick={() => onSelect(appointment.cancel_payload)}
      type="button"
      className="group w-full rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm
                 transition-all hover:border-amber-300 hover:shadow-md focus:outline-none
                 focus:ring-2 focus:ring-amber-400 focus:ring-offset-2"
    >
      <div className="flex items-start gap-3">
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full
                        bg-amber-50 text-amber-600 border border-amber-100">
          <Calendar className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-slate-900 text-sm">{appointment.date}</p>
          <div className="mt-1 flex items-center gap-1.5 text-xs text-slate-600">
            <Clock className="h-3.5 w-3.5 shrink-0" />
            <span>{appointment.time}</span>
            <span className="text-slate-300">|</span>
            <span>{appointment.duration_minutes} min</span>
          </div>
          <p className="mt-1.5 text-xs text-slate-500">{appointment.therapist_name}</p>
          <div className="mt-2.5 flex items-center gap-1.5 text-xs font-medium text-amber-600 transition-colors group-hover:text-amber-700">
            <XCircle className="h-3.5 w-3.5" />
            Tap to cancel this appointment
          </div>
        </div>
      </div>
    </button>
  )
}
