"""Prompt templates for generating evaluation improvement suggestions."""


def build_suggestion_prompt(category: str, eval_result: dict, transcript_text: str) -> str:
    """Build a focused prompt based on the evaluation category."""

    if category == "structural":
        issues = []
        if eval_result.get("missing_fields"):
            issues.append(f"Missing required fields: {', '.join(eval_result['missing_fields'])}")
        if eval_result.get("errors"):
            issues.append(f"Errors: {'; '.join(eval_result['errors'])}")
        if eval_result.get("jargon_found"):
            issues.append(f"Clinical jargon found in client content: {', '.join(eval_result['jargon_found'])}")
        if eval_result.get("risk_data_found"):
            issues.append("Risk-related terms found in client-facing content")
        if not eval_result.get("citation_bounds_valid", True):
            issues.append("Citation line references are out of bounds")

        issues_text = "\n".join(f"- {i}" for i in issues) if issues else "- No specific issues identified"

        return f"""You are a clinical documentation improvement advisor. Analyze the following structural validation failures for a therapy treatment plan and provide specific, actionable suggestions to fix each issue.

STRUCTURAL ISSUES:
{issues_text}

TRANSCRIPT (for citation context):
{transcript_text[:2000]}

Provide 2-5 concise, actionable suggestions. Each suggestion should directly address one of the issues above. For jargon issues, suggest specific plain-language alternatives. For missing fields, suggest what content could fill them based on the transcript."""

    elif category == "readability":
        therapist_scores = eval_result.get("therapist_scores", {})
        client_scores = eval_result.get("client_scores", {})
        client_grade = client_scores.get("flesch_kincaid_grade", 0)
        therapist_grade = therapist_scores.get("flesch_kincaid_grade", 0)
        client_grade_ok = eval_result.get("client_grade_ok", True)
        separation_ok = eval_result.get("separation_ok", True)

        issues = []
        if not client_grade_ok:
            issues.append(f"Client content reading level is grade {client_grade:.1f} (must be <= 8.0, over by {client_grade - 8.0:.1f} grades)")
        if not separation_ok:
            separation = therapist_grade - client_grade
            issues.append(f"Therapist-client grade separation is {separation:.1f} (must be >= 2.0, short by {2.0 - separation:.1f} grades)")

        issues_text = "\n".join(f"- {i}" for i in issues) if issues else "- Readability targets met"

        return f"""You are a readability improvement advisor for therapy treatment plans. The client-facing content must be at or below an 8th-grade reading level, and the therapist content should be at least 2 grade levels above the client content.

READABILITY ISSUES:
{issues_text}

SCORES:
- Client Flesch-Kincaid grade: {client_grade:.1f} (target: <= 8.0)
- Therapist Flesch-Kincaid grade: {therapist_grade:.1f}
- Client Flesch reading ease: {client_scores.get('flesch_reading_ease', 0):.1f}
- Client avg sentence length: {client_scores.get('avg_sentence_length', 0):.1f} words

Provide 2-5 specific suggestions to improve readability. Focus on: shorter sentences, simpler words, active voice, and removing unnecessary complexity from client-facing content."""

    elif category == "safety":
        expected = eval_result.get("expected_flags", 0)
        detected = eval_result.get("detected_flags", 0)

        return f"""You are a clinical safety detection advisor. Analyze the safety flag detection results for this therapy transcript.

The system uses a layered detection architecture:
- **safety_risk** flags: Genuine safety concerns (SI, self-harm, HI, substance crisis, acute distress). These count toward pass/fail.
- **clinical_observation** flags: DSM-5 symptom indicators (sleep, withdrawal, anhedonia) tracked for clinical context but NOT counted as safety alerts.
- **clinician_omission** flags: Notes when a therapist should have conducted a safety screen (e.g., SI probe absent despite multi-symptom depression).

Contextual disambiguation is applied: hopelessness language directed at treatment ("what's the point of this helping") is excluded from safety flags.
Medium-severity distress signals require co-occurrence of 2+ distinct signals before flagging.

SAFETY DETECTION RESULTS:
- Expected safety_risk flags: {expected}
- Detected safety_risk flags: {detected}
- Status: {"PASS" if eval_result.get("passed") else "FAIL"}

TRANSCRIPT:
{transcript_text[:3000]}

If the detection missed expected flags, identify what safety concerns should have been caught and suggest why they were missed. If extra flags were detected, evaluate whether they are false positives. Provide 2-5 specific, actionable suggestions."""

    else:
        return f"Analyze this evaluation result and provide improvement suggestions:\n{eval_result}"
