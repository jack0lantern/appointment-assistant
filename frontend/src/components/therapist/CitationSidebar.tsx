import type { Citation } from '@/types'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from '@/components/ui/sheet'

interface CitationSidebarProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  citations: Citation[]
}

export default function CitationSidebar({
  open,
  onOpenChange,
  citations,
}: CitationSidebarProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Transcript Citations</SheetTitle>
          <SheetDescription>
            Referenced excerpts from the session transcript.
          </SheetDescription>
        </SheetHeader>
        <div className="space-y-4 p-4">
          {citations.length === 0 ? (
            <p className="text-sm text-slate-500">No citations available.</p>
          ) : (
            citations.map((citation, idx) => (
              <div
                key={idx}
                className="rounded-lg border border-slate-200 bg-slate-50 p-3"
              >
                <div className="mb-2 flex items-center gap-2">
                  <span className="rounded bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-700">
                    Lines {citation.line_start}–{citation.line_end}
                  </span>
                </div>
                <blockquote className="border-l-2 border-slate-300 pl-3 text-sm italic text-slate-600">
                  {citation.text}
                </blockquote>
              </div>
            ))
          )}
        </div>
      </SheetContent>
    </Sheet>
  )
}
