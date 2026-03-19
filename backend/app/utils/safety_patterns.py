"""Regex-based safety pattern scanning for therapy session transcripts.

Scans transcript lines for safety-critical content (suicidal ideation, self-harm,
harm to others, substance crisis, severe distress) and returns SafetyFlagData objects.

Architecture (per suggestion analysis):
- RISK_PATTERNS: True safety risk indicators (SI, self-harm, HI, substance crisis,
  acute distress). These produce safety_risk flags.
- SYMPTOM_PATTERNS: Clinical symptom indicators (sleep disturbance, social withdrawal,
  anhedonia, appetite changes). These are tracked separately as clinical_observation
  flags and do NOT trigger safety alerts on their own.
- Contextual disambiguation: Hopelessness language directed at treatment/therapy
  (e.g., "what's the point of this helping") is excluded from safety flags.
- Multi-signal convergence: Medium-severity distress signals require co-occurrence
  of at least 2 distinct risk-specific signals before escalating to a safety flag.
- SI probe absence detection: Flags clinician omissions when a multi-symptom
  depressive presentation is detected but no direct SI screen was conducted.
"""

import re

from app.schemas.safety import FlagCategory, FlagType, SafetyFlagData, Severity


# ---------------------------------------------------------------------------
# Contextual exclusion: treatment-directed hopelessness
# ---------------------------------------------------------------------------
# When a severe_distress match is found, if these patterns also appear on the
# same line, the match is likely treatment-directed, not existential.
TREATMENT_CONTEXT_PATTERNS: list[re.Pattern] = [
    re.compile(
        r"\b(this|therapy|treatment|session|coming\s+here|counseling|medication|helping|helped|doctor|appointment)\b",
        re.IGNORECASE,
    ),
]


