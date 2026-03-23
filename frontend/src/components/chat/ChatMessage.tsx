import type { ChatMessage as ChatMessageType } from '@/types/agent'
import { cn } from '@/lib/utils'
import TherapistCard from './TherapistCard'
import AppointmentCard from './AppointmentCard'
import { FileCheck } from 'lucide-react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

const markdownClasses = {
  p: 'mb-2 last:mb-0',
  ul: 'my-2 ml-4 list-disc space-y-0.5',
  ol: 'my-2 ml-4 list-decimal space-y-0.5',
  li: 'leading-relaxed',
  strong: 'font-semibold',
  em: 'italic',
  code: 'rounded bg-black/10 px-1 py-0.5 font-mono text-xs',
  pre: 'my-2 overflow-x-auto rounded-lg bg-black/10 p-3 text-xs',
  a: 'underline hover:opacity-80',
  h1: 'mb-2 mt-3 text-base font-bold first:mt-0',
  h2: 'mb-1.5 mt-2 text-sm font-bold first:mt-0',
  h3: 'mb-1 mt-2 text-sm font-semibold first:mt-0',
}

interface ChatMessageProps {
  message: ChatMessageType
  onSelectTherapist?: (displayLabel: string) => void
  onSelectAppointment?: (cancelPayload: string) => void
}

function MarkdownContent({ content, className }: { content: string; className?: string }) {
  return (
    <div className={cn('break-words [&>p:empty]:hidden', className)}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          p: ({ children }) => <p className={markdownClasses.p}>{children}</p>,
          ul: ({ children }) => <ul className={markdownClasses.ul}>{children}</ul>,
          ol: ({ children }) => <ol className={markdownClasses.ol}>{children}</ol>,
          li: ({ children }) => <li className={markdownClasses.li}>{children}</li>,
          strong: ({ children }) => <strong className={markdownClasses.strong}>{children}</strong>,
          em: ({ children }) => <em className={markdownClasses.em}>{children}</em>,
          code: ({ className: _, ...props }) => (
            <code className={markdownClasses.code} {...props} />
          ),
          pre: ({ children }) => <pre className={markdownClasses.pre}>{children}</pre>,
          a: ({ href, children }) => (
            <a href={href} target="_blank" rel="noopener noreferrer" className={markdownClasses.a}>
              {children}
            </a>
          ),
          h1: ({ children }) => <h1 className={markdownClasses.h1}>{children}</h1>,
          h2: ({ children }) => <h2 className={markdownClasses.h2}>{children}</h2>,
          h3: ({ children }) => <h3 className={markdownClasses.h3}>{children}</h3>,
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  )
}

export default function ChatMessage({
  message,
  onSelectTherapist,
  onSelectAppointment,
}: ChatMessageProps) {
  const isUser = message.role === 'user'

  // Rich rendering for therapist search results
  if (message.rich_type === 'therapist_results' && message.therapist_results?.length) {
    return (
      <div className="flex w-full justify-start">
        <div className="max-w-[90%] space-y-2">
          <div className="rounded-2xl rounded-bl-md bg-slate-100 px-4 py-2.5 text-sm leading-relaxed text-slate-800">
            <MarkdownContent content={message.content} />
          </div>
          <div className="space-y-2 pl-1">
            {message.therapist_results.map((t) => (
              <TherapistCard
                key={t.display_label}
                therapist={t}
                onSelect={onSelectTherapist ?? (() => {})}
              />
            ))}
          </div>
        </div>
      </div>
    )
  }

  // Rich rendering for appointment list (cancel flow)
  if (message.rich_type === 'appointment_results' && message.appointment_results?.length) {
    return (
      <div className="flex w-full justify-start">
        <div className="max-w-[90%] space-y-2">
          <div className="rounded-2xl rounded-bl-md bg-slate-100 px-4 py-2.5 text-sm leading-relaxed text-slate-800">
            <MarkdownContent content={message.content} />
          </div>
          <div className="space-y-2 pl-1">
            {message.appointment_results.map((a) => (
              <AppointmentCard
                key={a.session_id}
                appointment={a}
                onSelect={onSelectAppointment ?? (() => {})}
              />
            ))}
          </div>
        </div>
      </div>
    )
  }

  // Rich rendering for document upload status
  if (message.rich_type === 'document_status' && message.document_result) {
    return (
      <div className="flex w-full justify-start">
        <div className="max-w-[85%] rounded-2xl rounded-bl-md bg-green-50 px-4 py-3 text-sm">
          <div className="flex items-center gap-2 text-green-700 font-medium mb-1">
            <FileCheck className="h-4 w-4" />
            Document Verified
          </div>
          <div className="text-xs text-green-600">
            <MarkdownContent content={message.content} className="text-xs [&_*]:text-xs" />
          </div>
          {message.document_result.fields && message.document_result.fields.length > 0 && (
            <div className="mt-2 space-y-1">
              {message.document_result.fields.map((f) => (
                <div key={f.field_name} className="flex justify-between text-xs text-green-700">
                  <span className="font-medium capitalize">{f.field_name.replace('_', ' ')}</span>
                  <span>{f.value}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    )
  }

  // Default text rendering
  return (
    <div className={cn('flex w-full', isUser ? 'justify-end' : 'justify-start')}>
      <div
        className={cn(
          'max-w-[85%] rounded-2xl px-4 py-2.5 text-sm leading-relaxed',
          isUser
            ? 'bg-teal-600 text-white rounded-br-md'
            : 'bg-slate-100 text-slate-800 rounded-bl-md'
        )}
      >
        {isUser ? (
          <div className="whitespace-pre-wrap break-words">{message.content}</div>
        ) : (
          <MarkdownContent content={message.content} />
        )}
      </div>
    </div>
  )
}
