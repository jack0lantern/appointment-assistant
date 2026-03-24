import { useState, useRef, useEffect } from 'react'
import { MessageCircle, X, RotateCcw, Bot } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useChat } from '@/hooks/useChat'
import ChatMessage from './ChatMessage'
import ChatInput from './ChatInput'
import QuickActions from './QuickActions'
import DocumentUpload from './DocumentUpload'
import type { AgentContextType, SuggestedAction } from '@/types/agent'

interface ChatWidgetProps {
  contextType?: AgentContextType
  pageContext?: Record<string, unknown>
  initialConversationId?: string
}

// Flow-graph aligned initial actions when chat is empty (per docs/chat-flow-graph.md)
const FLOW_GRAPH_ACTIONS: Record<AgentContextType, SuggestedAction[]> = {
  general: [
    { label: 'Help me get started', action_type: 'message', payload: "I'm new and want to get started" },
    { label: 'Schedule an appointment', action_type: 'message', payload: "I'd like to schedule an appointment" },
  ],
  onboarding: [
    { label: 'Start onboarding', action_type: 'message', payload: "I'd like to start the onboarding process" },
    { label: 'Upload a document', action_type: 'message', payload: "I want to upload my insurance card" },
    { label: 'What do I need?', action_type: 'message', payload: 'What information do I need to provide?' },
  ],
  scheduling: [
    { label: 'Find available times', action_type: 'message', payload: "What times are available this week?" },
    { label: 'Reschedule my appointment', action_type: 'message', payload: "I need to reschedule my appointment" },
    { label: 'Cancel appointment', action_type: 'message', payload: "I need to cancel my appointment" },
  ],
  emotional_support: [
    { label: 'Talk to someone now', action_type: 'message', payload: "I need to talk to someone right now" },
    { label: 'Breathing exercise', action_type: 'message', payload: "Can you guide me through a breathing exercise?" },
    { label: 'Schedule a session', action_type: 'message', payload: "I'd like to schedule a session with my therapist" },
  ],
  document_upload: [
    { label: 'Upload insurance card', action_type: 'message', payload: "I want to upload my insurance card" },
    { label: 'Upload ID', action_type: 'message', payload: "I want to upload my ID" },
    { label: 'What documents do I need?', action_type: 'message', payload: 'What documents do I need to provide?' },
  ],
}

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

  const activeActions =
    messages.length === 0 ? FLOW_GRAPH_ACTIONS[contextType] : suggestedActions
  const showDocUpload = onboardingState?.step === 'documents' && !onboardingState.docs_verified

  const handleSelectTherapist = (displayLabel: string) => {
    sendMessage(`I'd like to go with ${displayLabel}`)
  }

  const handleSelectAppointment = (cancelPayload: string) => {
    sendMessage(cancelPayload)
  }

  return (
    <>
      {/* Floating trigger button */}
      {!isOpen && (
        <button
          onClick={() => setIsOpen(true)}
          className="fixed bottom-6 right-6 z-50 flex h-14 w-14 items-center justify-center rounded-full
                     bg-gradient-to-br from-teal-500 to-teal-600 text-white shadow-lg shadow-teal-200/50
                     transition-all hover:shadow-xl hover:shadow-teal-200/50 hover:scale-105
                     focus:outline-none focus:ring-2 focus:ring-teal-400 focus:ring-offset-2"
          aria-label="Open chat assistant"
        >
          <MessageCircle className="h-6 w-6" />
        </button>
      )}

      {/* Chat panel */}
      {isOpen && (
        <div
          className="fixed bottom-6 right-6 z-50 flex w-[400px] flex-col rounded-2xl border
                     border-slate-200/80 bg-white shadow-2xl shadow-slate-200/50"
          style={{ maxHeight: 'calc(100vh - 120px)', height: '640px' }}
        >
          {/* Header */}
          <div className="flex items-center justify-between rounded-t-2xl bg-gradient-to-r from-teal-500 to-teal-600 px-4 py-3.5">
            <div className="flex items-center gap-2.5">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-white/20">
                <Bot className="h-4 w-4 text-white" />
              </div>
              <div>
                <h3 className="text-sm font-semibold text-white">Assistant</h3>
                <p className="text-[11px] text-teal-100">Here to help you every step</p>
              </div>
            </div>
            <div className="flex items-center gap-0.5">
              <Button
                variant="ghost"
                size="sm"
                onClick={clearChat}
                className="h-8 w-8 p-0 text-teal-100 hover:bg-white/10 hover:text-white"
                aria-label="Clear chat"
              >
                <RotateCcw className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setIsOpen(false)}
                className="h-8 w-8 p-0 text-teal-100 hover:bg-white/10 hover:text-white"
                aria-label="Close chat"
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </div>

          {/* Messages area */}
          <div className="flex-1 overflow-y-auto px-3 py-4 space-y-3 bg-slate-50/50">
            {messages.length === 0 && (
              <div className="flex flex-col items-center text-center py-10">
                <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-teal-500 to-teal-600 shadow-md shadow-teal-200/50">
                  <Bot className="h-6 w-6 text-white" />
                </div>
                <p className="font-medium text-slate-700 mb-1">How can I help?</p>
                <p className="text-xs text-slate-500 max-w-[240px] leading-relaxed">
                  I can help with scheduling, onboarding, or just being here for you.
                </p>
                <p className="mt-3 text-[11px] text-slate-400">
                  In crisis? Call <span className="font-medium text-teal-600">988</span>
                </p>
              </div>
            )}

            {messages.map((msg, i) => (
              <ChatMessage
                key={i}
                message={msg}
                onSelectTherapist={handleSelectTherapist}
                onSelectAppointment={handleSelectAppointment}
              />
            ))}

            {isLoading && (
              <div className="flex justify-start gap-2.5">
                <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-teal-500 to-teal-600">
                  <Bot className="h-3.5 w-3.5 text-white" />
                </div>
                <div className="rounded-2xl rounded-tl-md bg-white px-4 py-3 shadow-sm border border-slate-100">
                  <div className="flex gap-1.5">
                    <span className="h-2 w-2 animate-bounce rounded-full bg-teal-400" style={{ animationDelay: '0ms' }} />
                    <span className="h-2 w-2 animate-bounce rounded-full bg-teal-400" style={{ animationDelay: '150ms' }} />
                    <span className="h-2 w-2 animate-bounce rounded-full bg-teal-400" style={{ animationDelay: '300ms' }} />
                  </div>
                </div>
              </div>
            )}

            {error && (
              <div className="rounded-xl bg-red-50 border border-red-100 px-3 py-2 text-xs text-red-600">
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
          <ChatInput
            onSend={sendMessage}
            onUpload={uploadDocument}
            disabled={isLoading}
          />
        </div>
      )}
    </>
  )
}
