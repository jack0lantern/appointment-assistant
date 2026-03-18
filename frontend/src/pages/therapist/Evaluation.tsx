import { useState, useRef, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import api from '@/api/client'
import { consumeSSE } from '@/lib/sse'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import EvalTranscriptSheet from './EvalTranscriptSheet'
import EvalDetailDialog from './EvalDetailDialog'

// Evaluation-specific types (not shared globally)
interface ReadabilityScores {
  flesch_kincaid_grade: number
  flesch_reading_ease?: number
  gunning_fog?: number
  avg_sentence_length?: number
  avg_word_length?: number
  [key: string]: number | undefined
}

interface StructuralResult {
  valid: boolean
  missing_fields: string[]
  errors: string[]
  jargon_found: string[]
  risk_data_found: boolean
  citation_bounds_valid: boolean
}

interface ReadabilityResult {
  therapist_scores: ReadabilityScores
  client_scores: ReadabilityScores
  client_grade_ok: boolean
  separation_ok: boolean
  target_met: boolean
}

interface SafetyResult {
  transcript_name: string
  expected_flags: number
  detected_flags: number
  passed: boolean
}

interface SafetyFlagDetail {
  flag_type: string
  severity: string
  description?: string
  transcript_excerpt?: string
  line_start?: number
  line_end?: number
}

interface TranscriptEvalResult {
  transcript_name: string
  structural: StructuralResult
  readability: ReadabilityResult
  safety?: SafetyResult
  generation_time_seconds: number
  therapist_content?: Record<string, unknown> | null
  client_content?: Record<string, unknown> | null
  transcript_text?: string | null
  safety_flags_detail?: SafetyFlagDetail[] | null
}

interface EvaluationRunResponse {
  run_at: string
  results: TranscriptEvalResult[]
  overall_pass: boolean
  total_transcripts: number
  passed_structural: number
  passed_readability: number
  passed_safety: number
}

type EvalCategory = 'structural' | 'readability' | 'safety'

function PassIcon({ pass, onClick }: { pass: boolean; onClick?: () => void }) {
  if (onClick) {
    return (
      <button
        onClick={onClick}
        className="cursor-pointer rounded px-1 transition-colors hover:bg-slate-100"
        title="Click for details"
      >
        <span className={pass ? 'text-green-600' : 'text-red-500'}>{pass ? '✅' : '❌'}</span>
      </button>
    )
  }
  return <span className={pass ? 'text-green-600' : 'text-red-500'}>{pass ? '✅' : '❌'}</span>
}

function GradeCell({ value }: { value: number }) {
  return <span>{value.toFixed(1)}</span>
}

function TranscriptNameCell({
  name,
  onClick,
}: {
  name: string
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="cursor-pointer font-mono text-sm text-blue-600 underline decoration-blue-300 underline-offset-2 transition-colors hover:text-blue-800"
      title="Click to view transcript and plan"
    >
      {name}
    </button>
  )
}

function ResultTables({
  run,
  onTranscriptClick,
  onDetailClick,
}: {
  run: EvaluationRunResponse
  onTranscriptClick: (result: TranscriptEvalResult) => void
  onDetailClick: (result: TranscriptEvalResult, category: EvalCategory) => void
}) {
  const safetyRows = run.results.filter((r) => r.safety != null)

  return (
    <div className="space-y-6">
      {/* Table A — Structural Validation */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base font-semibold text-slate-800">
            Structural Validation
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow className="bg-slate-50">
                <TableHead className="pl-6">Transcript</TableHead>
                <TableHead className="text-center">Schema OK</TableHead>
                <TableHead className="text-center">Citations Valid</TableHead>
                <TableHead className="text-center">No Jargon</TableHead>
                <TableHead className="text-center">No Risk Data</TableHead>
                <TableHead className="text-center">Pass</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {run.results.map((r) => (
                <TableRow key={r.transcript_name}>
                  <TableCell className="pl-6">
                    <TranscriptNameCell name={r.transcript_name} onClick={() => onTranscriptClick(r)} />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={r.structural.missing_fields.length === 0 && r.structural.errors.length === 0}
                      onClick={() => onDetailClick(r, 'structural')}
                    />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={r.structural.citation_bounds_valid}
                      onClick={() => onDetailClick(r, 'structural')}
                    />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={r.structural.jargon_found.length === 0}
                      onClick={() => onDetailClick(r, 'structural')}
                    />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={!r.structural.risk_data_found}
                      onClick={() => onDetailClick(r, 'structural')}
                    />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={r.structural.valid}
                      onClick={() => onDetailClick(r, 'structural')}
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Table B — Readability */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base font-semibold text-slate-800">
            Readability
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow className="bg-slate-50">
                <TableHead className="pl-6">Transcript</TableHead>
                <TableHead className="text-center">Therapist Grade</TableHead>
                <TableHead className="text-center">Client Grade</TableHead>
                <TableHead className="text-center">Client &le; 8th</TableHead>
                <TableHead className="text-center">Separation &ge; 2</TableHead>
                <TableHead className="text-center">Pass</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {run.results.map((r) => (
                <TableRow key={r.transcript_name}>
                  <TableCell className="pl-6">
                    <TranscriptNameCell name={r.transcript_name} onClick={() => onTranscriptClick(r)} />
                  </TableCell>
                  <TableCell className="text-center">
                    <GradeCell value={r.readability.therapist_scores.flesch_kincaid_grade} />
                  </TableCell>
                  <TableCell className="text-center">
                    <GradeCell value={r.readability.client_scores.flesch_kincaid_grade} />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={r.readability.client_grade_ok}
                      onClick={() => onDetailClick(r, 'readability')}
                    />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={r.readability.separation_ok}
                      onClick={() => onDetailClick(r, 'readability')}
                    />
                  </TableCell>
                  <TableCell className="text-center">
                    <PassIcon
                      pass={r.readability.target_met}
                      onClick={() => onDetailClick(r, 'readability')}
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Table C — Safety Detection (only where safety data exists) */}
      {safetyRows.length > 0 && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base font-semibold text-slate-800">
              Safety Detection
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow className="bg-slate-50">
                  <TableHead className="pl-6">Transcript</TableHead>
                  <TableHead className="text-center">Expected</TableHead>
                  <TableHead className="text-center">Detected</TableHead>
                  <TableHead className="text-center">Pass</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {safetyRows.map((r) => (
                  <TableRow key={r.transcript_name}>
                    <TableCell className="pl-6">
                      <TranscriptNameCell name={r.transcript_name} onClick={() => onTranscriptClick(r)} />
                    </TableCell>
                    <TableCell className="text-center">{r.safety!.expected_flags}</TableCell>
                    <TableCell className="text-center">{r.safety!.detected_flags}</TableCell>
                    <TableCell className="text-center">
                      <PassIcon
                        pass={r.safety!.passed}
                        onClick={() => onDetailClick(r, 'safety')}
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Aggregate stats */}
      <Card className="border-slate-200 bg-slate-50">
        <CardContent className="pt-5">
          <div className="space-y-1.5 text-sm text-slate-700">
            <p>
              <span className="font-medium">{run.passed_structural}</span> of{' '}
              <span className="font-medium">{run.total_transcripts}</span> transcripts passed structural
              validation
            </p>
            <p>
              <span className="font-medium">{run.passed_readability}</span> of{' '}
              <span className="font-medium">{run.total_transcripts}</span> transcripts passed readability
              threshold
            </p>
            <p className="mt-3 text-base font-semibold">
              Overall:{' '}
              <Badge
                variant={run.overall_pass ? 'default' : 'destructive'}
                className={run.overall_pass ? 'bg-green-600' : ''}
              >
                {run.overall_pass ? 'PASS' : 'FAIL'}
              </Badge>
            </p>
            <p className="text-xs text-slate-500">
              Run at: {new Date(run.run_at).toLocaleString()}
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

export default function Evaluation() {
  const [isRunning, setIsRunning] = useState(false)
  const [logs, setLogs] = useState<string[]>([])
  const [liveResult, setLiveResult] = useState<EvaluationRunResponse | null>(null)
  const [runError, setRunError] = useState<string | null>(null)
  const abortControllerRef = useRef<AbortController | null>(null)
  const logsEndRef = useRef<HTMLDivElement>(null)

  // Sheet state — transcript/plan viewer
  const [sheetResult, setSheetResult] = useState<TranscriptEvalResult | null>(null)
  const [sheetOpen, setSheetOpen] = useState(false)

  // Dialog state — detail viewer
  const [detailResult, setDetailResult] = useState<TranscriptEvalResult | null>(null)
  const [detailCategory, setDetailCategory] = useState<EvalCategory | null>(null)
  const [detailOpen, setDetailOpen] = useState(false)

  const { data: pastResults, isLoading: loadingPast } = useQuery<EvaluationRunResponse[]>({
    queryKey: ['evaluation-results'],
    queryFn: async () => {
      const { data } = await api.get<EvaluationRunResponse[]>('/api/evaluation/results')
      return data
    },
  })

  const mostRecentPast = pastResults && pastResults.length > 0 ? pastResults[0] : null

  // The result to display: live result takes priority over most recent past
  const displayResult = liveResult ?? mostRecentPast

  // Auto-scroll logs to bottom when new logs are added
  useEffect(() => {
    if (logsEndRef.current) {
      logsEndRef.current.scrollIntoView({ behavior: 'smooth' })
    }
  }, [logs])

  function handleTranscriptClick(result: TranscriptEvalResult) {
    setSheetResult(result)
    setSheetOpen(true)
  }

  function handleDetailClick(result: TranscriptEvalResult, category: EvalCategory) {
    setDetailResult(result)
    setDetailCategory(category)
    setDetailOpen(true)
  }

  async function handleRunEvaluation() {
    setIsRunning(true)
    setRunError(null)
    setLiveResult(null)
    setLogs(['Starting evaluation run...'])
    abortControllerRef.current = new AbortController()

    try {
      await consumeSSE('/api/evaluation/run', {
        method: 'POST',
        signal: abortControllerRef.current.signal,
        onEvent: (event) => {
          if (event.event === 'progress') {
            try {
              const data = JSON.parse(event.data) as { message: string }
              setLogs((prev) => [...prev, data.message])
            } catch {
              setLogs((prev) => [...prev, event.data])
            }
          } else if (event.event === 'log') {
            try {
              const data = JSON.parse(event.data) as { message: string }
              setLogs((prev) => [...prev, data.message])
            } catch {
              setLogs((prev) => [...prev, event.data])
            }
          } else if (event.event === 'complete') {
            try {
              const result = JSON.parse(event.data) as EvaluationRunResponse
              setLiveResult(result)
            } catch {
              setRunError('Failed to parse evaluation result.')
            }
            setIsRunning(false)
          } else if (event.event === 'stopped') {
            try {
              const data = JSON.parse(event.data) as { message: string }
              setLogs((prev) => [...prev, data.message])
            } catch {
              setLogs((prev) => [...prev, event.data])
            }
            setIsRunning(false)
          } else if (event.event === 'error') {
            try {
              const errData = JSON.parse(event.data) as { message: string }
              setRunError(errData.message)
            } catch {
              setRunError(event.data)
            }
            setIsRunning(false)
          }
        },
        onError: (err) => {
          if (err.name !== 'AbortError') {
            setRunError(err.message || 'Connection lost during evaluation.')
            setIsRunning(false)
          }
        },
      })
    } catch (err: unknown) {
      if (!(err instanceof Error && err.name === 'AbortError')) {
        const message = err instanceof Error ? err.message : 'Unknown error'
        setRunError(message)
        setIsRunning(false)
      }
    }
  }

  async function handleStop() {
    // Call backend stop endpoint
    try {
      await api.post('/api/evaluation/stop', {})
    } catch (err) {
      console.error('Failed to stop evaluation:', err)
    }
    // Abort the fetch
    abortControllerRef.current?.abort()
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Evaluation Dashboard</h1>
          <p className="mt-1 text-sm text-slate-500">
            Run structural validation, readability analysis, and safety detection across all fixture
            transcripts.
          </p>
        </div>
        <div className="flex gap-2">
          <Button
            onClick={handleRunEvaluation}
            disabled={isRunning}
            className="bg-blue-600 hover:bg-blue-700"
          >
            {isRunning ? (
              <span className="flex items-center gap-2">
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                Running...
              </span>
            ) : (
              'Run Evaluation'
            )}
          </Button>
          {isRunning && (
            <Button
              onClick={handleStop}
              variant="outline"
              className="text-red-600 hover:bg-red-50"
            >
              Stop
            </Button>
          )}
        </div>
      </div>

      {/* Logs panel while running */}
      {isRunning && logs.length > 0 && (
        <Card className="border-slate-200 bg-slate-900">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-slate-300">Evaluation Progress</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="max-h-48 overflow-y-auto bg-slate-950 p-3">
              {logs.map((line, i) => (
                <p key={i} className="text-xs text-slate-300 font-mono">
                  {line}
                </p>
              ))}
              <div ref={logsEndRef} />
            </div>
          </CardContent>
        </Card>
      )}

      {/* Error display */}
      {runError && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="pt-4 pb-4">
            <p className="text-sm font-medium text-red-700">Evaluation failed</p>
            <p className="mt-1 text-sm text-red-600">{runError}</p>
          </CardContent>
        </Card>
      )}

      {/* Loading skeleton for initial past results fetch */}
      {loadingPast && !displayResult && (
        <div className="space-y-4">
          <Skeleton className="h-48 w-full rounded-lg" />
          <Skeleton className="h-48 w-full rounded-lg" />
        </div>
      )}

      {/* No results yet */}
      {!loadingPast && !displayResult && !isRunning && (
        <Card className="border-dashed">
          <CardContent className="py-12 text-center">
            <p className="text-slate-500">No evaluation results yet. Click "Run Evaluation" to start.</p>
          </CardContent>
        </Card>
      )}

      {/* Results tables */}
      {displayResult && (
        <ResultTables
          run={displayResult}
          onTranscriptClick={handleTranscriptClick}
          onDetailClick={handleDetailClick}
        />
      )}

      {/* Transcript/Plan Sheet */}
      <EvalTranscriptSheet
        result={sheetResult}
        open={sheetOpen}
        onOpenChange={setSheetOpen}
      />

      {/* Detail Dialog */}
      <EvalDetailDialog
        category={detailCategory}
        result={detailResult}
        open={detailOpen}
        onOpenChange={setDetailOpen}
      />
    </div>
  )
}
