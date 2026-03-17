import { useState } from 'react'
import type { Citation, GoalItem, InterventionItem } from '@/types'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Card, CardHeader, CardTitle, CardContent, CardAction } from '@/components/ui/card'

type SectionItem = string | GoalItem | InterventionItem

interface PlanSectionProps {
  title: string
  items: SectionItem[]
  citations?: Citation[]
  onSave: (updated: string) => void
  isSaving: boolean
  onShowCitations: (citations: Citation[]) => void
}

function renderItem(item: SectionItem): string {
  if (typeof item === 'string') return item
  if ('description' in item && 'name' in item) {
    const iv = item as InterventionItem
    return `[${iv.modality}] ${iv.name}: ${iv.description}`
  }
  if ('description' in item) {
    const gi = item as GoalItem
    const parts = [gi.description]
    if (gi.modality) parts.push(`(${gi.modality})`)
    if (gi.timeframe) parts.push(`— ${gi.timeframe}`)
    return parts.join(' ')
  }
  return String(item)
}

function itemsToText(items: SectionItem[]): string {
  return items.map(renderItem).join('\n')
}

export default function PlanSection({
  title,
  items,
  citations = [],
  onSave,
  isSaving,
  onShowCitations,
}: PlanSectionProps) {
  const [isEditing, setIsEditing] = useState(false)
  const [editValue, setEditValue] = useState('')

  const handleEdit = () => {
    setEditValue(itemsToText(items))
    setIsEditing(true)
  }

  const handleCancel = () => {
    setIsEditing(false)
    setEditValue('')
  }

  const handleSave = () => {
    onSave(editValue)
    setIsEditing(false)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-slate-900">{title}</CardTitle>
        <CardAction>
          <div className="flex gap-1">
            {citations.length > 0 && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onShowCitations(citations)}
              >
                Show Citations ({citations.length})
              </Button>
            )}
            {!isEditing && (
              <Button variant="outline" size="sm" onClick={handleEdit}>
                Edit
              </Button>
            )}
          </div>
        </CardAction>
      </CardHeader>
      <CardContent>
        {isEditing ? (
          <div className="space-y-3">
            <Textarea
              value={editValue}
              onChange={(e) => setEditValue(e.target.value)}
              className="min-h-[120px] font-mono text-sm"
            />
            <div className="flex gap-2">
              <Button size="sm" onClick={handleSave} disabled={isSaving}>
                {isSaving ? 'Saving...' : 'Save'}
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={handleCancel}
                disabled={isSaving}
              >
                Cancel
              </Button>
            </div>
          </div>
        ) : items.length === 0 ? (
          <p className="text-sm text-slate-400 italic">No data available.</p>
        ) : (
          <ul className="list-inside list-disc space-y-1 text-sm text-slate-700">
            {items.map((item, idx) => (
              <li key={idx}>{renderItem(item)}</li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
