## Model Field Name Contracts

All agents MUST use these exact field and relationship names.

### User
- id, email, name, role (str: "therapist"|"client"), password_hash
- Relationships: therapist_profile, client_profile

### Therapist
- id, user_id (FK users.id), license_type, specialties (JSONB), preferences (JSONB)
- Relationships: user, clients, sessions

### Client
- id, user_id (FK users.id), therapist_id (FK therapists.id), name (str)
- Relationships: user, therapist, sessions, treatment_plan

### Session
- id, therapist_id (FK), client_id (FK), session_date, session_number, duration_minutes, status (str)
- Relationships: therapist, client, transcript, summary, safety_flags

### Transcript
- id, session_id (FK unique), content (text), source_type, word_count
- Relationships: session

### SessionSummary
- id, session_id (FK unique), therapist_summary, client_summary, key_themes (JSONB)
- Relationships: session

### TreatmentPlan
- id, client_id (FK unique), therapist_id (FK), current_version_id (FK nullable), status (str)
- Relationships: client, therapist, versions, current_version

### TreatmentPlanVersion
- id, treatment_plan_id (FK), version_number, session_id (FK), therapist_content (JSONB), client_content (JSONB), change_summary, source (str), ai_metadata (JSONB)
- Relationships: treatment_plan, session, safety_flags, homework_items

### SafetyFlag
- id, session_id (FK), treatment_plan_version_id (FK), flag_type, severity, description, transcript_excerpt, line_start, line_end, source, acknowledged, acknowledged_at, acknowledged_by (FK nullable)
- Relationships: session, treatment_plan_version

### HomeworkItem
- id, treatment_plan_version_id (FK), client_id (FK), description, completed, completed_at
- Relationships: treatment_plan_version, client
