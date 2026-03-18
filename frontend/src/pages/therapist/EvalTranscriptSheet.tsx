import { useQuery } from '@tanstack/react-query'
import api from '@/api/client'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from '@/components/ui/sheet'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'

interface TranscriptEvalResult {
  transcript_name: string
  therapist_content?: Record<string, unknown> | null
  client_content?: Record<string, unknown> | null
  transcript_text?: string | null
  generation_time_seconds: number
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-4">
      <h4 className="mb-1.5 text-sm font-semibold text-slate-700">{title}</h4>
      {children}
    </div>
  )
}

function RenderList({ items }: { items: unknown[] }) {
  return (
    <ul className="list-disc space-y-1 pl-5 text-sm text-slate-600">
      {items.map((item, i) => (
        <li key={i}>
          {typeof item === 'string'
            ? item
            : typeof item === 'object' && item !== null
              ? Object.entries(item as Record<string, unknown>)
                  .filter(([k]) => !k.endsWith('_citations'))
                  .map(([k, v]) => `${k}: ${v}`)
                  .join(' | ')
              : String(item)}
        </li>
      ))}
    </ul>
  )
}

function PlanView({ content, label }: { content: Record<string, unknown>; label: string }) {
  const sectionOrder = label === 'therapist'
    ? ['presenting_concerns', 'goals', 'interventions', 'homework', 'strengths', 'barriers', 'diagnosis_considerations']
    : ['what_we_talked_about', 'your_goals', 'things_to_try', 'your_strengths', 'next_steps']

  const formatTitle = (key: string) =>
    key.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())

  return (
    <div className="space-y-3">
      {sectionOrder.map((key) => {
        const val = content[key]
        if (!val) return null
        return (
          <Section key={key} title={formatTitle(key)}>
            {typeof val === 'string' ? (
              <p className="text-sm text-slate-600">{val}</p>
            ) : Array.isArray(val) ? (
              <RenderList items={val} />
            ) : (
              <p className="text-sm text-slate-600">{JSON.stringify(val)}</p>
            )}
          </Section>
        )
      })}
    </div>
  )
}

export default function EvalTranscriptSheet({
  result,
  open,
  onOpenChange,
}: {
  result: TranscriptEvalResult | null
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const name = result?.transcript_name ?? ''

  // Fallback: fetch transcript text from API if not in result
  const { data: fetchedText } = useQuery<string>({
    queryKey: ['transcript-text', name],
    queryFn: async () => {
      const { data } = await api.get<string>(`/api/evaluation/transcripts/${name}`, {
        responseType: 'text',
        transformResponse: [(d: string) => d],
      })
      return data
    },
    enabled: open && !!name && !result?.transcript_text,
  })

  const transcriptText = result?.transcript_text ?? fetchedText ?? null

  if (!result) return null

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="sm:max-w-2xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <span className="font-mono">{result.transcript_name}</span>
            <Badge variant="outline" className="text-xs">
              {result.generation_time_seconds.toFixed(1)}s
            </Badge>
          </SheetTitle>
          <SheetDescription>
            Transcript, therapist plan, and client plan
          </SheetDescription>
        </SheetHeader>

        <div className="px-4 pb-4">
          <Tabs defaultValue="transcript">
            <TabsList>
              <TabsTrigger value="transcript">Transcript</TabsTrigger>
              <TabsTrigger value="therapist">Therapist Plan</TabsTrigger>
              <TabsTrigger value="client">Client Plan</TabsTrigger>
            </TabsList>

            <TabsContent value="transcript" className="mt-3">
              {transcriptText ? (
                <pre className="max-h-[60vh] overflow-auto rounded-md bg-slate-50 p-4 text-xs leading-relaxed text-slate-700 whitespace-pre-wrap">
                  {transcriptText}
                </pre>
              ) : (
                <p className="py-8 text-center text-sm text-slate-400">
                  Loading transcript...
                </p>
              )}
            </TabsContent>

            <TabsContent value="therapist" className="mt-3">
              {result.therapist_content ? (
                <PlanView content={result.therapist_content} label="therapist" />
              ) : (
                <p className="py-8 text-center text-sm text-slate-400">
                  Plan content not available for this run. Re-run evaluation to see details.
                </p>
              )}
            </TabsContent>

            <TabsContent value="client" className="mt-3">
              {result.client_content ? (
                <PlanView content={result.client_content} label="client" />
              ) : (
                <p className="py-8 text-center text-sm text-slate-400">
                  Plan content not available for this run. Re-run evaluation to see details.
                </p>
              )}
            </TabsContent>
          </Tabs>
        </div>
      </SheetContent>
    </Sheet>
  )
}
