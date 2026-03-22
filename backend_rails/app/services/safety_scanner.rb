# frozen_string_literal: true

# Regex-based safety pattern scanning for therapy session transcripts.
#
# Scans transcript lines for safety-critical content (suicidal ideation, self-harm,
# harm to others, substance crisis, severe distress) and returns SafetyFlagData structs.
#
# Architecture:
# - RISK_PATTERNS: True safety risk indicators (SI, self-harm, HI, substance crisis,
#   acute distress). These produce safety_risk flags.
# - SYMPTOM_PATTERNS: Clinical symptom indicators (sleep disturbance, social withdrawal,
#   anhedonia, appetite changes). These are tracked separately as clinical_observation
#   flags and do NOT trigger safety alerts on their own.
# - Contextual disambiguation: Hopelessness language directed at treatment/therapy
#   is excluded from safety flags.
# - Multi-signal convergence: Medium-severity distress signals require co-occurrence
#   of at least 2 distinct risk-specific signals before escalating to a safety flag.
# - SI probe absence detection: Flags clinician omissions when a multi-symptom
#   depressive presentation is detected but no direct SI screen was conducted.
class SafetyScanner
  # Data struct returned for each safety flag found
  SafetyFlagData = Struct.new(
    :flag_type, :severity, :description, :transcript_excerpt,
    :line_start, :line_end, :source, :category,
    keyword_init: true
  )

  # --- Constants: Flag types ---
  FLAG_TYPES = %w[
    suicidal_ideation self_harm harm_to_others substance_crisis
    severe_distress si_screen_absent substance_screen_absent
  ].freeze

  # --- Constants: Categories ---
  CATEGORY_SAFETY_RISK = "safety_risk"
  CATEGORY_CLINICAL_OBSERVATION = "clinical_observation"
  CATEGORY_CLINICIAN_OMISSION = "clinician_omission"

  # --- Constants: Severities ---
  SEVERITY_LOW = "low"
  SEVERITY_MEDIUM = "medium"
  SEVERITY_HIGH = "high"
  SEVERITY_CRITICAL = "critical"

  # ---------------------------------------------------------------------------
  # Contextual exclusion: treatment-directed hopelessness
  # ---------------------------------------------------------------------------
  TREATMENT_CONTEXT_PATTERNS = [
    /\b(this|therapy|treatment|session|coming\s+here|counseling|medication|helping|helped|doctor|appointment)\b/i
  ].freeze

  # ---------------------------------------------------------------------------
  # Safety risk patterns - genuine safety indicators
  # ---------------------------------------------------------------------------
  # Each entry maps a flag_type to a list of [pattern, severity, description]
  RISK_PATTERNS = {
    "suicidal_ideation" => [
      [
        /\b(want\s+to\s+(die|end\s+(it|my\s+life|everything))|(wish|rather)\s+(I\s+)?(was|were)\s+dead|kill\s+myself|suicid(e|al)|don'?t\s+want\s+to\s+(be\s+alive|live|exist)|no\s+(reason|point)\s+(to|in)\s+(live|living|go\s+on)|better\s+off\s+(dead|without\s+me)|end(ing)?\s+my\s+life|take\s+my\s+(own\s+)?life)/i,
        SEVERITY_CRITICAL,
        "Potential suicidal ideation detected"
      ],
      [
        /\b(thought(s)?\s+(about|of)\s+dying|think(ing)?\s+about\s+(not\s+being\s+here|death|dying)|plan\s+to\s+(end|kill)|written\s+a\s+(note|letter|will)|given\s+away\s+(my\s+)?(stuff|things|belongings))/i,
        SEVERITY_HIGH,
        "Possible suicidal ideation or planning indicators"
      ]
    ],
    "self_harm" => [
      [
        /\b(cut(ting)?\s+(myself|my\s+(arm|wrist|leg|skin))|hurt(ing)?\s+myself|burn(ing)?\s+myself|hit(ting)?\s+myself|scratch(ing)?\s+myself|bang(ing)?\s+my\s+head|self[- ]?harm|injur(e|ing)\s+myself|pul(l|ling)\s+(out\s+)?my\s+hair)/i,
        SEVERITY_HIGH,
        "Self-harm behavior or ideation detected"
      ],
      [
        /\b(punish\s+myself|deserve\s+to\s+(hurt|suffer|be\s+in\s+pain)|(need|want)\s+to\s+feel\s+pain)/i,
        SEVERITY_MEDIUM,
        "Possible self-punitive ideation"
      ]
    ],
    "harm_to_others" => [
      [
        /\b(kill\s+(him|her|them|someone|my)|want\s+to\s+hurt\s+(him|her|them|someone|my)|going\s+to\s+hurt\s+(him|her|them|someone)|plan\s+to\s+(attack|harm|hurt)|homicid(e|al)|violent\s+(urge|thought|fantasy|fantasies)|(have|own|bought)\s+a\s+(gun|weapon|knife)\s+(to|for)\s+(use|hurt))/i,
        SEVERITY_CRITICAL,
        "Potential harm to others detected"
      ],
      [
        /\b(thought(s)?\s+(about|of)\s+hurt(ing)?|fantasiz(e|ing)\s+about\s+(hurt|violence|attack)|so\s+angry\s+(I\s+)?(could|might|want\s+to)\s+(hit|punch|hurt|kill))/i,
        SEVERITY_HIGH,
        "Violent ideation or aggressive fantasies"
      ]
    ],
    "substance_crisis" => [
      # Tier 1: Standalone high-severity triggers
      # Blackout events
      [
        /\b(black(ed)?\s+out|blacked\s+out)/i,
        SEVERITY_HIGH,
        "Blackout episode reported — standalone acute substance safety event"
      ],
      # Found unconscious / passed out
      [
        /\b(found\s+(me|him|her|them)\s+(passed\s+out|unconscious)|passed\s+out\s+(in|on|at)\s+(my|the|a))/i,
        SEVERITY_HIGH,
        "Loss of consciousness reported — acute substance safety event"
      ],
      # Original high-severity patterns
      [
        /\b(overdos(e|ed|ing)|can'?t\s+stop\s+(drink|using|taking)|withdraw(al|ing)|(drink|us)(ing|ed)\s+(every\s+day|all\s+day|constantly|non[- ]?stop)|relaps(e|ed|ing)|detox|(need|have)\s+to\s+(drink|use|take)\s+(to|just\s+to)\s+(function|cope|get\s+through))/i,
        SEVERITY_HIGH,
        "Substance use crisis indicators detected"
      ],
      # Behavioral indicators: escalating frequency
      [
        /\b(drinking|using)\s+.{0,30}(four|five|six|seven|4|5|6|7)\s+(or\s+\w+\s+)?times\s+a\s+week/i,
        SEVERITY_HIGH,
        "Escalating substance use frequency detected"
      ],
      # High quantity per session (6+ drinks)
      [
        /\b(six|seven|eight|nine|ten|6|7|8|9|10|\d{2,})\s+(or\s+\w+\s+)?(drink|beer|shot|glass|wine|cocktail)s?/i,
        SEVERITY_HIGH,
        "High-quantity substance use reported"
      ],
      # Resumed use after harmful event
      [
        /\b(start(ed)?\s+(drinking|using)\s+again|went\s+back\s+to\s+(drinking|using)|(drank|used)\s+again\s+.{0,20}(after|later|next\s+day))/i,
        SEVERITY_HIGH,
        "Resumed substance use after harmful event"
      ],
      # Emotional dependency / using to cope
      [
        /\b(only\s+thing\s+that\s+(helps|works|numbs|stops)|drink(ing)?\s+to\s+(forget|cope|numb|not\s+think|not\s+feel|deal\s+with)|(need|have)\s+to\s+(drink|use)\s+(when|because|after))/i,
        SEVERITY_MEDIUM,
        "Emotional dependency on substance use"
      ],
      # Original medium-severity patterns
      [
        /\b(mixing\s+(drugs|medications|pills)|driving\s+(drunk|high|under\s+the\s+influence)|(hiding|sneaking)\s+(my\s+)?(drink|drug|substance|alcohol))/i,
        SEVERITY_MEDIUM,
        "Risky substance use behavior"
      ]
    ],
    "severe_distress" => [
      [
        /\b(can'?t\s+(take|handle|do)\s+(it|this)\s+anymore|(feel|feeling)\s+(hopeless|worthless)|no\s+(hope|way\s+out)|nothing\s+(matters|will\s+(ever\s+)?(help|change|get\s+better))|(no|don'?t\s+have)\s+(any\s+)?(reason|purpose)\s+(to|for)\s+(live|living|go\s+on))/i,
        SEVERITY_HIGH,
        "Severe emotional distress or hopelessness"
      ],
      [
        /\b(panic\s+attack|thought\s+(I\s+)?(was|am)\s+(dying|having\s+a\s+heart\s+attack)|can'?t\s+breathe|dissociat(e|ed|ing)|out\s+of\s+my\s+body|don'?t\s+feel\s+real)/i,
        SEVERITY_MEDIUM,
        "Acute distress symptoms (panic, dissociation)"
      ]
    ]
  }.freeze

  # ---------------------------------------------------------------------------
  # Clinical symptom patterns - DSM-5 diagnostic criteria, NOT safety flags
  # ---------------------------------------------------------------------------
  SYMPTOM_PATTERNS = {
    "sleep_disturbance" => [
      [
        /\b(sleep(ing)?\s+(too\s+much|all\s+day|ten|eleven|twelve|\d{2}\s+hours)|insomnia|can'?t\s+sleep|wake\s+up\s+(at|in\s+the\s+middle)|hypersomni)/i,
        "Sleep disturbance detected"
      ]
    ],
    "social_withdrawal" => [
      [
        /\b(withdraw(n|ing)|isolat(e|ed|ing)|stop(ped)?\s+(seeing|going|hanging\s+out|responding)|avoid(ing)?\s+(people|friends|family|everyone)|don'?t\s+(want\s+to\s+)?(see|talk\s+to)\s+(anyone|people|friends))/i,
        "Social withdrawal or isolation markers"
      ]
    ],
    "anhedonia" => [
      [
        /\b(don'?t\s+(enjoy|care\s+about)|lost\s+interest|stop(ped)?\s+caring|nothing\s+(is\s+)?fun|used\s+to\s+(enjoy|like|love).*?(don'?t|haven'?t|stopped))/i,
        "Anhedonia or loss of interest"
      ]
    ],
    "appetite_change" => [
      [
        /\b(not\s+eating|skip(ping)?\s+(meals?|breakfast|lunch|dinner)|no\s+appetite|eating\s+too\s+much|lost\s+weight|gained\s+weight)/i,
        "Appetite or weight change"
      ]
    ],
    "concentration_difficulty" => [
      [
        /\b(can'?t\s+(focus|concentrate|think)|hard\s+to\s+(focus|concentrate|think)|mind\s+(goes\s+blank|wanders)|forgetful|brain\s+fog)/i,
        "Concentration or cognitive difficulty"
      ]
    ],
    "fatigue" => [
      [
        /\b(exhaust(ed|ing)|no\s+energy|fatigue(d)?|tired\s+all\s+the\s+time|can'?t\s+get\s+out\s+of\s+bed)/i,
        "Fatigue or low energy"
      ]
    ]
  }.freeze

  # Minimum distinct symptom categories for "multi-symptom depressive presentation"
  MULTI_SYMPTOM_THRESHOLD = 3

  # ---------------------------------------------------------------------------
  # SI probe patterns - therapist conducting a suicide/safety screen
  # ---------------------------------------------------------------------------
  SI_PROBE_PATTERNS = [
    /\b(thought(s)?\s+(about|of)\s+(hurt|harm|kill|end)(ing)?\s+(yourself|your\s+life)|suicid(e|al)|(want|wish)\s+to\s+(die|not\s+be\s+alive|end\s+(your|it))|safe(ty)?\s+(plan|screen|check|assessment)|(harm|hurt)\s+yourself|(thought|think)(s|ing)?\s+(about|of)\s+not\s+(being|wanting\s+to\s+be)\s+(here|alive))/i
  ].freeze

  # ---------------------------------------------------------------------------
  # Substance safety screen patterns
  # ---------------------------------------------------------------------------
  SUBSTANCE_PROBE_PATTERNS = [
    /\b(cut\s+down\s+on\s+(your\s+)?drinking|AUDIT|CAGE|how\s+much\s+(are\s+you|do\s+you)\s+(drink|us)|concern(ed)?\s+about\s+(your\s+)?(drinking|alcohol|substance|drug|use)|(think|feel|felt)\s+.{0,10}(need|should)\s+(to\s+)?(cut\s+down|stop|quit|reduce)|withdrawal\s+(symptom|sign|risk)|driv(e|ing)\s+(after|while|when)\s+(drinking|using)|safe(ty)?\s+(plan|screen|check|assessment)\s+.{0,20}(substance|alcohol|drug|drinking))/i
  ].freeze

  # Minimum distinct substance risk signals for substance_screen_absent flag
  SUBSTANCE_SIGNAL_THRESHOLD = 2

  # Medium-severity severe_distress signals require this many distinct signals
  MEDIUM_CONVERGENCE_THRESHOLD = 2

  # Clause boundary pattern for contextual disambiguation
  CLAUSE_BOUNDARY = /[,;.!?\u2014]|\s+but\s+|\s+although\s+|\s+though\s+|\s+however\s+/i

  # ---------------------------------------------------------------------------
  # Main scanner
  # ---------------------------------------------------------------------------
  def scan_transcript(lines, existing_ai_flags = [])
    existing_ai_flags ||= []
    results = []
    medium_distress_candidates = []

    lines.each_with_index do |line, line_idx|
      line_num = line_idx + 1

      # Skip therapist lines for risk pattern matching
      next if therapist_line?(line)

      RISK_PATTERNS.each do |flag_type, patterns|
        patterns.each do |pattern, severity, description|
          match = pattern.match(line)
          next unless match

          # Contextual exclusion for severe_distress
          if flag_type == "severe_distress" && treatment_context?(line, match)
            next
          end

          # Deduplication against existing AI flags
          next if existing_ai_flags.any? do |existing|
            existing_flag_type = existing.respond_to?(:flag_type) ? existing.flag_type : existing[:flag_type]
            existing_line_start = existing.respond_to?(:line_start) ? existing.line_start : existing[:line_start]
            existing_line_end = existing.respond_to?(:line_end) ? existing.line_end : existing[:line_end]
            existing_flag_type.to_s == flag_type &&
              ranges_overlap?(line_num, line_num, existing_line_start, existing_line_end)
          end

          # Deduplication against results already found
          next if results.any? do |r|
            r.flag_type == flag_type &&
              ranges_overlap?(line_num, line_num, r.line_start, r.line_end)
          end

          # Deduplication against medium_distress_candidates
          next if medium_distress_candidates.any? do |r|
            r.flag_type == flag_type &&
              ranges_overlap?(line_num, line_num, r.line_start, r.line_end)
          end

          excerpt = line.strip
          excerpt = excerpt[0, 200] + "..." if excerpt.length > 200

          flag_data = SafetyFlagData.new(
            flag_type: flag_type,
            severity: severity,
            description: description,
            transcript_excerpt: excerpt,
            line_start: line_num,
            line_end: line_num,
            source: "regex",
            category: CATEGORY_SAFETY_RISK
          )

          # Multi-signal convergence for medium-severity severe_distress
          if flag_type == "severe_distress" && severity == SEVERITY_MEDIUM
            medium_distress_candidates << flag_data
          else
            results << flag_data
          end
        end
      end
    end

    # Convergence check for medium-severity distress
    if medium_distress_candidates.length >= MEDIUM_CONVERGENCE_THRESHOLD
      results.concat(medium_distress_candidates)
    end

    # Symptom detection
    detected_symptoms = detect_symptoms(lines)
    symptom_categories_found = detected_symptoms.keys

    detected_symptoms.each do |category_name, line_nums|
      patterns_for_cat = SYMPTOM_PATTERNS[category_name]
      _pattern, description = patterns_for_cat[0]
      first_line_num = line_nums[0]
      excerpt = lines[first_line_num - 1].strip
      excerpt = excerpt[0, 200] + "..." if excerpt.length > 200

      results << SafetyFlagData.new(
        flag_type: "severe_distress",
        severity: SEVERITY_LOW,
        description: "Clinical observation: #{description}",
        transcript_excerpt: excerpt,
        line_start: first_line_num,
        line_end: first_line_num,
        source: "regex",
        category: CATEGORY_CLINICAL_OBSERVATION
      )
    end

    # SI probe absence detection
    if symptom_categories_found.length >= MULTI_SYMPTOM_THRESHOLD &&
       !therapist_conducted_si_probe?(lines)
      results << SafetyFlagData.new(
        flag_type: "si_screen_absent",
        severity: SEVERITY_MEDIUM,
        description: "Multi-symptom depressive presentation detected " \
                     "(#{symptom_categories_found.join(', ')}) but no direct " \
                     "suicidal ideation screen was conducted by the therapist.",
        transcript_excerpt: "",
        line_start: 1,
        line_end: lines.length,
        source: "regex",
        category: CATEGORY_CLINICIAN_OMISSION
      )
    end

    # Substance safety screen absence detection
    substance_safety_flags = results.select do |f|
      f.flag_type == "substance_crisis" && f.category == CATEGORY_SAFETY_RISK
    end

    if substance_safety_flags.length >= SUBSTANCE_SIGNAL_THRESHOLD &&
       !therapist_conducted_substance_probe?(lines)
      results << SafetyFlagData.new(
        flag_type: "substance_screen_absent",
        severity: SEVERITY_MEDIUM,
        description: "Substance crisis signals detected " \
                     "(#{substance_safety_flags.length} distinct indicators) but no " \
                     "structured substance use safety screen was conducted by " \
                     "the therapist.",
        transcript_excerpt: "",
        line_start: 1,
        line_end: lines.length,
        source: "regex",
        category: CATEGORY_CLINICIAN_OMISSION
      )
    end

    results
  end

  private

  def ranges_overlap?(start1, end1, start2, end2)
    start1 <= end2 && start2 <= end1
  end

  def treatment_context?(line, match)
    # Find clause boundaries
    boundaries = [0]
    line.scan(CLAUSE_BOUNDARY) do
      boundaries << Regexp.last_match.end(0)
    end
    boundaries << line.length

    match_start = match.begin(0)

    (0...(boundaries.length - 1)).each do |i|
      clause_start = boundaries[i]
      clause_end = boundaries[i + 1]
      if clause_start <= match_start && match_start < clause_end
        clause = line[clause_start...clause_end]
        return TREATMENT_CONTEXT_PATTERNS.any? { |pat| pat.match?(clause) }
      end
    end

    false
  end

  def therapist_line?(line)
    line.strip.downcase.start_with?("therapist:")
  end

  def detect_symptoms(lines)
    detected = {}
    lines.each_with_index do |line, line_idx|
      line_num = line_idx + 1
      SYMPTOM_PATTERNS.each do |category, patterns|
        patterns.each do |compiled_re, _desc|
          if compiled_re.match?(line)
            detected[category] ||= []
            detected[category] << line_num
            break # One match per category per line is enough
          end
        end
      end
    end
    detected
  end

  def therapist_conducted_si_probe?(lines)
    lines.any? do |line|
      next unless therapist_line?(line)
      SI_PROBE_PATTERNS.any? { |pat| pat.match?(line) }
    end
  end

  def therapist_conducted_substance_probe?(lines)
    lines.any? do |line|
      next unless therapist_line?(line)
      SUBSTANCE_PROBE_PATTERNS.any? { |pat| pat.match?(line) }
    end
  end
end
