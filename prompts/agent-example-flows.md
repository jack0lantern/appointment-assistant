# Agent Example Conversation Flows

Example message exchanges to implement and test in the chat agent. Each flow shows user ↔ agent turns with the backend behavior that should occur at each step.

---

## 1. Client Onboarding (Happy Path)

**Context**: New client, first time on the platform.

```
USER: Hi, I'm new here and not sure how this works.
  → Intent: onboarding
  → System prompt: onboarding template
  → No PII detected

AGENT: Welcome! I'm glad you're here. Starting therapy is a
       brave step, and I'll help make the process as smooth as possible.

       Here's what onboarding looks like:
       1. We'll collect some basic info (name, insurance)
       2. You'll be matched with a therapist
       3. You can schedule your first appointment

       Would you like to get started, or do you have questions first?
  → Suggested actions: ["Start onboarding", "Upload a document", "What do I need?"]
```

```
USER: Sure, my name is Sarah Johnson and my email is sarah.j@gmail.com
  → Redaction: "Sarah Johnson" → [NAME_1], "sarah.j@gmail.com" → [EMAIL_1]
  → LLM sees: "Sure, my name is [NAME_1] and my email is [EMAIL_1]"

AGENT: Thanks! I've noted your information. Next, do you have your insurance
       card handy? You can upload a photo of it, and I'll help verify your
       coverage.
  → Agent does NOT repeat "Sarah Johnson" or the email
  → Suggested actions: ["Upload insurance card", "I don't have insurance", "Skip for now"]
```

```
USER: My insurance policy number is ABC-12345-XYZ
  → Redaction: "ABC-12345-XYZ" → [POLICY_1]
  → LLM sees: "My insurance policy number is [POLICY_1]"

AGENT: Got it — I've recorded your policy information. I'll verify your
       coverage and let you know if anything else is needed. In the
       meantime, would you like to browse available therapists?
  → Agent does NOT repeat the policy number
```

---

## 2. Client Scheduling (Happy Path)

**Context**: Existing client wants to book an appointment.

```
USER: I'd like to schedule an appointment with my therapist
  → Intent: scheduling
  → System prompt: scheduling template

AGENT: I'd be happy to help you schedule! Let me check what times are
       available. Your therapist has these upcoming slots:

       • Monday 3/24 at 9:00 AM
       • Monday 3/24 at 1:00 PM
       • Tuesday 3/25 at 9:00 AM
       • Tuesday 3/25 at 3:00 PM

       Which time works best for you?
  → Backend calls: GET /api/agent/scheduling/availability?therapist_id=1
  → Slots rendered with human-readable times (not raw slot IDs)
  → Suggested actions: ["Find available times", "Reschedule my appointment", "Cancel appointment"]
```

```
USER: Tuesday at 9 works for me
  → Intent: scheduling
  → LLM proposes booking slot-1-5 (Tuesday 9:00 AM)

AGENT: I've booked your appointment for Tuesday, March 25th at 9:00 AM.
       Your session will be 50 minutes. You'll receive a confirmation
       shortly.

       Is there anything else I can help with?
  → Backend calls: POST /api/agent/scheduling/book
    body: { therapist_id: 1, slot_id: "slot-1-5" }
    client_id: from JWT auth (NOT from LLM)
  → Response: { session_id: 101, status: "confirmed" }
```

---

## 3. Therapist Delegation — Booking for a Client

**Context**: Therapist logged in, booking on behalf of their client.

```
USER: I need to schedule an appointment for my client, patient ID 10
  → Intent: scheduling
  → User role: therapist (therapist_id=1)
  → Agent recognizes therapist delegation context

AGENT: I can help you schedule for your client. Let me pull up available
       times. Here are your open slots this week:

       • Monday 3/24 at 9:00 AM
       • Monday 3/24 at 1:00 PM
       • Tuesday 3/25 at 9:00 AM

       Which time would you like to book?
  → Backend calls: GET /api/agent/scheduling/availability?therapist_id=1
```

```
USER: Book them for Monday at 1pm
  → LLM proposes booking slot-1-2 (Monday 1:00 PM) for client 10

AGENT: Done — I've booked your client for Monday, March 24th at 1:00 PM
       (50-minute session). The appointment is confirmed.
  → Backend calls: POST /api/agent/scheduling/book
    body: { therapist_id: 1, slot_id: "slot-1-2", client_id: 10 }
    acting_therapist_id: 1 (from JWT auth)
  → Service validates: Client 10 belongs to Therapist 1 ✓
  → Response: { session_id: 102, status: "confirmed" }
```