# ---------------------------------------------------------------------------
# Safety risk patterns — genuine safety indicators
# ---------------------------------------------------------------------------
# Each entry maps a FlagType to a list of (compiled_pattern, severity, description)
# tuples. These produce safety_risk category flags.
RISK_PATTERNS: dict[FlagType, list[tuple[re.Pattern, Severity, str]]] = {
    FlagType.suicidal_ideation: [
        (
            re.compile(
                r"\b(want\s+to\s+(die|end\s+(it|my\s+life|everything))|"
                r"(wish|rather)\s+(I\s+)?(was|were)\s+dead|"
                r"kill\s+myself|"
                r"suicid(e|al)|"
                r"don\'?t\s+want\s+to\s+(be\s+alive|live|exist)|"
                r"no\s+(reason|point)\s+(to|in)\s+(live|living|go\s+on)|"
                r"better\s+off\s+(dead|without\s+me)|"
                r"end(ing)?\s+my\s+life|"
                r"take\s+my\s+(own\s+)?life)",
                re.IGNORECASE,
            ),
            Severity.critical,
            "Potential suicidal ideation detected",
        ),
        (
            re.compile(
                r"\b(thought(s)?\s+(about|of)\s+dying|"
                r"think(ing)?\s+about\s+(not\s+being\s+here|death|dying)|"
                r"plan\s+to\s+(end|kill)|"
                r"written\s+a\s+(note|letter|will)|"
                r"given\s+away\s+(my\s+)?(stuff|things|belongings))",
                re.IGNORECASE,
            ),
            Severity.high,
            "Possible suicidal ideation or planning indicators",
        ),
    ],
    FlagType.self_harm: [
        (
            re.compile(
                r"\b(cut(ting)?\s+(myself|my\s+(arm|wrist|leg|skin))|"
                r"hurt(ing)?\s+myself|"
                r"burn(ing)?\s+myself|"
                r"hit(ting)?\s+myself|"
                r"scratch(ing)?\s+myself|"
                r"bang(ing)?\s+my\s+head|"
                r"self[- ]?harm|"
                r"injur(e|ing)\s+myself|"
                r"pul(l|ling)\s+(out\s+)?my\s+hair)",
                re.IGNORECASE,
            ),
            Severity.high,
            "Self-harm behavior or ideation detected",
        ),
        (
            re.compile(
                r"\b(punish\s+myself|"
                r"deserve\s+to\s+(hurt|suffer|be\s+in\s+pain)|"
                r"(need|want)\s+to\s+feel\s+pain)",
                re.IGNORECASE,
            ),
            Severity.medium,
            "Possible self-punitive ideation",
        ),
    ],
    FlagType.harm_to_others: [
        (
            re.compile(
                r"\b(kill\s+(him|her|them|someone|my)|"
                r"want\s+to\s+hurt\s+(him|her|them|someone|my)|"
                r"going\s+to\s+hurt\s+(him|her|them|someone)|"
                r"plan\s+to\s+(attack|harm|hurt)|"
                r"homicid(e|al)|"
                r"violent\s+(urge|thought|fantasy|fantasies)|"
                r"(have|own|bought)\s+a\s+(gun|weapon|knife)\s+(to|for)\s+(use|hurt))",
                re.IGNORECASE,
            ),
            Severity.critical,
            "Potential harm to others detected",
        ),
        (
            re.compile(
                r"\b(thought(s)?\s+(about|of)\s+hurt(ing)?|"
                r"fantasiz(e|ing)\s+about\s+(hurt|violence|attack)|"
                r"so\s+angry\s+(I\s+)?(could|might|want\s+to)\s+(hit|punch|hurt|kill))",
                re.IGNORECASE,
            ),
            Severity.high,
            "Violent ideation or aggressive fantasies",
        ),
    ],
    FlagType.substance_crisis: [
        (
            re.compile(
                r"\b(overdos(e|ed|ing)|"
                r"black(ed)?\s+out\s+(from|after)\s+(drink|drug|using)|"
                r"can\'?t\s+stop\s+(drink|using|taking)|"
                r"withdraw(al|ing)|"
                r"(drink|us)(ing|ed)\s+(every\s+day|all\s+day|constantly|non[- ]?stop)|"
                r"relaps(e|ed|ing)|"
                r"detox|"
                r"(need|have)\s+to\s+(drink|use|take)\s+(to|just\s+to)\s+(function|cope|get\s+through))",
                re.IGNORECASE,
            ),
            Severity.high,
            "Substance use crisis indicators detected",
        ),
        (
            re.compile(
                r"\b(mixing\s+(drugs|medications|pills)|"
                r"driving\s+(drunk|high|under\s+the\s+influence)|"
                r"(hiding|sneaking)\s+(my\s+)?(drink|drug|substance|alcohol))",
                re.IGNORECASE,
            ),
            Severity.medium,
            "Risky substance use behavior",
        ),
    ],
    FlagType.severe_distress: [
        # Tightened: only patterns indicating imminent risk or existential hopelessness.
        # Removed standalone "trapped", "give up", "giving up" — too broad.
        # "feel hopeless" etc. are now subject to contextual exclusion check.
        (
            re.compile(
                r"\b(can\'?t\s+(take|handle|do)\s+(it|this)\s+anymore|"
                r"(feel|feeling)\s+(hopeless|worthless)|"
                r"no\s+(hope|way\s+out)|"
                r"nothing\s+(matters|will\s+(ever\s+)?(help|change|get\s+better))|"
                r"(no|don\'?t\s+have)\s+(any\s+)?(reason|purpose)\s+(to|for)\s+(live|living|go\s+on))",
                re.IGNORECASE,
            ),
            Severity.high,
            "Severe emotional distress or hopelessness",
        ),
        (
            re.compile(
                r"\b(panic\s+attack|"
                r"thought\s+(I\s+)?(was|am)\s+(dying|having\s+a\s+heart\s+attack)|"
                r"can\'?t\s+breathe|"
                r"dissociat(e|ed|ing)|"
                r"out\s+of\s+my\s+body|"
                r"don\'?t\s+feel\s+real)",
                re.IGNORECASE,
            ),
            Severity.medium,
            "Acute distress symptoms (panic, dissociation)",
        ),
    ],
}


