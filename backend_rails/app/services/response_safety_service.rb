# frozen_string_literal: true

# Checks agent responses for harmful clinical or medical content.
# Port of check_response_safety from Python agent_service.py.
class ResponseSafetyService
  SAFE_REPLACEMENT = "I want to make sure I'm being helpful in the right way. " \
    "I'm not able to provide medical advice, diagnoses, or medication recommendations. " \
    "Please speak directly with your therapist or prescribing provider " \
    "for clinical questions. Is there something else I can help you with?"

  DIAGNOSIS_PATTERN = /\b(you\s+(have|suffer\s+from|are\s+diagnosed\s+with)\s+(depression|anxiety|bipolar|ptsd|adhd|ocd|bpd|schizophren|major\s+depressive|generalized\s+anxiety|panic\s+disorder|social\s+anxiety|eating\s+disorder|personality\s+disorder|dissociative|psychosis|mania|autis|asperg)|your\s+diagnosis\s+is|I\s+diagnose)/i

  MEDICATION_PATTERN = /\b(you\s+should\s+take\s+\w+[\s\w.]*(mg|milligram)|(tak(e|ing)|try(ing)?|start(ing)?|increas(e|ing)|decreas(e|ing)|stop\s+taking|switch(ing)?\s+to)\s+(sertraline|prozac|fluoxetine|zoloft|lexapro|escitalopram|citalopram|celexa|paxil|paroxetine|wellbutrin|bupropion|effexor|venlafaxine|cymbalta|duloxetine|xanax|alprazolam|klonopin|clonazepam|ativan|lorazepam|valium|diazepam|ambien|zolpidem|trazodone|buspirone|lithium|lamictal|lamotrigine|abilify|aripiprazole|seroquel|quetiapine|risperdal|risperidone|adderall|ritalin|concerta|vyvanse|gabapentin|pregabalin|hydroxyzine|propranolol|clonidine)|I\s+(recommend|prescribe|suggest)\s+\w+[\s\w.]*(mg|milligram|daily|twice|weekly)|(dosage|dose)\s+(of|should\s+be|is)\s+\d+\s*(mg|milligram)|\d+\s*(mg|milligram)\s+(daily|twice|once|every|per\s+day))/i

  MEDICAL_ADVICE_PATTERN = /\b(you\s+should\s+(stop|start|change|adjust|increase|decrease)\s+(your\s+)?(medication|treatment|dosage|prescription|therapy\s+medication)|(stop|don'?t)\s+taking\s+your\s+(medication|prescription|pills))/i

  # Catches any mention of specific drug names regardless of framing
  # (e.g. "SSRIs like sertraline are commonly prescribed")
  DRUG_NAMES = %w[
    sertraline prozac fluoxetine zoloft lexapro escitalopram citalopram celexa
    paxil paroxetine wellbutrin bupropion effexor venlafaxine cymbalta duloxetine
    xanax alprazolam klonopin clonazepam ativan lorazepam valium diazepam
    ambien zolpidem trazodone buspirone lithium lamictal lamotrigine
    abilify aripiprazole seroquel quetiapine risperdal risperidone
    adderall ritalin concerta vyvanse gabapentin pregabalin
    hydroxyzine propranolol clonidine
  ].freeze
  MEDICATION_MENTION_PATTERN = /\b(#{DRUG_NAMES.join("|")})\b/i

  # Catches system prompt / tool definition leakage
  SYSTEM_PROMPT_LEAKAGE_PATTERN = /\b(system\s+(instructions?|prompt)|my\s+(instructions?|rules)\s+(say|are|include)|RULES:|NEVER\s+provide\s+diagnos)/i
  TOOL_LEAKAGE_PATTERN = /\b(tools?\s+(available|I\s+have|access)|book_appointment\s+tool|input_schema|tool_use_id|get_available_slots,\s*book_appointment)\b/i

  # Catches PII token-to-value mapping / confirmation
  PII_TOKEN_LEAKAGE_PATTERN = /\[(NAME|EMAIL|SSN|DOB|PHONE|POLICY|ADDRESS)_\d+\]\s*(\w+\s+){0,5}(refers?\s+to|is\b|represents?|means|=|stands\s+for|maps?\s+to)/i

  SAFE_PROMPT_REPLACEMENT = "I'm not able to share details about my internal configuration. " \
    "I'm here to help you with scheduling, onboarding, and general questions about the platform. " \
    "Is there something I can help you with?"

  SAFE_PII_REPLACEMENT = "I'm not able to confirm or reveal personal information. " \
    "Your data is kept private and secure. If you need to update your records, " \
    "please contact your care coordinator. Is there something else I can help with?"

  # Returns a hash with :flagged, :flag_type, :replacement
  def check(response_text)
    if DIAGNOSIS_PATTERN.match?(response_text)
      return { flagged: true, flag_type: "inappropriate_clinical_advice", replacement: SAFE_REPLACEMENT }
    end

    if MEDICATION_PATTERN.match?(response_text)
      return { flagged: true, flag_type: "inappropriate_medical_advice", replacement: SAFE_REPLACEMENT }
    end

    if MEDICAL_ADVICE_PATTERN.match?(response_text)
      return { flagged: true, flag_type: "inappropriate_medical_advice", replacement: SAFE_REPLACEMENT }
    end

    if MEDICATION_MENTION_PATTERN.match?(response_text)
      return { flagged: true, flag_type: "medication_name_disclosure", replacement: SAFE_REPLACEMENT }
    end

    if SYSTEM_PROMPT_LEAKAGE_PATTERN.match?(response_text) || TOOL_LEAKAGE_PATTERN.match?(response_text)
      return { flagged: true, flag_type: "system_prompt_leakage", replacement: SAFE_PROMPT_REPLACEMENT }
    end

    if PII_TOKEN_LEAKAGE_PATTERN.match?(response_text)
      return { flagged: true, flag_type: "pii_token_leakage", replacement: SAFE_PII_REPLACEMENT }
    end

    { flagged: false, flag_type: nil, replacement: nil }
  end
end
