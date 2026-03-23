export type AgentContextType =
  | 'onboarding'
  | 'scheduling'
  | 'emotional_support'
  | 'document_upload'
  | 'general'

export interface TherapistSearchResult {
  display_label: string
  name: string
  license_type: string
  specialties: string[]
  bio?: string
}

export interface AppointmentResult {
  session_id: number
  date: string
  time: string
  duration_minutes: number
  therapist_name: string
  cancel_payload: string
}

export interface DocumentUploadResult {
  document_ref: string
  status: string
  redacted_preview?: string
  fields?: Array<{ field_name: string; value: string }>
}

export interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
  timestamp?: string
  /** Rich content type for structured rendering */
  rich_type?: 'therapist_results' | 'document_status' | 'appointment_results' | 'text'
  therapist_results?: TherapistSearchResult[]
  appointment_results?: AppointmentResult[]
  document_result?: DocumentUploadResult
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
  therapist_results?: TherapistSearchResult[]
  appointment_results?: AppointmentResult[]
  onboarding_state?: OnboardingState | null
}

export interface OnboardingState {
  step: 'intake' | 'documents' | 'therapist' | 'schedule' | 'complete'
  docs_verified: boolean
  therapist_selected: boolean
}