# ---------------------------------------------------------------------------
# Clinical symptom patterns — DSM-5 diagnostic criteria, NOT safety flags
# ---------------------------------------------------------------------------
# These are tracked as clinical_observation category. They inform severity
# scoring and SI probe absence detection but do NOT trigger safety alerts.
SYMPTOM_PATTERNS: dict[str, list[tuple[re.Pattern, str]]] = {
    "sleep_disturbance": [
        (
            re.compile(
                r"\b(sleep(ing)?\s+(too\s+much|all\s+day|ten|eleven|twelve|\d{2}\s+hours)|"
                r"insomnia|"
                r"can\'?t\s+sleep|"
                r"wake\s+up\s+(at|in\s+the\s+middle)|"
                r"hypersomni)",
                re.IGNORECASE,
            ),
            "Sleep disturbance detected",
        ),
    ],
    "social_withdrawal": [
        (
            re.compile(
                r"\b(withdraw(n|ing)|"
                r"isolat(e|ed|ing)|"
                r"stop(ped)?\s+(seeing|going|hanging\s+out|responding)|"
                r"avoid(ing)?\s+(people|friends|family|everyone)|"
                r"don\'?t\s+(want\s+to\s+)?(see|talk\s+to)\s+(anyone|people|friends))",
                re.IGNORECASE,
            ),
            "Social withdrawal or isolation markers",
        ),
    ],
    "anhedonia": [
        (
            re.compile(
                r"\b(don\'?t\s+(enjoy|care\s+about)|"
                r"lost\s+interest|"
                r"stop(ped)?\s+caring|"
                r"nothing\s+(is\s+)?fun|"
                r"used\s+to\s+(enjoy|like|love).*?(don\'?t|haven\'?t|stopped))",
                re.IGNORECASE,
            ),
            "Anhedonia or loss of interest",
        ),
    ],
    "appetite_change": [
        (
            re.compile(
                r"\b(not\s+eating|"
                r"skip(ping)?\s+(meals?|breakfast|lunch|dinner)|"
                r"no\s+appetite|"
                r"eating\s+too\s+much|"
                r"lost\s+weight|"
                r"gained\s+weight)",
                re.IGNORECASE,
            ),
            "Appetite or weight change",
        ),
    ],
    "concentration_difficulty": [
        (
            re.compile(
                r"\b(can\'?t\s+(focus|concentrate|think)|"
                r"hard\s+to\s+(focus|concentrate|think)|"
                r"mind\s+(goes\s+blank|wanders)|"
                r"forgetful|"
                r"brain\s+fog)",
                re.IGNORECASE,
            ),
            "Concentration or cognitive difficulty",
        ),
    ],
    "fatigue": [
        (
            re.compile(
                r"\b(exhaust(ed|ing)|"
                r"no\s+energy|"
                r"fatigue(d)?|"
                r"tired\s+all\s+the\s+time|"
                r"can\'?t\s+get\s+out\s+of\s+bed)",
                re.IGNORECASE,
            ),
            "Fatigue or low energy",
        ),
    ],
}

# Minimum number of distinct symptom categories required to consider a
# "multi-symptom depressive presentation" (for SI probe absence detection).
MULTI_SYMPTOM_THRESHOLD = 3


# ---------------------------------------------------------------------------
# SI probe patterns — therapist conducting a suicide/safety screen
# ---------------------------------------------------------------------------
# If the therapist uses any of these patterns, we consider that a direct SI
# screen was conducted. Checked against therapist-spoken lines only.
SI_PROBE_PATTERNS: list[re.Pattern] = [
    re.compile(
        r"\b(thought(s)?\s+(about|of)\s+(hurt|harm|kill|end)(ing)?\s+(yourself|your\s+life)|"
        r"suicid(e|al)|"
        r"(want|wish)\s+to\s+(die|not\s+be\s+alive|end\s+(your|it))|"
        r"safe(ty)?\s+(plan|screen|check|assessment)|"
        r"(harm|hurt)\s+yourself|"
        r"(thought|think)(s|ing)?\s+(about|of)\s+not\s+(being|wanting\s+to\s+be)\s+(here|alive))",
        re.IGNORECASE,
    ),
]


