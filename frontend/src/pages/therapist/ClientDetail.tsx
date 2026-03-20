import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import type { ClientProfile, Session, TreatmentPlan, SafetyFlag } from '@/types'
import api from '@/api/client'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardHeader, CardTitle, CardContent, CardDescription } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Skeleton } from '@/components/ui/skeleton'

interface ClientDetailData {
  client: ClientProfile
  sessions: Session[]
  treatment_plan: TreatmentPlan | null
  safety_flags: SafetyFlag[]
}

export default function ClientDetail() {
  const { clientId } = useParams<{ clientId: string }>()
  const navigate = useNavigate()

  const { data, isLoading, error } = useQuery<ClientDetailData>({
    queryKey: ['client', clientId],
    queryFn: async () => {
      const { data } = await api.get<ClientDetailData>(`/api/clients/${clientId}`)
      return data
    },
    enabled: !!clientId,
  })

  if (isLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-10 w-60" />
        <Skeleton className="h-48 rounded-xl" />
        <Skeleton className="h-64 rounded-xl" />
      </div>
    )
  }

  if (error || !data) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
        <p className="text-sm text-red-700">
          Failed to load client details. Please try again.
        </p>
        <Button
          variant="outline"
          size="sm"
          className="mt-3"
          onClick={() => navigate('/therapist/dashboard')}
        >
          Back to Dashboard
        </Button>
      </div>
    )
  }

  const { client, sessions, treatment_plan, safety_flags } = data
  const unacknowledgedFlags = safety_flags.filter((f) => !f.acknowledged)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <button
            onClick={() => navigate('/therapist/dashboard')}
            className="mb-1 text-sm text-blue-600 hover:underline"
          >
            &larr; Back to Clients
          </button>
          <h1 className="text-2xl font-semibold text-slate-900">
            {client.name}
          </h1>
        </div>
        <div className="flex gap-2">
          <Button
            onClick={() =>
              navigate(`/therapist/clients/${client.id}/live`, {
                state: { clientId: client.id, clientName: client.name },
              })
            }
          >
            Start Live Session
          </Button>
          <Button
            variant="outline"
            onClick={() =>
              navigate('/therapist/sessions/new', {
                state: { clientId: client.id, clientName: client.name },
              })
            }
          >
            Upload Transcript
          </Button>
        </div>
      </div>

      {/* Treatment Plan Summary */}
      {treatment_plan && (
        <Card
          className="cursor-pointer transition-shadow hover:shadow-md"
          onClick={() => navigate(`/therapist/clients/${clientId}/plan`)}
        >
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle className="text-slate-900">Treatment Plan</CardTitle>
              <Badge
                variant={
                  treatment_plan.status === 'approved' ? 'default' : 'secondary'
                }
              >
                {treatment_plan.status}
              </Badge>
            </div>
            <CardDescription>Click to review and edit</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex gap-6 text-sm text-slate-600">
              {treatment_plan.current_version && (
                <>
                  <div>
                    <span className="text-slate-500">Last updated: </span>
                    <span className="font-medium text-slate-900">
                      {new Date(
                        treatment_plan.current_version.created_at,
                      ).toLocaleDateString()}
                    </span>
                  </div>
                  <div>
                    <span className="text-slate-500">Version: </span>
                    <span className="font-medium text-slate-900">
                      {treatment_plan.current_version.version_number}
                    </span>
                  </div>
                </>
              )}
              {treatment_plan.versions && (
                <div>
                  <span className="text-slate-500">Total versions: </span>
                  <span className="font-medium text-slate-900">
                    {treatment_plan.versions.length}
                  </span>
                </div>
              )}
            </div>
            {unacknowledgedFlags.length > 0 && (
              <div className="mt-3">
                <Badge variant="destructive">
                  {unacknowledgedFlags.length} unacknowledged safety{' '}
                  {unacknowledgedFlags.length === 1 ? 'flag' : 'flags'}
                </Badge>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {!treatment_plan && (
        <Card>
          <CardContent className="py-8 text-center">
            <p className="text-sm text-slate-500">
              No treatment plan yet. Create a session to generate one.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Session History */}
      <div>
        <h2 className="mb-3 text-lg font-semibold text-slate-900">
          Session History
        </h2>
        {sessions.length === 0 ? (
          <Card>
            <CardContent className="py-8 text-center">
              <p className="text-sm text-slate-500">No sessions recorded yet.</p>
            </CardContent>
          </Card>
        ) : (
          <Card>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Session</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Date</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Safety Flags</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sessions.map((session) => {
                  const sessionFlags = safety_flags.filter(
                    (f) =>
                      f.id === session.id ||
                      safety_flags.some(() => true),
                  )
                  const flagCount = sessionFlags.length > 0 ? sessionFlags.length : 0

                  return (
                    <TableRow key={session.id}>
                      <TableCell className="font-medium">
                        #{session.session_number}
                      </TableCell>
                      <TableCell>
                        <Badge variant={session.session_type === 'live' ? 'default' : 'secondary'}>
                          {session.session_type === 'live' ? 'Live' : 'Upload'}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        {new Date(session.session_date).toLocaleDateString()}
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant={
                            session.status === 'completed'
                              ? 'default'
                              : 'secondary'
                          }
                        >
                          {session.status}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        {flagCount > 0 ? (
                          <Badge variant="destructive">{flagCount}</Badge>
                        ) : (
                          <span className="text-slate-400">0</span>
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </Card>
        )}
      </div>
    </div>
  )
}
