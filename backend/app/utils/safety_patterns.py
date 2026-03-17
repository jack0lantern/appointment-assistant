"""Regex-based safety pattern scanning for therapy session transcripts.

Scans transcript lines for safety-critical content (suicidal ideation, self-harm,
harm to others, substance crisis, severe distress) and returns SafetyFlagData objects.
"""

import re

from app.schemas.safety import FlagType, SafetyFlagData, Severity


# Each entry maps a FlagType to a list of (compiled_pattern, severity, description) tuples.
# Patterns are case-insensitive and designed to match client speech in therapy transcripts.
SAFETY_PATTERNS: dict[FlagType, list[tuple[re.Pattern, Severity, str]]] = {
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
        (
            re.compile(
                r"\b(can\'?t\s+(take|handle|do)\s+(it|this)\s+anymore|"
                r"(feel|feeling)\s+(hopeless|helpless|worthless|empty)|"
                r"no\s+(hope|way\s+out)|"
                r"give\s+up|"
                r"giving\s+up|"
                r"nothing\s+(matters|will\s+(help|change|get\s+better))|"
                r"trapped|"
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


def _ranges_overlap(
    start1: int, end1: int, start2: int, end2: int
) -> bool:
    """Check whether two line ranges overlap."""
    return start1 <= end2 and start2 <= end1


def scan_transcript_for_safety(
    lines: list[str],
    existing_ai_flags: list[SafetyFlagData] | None = None,
) -> list[SafetyFlagData]:
    """Scan transcript lines for safety-critical patterns.

    Args:
        lines: List of transcript lines (0-indexed internally, reported as 1-indexed).
        existing_ai_flags: Flags already found by AI analysis. Used for deduplication:
            if a regex match overlaps the same line range and flag_type as an existing
            AI flag, it is skipped.

    Returns:
        List of SafetyFlagData for each unique match found.
    """
    if existing_ai_flags is None:
        existing_ai_flags = []

    results: list[SafetyFlagData] = []

    for line_idx, line in enumerate(lines):
        line_num = line_idx + 1  # 1-indexed for output

        for flag_type, patterns in SAFETY_PATTERNS.items():
            for compiled_re, severity, description in patterns:
                match = compiled_re.search(line)
                if match is None:
                    continue

                # Deduplication: skip if an existing AI flag covers the same
                # line range with the same flag type.
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

                # Also deduplicate against results we already found in this scan
                # (same flag_type and overlapping line).
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

                # Extract a short excerpt around the match
                excerpt = line.strip()
                if len(excerpt) > 200:
                    excerpt = excerpt[:200] + "..."

                results.append(
                    SafetyFlagData(
                        flag_type=flag_type,
                        severity=severity,
                        description=description,
                        transcript_excerpt=excerpt,
                        line_start=line_num,
                        line_end=line_num,
                        source="regex",
                    )
                )

    return results