# ---------------------------------------------------------------------------
# Convergence: medium-severity distress signals that require co-occurrence
# ---------------------------------------------------------------------------
# Medium-severity severe_distress flags require at least this many distinct
# risk-signal matches (across different lines) to be promoted to a safety flag.
MEDIUM_CONVERGENCE_THRESHOLD = 2


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ranges_overlap(
    start1: int, end1: int, start2: int, end2: int
) -> bool:
    """Check whether two line ranges overlap."""
    return start1 <= end2 and start2 <= end1


_CLAUSE_BOUNDARY = re.compile(r"[,;.!?\u2014]|\s+but\s+|\s+although\s+|\s+though\s+|\s+however\s+", re.IGNORECASE)


def _is_treatment_context(line: str, match: re.Match) -> bool:
    """Return True if the distress match is in the same clause as treatment language.

    Splits the line on clause boundaries (punctuation, conjunctions) and only
    considers the match treatment-directed if a treatment keyword appears in the
    same clause as the distress keyword.
    """
    # Find which clause the match falls in
    boundaries = [0] + [m.end() for m in _CLAUSE_BOUNDARY.finditer(line)] + [len(line)]
    match_start = match.start()

    for i in range(len(boundaries) - 1):
        clause_start, clause_end = boundaries[i], boundaries[i + 1]
        if clause_start <= match_start < clause_end:
            clause = line[clause_start:clause_end]
            return any(pat.search(clause) for pat in TREATMENT_CONTEXT_PATTERNS)

    return False


def _is_therapist_line(line: str) -> bool:
    """Heuristic: line starts with 'Therapist:' prefix."""
    stripped = line.strip()
    return stripped.lower().startswith("therapist:")


def _detect_symptoms(lines: list[str]) -> dict[str, list[int]]:
    """Scan lines for clinical symptom patterns.

    Returns a dict mapping symptom category name to list of 1-indexed line
    numbers where that symptom was detected.
    """
    detected: dict[str, list[int]] = {}
    for line_idx, line in enumerate(lines):
        line_num = line_idx + 1
        for category, patterns in SYMPTOM_PATTERNS.items():
            for compiled_re, _desc in patterns:
                if compiled_re.search(line):
                    detected.setdefault(category, []).append(line_num)
                    break  # One match per category per line is enough
    return detected


def _therapist_conducted_si_probe(lines: list[str]) -> bool:
    """Check if the therapist conducted a direct SI/safety screen."""
    for line in lines:
        if _is_therapist_line(line):
            for pat in SI_PROBE_PATTERNS:
                if pat.search(line):
                    return True
    return False


# ---------------------------------------------------------------------------
# Main scanner
# ---------------------------------------------------------------------------

