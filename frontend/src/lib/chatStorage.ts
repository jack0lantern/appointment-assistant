import type { AgentContextType, ChatMessage, OnboardingState, SuggestedAction } from '@/types/agent'

export const CHAT_STORAGE_VERSION = 1 as const

export interface ChatStorageSnapshot {
  v: typeof CHAT_STORAGE_VERSION
  messages: ChatMessage[]
  suggestedActions: SuggestedAction[]
  onboardingState: OnboardingState | null
  conversationId: string | null
}

export function defaultChatStorageKey(contextType: AgentContextType | undefined): string {
  return `appointment-assistant:chat:v${CHAT_STORAGE_VERSION}:${contextType ?? 'general'}`
}

export function readChatStorage(key: string): ChatStorageSnapshot | null {
  if (typeof window === 'undefined') return null
  try {
    const raw = localStorage.getItem(key)
    if (!raw) return null
    const parsed = JSON.parse(raw) as unknown
    if (!parsed || typeof parsed !== 'object') return null
    const o = parsed as Record<string, unknown>
    if (o.v !== CHAT_STORAGE_VERSION) return null
    if (!Array.isArray(o.messages)) return null
    return {
      v: CHAT_STORAGE_VERSION,
      messages: o.messages as ChatMessage[],
      suggestedActions: (Array.isArray(o.suggestedActions) ? o.suggestedActions : []) as SuggestedAction[],
      onboardingState: (o.onboardingState as OnboardingState | null) ?? null,
      conversationId: typeof o.conversationId === 'string' ? o.conversationId : null,
    }
  } catch {
    return null
  }
}

export function writeChatStorage(key: string, snapshot: ChatStorageSnapshot): void {
  if (typeof window === 'undefined') return
  try {
    localStorage.setItem(key, JSON.stringify(snapshot))
  } catch {
    // Quota, private mode, etc.
  }
}

export function clearChatStorage(key: string): void {
  if (typeof window === 'undefined') return
  try {
    localStorage.removeItem(key)
  } catch {
    // ignore
  }
}
