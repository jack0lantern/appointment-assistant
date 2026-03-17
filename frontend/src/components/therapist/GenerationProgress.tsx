import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { consumeSSE } from '@/lib/sse'
import { Button } from '@/components/ui/button'

const STAGES = [
  { key: 'preparing', label: 'Preparing' },
  { key: 'analyzing', label: 'Analyzing' },
  { key: 'generating', label: 'Generating Client View' },
  { key: 'validating', label: 'Validating' },
] as const

type StageKey = (typeof STAGES)[number]['key']

interface GenerationProgressProps {
  sessionId: number
  clientId: number
  onClose: () => void
}

export default function GenerationProgress({
  sessionId,
  clientId,
  onClose,
}: GenerationProgressProps) {
  const navigate = useNavigate()
  const [currentStage, setCurrentStage] = useState<StageKey>('preparing')
  const [stageMessage, setStageMessage] = useState('Starting generation...')
  const [error, setError] = useState<string | null>(null)
  const [isComplete, setIsComplete] = useState(false)

  const stageIndex = STAGES.findIndex((s) => s.key === currentStage)

  const startGeneration = useCallback(() => {
    setError(null)
    setCurrentStage('preparing')
    setStageMessage('Starting generation...')
    setIsComplete(false)

    consumeSSE(`/api/sessions/${sessionId}/generate`, {
      method: 'POST',
      onEvent: (event) => {
        if (event.event === 'progress') {
          try {
            const data = JSON.parse(event.data) as { stage: string; message: string }
            const matchedStage = STAGES.find((s) => s.key === data.stage)
            if (matchedStage) {
              setCurrentStage(matchedStage.key)
            }
            setStageMessage(data.message)
          } catch {
            // non-JSON progress message
            setStageMessage(event.data)
          }
        } else if (event.event === 'complete') {
          setIsComplete(true)
          setStageMessage('Treatment plan generated successfully.')
          setTimeout(() => {
            navigate(`/therapist/clients/${clientId}/plan`)
          }, 800)
        } else if (event.event === 'error') {
          setError(event.data || 'An error occurred during generation.')
        }
      },
      onError: (err) => {
        setError(err.message || 'Connection lost during generation.')
      },
    })
  }, [sessionId, clientId, navigate])

  useEffect(() => {
    startGeneration()
  }, [startGeneration])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
      <div className="mx-4 w-full max-w-lg rounded-xl bg-white p-8 shadow-2xl">
        <h2 className="mb-6 text-lg font-semibold text-slate-900">
          Generating Treatment Plan
        </h2>

        <div className="space-y-4">
          {STAGES.map((stage, idx) => {
            let status: 'pending' | 'active' | 'done'
            if (isComplete || idx < stageIndex) {
              status = 'done'
            } else if (idx === stageIndex && !error) {
              status = 'active'
            } else {
              status = 'pending'
            }

            return (
              <div key={stage.key} className="flex items-center gap-3">
                <div
                  className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-medium ${
                    status === 'done'
                      ? 'bg-green-100 text-green-700'
                      : status === 'active'
                        ? 'bg-blue-100 text-blue-700'
                        : 'bg-slate-100 text-slate-400'
                  }`}
                >
                  {status === 'done' ? (
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  ) : (
                    idx + 1
                  )}
                </div>
                <span
                  className={`text-sm ${
                    status === 'done'
                      ? 'font-medium text-green-700'
                      : status === 'active'
                        ? 'font-medium text-blue-700'
                        : 'text-slate-400'
                  }`}
                >
                  {stage.label}
                </span>
                {status === 'active' && !error && (
                  <div className="ml-auto h-4 w-4 animate-spin rounded-full border-2 border-blue-200 border-t-blue-600" />
                )}
              </div>
            )
          })}
        </div>

        <p className="mt-6 text-sm text-slate-500">{stageMessage}</p>

        {error && (
          <div className="mt-4 space-y-3">
            <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
              {error}
            </div>
            <div className="flex gap-2">
              <Button variant="outline" onClick={onClose}>
                Cancel
              </Button>
              <Button onClick={startGeneration}>Retry</Button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