def scan_transcript_for_safety(
    lines: list[str],
    existing_ai_flags: list[SafetyFlagData] | None = None,
) -> list[SafetyFlagData]:
    """Scan transcript lines for safety-critical patterns.

    Improvements over naive keyword matching:
    1. Contextual disambiguation — hopelessness language directed at treatment
       ("what's the point of this helping") is excluded.
    2. Symptom/safety separation — DSM-5 symptom indicators (sleep, withdrawal,
       anhedonia) are tracked as clinical_observation, not safety_risk.
    3. Multi-signal convergence — medium-severity distress signals require
       co-occurrence of 2+ distinct signals before becoming safety flags.
    4. SI probe absence detection — flags clinician omission when multi-symptom
       depression is present but no SI screen was conducted.

    Args:
        lines: List of transcript lines (0-indexed internally, reported as 1-indexed).
        existing_ai_flags: Flags already found by AI analysis. Used for deduplication.

    Returns:
        List of SafetyFlagData for each unique match found.
    """
    if existing_ai_flags is None:
        existing_ai_flags = []

    results: list[SafetyFlagData] = []

    # Collect medium-severity severe_distress candidates separately for
    # convergence check.
    medium_distress_candidates: list[SafetyFlagData] = []

    for line_idx, line in enumerate(lines):
        line_num = line_idx + 1

        # Skip therapist lines for risk pattern matching — therapists use
        # safety language in screening questions ("have you thought about
        # hurting yourself?") which are not risk indicators.
        if _is_therapist_line(line):
            continue

        for flag_type, patterns in RISK_PATTERNS.items():
            for compiled_re, severity, description in patterns:
                match = compiled_re.search(line)
                if match is None:
                    continue

                # --- Contextual exclusion (suggestion #1) ---
                # For severe_distress, check if the distress match is in the
                # same clause as treatment-directed language.
                if flag_type == FlagType.severe_distress and _is_treatment_context(line, match):
                    continue

                # --- Deduplication against existing AI flags ---
                is_duplicate = any(
                    existing.flag_type == flag_type
                    and _ranges_overlap(
                        line_num, line_num,
                        existing.line_start, existing.line_end,
                    )
                    for existing in existing_ai_flags
                )
                if is_duplicate:
                    continue

                # --- Deduplication against results already found ---
                is_self_duplicate = any(
                    r.flag_type == flag_type
                    and _ranges_overlap(
                        line_num, line_num,
                        r.line_start, r.line_end,
                    )
                    for r in results
                )
                if is_self_duplicate:
                    continue

                # Also check against medium_distress_candidates
                is_candidate_duplicate = any(
                    r.flag_type == flag_type
                    and _ranges_overlap(
                        line_num, line_num,
                        r.line_start, r.line_end,
                    )
                    for r in medium_distress_candidates
                )
                if is_candidate_duplicate:
                    continue

                excerpt = line.strip()
                if len(excerpt) > 200:
                    excerpt = excerpt[:200] + "..."

                flag_data = SafetyFlagData(
                    flag_type=flag_type,
                    severity=severity,
                    description=description,
                    transcript_excerpt=excerpt,
                    line_start=line_num,
                    line_end=line_num,
                    source="regex",
                    category=FlagCategory.safety_risk,
                )

                # --- Multi-signal convergence (suggestion #3) ---
                # Medium-severity severe_distress signals are held back; they
                # only become flags if enough distinct signals co-occur.
                if (
                    flag_type == FlagType.severe_distress
                    and severity == Severity.medium
                ):
                    medium_distress_candidates.append(flag_data)
                else:
                    results.append(flag_data)

    # --- Convergence check for medium-severity distress ---
    # Promote candidates only if enough distinct signals were found.
    if len(medium_distress_candidates) >= MEDIUM_CONVERGENCE_THRESHOLD:
        results.extend(medium_distress_candidates)

    # --- Symptom detection (suggestion #2) ---
    detected_symptoms = _detect_symptoms(lines)
    symptom_categories_found = list(detected_symptoms.keys())

    for category_name, line_nums in detected_symptoms.items():
        patterns_for_cat = SYMPTOM_PATTERNS[category_name]
        _pattern, description = patterns_for_cat[0]
        # Use the first detected line for the excerpt
        first_line_num = line_nums[0]
        excerpt = lines[first_line_num - 1].strip()
        if len(excerpt) > 200:
            excerpt = excerpt[:200] + "..."

        results.append(
            SafetyFlagData(
                flag_type=FlagType.severe_distress,
                severity=Severity.low,
                description=f"Clinical observation: {description}",
                transcript_excerpt=excerpt,
                line_start=first_line_num,
                line_end=first_line_num,
                source="regex",
                category=FlagCategory.clinical_observation,
            )
        )

    # --- SI probe absence detection (suggestion #4) ---
    if (
        len(symptom_categories_found) >= MULTI_SYMPTOM_THRESHOLD
        and not _therapist_conducted_si_probe(lines)
    ):
        results.append(
            SafetyFlagData(
                flag_type=FlagType.si_screen_absent,
                severity=Severity.medium,
                description=(
                    f"Multi-symptom depressive presentation detected "
                    f"({', '.join(symptom_categories_found)}) but no direct "
                    f"suicidal ideation screen was conducted by the therapist."
                ),
                transcript_excerpt="",
                line_start=1,
                line_end=len(lines),
                source="regex",
                category=FlagCategory.clinician_omission,
            )
        )

    return results
