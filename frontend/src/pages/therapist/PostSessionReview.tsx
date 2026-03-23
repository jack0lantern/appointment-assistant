import { useState } from 'react'
import { useParams, useNavigate, useLocation } from 'react-router-dom'
import { useQuery, useMutation } from '@tanstack/react-query'
import api from '@/api/client'
import type { TranscriptPreview, LiveSessionStatus } from '@/types'
import GenerationProgress from '@/components/therapist/GenerationProgress'
import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardContent, CardDescription } from '@/components/ui/card'

interface LocationState {
  clientId?: number
  clientName?: string
}

export default function PostSessionReview() {
  const { sessionId } = useParams<{ sessionId: string }>()
  const location = useLocation()
  const navigate = useNavigate()
  const state = (location.state as LocationState) ?? {}
  const clientId = state.clientId ?? 0
  const clientName = state.clientName ?? 'Client'

  const [speakerMap, setSpeakerMap] = useState<Record<string, string>>({})
  const [confirmed, setConfirmed] = useState(false)
  const [generating, setGenerating] = useState(false)

  // Poll session status for recording processing
  const { data: sessionStatus } = useQuery<LiveSessionStatus>({
    queryKey: ['live-status', sessionId],
    queryFn: async () => {
      const { data } = await api.get(`/api/sessions/${sessionId}/live/status`)
      return data
    },
    refetchInterval: (query) => {
      const status = query.state.data?.recording_status
      return status === 'processing' ? 3000 : false
    },
  })

  // Fetch transcript preview once processing is complete
  const { data: preview } = useQuery<TranscriptPreview>({
    queryKey: ['transcript-preview', sessionId],
    queryFn: async () => {
      const { data } = await api.get(`/api/sessions/${sessionId}/transcript/preview`)
      return data
    },
    enabled: sessionStatus?.recording_status === 'complete',
  })

  // Confirm speaker mapping
  const confirmSpeakers = useMutation({
    mutationFn: async () => {
      await api.post(`/api/sessions/${sessionId}/transcript/confirm`, {
        speaker_map: speakerMap,
      })
    },
    onSuccess: () => {
      setConfirmed(true)
    },
  })

  const isProcessing = sessionStatus?.recording_status === 'processing'
  const isFailed = sessionStatus?.recording_status === 'failed'
  const isComplete = sessionStatus?.recording_status === 'complete'

  // Initialize speaker map from preview
  if (preview && Object.keys(speakerMap).length === 0) {
    const initial: Record<string, string> = {}
    preview.speakers.forEach((s, i) => {
      initial[s] = i === 0 ? 'therapist' : 'client'
    })
    setSpeakerMap(initial)
  }

  // Get sample utterances per speaker
  const getSamples = (speaker: string) => {
    if (!preview) return []
    return preview.utterances.filter((u) => u.speaker === speaker).slice(0, 2)
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <button
          onClick={() => navigate(`/therapist/clients/${clientId}`)}
          className="mb-1 text-sm text-blue-600 hover:underline"
        >
          &larr; Back to {clientName}
        </button>
        <h1 className="text-2xl font-semibold text-slate-900">Post-Session Review</h1>
        <p className="text-sm text-slate-500">Session #{sessionId} with {clientName}</p>
      </div>

      {/* Processing state */}
      {isProcessing && (
        <Card>
          <CardContent className="py-12 text-center">
            <div className="mx-auto mb-4 h-8 w-8 animate-spin rounded-full border-2 border-slate-200 border-t-blue-600" />
            <p className="text-sm font-medium text-slate-900">Processing recording...</p>
            <p className="mt-1 text-xs text-slate-500">
              Extracting audio and generating transcript with speaker identification.
              This may take a few minutes.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Failed state */}
      {isFailed && (
        <Card>
          <CardContent className="py-8 text-center">
            <p className="text-sm text-red-700">
              Recording processing failed. You can upload a transcript manually instead.
            </p>
            <Button
              variant="outline"
              size="sm"
              className="mt-3"
              onClick={() =>
                navigate('/therapist/sessions/new', {
                  state: { clientId, clientName },
                })
              }
            >
              Upload Transcript
            </Button>
          </CardContent>
        </Card>
      )}

      {/* No recording */}
      {!sessionStatus?.recording_status && (
        <Card>
          <CardContent className="py-8 text-center">
            <p className="text-sm text-slate-500">
              No recording was made for this session.
              You can upload a transcript manually to generate a treatment plan.
            </p>
            <Button
              variant="outline"
              size="sm"
              className="mt-3"
              onClick={() =>
                navigate('/therapist/sessions/new', {
                  state: { clientId, clientName },
                })
              }
            >
              Upload Transcript
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Speaker assignment */}
      {isComplete && preview && !confirmed && (
        <Card>
          <CardHeader>
            <CardTitle className="text-slate-900">Confirm Speakers</CardTitle>
            <CardDescription>
              We identified {preview.speakers.length} speakers. Please confirm who is who
              by reviewing the sample utterances below.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {preview.speakers.map((speaker) => (
              <div key={speaker} className="rounded-lg border p-4">
                <div className="mb-3 flex items-center justify-between">
                  <span className="text-sm font-medium text-slate-500">
                    {speaker.replace('_', ' ')}
                  </span>
                  <select
                    value={speakerMap[speaker] ?? 'unknown'}
                    onChange={(e) =>
                      setSpeakerMap((prev) => ({ ...prev, [speaker]: e.target.value }))
                    }
                    className="rounded-md border border-slate-200 px-3 py-1.5 text-sm font-medium"
                  >
                    <option value="therapist">Therapist</option>
                    <option value="client">Client</option>
                  </select>
                </div>
                <div className="space-y-2">
                  {getSamples(speaker).map((u, i) => (
                    <div key={i} className="rounded bg-slate-50 p-2 text-sm text-slate-700">
                      &ldquo;{u.text}&rdquo;
                    </div>
                  ))}
                  {getSamples(speaker).length === 0 && (
                    <p className="text-xs text-slate-400">No utterances found</p>
                  )}
                </div>
              </div>
            ))}

            {confirmSpeakers.isError && (
              <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
                Failed to confirm speakers. Please try again.
              </div>
            )}

            <div className="flex justify-end">
              <Button
                onClick={() => confirmSpeakers.mutate()}
                disabled={confirmSpeakers.isPending}
              >
                {confirmSpeakers.isPending ? 'Confirming...' : 'Confirm & Continue'}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Generate plan */}
      {confirmed && !generating && (
        <Card>
          <CardContent className="py-8 text-center">
            <p className="mb-2 text-sm font-medium text-slate-900">
              Transcript is ready!
            </p>
            <p className="mb-4 text-xs text-slate-500">
              Speaker labels have been confirmed. You can now generate a treatment plan
              from this session's transcript.
            </p>
            <Button onClick={() => setGenerating(true)}>
              Generate Treatment Plan
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Generation progress (reuse existing component) */}
      {generating && (
        <GenerationProgress
          sessionId={Number(sessionId)}
          clientId={clientId}
          onClose={() => setGenerating(false)}
        />
      )}
    </div>
  )
}
