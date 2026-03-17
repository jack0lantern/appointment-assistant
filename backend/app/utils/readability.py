"""Readability scoring using textstat."""
import textstat
from app.schemas.evaluation import ReadabilityScores


def compute_readability(text: str) -> ReadabilityScores:
    """Compute readability metrics for a text string."""
    if not text.strip():
        return ReadabilityScores(
            flesch_reading_ease=0.0,
            flesch_kincaid_grade=0.0,
            gunning_fog=0.0,
            avg_sentence_length=0.0,
            avg_word_length=0.0,
        )
    words = text.split()
    sentences = max(1, textstat.sentence_count(text))
    avg_sentence_len = len(words) / sentences
    avg_word_len = sum(len(w.strip('.,!?;:')) for w in words) / max(1, len(words))
    return ReadabilityScores(
        flesch_reading_ease=textstat.flesch_reading_ease(text),
        flesch_kincaid_grade=textstat.flesch_kincaid_grade(text),
        gunning_fog=textstat.gunning_fog(text),
        avg_sentence_length=round(avg_sentence_len, 1),
        avg_word_length=round(avg_word_len, 2),
    )
