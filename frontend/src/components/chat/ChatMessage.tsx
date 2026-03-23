import type { ChatMessage as ChatMessageType } from '@/types/agent'
import { cn } from '@/lib/utils'
import TherapistCard from './TherapistCard'
import { FileCheck } from 'lucide-react'

interface ChatMessageProps {
  message: ChatMessageType
  onSelectTherapist?: (displayLabel: string) => void
}

export default function ChatMessage({ message, onSelectTherapist }: ChatMessageProps) {
  const isUser = message.role === 'user'

  // Rich rendering for therapist search results
  if (message.rich_type === 'therapist_results' && message.therapist_results?.length) {
    return (
      <div className="flex w-full justify-start">
        <div className="max-w-[90%] space-y-2">
          <div className="rounded-2xl rounded-bl-md bg-slate-100 px-4 py-2.5 text-sm leading-relaxed text-slate-800">
            <div className="whitespace-pre-wrap break-words">{message.content}</div>
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

  // Rich rendering for document upload status
  if (message.rich_type === 'document_status' && message.document_result) {
    return (
      <div className="flex w-full justify-start">
        <div className="max-w-[85%] rounded-2xl rounded-bl-md bg-green-50 px-4 py-3 text-sm">
          <div className="flex items-center gap-2 text-green-700 font-medium mb-1">
            <FileCheck className="h-4 w-4" />
            Document Verified
          </div>
          <p className="text-xs text-green-600">{message.content}</p>
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
        <div className="whitespace-pre-wrap break-words">{message.content}</div>
      </div>
    </div>
  )
}
