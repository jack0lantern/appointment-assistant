import { useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'

interface VersionSummary {
  id: number
  version_number: number
  source: string
  session_id: number | null
  change_summary: string | null
  created_at: string | null
}

interface VersionHistoryProps {
  versions: VersionSummary[]
  onCompare: (v1: number, v2: number) => void
}

const SOURCE_LABELS: Record<string, string> = {
  ai_generated: 'AI Generated',
  ai_updated: 'AI Updated',
  therapist_edit: 'Therapist Edited',
}

export default function VersionHistory({ versions, onCompare }: VersionHistoryProps) {
  const [selected, setSelected] = useState<number[]>([])

  const toggleSelect = (versionNumber: number) => {
    setSelected((prev) => {
      if (prev.includes(versionNumber)) return prev.filter((v) => v !== versionNumber)
      if (prev.length >= 2) return [prev[1], versionNumber]
      return [...prev, versionNumber]
    })
  }

  const handleCompare = () => {
    if (selected.length === 2) onCompare(selected[0], selected[1])
  }

  if (versions.length === 0) {
    return (
      <p className="text-sm text-slate-500 text-center py-8">No versions yet.</p>
    )
  }

  return (
    <div className="space-y-3">
      {selected.length > 0 && (
        <div className="flex items-center gap-3 p-3 bg-blue-50 rounded-lg text-sm">
          <span className="text-blue-700">
            {selected.length === 1
              ? 'Select a second version to compare'
              : `Comparing v${selected[0]} and v${selected[1]}`}
          </span>
          {selected.length === 2 && (
            <Button size="sm" onClick={handleCompare}>Compare</Button>
          )}
          <Button variant="ghost" size="sm" onClick={() => setSelected([])}>Clear</Button>
        </div>
      )}

      <div className="relative">
        <div className="absolute left-4 top-0 bottom-0 w-px bg-slate-200" />
        <div className="space-y-3">
          {versions.map((v) => {
            const isSelected = selected.includes(v.version_number)
            return (
              <div key={v.id} className="relative pl-10">
                <div
                  className={`absolute left-2.5 top-3 h-3 w-3 rounded-full border-2 ${
                    isSelected ? 'bg-blue-500 border-blue-500' : 'bg-white border-slate-300'
                  }`}
                />
                <Card
                  className={`cursor-pointer transition-colors ${isSelected ? 'border-blue-300' : ''}`}
                  onClick={() => toggleSelect(v.version_number)}
                >
                  <CardContent className="py-3 px-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-sm text-slate-800">
                          v{v.version_number}
                        </span>
                        <Badge variant={v.source === 'therapist_edit' ? 'outline' : 'secondary'}>
                          {SOURCE_LABELS[v.source] ?? v.source}
                        </Badge>
                      </div>
                      {v.created_at && (
                        <span className="text-xs text-slate-400">
                          {new Date(v.created_at).toLocaleDateString('en-US', {
                            month: 'short', day: 'numeric', year: 'numeric',
                          })}
                        </span>
                      )}
                    </div>
                    {v.change_summary && (
                      <p className="mt-1 text-xs text-slate-500">{v.change_summary}</p>
                    )}
                  </CardContent>
                </Card>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
