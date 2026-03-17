import { Checkbox } from '@/components/ui/checkbox'
import type { HomeworkItem as HomeworkItemType } from '@/types'

interface HomeworkItemProps {
  item: HomeworkItemType
  onToggle: (id: number) => void
  isUpdating: boolean
}

export default function HomeworkItem({ item, onToggle, isUpdating }: HomeworkItemProps) {
  return (
    <label
      className={`flex items-start gap-3 rounded-xl border p-4 transition-all cursor-pointer ${
        item.completed
          ? 'border-green-200 bg-green-50/60'
          : 'border-slate-200 bg-white hover:border-teal-200 hover:bg-teal-50/30'
      } ${isUpdating ? 'opacity-60 pointer-events-none' : ''}`}
    >
      <Checkbox
        checked={item.completed}
        onCheckedChange={() => {
          if (!item.completed) {
            onToggle(item.id)
          }
        }}
        disabled={item.completed || isUpdating}
        className="mt-0.5"
      />
      <div className="flex-1 min-w-0">
        <p
          className={`text-sm leading-relaxed ${
            item.completed ? 'text-green-700 line-through' : 'text-slate-700'
          }`}
        >
          {item.description}
        </p>
        {item.completed && item.completed_at && (
          <p className="mt-1 text-xs text-green-500">
            Completed {new Date(item.completed_at).toLocaleDateString()}
          </p>
        )}
      </div>
      {item.completed && (
        <span className="text-green-500 text-lg leading-none" aria-hidden="true">
          &#10003;
        </span>
      )}
    </label>
  )
}
