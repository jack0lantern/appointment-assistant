export type AgentContextType =
  | 'onboarding'
  | 'scheduling'
  | 'emotional_support'
  | 'document_upload'
  | 'general'

export interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
  timestamp?: string
}

export interface SuggestedAction {
  label: string
  action_type: string
  payload?: string
}

export interface SafetyMeta {
  flagged: boolean
  flag_type?: string
  escalated?: boolean
}

export interface AgentChatRequest {
  message: string
  conversation_id?: string
  context_type?: AgentContextType
  page_context?: Record<string, unknown>
}

export interface AgentChatResponse {
  message: string
  conversation_id: string
  suggested_actions: SuggestedAction[]
  follow_up_questions: string[]
  safety: SafetyMeta
  context_type: AgentContextType
}
