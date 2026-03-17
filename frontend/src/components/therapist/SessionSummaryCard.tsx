import type { SessionSummary } from '@/types'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

interface SessionSummaryCardProps {
  summary: SessionSummary
}

export default function SessionSummaryCard({ summary }: SessionSummaryCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-slate-900">Session Summary</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          <div>
            <h4 className="mb-1 text-xs font-medium uppercase tracking-wider text-slate-500">
              Therapist Summary
            </h4>
            <p className="text-sm text-slate-700 whitespace-pre-wrap">
              {summary.therapist_summary}
            </p>
          </div>

          {summary.key_themes.length > 0 && (
            <div>
              <h4 className="mb-2 text-xs font-medium uppercase tracking-wider text-slate-500">
                Key Themes
              </h4>
              <div className="flex flex-wrap gap-1.5">
                {summary.key_themes.map((theme, idx) => (
                  <Badge key={idx} variant="secondary">
                    {theme}
                  </Badge>
                ))}
              </div>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
