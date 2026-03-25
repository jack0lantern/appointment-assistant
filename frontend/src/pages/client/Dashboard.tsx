import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/context/AuthContext'
import api from '@/api/client'
import type { TreatmentPlan, HomeworkItem, Session, ClientAppointment } from '@/types'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import WelcomeCard from '@/components/client/WelcomeCard'
import SessionSummaryClient from '@/components/client/SessionSummaryClient'

export default function Dashboard() {
  const { user } = useAuth()
  const navigate = useNavigate()

  const { data: plan, isLoading: planLoading } = useQuery<TreatmentPlan>({
    queryKey: ['client-plan'],
    queryFn: async () => {
      const { data } = await api.get('/api/my/treatment-plan')
      return data
    },
  })

  const { data: homework, isLoading: homeworkLoading } = useQuery<HomeworkItem[]>({
    queryKey: ['client-homework'],
    queryFn: async () => {
      const { data } = await api.get('/api/my/homework')
      return data
    },
  })

  const { data: sessions, isLoading: sessionsLoading } = useQuery<Session[]>({
    queryKey: ['client-sessions'],
    queryFn: async () => {
      const { data } = await api.get('/api/my/sessions')
      return data
    },
  })

  const { data: appointmentsData } = useQuery<{ appointments: ClientAppointment[] }>({
    queryKey: ['clientAppointments'],
    queryFn: async () => {
      const { data } = await api.get<{ appointments: ClientAppointment[] }>('/api/my/appointments')
      return data
    },
  })

  const upcomingAppointments = appointmentsData?.appointments ?? []
  const incompleteHomework = homework?.filter((h) => !h.completed).length ?? 0
  const recentSessions = sessions?.slice(0, 3) ?? []

  return (
    <div className="space-y-6">
      <WelcomeCard name={user?.name ?? 'there'} />

      {/* AI plan disclaimer — only when a plan has been shared */}
      {!planLoading && plan?.current_version && (
        <Card className="border-teal-100 bg-teal-50/50 shadow-none">
          <CardContent className="flex items-start gap-3 py-4">
            <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-teal-100 text-teal-600 text-xs">
              i
            </span>
            <p className="text-sm leading-relaxed text-teal-800">
              This plan was created by your therapist with AI assistance. If you have questions,
              please bring them up in your next session.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Upcoming Appointments */}
      {upcomingAppointments.length > 0 && (
        <div>
          <h3 className="mb-3 text-lg font-semibold text-slate-800">Upcoming Appointments</h3>
          <div className="divide-y divide-slate-100 rounded-xl border border-slate-200 bg-white">
            {upcomingAppointments.map((apt) => (
              <div
                key={apt.session_id}
                className="flex items-center justify-between px-4 py-3"
              >
                <div>
                  <p className="font-medium text-slate-900">{apt.therapist_name}</p>
                  <p className="text-sm text-slate-500">
                    {new Date(apt.session_date).toLocaleDateString('en-US', {
                      weekday: 'short',
                      month: 'short',
                      day: 'numeric',
                      year: 'numeric',
                      timeZone: 'America/Denver',
                    })}{' '}
                    at {new Date(apt.session_date).toLocaleTimeString('en-US', {
                      hour: 'numeric',
                      minute: '2-digit',
                      timeZone: 'America/Denver',
                    })}{' '}
                    · {apt.duration_minutes} min
                  </p>
                </div>
                <span className="inline-flex items-center rounded-full bg-teal-100 px-2.5 py-0.5 text-xs font-medium text-teal-700">
                  Scheduled
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        {/* Treatment Plan card */}
        <Card
          className="cursor-pointer border-none shadow-sm bg-white/80 backdrop-blur-sm hover:shadow-md transition-all"
          onClick={() => navigate('/client/plan')}
        >
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-teal-800">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-teal-100 text-teal-600 text-sm">
                &#9733;
              </span>
              Your Treatment Plan
            </CardTitle>
          </CardHeader>
          <CardContent>
            {planLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-4 w-1/2" />
              </div>
            ) : plan?.current_version ? (
              <div className="space-y-2">
                <span className="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-700">
                  Active plan
                </span>
                <p className="text-xs text-slate-500">
                  Last updated{' '}
                  {new Date(plan.current_version.created_at).toLocaleDateString('en-US', {
                    month: 'long',
                    day: 'numeric',
                    year: 'numeric',
                  })}
                </p>
              </div>
            ) : (
              <p className="text-sm text-slate-500">No plan shared yet</p>
            )}
          </CardContent>
        </Card>

        {/* Homework card */}
        <Card
          className="cursor-pointer border-none shadow-sm bg-white/80 backdrop-blur-sm hover:shadow-md transition-all"
          onClick={() => navigate('/client/homework')}
        >
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-teal-800">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-teal-100 text-teal-600 text-sm">
                &#10003;
              </span>
              Your Homework
            </CardTitle>
          </CardHeader>
          <CardContent>
            {homeworkLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-4 w-1/2" />
              </div>
            ) : homework && homework.length > 0 ? (
              <div className="space-y-2">
                <p className="text-sm text-slate-700">
                  <span className="font-semibold text-teal-700">{incompleteHomework}</span>{' '}
                  {incompleteHomework === 1 ? 'item' : 'items'} to complete
                </p>
                <div className="h-2 w-full overflow-hidden rounded-full bg-slate-100">
                  <div
                    className="h-full rounded-full bg-teal-500 transition-all duration-500"
                    style={{
                      width: `${((homework.length - incompleteHomework) / homework.length) * 100}%`,
                    }}
                  />
                </div>
              </div>
            ) : (
              <p className="text-sm text-slate-500">No homework assigned yet</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Recent Sessions */}
      <div className="space-y-3">
        <h3 className="text-lg font-semibold text-slate-800">Recent Sessions</h3>
        {sessionsLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full rounded-xl" />
            <Skeleton className="h-24 w-full rounded-xl" />
          </div>
        ) : recentSessions.length > 0 ? (
          <div className="space-y-3">
            {recentSessions.map((session) => (
              <SessionSummaryClient key={session.id} session={session} />
            ))}
          </div>
        ) : (
          <Card className="border-none shadow-sm bg-white/80">
            <CardContent className="py-8 text-center">
              <p className="text-sm text-slate-500">No sessions recorded yet.</p>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}
