import { Lock } from 'lucide-react'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip'
import { cn } from '@/lib/utils'
import type { HomeworkItem as HomeworkItemType } from '@/types'

interface HomeworkItemProps {
  item: HomeworkItemType
  onToggle: (id: number) => void
  isUpdating: boolean
}

const LOCKED_HINT =
  'This item stays checked once completed. If you need a change, contact your therapist.'

export default function HomeworkItem({ item, onToggle, isUpdating }: HomeworkItemProps) {
  const isLocked = item.completed

  const rowClassName = cn(
    'flex items-start gap-3 rounded-xl border p-4 transition-colors',
    isLocked
      ? 'cursor-default border-green-200 bg-green-50/60'
      : 'cursor-pointer border-slate-200 bg-white hover:border-teal-200 hover:bg-teal-50/30',
    isUpdating && 'pointer-events-none opacity-60'
  )

  const checkbox = (
    <Checkbox
      checked={item.completed}
      onCheckedChange={() => {
        if (!item.completed) {
          onToggle(item.id)
        }
      }}
      disabled={isLocked || isUpdating}
      className={cn(
        'mt-0.5',
        isLocked && 'cursor-not-allowed opacity-70 data-checked:opacity-90'
      )}
    />
  )

  const checkboxSlot = isLocked ? (
    <Tooltip>
      <TooltipTrigger
        nativeButton={false}
        render={(props) => (
          <span
            {...props}
            className={cn(
              props.className,
              'inline-flex shrink-0 items-center gap-1.5 rounded-md outline-none mt-0.5 cursor-help focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2'
            )}
          >
            {checkbox}
            <Lock
              className="size-3.5 shrink-0 text-green-700"
              aria-hidden
            />
          </span>
        )}
      />
      <TooltipContent side="top" className="max-w-xs text-left">
        <p>{LOCKED_HINT}</p>
      </TooltipContent>
    </Tooltip>
  ) : (
    checkbox
  )

  const body = (
    <>
      {checkboxSlot}
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            'text-sm leading-relaxed',
            isLocked ? 'text-green-700 line-through' : 'text-slate-700'
          )}
        >
          {item.description}
        </p>
        {isLocked && item.completed_at && (
          <p className="mt-1 text-xs text-green-600">
            Completed {new Date(item.completed_at).toLocaleDateString()}
          </p>
        )}
      </div>
    </>
  )

  if (isLocked) {
    return <div className={rowClassName}>{body}</div>
  }

  return <label className={rowClassName}>{body}</label>
}
