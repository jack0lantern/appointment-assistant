import { useState } from 'react'
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { useMutation } from '@tanstack/react-query'
import api from '@/api/client'
import type { Session } from '@/types'
import TranscriptUpload from '@/components/therapist/TranscriptUpload'
import GenerationProgress from '@/components/therapist/GenerationProgress'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'

interface LocationState {
  clientId?: number
  clientName?: string
}

export default function NewSession() {
  const location = useLocation()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()

  const state = (location.state as LocationState) ?? {}
  const clientId = state.clientId ?? Number(searchParams.get('clientId'))
  const clientName = state.clientName ?? `Client #${clientId}`

  const today = new Date().toISOString().split('T')[0]
  const [sessionDate, setSessionDate] = useState(today)
  const [duration, setDuration] = useState(50)
  const [transcript, setTranscript] = useState('')
  const [createdSessionId, setCreatedSessionId] = useState<number | null>(null)

  const createSessionMutation = useMutation({
    mutationFn: async () => {
      const { data } = await api.post<Session>(
        `/api/clients/${clientId}/sessions`,
        {
          session_date: sessionDate,
          duration_minutes: duration,
          transcript_text: transcript,
        },
      )
      return data
    },
    onSuccess: (session) => {
      setCreatedSessionId(session.id)
    },
  })

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!transcript.trim()) return
    createSessionMutation.mutate()
  }

  if (!clientId) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-6 text-center">
        <p className="text-sm text-red-700">No client selected.</p>
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

  return (
    <>
      <div className="mx-auto max-w-2xl space-y-6">
        <div>
          <button
            onClick={() => navigate(`/therapist/clients/${clientId}`)}
            className="mb-1 text-sm text-blue-600 hover:underline"
          >
            &larr; Back to {clientName}
          </button>
          <h1 className="text-2xl font-semibold text-slate-900">New Session</h1>
          <p className="text-sm text-slate-500">{clientName}</p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-slate-900">Session Details</CardTitle>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-5">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="session-date">Session Date</Label>
                  <Input
                    id="session-date"
                    type="date"
                    value={sessionDate}
                    onChange={(e) => setSessionDate(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="duration">Duration (minutes)</Label>
                  <Input
                    id="duration"
                    type="number"
                    min={15}
                    max={180}
                    value={duration}
                    onChange={(e) => setDuration(Number(e.target.value))}
                  />
                </div>
              </div>

              <TranscriptUpload value={transcript} onChange={setTranscript} />

              {createSessionMutation.isError && (
                <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
                  Failed to create session. Please try again.
                </div>
              )}

              <div className="flex justify-end gap-3">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => navigate(`/therapist/clients/${clientId}`)}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={
                    !transcript.trim() || createSessionMutation.isPending
                  }
                >
                  {createSessionMutation.isPending
                    ? 'Creating Session...'
                    : 'Generate Treatment Plan'}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      </div>

      {createdSessionId !== null && (
        <GenerationProgress
          sessionId={createdSessionId}
          clientId={clientId}
          onClose={() => setCreatedSessionId(null)}
        />
      )}
    </>
  )
}
