import { useState, useRef, useEffect } from 'react'
import { MessageCircle, X, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useChat } from '@/hooks/useChat'
import ChatMessage from './ChatMessage'
import ChatInput from './ChatInput'
import QuickActions from './QuickActions'
import OnboardingProgress from './OnboardingProgress'
import DocumentUpload from './DocumentUpload'
import type { AgentContextType, SuggestedAction } from '@/types/agent'

interface ChatWidgetProps {
  contextType?: AgentContextType
  pageContext?: Record<string, unknown>
  initialConversationId?: string
}

const DEFAULT_ACTIONS: SuggestedAction[] = [
  { label: 'Help me get started', action_type: 'message', payload: "I'm new and want to get started" },
  { label: 'Schedule an appointment', action_type: 'message', payload: "I'd like to schedule an appointment" },
  { label: "I'm feeling overwhelmed", action_type: 'message', payload: "I'm feeling overwhelmed right now" },
]

export default function ChatWidget({ contextType = 'general', pageContext, initialConversationId }: ChatWidgetProps) {
  const [isOpen, setIsOpen] = useState(!!initialConversationId)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const {
    messages, isLoading, error, suggestedActions,
    onboardingState, sendMessage, uploadDocument, clearChat,
  } = useChat({ contextType, pageContext, initialConversationId })

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, isLoading])

  const activeActions = messages.length === 0 ? DEFAULT_ACTIONS : suggestedActions
  const showDocUpload = onboardingState?.step === 'documents' && !onboardingState.docs_verified

  const handleSelectTherapist = (displayLabel: string) => {
    sendMessage(`I'd like to go with ${displayLabel}`)
  }

  return (
    <>
      {!isOpen && (
        <button
          onClick={() => setIsOpen(true)}
          className="fixed bottom-6 right-6 z-50 flex h-14 w-14 items-center justify-center rounded-full
                     bg-teal-600 text-white shadow-lg transition-all hover:bg-teal-700 hover:scale-105
                     focus:outline-none focus:ring-2 focus:ring-teal-400 focus:ring-offset-2"
          aria-label="Open chat assistant"
        >
          <MessageCircle className="h-6 w-6" />
        </button>
      )}

      {isOpen && (
        <div
          className="fixed bottom-6 right-6 z-50 flex w-[380px] flex-col rounded-2xl border
                     border-slate-200 bg-white shadow-2xl"
          style={{ maxHeight: 'calc(100vh - 120px)', height: '600px' }}
        >
          {/* Header */}
          <div className="flex items-center justify-between rounded-t-2xl bg-teal-600 px-4 py-3">
            <div>
              <h3 className="text-sm font-semibold text-white">Assistant</h3>
              <p className="text-xs text-teal-100">Here to help you every step</p>
            </div>
            <div className="flex items-center gap-1">
              <Button
                variant="ghost"
                size="sm"
                onClick={clearChat}
                className="h-8 w-8 p-0 text-teal-100 hover:bg-teal-700 hover:text-white"
                aria-label="Clear chat"
              >
                <RotateCcw className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setIsOpen(false)}
                className="h-8 w-8 p-0 text-teal-100 hover:bg-teal-700 hover:text-white"
                aria-label="Close chat"
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </div>

          {/* Onboarding progress indicator */}
          {onboardingState && <OnboardingProgress state={onboardingState} />}

          {/* Messages area */}
          <div className="flex-1 overflow-y-auto px-3 py-4 space-y-3">
            {messages.length === 0 && (
              <div className="text-center text-sm text-slate-400 py-8">
                <p className="font-medium text-slate-600 mb-1">Welcome to Appointment Assistant</p>
                <p>I can help with onboarding, scheduling, or just being here for you.</p>
              </div>
            )}

            {messages.map((msg, i) => (
              <ChatMessage
                key={i}
                message={msg}
                onSelectTherapist={handleSelectTherapist}
              />
            ))}

            {isLoading && (
              <div className="flex justify-start">
                <div className="rounded-2xl rounded-bl-md bg-slate-100 px-4 py-3">
                  <div className="flex gap-1">
                    <span className="h-2 w-2 animate-bounce rounded-full bg-slate-400" style={{ animationDelay: '0ms' }} />
                    <span className="h-2 w-2 animate-bounce rounded-full bg-slate-400" style={{ animationDelay: '150ms' }} />
                    <span className="h-2 w-2 animate-bounce rounded-full bg-slate-400" style={{ animationDelay: '300ms' }} />
                  </div>
                </div>
              </div>
            )}

            {error && (
              <div className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">
                {error}
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>

          {/* Document upload widget (shown during documents step) */}
          {showDocUpload && (
            <DocumentUpload onUpload={uploadDocument} disabled={isLoading} />
          )}

          {/* Quick actions */}
          <QuickActions
            actions={activeActions}
            onSelect={sendMessage}
            disabled={isLoading}
          />

          {/* Input */}
          <ChatInput onSend={sendMessage} disabled={isLoading} />
        </div>
      )}
    </>
  )
}