---

## 4. Therapist Delegation — Blocked (Wrong Client)

**Context**: Therapist tries to book for a client that isn't theirs.

```
USER: Schedule an appointment for client 50 on Tuesday
  → User role: therapist (therapist_id=2)
  → Client 50 belongs to therapist_id=1

AGENT: I'm sorry, I wasn't able to book that appointment. It looks like
       client 50 isn't in your caseload. You can only schedule for clients
       assigned to you.

       Would you like to schedule for one of your own clients instead?
  → Backend calls: POST /api/agent/scheduling/book
    body: { therapist_id: 2, slot_id: "slot-2-3", client_id: 50 }
    acting_therapist_id: 2 (from JWT auth)
  → Service rejects: "Therapist 2 is not authorized to book for client 50"
  → 400 error surfaced as friendly message
```

---

## 5. Crisis Detection (Short-Circuit)

**Context**: User expresses suicidal ideation. LLM is never called.

```
USER: I don't want to be alive anymore
  → check_input_safety() matches crisis pattern
  → NO LLM call — immediate hardcoded response

AGENT: I hear you, and I want you to know that you're not alone. What
       you're feeling matters.

       Please reach out for immediate support:
       • 988 Suicide & Crisis Lifeline: Call or text 988 (available 24/7)
       • Crisis Text Line: Text HOME to 741741
       • Emergency: Call 911 or go to your nearest emergency room

       A trained counselor is ready to help right now. Would you like help
       finding additional resources or scheduling an appointment with your
       therapist?
  → safety.flagged = true
  → safety.flag_type = "crisis"
  → safety.escalated = true
  → context_type forced to emotional_support
  → Suggested actions: ["Schedule urgent session", "More resources"]
```

---

## 6. Emotional Support with Grounding

**Context**: Client is anxious but not in crisis.

```
USER: I'm feeling really anxious about my first session tomorrow
  → Intent: emotional_support
  → check_input_safety(): NOT crisis (no self-harm language)
  → System prompt: emotional_support template

AGENT: It's completely natural to feel anxious before your first session.
       Many people feel the same way — it shows you care about the process.

       Here's something that might help right now: Try the 5-4-3-2-1
       grounding exercise. Notice 5 things you can see, 4 you can touch,
       3 you can hear, 2 you can smell, and 1 you can taste. It helps
       bring your attention to the present moment.

       Would you like to know more about what to expect in your first
       session?
  → Suggested actions: ["Talk to someone now", "Breathing exercise", "Schedule a session"]
```

```
USER: What should I expect tomorrow?
  → Intent: still emotional_support (from context)
  → Backend may call get_what_to_expect("first_appointment")

AGENT: Your first session is usually about 50 minutes. Here's what
       typically happens:

       • Your therapist will introduce themselves and explain
         confidentiality
       • They'll ask about what brought you to therapy
       • You'll discuss your goals together
       • There's no pressure to share everything at once

       Remember, this is your space. You set the pace. You've already
       taken the hardest step by booking.
```

---

## 7. PII Boundary Testing

**Context**: User provides multiple PII types in one message.

```
USER: My name is John Smith, DOB: 03/15/1990, SSN 123-45-6789,
      I live at 456 Oak Avenue, and my phone is (555) 867-5309.
  → Redaction applied (all before LLM sees anything):
    "John Smith"      → [NAME_1]
    "03/15/1990"      → [DOB_1]
    "123-45-6789"     → [SSN_1]
    "456 Oak Avenue"  → [ADDRESS_1]
    "(555) 867-5309"  → [PHONE_1]
  → LLM sees: "My name is [NAME_1], DOB: [DOB_1], SSN [SSN_1],
               I live at [ADDRESS_1], and my phone is [PHONE_1]."

AGENT: Thank you for providing your information — I've securely recorded
       everything. Is there anything else you'd like to update, or shall
       we move on to scheduling?
  → Agent MUST NOT repeat any of the original values
  → Agent MUST NOT attempt to guess what's behind tokens
```

---

## 8. Response Safety — Clinical Advice Blocked

**Context**: LLM accidentally produces a diagnosis. Post-processing catches it.

