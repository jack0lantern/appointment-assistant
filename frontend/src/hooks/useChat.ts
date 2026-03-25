import { useState, useCallback, useRef, useEffect, useMemo } from 'react'
import api from '@/api/client'
import {
  CHAT_STORAGE_VERSION,
  clearChatStorage,
  defaultChatStorageKey,
  readChatStorage,
  writeChatStorage,
} from '@/lib/chatStorage'
import { MAX_CHAT_MESSAGE_CHARS, chatMessageLengthExceededError } from '@/lib/chatLimits'
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
  /** Storage key for local persistence, or false to disable */
  persistStorageKey?: string | false
}

interface UseChatReturn {
  messages: ChatMessage[]
  isLoading: boolean
  error: string | null
  suggestedActions: SuggestedAction[]
  conversationId: string | null
  onboardingState: OnboardingState | null
  sendMessage: (text: string) => Promise<void>
  uploadDocument: (file: File, documentType?: string) => Promise<boolean>
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

function resolvePersistKey(options: UseChatOptions): string | null {
  if (options.persistStorageKey === false) return null
  if (typeof options.persistStorageKey === 'string') return options.persistStorageKey
  return defaultChatStorageKey(options.contextType)
}

function defaultOnboardingState(options: UseChatOptions): OnboardingState | null {
  return options.contextType === 'onboarding'
    ? { step: 'intake', docs_verified: false, therapist_selected: false }
    : null
}

function buildInitialSession(options: UseChatOptions): {
  messages: ChatMessage[]
  suggestedActions: SuggestedAction[]
  onboardingState: OnboardingState | null
  conversationId: string | null
} {
  const persistKey = resolvePersistKey(options)
  const baseOnboarding = defaultOnboardingState(options)
  const fallbackConv = options.initialConversationId ?? null

  if (!persistKey) {
    return {
      messages: [],
      suggestedActions: [],
      onboardingState: baseOnboarding,
      conversationId: fallbackConv,
    }
  }

  const snap = readChatStorage(persistKey)
  if (snap && snap.messages.length > 0) {
    return {
      messages: snap.messages,
      suggestedActions: snap.suggestedActions,
      onboardingState: snap.onboardingState ?? baseOnboarding,
      conversationId: snap.conversationId ?? fallbackConv,
    }
  }

  return {
    messages: [],
    suggestedActions: [],
    onboardingState: baseOnboarding,
    conversationId: fallbackConv,
  }
}

export function useChat(options: UseChatOptions = {}): UseChatReturn {
  const initialRef = useRef<ReturnType<typeof buildInitialSession> | null>(null)
  const getInitial = () => {
    if (!initialRef.current) {
      initialRef.current = buildInitialSession(options)
    }
    return initialRef.current
  }

  const persistKey = useMemo(
    () => resolvePersistKey(options),
    [options.contextType, options.persistStorageKey]
  )

  const [messages, setMessages] = useState<ChatMessage[]>(() => getInitial().messages)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [suggestedActions, setSuggestedActions] = useState<SuggestedAction[]>(() => getInitial().suggestedActions)
  const [onboardingState, setOnboardingState] = useState<OnboardingState | null>(() => getInitial().onboardingState)
  const conversationIdRef = useRef<string | null>(getInitial().conversationId)

  useEffect(() => {
    const id = options.initialConversationId
    if (!id) return
    if (messages.length > 0) return
    if (conversationIdRef.current === id) return
    conversationIdRef.current = id
  }, [options.initialConversationId, messages.length])

  useEffect(() => {
    if (!persistKey) return
    if (messages.length === 0) {
      clearChatStorage(persistKey)
      return
    }
    writeChatStorage(persistKey, {
      v: CHAT_STORAGE_VERSION,
      messages,
      suggestedActions,
      onboardingState,
      conversationId: conversationIdRef.current,
    })
  }, [persistKey, messages, suggestedActions, onboardingState])

  const sendMessage = useCallback(
    async (text: string) => {
      const trimmed = text.trim()
      if (!trimmed) return
      if (trimmed.length > MAX_CHAT_MESSAGE_CHARS) {
        setError(chatMessageLengthExceededError())
        return
      }

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
    async (file: File, documentType?: string): Promise<boolean> => {
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
        return true
      } catch (err) {
        const apiError = (err as { response?: { data?: { error?: string } } })?.response?.data?.error
        const msg =
          apiError ??
          (err instanceof Error ? err.message : 'Failed to upload document. Please try again.')
        setError(msg)
        return false
      } finally {
        setIsLoading(false)
      }
    },
    [options.contextType, options.pageContext]
  )

  const clearChat = useCallback(() => {
    if (persistKey) clearChatStorage(persistKey)
    setMessages([])
    setSuggestedActions([])
    setOnboardingState(defaultOnboardingState({ contextType: options.contextType }))
    conversationIdRef.current = null
    setError(null)
  }, [persistKey, options.contextType])

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
