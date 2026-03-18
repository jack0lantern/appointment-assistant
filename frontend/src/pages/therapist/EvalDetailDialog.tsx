import { useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import api from '@/api/client'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

type EvalCategory = 'structural' | 'readability' | 'safety'

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
  safety?: SafetyResult | null
  safety_flags_detail?: SafetyFlagDetail[] | null
}

function StatusBadge({ pass }: { pass: boolean }) {
  return (
    <Badge variant={pass ? 'default' : 'destructive'} className={pass ? 'bg-green-600' : ''}>
      {pass ? 'Pass' : 'Fail'}
    </Badge>
  )
}

function DeltaText({ value, threshold, direction }: { value: number; threshold: number; direction: 'lte' | 'gte' }) {
  const pass = direction === 'lte' ? value <= threshold : value >= threshold
  const delta = direction === 'lte' ? value - threshold : threshold - value
  if (pass) return <span className="text-green-600">OK</span>
  return <span className="text-red-500">{delta > 0 ? `+${delta.toFixed(1)} over` : `${Math.abs(delta).toFixed(1)} short`}</span>
}

function StructuralDetail({ structural }: { structural: StructuralResult }) {
  const checks = [
    {
      label: 'Required Fields',
      pass: structural.missing_fields.length === 0,
      detail: structural.missing_fields.length > 0 ? structural.missing_fields.join(', ') : 'All present',
    },
    {
      label: 'Validation Errors',
      pass: structural.errors.length === 0,
      detail: structural.errors.length > 0 ? structural.errors.join('; ') : 'None',
    },
    {
      label: 'Client Jargon',
      pass: structural.jargon_found.length === 0,
      detail: structural.jargon_found.length > 0 ? structural.jargon_found.join(', ') : 'None found',
    },
    {
      label: 'Risk Data in Client',
      pass: !structural.risk_data_found,
      detail: structural.risk_data_found ? 'Risk terms detected' : 'Clean',
    },
    {
      label: 'Citation Bounds',
      pass: structural.citation_bounds_valid,
      detail: structural.citation_bounds_valid ? 'All valid' : 'Out-of-bounds citations',
    },
  ]

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Check</TableHead>
          <TableHead className="text-center">Status</TableHead>
          <TableHead>Details</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {checks.map((c) => (
          <TableRow key={c.label}>
            <TableCell className="font-medium">{c.label}</TableCell>
            <TableCell className="text-center"><StatusBadge pass={c.pass} /></TableCell>
            <TableCell className="text-xs text-slate-600">{c.detail}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

function ReadabilityDetail({ readability }: { readability: ReadabilityResult }) {
  const t = readability.therapist_scores
  const c = readability.client_scores
  const separation = t.flesch_kincaid_grade - c.flesch_kincaid_grade

  return (
    <div className="space-y-3">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Metric</TableHead>
            <TableHead className="text-center">Therapist</TableHead>
            <TableHead className="text-center">Client</TableHead>
            <TableHead className="text-center">Threshold</TableHead>
            <TableHead className="text-center">Status</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow>
            <TableCell className="font-medium">FK Grade</TableCell>
            <TableCell className="text-center">{t.flesch_kincaid_grade.toFixed(1)}</TableCell>
            <TableCell className="text-center">{c.flesch_kincaid_grade.toFixed(1)}</TableCell>
            <TableCell className="text-center text-slate-500">&le; 8.0</TableCell>
            <TableCell className="text-center">
              <DeltaText value={c.flesch_kincaid_grade} threshold={8.0} direction="lte" />
            </TableCell>
          </TableRow>
          <TableRow>
            <TableCell className="font-medium">Separation</TableCell>
            <TableCell colSpan={2} className="text-center">{separation.toFixed(1)} grades</TableCell>
            <TableCell className="text-center text-slate-500">&ge; 2.0</TableCell>
            <TableCell className="text-center">
              <DeltaText value={separation} threshold={2.0} direction="gte" />
            </TableCell>
          </TableRow>
          <TableRow className="text-slate-500">
            <TableCell>Flesch Ease</TableCell>
            <TableCell className="text-center">{(t.flesch_reading_ease ?? 0).toFixed(1)}</TableCell>
            <TableCell className="text-center">{(c.flesch_reading_ease ?? 0).toFixed(1)}</TableCell>
            <TableCell className="text-center">-</TableCell>
            <TableCell className="text-center">-</TableCell>
          </TableRow>
          <TableRow className="text-slate-500">
            <TableCell>Gunning Fog</TableCell>
            <TableCell className="text-center">{(t.gunning_fog ?? 0).toFixed(1)}</TableCell>
            <TableCell className="text-center">{(c.gunning_fog ?? 0).toFixed(1)}</TableCell>
            <TableCell className="text-center">-</TableCell>
            <TableCell className="text-center">-</TableCell>
          </TableRow>
          <TableRow className="text-slate-500">
            <TableCell>Avg Sentence Len</TableCell>
            <TableCell className="text-center">{(t.avg_sentence_length ?? 0).toFixed(1)}</TableCell>
            <TableCell className="text-center">{(c.avg_sentence_length ?? 0).toFixed(1)}</TableCell>
            <TableCell className="text-center">-</TableCell>
            <TableCell className="text-center">-</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>
  )
}

function SafetyDetail({ safety, flags }: { safety: SafetyResult; flags?: SafetyFlagDetail[] | null }) {
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-4 text-sm">
        <span>Expected: <strong>{safety.expected_flags}</strong></span>
        <span>Detected: <strong>{safety.detected_flags}</strong></span>
        <StatusBadge pass={safety.passed} />
      </div>

      {flags && flags.length > 0 && (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Flag Type</TableHead>
              <TableHead>Severity</TableHead>
              <TableHead>Lines</TableHead>
              <TableHead>Excerpt</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {flags.map((f, i) => (
              <TableRow key={i}>
                <TableCell className="font-mono text-xs">{f.flag_type}</TableCell>
                <TableCell>
                  <Badge variant={
                    f.severity === 'critical' ? 'destructive' :
                    f.severity === 'high' ? 'destructive' :
                    'outline'
                  }>
                    {f.severity}
                  </Badge>
                </TableCell>
                <TableCell className="text-xs">
                  {f.line_start != null ? `${f.line_start}-${f.line_end}` : '-'}
                </TableCell>
                <TableCell className="max-w-[200px] truncate text-xs text-slate-600">
                  {f.transcript_excerpt ?? f.description ?? '-'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {(!flags || flags.length === 0) && safety.detected_flags > 0 && (
        <p className="text-xs text-slate-400">
          Flag details not available for this run. Re-run evaluation to see details.
        </p>
      )}
    </div>
  )
}

const CATEGORY_TITLES: Record<EvalCategory, string> = {
  structural: 'Structural Validation',
  readability: 'Readability Analysis',
  safety: 'Safety Detection',
}

export default function EvalDetailDialog({
  category,
  result,
  open,
  onOpenChange,
}: {
  category: EvalCategory | null
  result: TranscriptEvalResult | null
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [suggestions, setSuggestions] = useState<string[] | null>(null)

  const suggestionMutation = useMutation({
    mutationFn: async () => {
      if (!result || !category) return []
      const evalData = category === 'structural' ? result.structural
        : category === 'readability' ? result.readability
        : result.safety
      const { data } = await api.post<{ suggestions: string[] }>('/api/evaluation/suggestions', {
        transcript_name: result.transcript_name,
        category,
        eval_result: evalData,
      })
      return data.suggestions
    },
    onSuccess: (data) => setSuggestions(data),
  })

  const handleGetSuggestions = () => {
    setSuggestions(null)
    suggestionMutation.mutate()
  }

  // Reset suggestions when dialog closes
  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen) {
      setSuggestions(null)
      suggestionMutation.reset()
    }
    onOpenChange(newOpen)
  }

  if (!result || !category) return null

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {CATEGORY_TITLES[category]}: <span className="font-mono">{result.transcript_name}</span>
          </DialogTitle>
          <DialogDescription>
            Detailed evaluation metrics and threshold comparisons
          </DialogDescription>
        </DialogHeader>

        <div className="py-2">
          {category === 'structural' && <StructuralDetail structural={result.structural} />}
          {category === 'readability' && <ReadabilityDetail readability={result.readability} />}
          {category === 'safety' && result.safety && (
            <SafetyDetail safety={result.safety} flags={result.safety_flags_detail} />
          )}
        </div>

        {/* Suggestions section */}
        {suggestions && (
          <div className="rounded-md bg-blue-50 p-3">
            <h4 className="mb-2 text-sm font-semibold text-blue-800">Improvement Suggestions</h4>
            <ul className="list-disc space-y-1 pl-5 text-sm text-blue-700">
              {suggestions.map((s, i) => (
                <li key={i}>{s}</li>
              ))}
            </ul>
          </div>
        )}

        {suggestionMutation.isError && (
          <p className="text-sm text-red-500">
            Failed to get suggestions: {suggestionMutation.error?.message ?? 'Unknown error'}
          </p>
        )}

        <DialogFooter showCloseButton>
          <Button
            onClick={handleGetSuggestions}
            disabled={suggestionMutation.isPending}
            variant="outline"
            className="border-blue-200 text-blue-700 hover:bg-blue-50"
          >
            {suggestionMutation.isPending ? (
              <span className="flex items-center gap-2">
                <span className="h-3 w-3 animate-spin rounded-full border-2 border-blue-600 border-t-transparent" />
                Analyzing...
              </span>
            ) : (
              'Get Improvement Suggestions'
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
