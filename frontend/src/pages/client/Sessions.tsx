import { useQuery } from '@tanstack/react-query'
import api from '@/api/client'
import type { Session } from '@/types'
import { Skeleton } from '@/components/ui/skeleton'
import { Card, CardContent } from '@/components/ui/card'
import SessionSummaryClient from '@/components/client/SessionSummaryClient'

export default function Sessions() {
  const {
    data: sessions,
    isLoading,
    error,
  } = useQuery<Session[]>({
    queryKey: ['client-sessions'],
    queryFn: async () => {
      const { data } = await api.get('/api/my/sessions')
      return data
    },
  })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-800">Your Sessions</h1>
        <p className="mt-1 text-sm text-slate-500">
          A look back at what you've been working on together
        </p>
      </div>

      {isLoading ? (
        <div className="space-y-3">
          <Skeleton className="h-28 w-full rounded-xl" />
          <Skeleton className="h-28 w-full rounded-xl" />
          <Skeleton className="h-28 w-full rounded-xl" />
        </div>
      ) : error ? (
        <Card className="border-none shadow-sm bg-white/80">
          <CardContent className="py-12 text-center">
            <p className="text-sm text-slate-500">
              Something went wrong loading your sessions. Please try again later.
            </p>
          </CardContent>
        </Card>
      ) : sessions && sessions.length > 0 ? (
        <div className="space-y-3">
          {sessions.map((session) => (
            <SessionSummaryClient key={session.id} session={session} />
          ))}
        </div>
      ) : (
        <Card className="border-none shadow-sm bg-white/80">
          <CardContent className="py-16 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-teal-50">
              <span className="text-2xl text-teal-400">&#128197;</span>
            </div>
            <h2 className="text-lg font-semibold text-slate-700">No sessions yet</h2>
            <p className="mt-2 max-w-sm mx-auto text-sm leading-relaxed text-slate-500">
              Your session history will appear here after your first appointment.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
