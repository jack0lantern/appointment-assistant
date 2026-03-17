import type { Session } from '@/types'
import { Card, CardContent } from '@/components/ui/card'

interface SessionSummaryClientProps {
  session: Session
}

export default function SessionSummaryClient({ session }: SessionSummaryClientProps) {
  const formattedDate = new Date(session.session_date).toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })

  return (
    <Card className="border-none shadow-sm bg-white/80 backdrop-blur-sm hover:shadow-md transition-shadow">
      <CardContent className="py-5">
        <div className="flex items-start justify-between">
          <div className="space-y-1">
            <p className="text-xs font-medium text-teal-600 uppercase tracking-wide">
              Session {session.session_number}
            </p>
            <p className="text-sm text-slate-500">{formattedDate}</p>
          </div>
          <span className="rounded-full bg-teal-50 px-3 py-1 text-xs font-medium text-teal-700">
            {session.duration_minutes} min
          </span>
        </div>

        {session.summary?.client_summary && (
          <div className="mt-4">
            <p className="text-xs text-slate-400 mb-1">Here's what we worked on together...</p>
            <p className="text-sm leading-relaxed text-slate-700">
              {session.summary.client_summary}
            </p>
          </div>
        )}

        {session.summary?.key_themes && session.summary.key_themes.length > 0 && (
          <div className="mt-3 flex flex-wrap gap-2">
            {session.summary.key_themes.map((theme) => (
              <span
                key={theme}
                className="rounded-full bg-teal-50 px-3 py-1 text-xs text-teal-700"
              >
                {theme}
              </span>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
