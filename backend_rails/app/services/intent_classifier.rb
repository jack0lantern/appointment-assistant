class IntentClassifier
  SCHEDULING_KEYWORDS = /\b(book|schedule|appointment|reschedule|cancel|available|slot|session|next\s+tuesday|next\s+week|this\s+week|tomorrow|time)\b/i
  ONBOARDING_KEYWORDS = /\b(new\s+patient|register|sign\s+up|first\s+time|intake|onboard|getting\s+started|new\s+here)\b/i
  EMOTIONAL_KEYWORDS  = /\b(overwhelmed|anxious|scared|depressed|stressed|panic|afraid|lonely|sad|hopeless|can'?t\s+cope|feeling\s+(bad|terrible|awful|down))\b/i
  DOCUMENT_KEYWORDS   = /\b(upload|insurance\s+card|id\s+card|document|photo|scan|image|form)\b/i

  CONTEXT_TYPES = %w[scheduling onboarding emotional_support document_upload general].freeze

  # Classify a user message into a context type string.
  # Priority: document_upload > scheduling > onboarding > emotional_support > general
  def self.classify(message)
    return "document_upload"    if DOCUMENT_KEYWORDS.match?(message)
    return "scheduling"         if SCHEDULING_KEYWORDS.match?(message)
    return "onboarding"         if ONBOARDING_KEYWORDS.match?(message)
    return "emotional_support"  if EMOTIONAL_KEYWORDS.match?(message)

    "general"
  end
end
