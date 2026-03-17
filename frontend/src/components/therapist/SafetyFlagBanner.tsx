import type { SafetyFlag } from '@/types'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

interface SafetyFlagBannerProps {
  flags: SafetyFlag[]
  onAcknowledge: (flagId: number) => void
  isAcknowledging: boolean
}

function severityColor(severity: string): string {
  switch (severity.toLowerCase()) {
    case 'critical':
    case 'high':
      return 'bg-red-50 border-red-300'
    case 'medium':
      return 'bg-amber-50 border-amber-300'
    default:
      return 'bg-yellow-50 border-yellow-300'
  }
}

function severityBadgeVariant(severity: string): 'destructive' | 'secondary' {
  switch (severity.toLowerCase()) {
    case 'critical':
    case 'high':
      return 'destructive'
    default:
      return 'secondary'
  }
}

export default function SafetyFlagBanner({
  flags,
  onAcknowledge,
  isAcknowledging,
}: SafetyFlagBannerProps) {
  const unacknowledged = flags.filter((f) => !f.acknowledged)

  if (unacknowledged.length === 0) return null

  return (
    <div className="space-y-3">
      <div className="rounded-lg border border-red-300 bg-red-50 p-4">
        <h3 className="text-sm font-semibold text-red-800">
          Safety Flags Detected ({unacknowledged.length})
        </h3>
        <p className="mt-1 text-xs text-red-700">
          You must acknowledge all safety flags before approving this treatment
          plan.
        </p>
      </div>

      {unacknowledged.map((flag) => (
        <div
          key={flag.id}
          className={`rounded-lg border p-4 ${severityColor(flag.severity)}`}
        >
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0 flex-1">
              <div className="mb-2 flex flex-wrap items-center gap-2">
                <Badge variant={severityBadgeVariant(flag.severity)}>
                  {flag.severity}
                </Badge>
                <Badge variant="outline">{flag.flag_type}</Badge>
                <span className="text-xs text-slate-500">
                  Lines {flag.line_start}–{flag.line_end}
                </span>
              </div>
              <p className="text-sm text-slate-800">{flag.description}</p>
              {flag.transcript_excerpt && (
                <blockquote className="mt-2 border-l-2 border-slate-300 pl-3 text-xs italic text-slate-600">
                  {flag.transcript_excerpt}
                </blockquote>
              )}
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => onAcknowledge(flag.id)}
              disabled={isAcknowledging}
              className="shrink-0"
            >
              Acknowledge
            </Button>
          </div>
        </div>
      ))}
    </div>
  )
}
