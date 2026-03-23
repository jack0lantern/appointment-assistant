import { useState, useCallback, useRef } from 'react'
import api from '@/api/client'
import type {
  AgentChatRequest,
  AgentChatResponse,
  AgentContextType,
  ChatMessage,
  SuggestedAction,
  OnboardingState,
} from '@/types/agent'

interface UseChatOptions {
  contextType?: AgentContextType
  pageContext?: Record<string, unknown>
  initialConversationId?: string
}

interface UseChatReturn {
  messages: ChatMessage[]
  isLoading: boolean
  error: string | null
  suggestedActions: SuggestedAction[]
  conversationId: string | null
  onboardingState: OnboardingState | null
  sendMessage: (text: string) => Promise<void>
  uploadDocument: (file: File, documentType?: string) => Promise<void>
  clearChat: () => void
}

function inferOnboardingState(response: AgentChatResponse): OnboardingState | null {
  if (response.context_type !== 'onboarding') return null

  const msg = response.message.toLowerCase()
  const actions = response.suggested_actions.map((a) => a.label.toLowerCase())

  if (actions.some((a) => a.includes('schedule') || a.includes('book'))) {
    return { step: 'schedule', docs_verified: true, therapist_selected: true }
  }
  if (actions.some((a) => a.includes('confirm') || a.includes('select'))) {
    return { step: 'therapist', docs_verified: true, therapist_selected: false }
  }
  if (actions.some((a) => a.includes('upload') || a.includes('document'))) {
    return { step: 'documents', docs_verified: false, therapist_selected: false }
  }
  if (msg.includes('welcome') || msg.includes('get started')) {
    return { step: 'intake', docs_verified: false, therapist_selected: false }
  }

  return { step: 'intake', docs_verified: false, therapist_selected: false }
}

export function useChat(options: UseChatOptions = {}): UseChatReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [suggestedActions, setSuggestedActions] = useState<SuggestedAction[]>([])
  const [onboardingState, setOnboardingState] = useState<OnboardingState | null>(
    options.contextType === 'onboarding'
      ? { step: 'intake', docs_verified: false, therapist_selected: false }
      : null
  )
  const conversationIdRef = useRef<string | null>(options.initialConversationId ?? null)

  const sendMessage = useCallback(
    async (text: string) => {
      const trimmed = text.trim()
      if (!trimmed) return

      const userMsg: ChatMessage = {
        role: 'user',
        content: trimmed,
        timestamp: new Date().toISOString(),
      }
      setMessages((prev) => [...prev, userMsg])
      setIsLoading(true)
      setError(null)

      try {
        const payload: AgentChatRequest = {
          message: trimmed,
          conversation_id: conversationIdRef.current ?? undefined,
          context_type: options.contextType ?? 'general',
          page_context: options.pageContext,
        }

        const { data } = await api.post<AgentChatResponse>('/api/agent/chat', payload)

        conversationIdRef.current = data.conversation_id

        const assistantMsg: ChatMessage = {
          role: 'assistant',
          content: data.message,
          timestamp: new Date().toISOString(),
          ...(data.therapist_results?.length
            ? {
                rich_type: 'therapist_results' as const,
                therapist_results: data.therapist_results,
              }
            : data.appointment_results?.length
              ? {
                  rich_type: 'appointment_results' as const,
                  appointment_results: data.appointment_results,
                }
              : {}),
        }
        setMessages((prev) => [...prev, assistantMsg])
        setSuggestedActions(data.suggested_actions)
        setOnboardingState(data.onboarding_state ?? inferOnboardingState(data))
      } catch (err) {
        const apiError = (err as { response?: { data?: { error?: string } } })?.response?.data?.error
        const msg =
          apiError ?? (err instanceof Error ? err.message : 'Something went wrong. Please try again.')
        setError(msg)
      } finally {
        setIsLoading(false)
      }
    },
    [options.contextType, options.pageContext]
  )

  const uploadDocument = useCallback(
    async (file: File, documentType?: string) => {
      setIsLoading(true)
      setError(null)

      try {
        const formData = new FormData()
        formData.append('file', file)
        if (conversationIdRef.current) {
          formData.append('conversation_id', conversationIdRef.current)
        }
        if (documentType) {
          formData.append('document_type', documentType)
        }

        const { data } = await api.post('/api/agent/documents/upload', formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        })

        const syntheticMessage = documentType
          ? `I've uploaded my ${documentType.replace(/_/g, ' ')}`
          : "I've uploaded a document"

        const userMsg: ChatMessage = {
          role: 'user',
          content: syntheticMessage,
          timestamp: new Date().toISOString(),
        }
        setMessages((prev) => [...prev, userMsg])

        if (conversationIdRef.current) {
          // Trigger LLM response with the document in context (conversation already has doc in onboarding)
          const payload: AgentChatRequest = {
            message: syntheticMessage,
            conversation_id: conversationIdRef.current,
            context_type: options.contextType ?? 'general',
            page_context: options.pageContext,
          }

          const { data: chatData } = await api.post<AgentChatResponse>('/api/agent/chat', payload)

          conversationIdRef.current = chatData.conversation_id

          const assistantMsg: ChatMessage = {
            role: 'assistant',
            content: chatData.message,
            timestamp: new Date().toISOString(),
            ...(chatData.therapist_results?.length
              ? {
                  rich_type: 'therapist_results' as const,
                  therapist_results: chatData.therapist_results,
                }
              : chatData.appointment_results?.length
                ? {
                    rich_type: 'appointment_results' as const,
                    appointment_results: chatData.appointment_results,
                  }
                : {}),
          }
          setMessages((prev) => [...prev, assistantMsg])
          setSuggestedActions(chatData.suggested_actions)
          setOnboardingState(chatData.onboarding_state ?? inferOnboardingState(chatData))
        } else {
          // No conversation yet — document not attached; show static confirmation
          const docMsg: ChatMessage = {
            role: 'assistant',
            content: `Document uploaded successfully. ${data.redacted_preview ?? ''}`,
            timestamp: new Date().toISOString(),
            rich_type: 'document_status',
            document_result: data,
          }
          setMessages((prev) => [...prev, docMsg])
        }
      } catch (err) {
        const apiError = (err as { response?: { data?: { error?: string } } })?.response?.data?.error
        const msg =
          apiError ??
          (err instanceof Error ? err.message : 'Failed to upload document. Please try again.')
        setError(msg)
      } finally {
        setIsLoading(false)
      }
    },
    [options.contextType, options.pageContext]
  )

  const clearChat = useCallback(() => {
    setMessages([])
    setSuggestedActions([])
    setOnboardingState(null)
    conversationIdRef.current = null
    setError(null)
  }, [])

  return {
    messages,
    isLoading,
    error,
    suggestedActions,
    conversationId: conversationIdRef.current,
    onboardingState,
    sendMessage,
    uploadDocument,
    clearChat,
  }
}