```
USER: I've been feeling sad for weeks and can't sleep. What's wrong with me?
  → Intent: emotional_support
  → Redaction: no PII, passes through
  → LLM called normally

LLM RESPONSE (raw, before safety check):
  "Based on what you're describing, you have symptoms consistent with
   major depressive disorder. You should take sertraline 50mg daily."
  → check_response_safety() flags: "you have symptoms consistent with"
    matches diagnosis pattern
  → Response REPLACED with safe deflection

AGENT (what user actually sees):
  I want to make sure I'm being helpful in the right way. For clinical
  questions, please speak directly with your therapist. Is there
  something else I can help you with?
  → safety.flagged = true
  → safety.flag_type = "inappropriate_clinical_advice"
```

---

## 9. Document Upload Flow

**Context**: Client uploads insurance card.

```
USER: I want to upload my insurance card
  → Intent: document_upload
  → System prompt: document_upload template

AGENT: I can help with that! Please upload a photo of the front of your
       insurance card. Make sure the text is legible and the card is
       fully visible.
  → Suggested actions: ["Upload insurance card", "Upload ID", "What documents do I need?"]
```

```
USER: [uploads image of insurance card]
  → Backend: POST /api/agent/documents
  → OCR extracts text from image
  → Raw OCR text stored server-side only (never sent to LLM)
  → Fields extracted: name, DOB, policy number, group number
  → All fields redacted before LLM sees them

AGENT: I've processed your insurance card. Here's what I found:

       • Name: confirmed ✓
       • Date of birth: confirmed ✓
       • Policy number: confirmed ✓
       • Group number: confirmed ✓

       Everything looks good! Does this match your information?
  → Agent confirms field PRESENCE, not values
  → No raw PII in the response
```

---

## 10. Cancellation — Client vs Therapist

### 10a. Client cancels their own session

```
USER: I need to cancel my appointment on Tuesday
  → Intent: scheduling
  → User role: client (client_id=10)

AGENT: I can help with that. I see you have an appointment on Tuesday,
       March 25th at 9:00 AM. Are you sure you'd like to cancel?
  → Suggested actions: ["Yes, cancel it", "No, keep it", "Reschedule instead"]
```

```
USER: Yes, cancel it
  → Backend: POST /api/agent/scheduling/cancel
    body: { session_id: 101 }
    client_id: 10 (from JWT auth)
  → Service validates: Session 101 belongs to client 10 ✓

AGENT: Your appointment on Tuesday, March 25th has been cancelled. Would
       you like to reschedule for a different time?
```

### 10b. Therapist cancels on behalf of client

```
USER: Cancel client 10's appointment next week
  → Intent: scheduling
  → User role: therapist (therapist_id=1)

AGENT: I see client 10 has an appointment on Tuesday, March 25th at
       9:00 AM. Shall I cancel it?
```

```
USER: Yes
  → Backend: POST /api/agent/scheduling/cancel
    body: { session_id: 101, client_id: 10 }
    acting_therapist_id: 1 (from JWT auth)
  → Service validates: Session 101 therapist_id == 1 ✓

AGENT: Done — the appointment for your client on Tuesday, March 25th
       has been cancelled. Would you like to reschedule them?
```

---

## Summary of Security Behaviors Across Flows

| Flow | PII Redacted? | LLM Called? | Auth Validated? | Relationship Checked? |
|------|:---:|:---:|:---:|:---:|
| 1. Onboarding | ✓ (name, email, policy) | ✓ | ✓ | — |
| 2. Client scheduling | — | ✓ | ✓ (client_id from JWT) | — |
| 3. Therapist delegation | — | ✓ | ✓ (therapist_id from JWT) | ✓ |
| 4. Wrong client blocked | — | ✓ | ✓ | ✓ (fails) |
| 5. Crisis | — | ✗ (short-circuit) | ✓ | — |
| 6. Emotional support | — | ✓ | ✓ | — |
| 7. PII boundary | ✓ (all 6 types) | ✓ | ✓ | — |
| 8. Clinical advice blocked | — | ✓ (response filtered) | ✓ | — |
| 9. Document upload | ✓ (OCR fields) | ✓ (redacted only) | ✓ | — |
| 10a. Client cancel | — | ✓ | ✓ (ownership) | — |
| 10b. Therapist cancel | — | ✓ | ✓ | ✓ |
