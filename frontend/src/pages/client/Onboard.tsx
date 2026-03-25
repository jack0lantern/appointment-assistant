import { useEffect, useState, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import api from '@/api/client'
import { useChat } from '@/hooks/useChat'
import { CHAT_STORAGE_VERSION } from '@/lib/chatStorage'
import ChatMessage from '@/components/chat/ChatMessage'
import ChatInput from '@/components/chat/ChatInput'
import QuickActions from '@/components/chat/QuickActions'
import DocumentUpload from '@/components/chat/DocumentUpload'
import OnboardingProgress from '@/components/chat/OnboardingProgress'
import { Heart, Shield, Phone } from 'lucide-react'
import type { SuggestedAction } from '@/types/agent'

interface OnboardResponse {
  conversation_id: string
  therapist_name: string
  context_type: string
  welcome_message: string
}

const ONBOARDING_INITIAL_ACTIONS: SuggestedAction[] = [
  { label: 'Start onboarding', action_type: 'message', payload: "I'd like to start the onboarding process" },
  { label: 'Upload a document', action_type: 'message', payload: 'I want to upload my insurance card' },
  { label: 'What do I need?', action_type: 'message', payload: 'What information do I need to provide?' },
]

export default function Onboard() {
  const { slug } = useParams<{ slug: string }>()
  const navigate = useNavigate()
  const [data, setData] = useState<OnboardResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!slug) return

    const token = localStorage.getItem('token')
    if (!token) {
      localStorage.setItem('onboard_slug', slug)
      navigate('/login/client', { replace: true })
      return
    }

    api
      .get<OnboardResponse>(`/api/onboard/${slug}`)
      .then(({ data }) => {
        setData(data)
        localStorage.removeItem('onboard_slug')
      })
      .catch((err) => {
        if (err.response?.status === 404) {
          setError('This onboarding link is invalid or has expired.')
        } else if (err.response?.status === 401) {
          localStorage.setItem('onboard_slug', slug)
          navigate('/login/client', { replace: true })
        } else {
          setError('Something went wrong. Please try again.')
        }
      })
      .finally(() => setLoading(false))
  }, [slug, navigate])

  const {
    messages, isLoading: chatLoading, error: chatError,
    suggestedActions, onboardingState, sendMessage, uploadDocument,
  } = useChat({
    contextType: 'onboarding',
    initialConversationId: data?.conversation_id,
    persistStorageKey: slug
      ? `appointment-assistant:chat:v${CHAT_STORAGE_VERSION}:onboarding:${slug}`
      : false,
  })

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, chatLoading])

  const activeActions = messages.length === 0 ? ONBOARDING_INITIAL_ACTIONS : suggestedActions
  const showDocUpload = onboardingState?.step === 'documents' && !onboardingState.docs_verified

  const handleSelectTherapist = (displayLabel: string) => {
    sendMessage(`I'd like to go with ${displayLabel}`)
  }

  const handleSelectAppointment = (cancelPayload: string) => {
    sendMessage(cancelPayload)
  }

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-teal-50 via-white to-emerald-50">
        <div className="text-center text-slate-500">
          <div className="mx-auto mb-4 h-10 w-10 animate-spin rounded-full border-[3px] border-teal-200 border-t-teal-600" />
          <p className="text-sm font-medium">Setting up your onboarding...</p>
          <p className="mt-1 text-xs text-slate-400">This will only take a moment</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-teal-50 via-white to-emerald-50">
        <div className="max-w-md rounded-2xl bg-white p-8 shadow-lg text-center">
          <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-50">
            <span className="text-lg text-red-500">!</span>
          </div>
          <p className="text-base font-semibold text-slate-900 mb-1">Something went wrong</p>
          <p className="text-sm text-slate-500">{error}</p>
          <button
            onClick={() => navigate('/login/client')}
            className="mt-5 rounded-lg bg-teal-600 px-5 py-2.5 text-sm font-medium text-white hover:bg-teal-700 transition-colors"
          >
            Go to Login
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen flex-col bg-gradient-to-br from-teal-50 via-white to-emerald-50">
      {/* Header */}
      <header className="shrink-0 border-b border-teal-100 bg-white/80 backdrop-blur-sm">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-4 py-3">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-teal-500 to-teal-600 shadow-sm">
              <Heart className="h-4.5 w-4.5 text-white" />
            </div>
            <div>
              <h1 className="text-sm font-semibold text-slate-900">Appointment Assistant</h1>
              <p className="text-xs text-slate-500">
                {data?.therapist_name
                  ? `Referred to ${data.therapist_name}`
                  : 'Onboarding'}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-1.5 text-xs text-slate-400">
            <Shield className="h-3.5 w-3.5" />
            <span>Private & Secure</span>
          </div>
        </div>
      </header>

      {/* Onboarding Progress */}
      {onboardingState && onboardingState.step !== 'complete' && (
        <OnboardingProgress state={onboardingState} />
      )}

      {/* Main chat area */}
      <div className="flex flex-1 flex-col">
        <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col">
          {/* Messages */}
          <div className="flex-1 overflow-y-auto px-4 py-6 space-y-4">
            {/* Welcome state */}
            {messages.length === 0 && (
              <div className="flex flex-col items-center py-12 text-center">
                <div className="mb-5 flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-teal-500 to-teal-600 shadow-lg shadow-teal-200/50">
                  <Heart className="h-8 w-8 text-white" />
                </div>
                <h2 className="text-xl font-semibold text-slate-900">
                  {data?.therapist_name
                    ? `Welcome — you've been referred to ${data.therapist_name}`
                    : 'Welcome to your onboarding'}
                </h2>
                <p className="mt-2 max-w-md text-sm text-slate-500 leading-relaxed">
                  I'll guide you through a few simple steps to get you set up. We'll cover
                  your information, documents, and help you schedule your first appointment.
                </p>
                <div className="mt-6 flex items-center gap-4 text-xs text-slate-400">
                  <span className="flex items-center gap-1">
                    <Shield className="h-3.5 w-3.5" />
                    HIPAA-compliant
                  </span>
                  <span className="h-3 w-px bg-slate-200" />
                  <span>Takes about 5 minutes</span>
                </div>
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

            {chatLoading && (
              <div className="flex justify-start">
                <div className="rounded-2xl rounded-bl-md bg-white px-4 py-3 shadow-sm border border-slate-100">
                  <div className="flex gap-1.5">
                    <span className="h-2 w-2 animate-bounce rounded-full bg-teal-400" style={{ animationDelay: '0ms' }} />
                    <span className="h-2 w-2 animate-bounce rounded-full bg-teal-400" style={{ animationDelay: '150ms' }} />
                    <span className="h-2 w-2 animate-bounce rounded-full bg-teal-400" style={{ animationDelay: '300ms' }} />
                  </div>
                </div>
              </div>
            )}

            {chatError && (
              <div className="rounded-xl bg-red-50 border border-red-100 px-4 py-3 text-sm text-red-600">
                {chatError}
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>

          {/* Document upload (shown during documents step) */}
          {showDocUpload && (
            <div className="mx-4 mb-2">
              <DocumentUpload onUpload={uploadDocument} disabled={chatLoading} />
            </div>
          )}

          {/* Quick actions */}
          {activeActions.length > 0 && (
            <div className="px-4 pb-2">
              <QuickActions actions={activeActions} onSelect={sendMessage} disabled={chatLoading} />
            </div>
          )}

          {/* Input area */}
          <div className="sticky bottom-0 border-t border-slate-100 bg-white/80 backdrop-blur-sm">
            <div className="mx-auto max-w-3xl">
              <ChatInput
                onSend={sendMessage}
                onUpload={uploadDocument}
                disabled={chatLoading}
                placeholder="Type your message..."
              />
            </div>
          </div>
        </div>
      </div>

      {/* Crisis footer */}
      <div className="shrink-0 border-t border-slate-100 bg-white/60 py-2 text-center">
        <p className="flex items-center justify-center gap-1.5 text-xs text-slate-400">
          <Phone className="h-3 w-3" />
          If you're in crisis, please call <a href="tel:988" className="font-medium text-teal-600 hover:underline">988</a> (Suicide & Crisis Lifeline)
        </p>
      </div>
    </div>
  )
}
