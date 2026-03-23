// Auth
export interface User { id: number; email: string; name: string; role: 'therapist' | 'client' | 'admin' }
export interface LoginResponse { token: string; user: User }

// Client (the patient entity, not HTTP client)
export interface ClientProfile { id: number; name: string; therapist_id: number; session_count?: number; last_session_date?: string; has_safety_flags?: boolean }

// Draft plan summary for therapist dashboard
export interface DraftPlanSummary { plan_id: number; client_id: number; client_name: string; created_at: string }

// Upcoming appointment for client dashboard
export interface ClientAppointment {
  session_id: number
  session_date: string
  therapist_name: string
  duration_minutes: number
}

// Upcoming appointment for therapist dashboard
export interface TherapistAppointment {
  session_id: number
  session_date: string
  client_id: number
  client_name: string
  duration_minutes: number
}

// Session
export interface Session { id: number; client_id: number; therapist_id: number; session_date: string; session_number: number; duration_minutes: number; status: string; session_type?: 'uploaded' | 'live'; recording_status?: string | null; summary?: SessionSummary }
export interface SessionSummary { therapist_summary: string; client_summary: string; key_themes: string[] }

// Treatment Plan
export interface TreatmentPlan { id: number; client_id: number; status: string; current_version?: TreatmentPlanVersion; versions?: TreatmentPlanVersion[] }
export interface TreatmentPlanVersion { id: number; version_number: number; session_id: number; therapist_content: TherapistPlanContent; client_content: ClientPlanContent; change_summary: string; source: string; created_at: string }

// Plan content structures — match actual Python schemas
export interface Citation { text: string; line_start: number; line_end: number }

export interface GoalItem { description: string; modality?: string; timeframe?: string }
export interface InterventionItem { name: string; modality: string; description: string }

export interface TherapistPlanContent {
  presenting_concerns: string[]
  presenting_concerns_citations?: Citation[]
  goals: GoalItem[]
  goals_citations?: Citation[]
  interventions: InterventionItem[]
  interventions_citations?: Citation[]
  homework: string[]
  homework_citations?: Citation[]
  strengths: string[]
  strengths_citations?: Citation[]
  barriers?: string[]
  barriers_citations?: Citation[]
  diagnosis_considerations?: string[]
}

export interface ClientPlanContent {
  what_we_talked_about: string
  your_goals: string[]
  things_to_try: string[]
  your_strengths: string[]
  next_steps?: string[]
}

// Safety
export interface SafetyFlag { id: number; flag_type: string; severity: string; description: string; transcript_excerpt: string; line_start: number; line_end: number; source: string; acknowledged: boolean }

// Homework
export interface HomeworkItem { id: number; description: string; completed: boolean; completed_at?: string }

// SSE
export interface GenerationProgress { stage: string; message: string }

// Live Session
export interface LiveSessionToken { token: string; room_name: string; server_url: string; peer_name?: string }
export interface LiveSessionStatus { is_active: boolean; session_id: number; room_name: string | null; participants: LiveParticipant[]; duration_seconds: number; recording_status: string | null }
export interface LiveParticipant { user_id: number; role: 'therapist' | 'client'; joined_at: string; left_at?: string }

// Recording
export interface RecordingConsent { session_id: number; user_id: number; consented: boolean; consented_at: string | null }
export interface RecordingStatus { recording_status: string | null; all_consented: boolean; consents: RecordingConsent[] }

// Transcript diarization
export interface Utterance { speaker: string; speaker_raw: string; text: string; start_time: number; end_time: number; confidence: number }
export interface TranscriptPreview { session_id: number; utterances: Utterance[]; speakers: string[]; duration_seconds: number }

// Legacy PlanItem kept for any transitional use (not used in production data)
export interface PlanItem { content: string; citations?: Citation[] }
