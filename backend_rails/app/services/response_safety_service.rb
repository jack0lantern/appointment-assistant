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

    { flagged: false, flag_type: nil, replacement: nil }
  end
end
