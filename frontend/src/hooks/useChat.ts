import { useState, useCallback, useRef } from 'react'
import api from '@/api/client'
import type {
  AgentChatRequest,
  AgentChatResponse,
  AgentContextType,
  ChatMessage,
  SuggestedAction,
} from '@/types/agent'

interface UseChatOptions {
  contextType?: AgentContextType
  pageContext?: Record<string, unknown>
}

interface UseChatReturn {
  messages: ChatMessage[]
  isLoading: boolean
  error: string | null
  suggestedActions: SuggestedAction[]
  conversationId: string | null
  sendMessage: (text: string) => Promise<void>
  clearChat: () => void
}

export function useChat(options: UseChatOptions = {}): UseChatReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [suggestedActions, setSuggestedActions] = useState<SuggestedAction[]>([])
  const conversationIdRef = useRef<string | null>(null)

  const sendMessage = useCallback(
    async (text: string) => {
      const trimmed = text.trim()
      if (!trimmed) return

      // Add user message optimistically
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
        }
        setMessages((prev) => [...prev, assistantMsg])
        setSuggestedActions(data.suggested_actions)
      } catch (err) {
        const msg =
          err instanceof Error ? err.message : 'Something went wrong. Please try again.'
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
    conversationIdRef.current = null
    setError(null)
  }, [])

  return {
    messages,
    isLoading,
    error,
    suggestedActions,
    conversationId: conversationIdRef.current,
    sendMessage,
    clearChat,
  }
}
