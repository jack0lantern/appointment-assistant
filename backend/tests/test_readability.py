import pytest
from app.utils.readability import compute_readability


CLINICAL_TEXT = (
    "The patient presents with comorbid generalized anxiety disorder and major depressive episode, "
    "manifesting as hypervigilance, psychomotor retardation, anhedonia, and somatic complaints. "
    "Differential diagnosis includes dysthymia and adjustment disorder with anxious mood. "
    "Recommended pharmacological augmentation with CBT using cognitive restructuring and behavioral activation protocols."
)

PLAIN_TEXT = (
    "You have been feeling very anxious and sad. "
    "It is hard to sleep and you do not enjoy things you used to like. "
    "We will work on changing negative thoughts and doing more activities. "
    "Try to go for a walk each day and write down your worries."
)


def test_clinical_text_higher_grade_than_plain_text():
    clinical = compute_readability(CLINICAL_TEXT)
    plain = compute_readability(PLAIN_TEXT)
    assert clinical.flesch_kincaid_grade > plain.flesch_kincaid_grade


def test_plain_text_meets_8th_grade_threshold():
    result = compute_readability(PLAIN_TEXT)
    assert result.flesch_kincaid_grade <= 8.0, (
        f"Plain text should be <= 8th grade, got {result.flesch_kincaid_grade}"
    )


def test_clinical_text_fails_8th_grade_threshold():
    result = compute_readability(CLINICAL_TEXT)
    assert result.flesch_kincaid_grade > 8.0, (
        f"Clinical text should be > 8th grade, got {result.flesch_kincaid_grade}"
    )


def test_empty_text_returns_zero_scores():
    result = compute_readability("")
    assert result.flesch_kincaid_grade == 0.0
    assert result.flesch_reading_ease == 0.0


def test_readability_returns_all_fields():
    result = compute_readability(PLAIN_TEXT)
    assert hasattr(result, 'flesch_reading_ease')
    assert hasattr(result, 'flesch_kincaid_grade')
    assert hasattr(result, 'gunning_fog')
    assert hasattr(result, 'avg_sentence_length')
    assert hasattr(result, 'avg_word_length')
