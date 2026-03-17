import type { HomeworkItem as HomeworkItemType } from '@/types'
import HomeworkItem from './HomeworkItem'

interface HomeworkChecklistProps {
  items: HomeworkItemType[]
  onToggle: (id: number) => void
  updatingId: number | null
}

export default function HomeworkChecklist({ items, onToggle, updatingId }: HomeworkChecklistProps) {
  const completedCount = items.filter((i) => i.completed).length
  const allDone = items.length > 0 && completedCount === items.length

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-slate-600">
          {completedCount} of {items.length} completed
        </p>
        <div className="h-2 w-32 overflow-hidden rounded-full bg-slate-100">
          <div
            className="h-full rounded-full bg-teal-500 transition-all duration-500"
            style={{
              width: items.length > 0 ? `${(completedCount / items.length) * 100}%` : '0%',
            }}
          />
        </div>
      </div>

      <div className="space-y-3">
        {items.map((item) => (
          <HomeworkItem
            key={item.id}
            item={item}
            onToggle={onToggle}
            isUpdating={updatingId === item.id}
          />
        ))}
      </div>

      {allDone && (
        <div className="rounded-xl border border-green-200 bg-green-50 p-5 text-center">
          <p className="text-lg font-semibold text-green-700">Great work this week!</p>
          <p className="mt-1 text-sm text-green-600">
            You've completed all your homework. Keep up the momentum!
          </p>
        </div>
      )}
    </div>
  )
}
