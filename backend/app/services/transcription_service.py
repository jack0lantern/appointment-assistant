"""AssemblyAI-powered transcription with speaker diarization."""

import logging
from dataclasses import dataclass, field

import assemblyai as aai

from app.config import settings

logger = logging.getLogger(__name__)


@dataclass
class Utterance:
    speaker: str          # raw label e.g. "speaker_0"
    text: str
    start_time: float     # seconds
    end_time: float       # seconds
    confidence: float

    def to_dict(self) -> dict:
        return {
            "speaker": self.speaker,
            "speaker_raw": self.speaker,
            "text": self.text,
            "start_time": self.start_time,
            "end_time": self.end_time,
            "confidence": self.confidence,
        }


@dataclass
class DiarizedTranscript:
    utterances: list[Utterance] = field(default_factory=list)
    speakers: list[str] = field(default_factory=list)
    duration_seconds: float = 0.0

    def to_flat_text(self, speaker_map: dict[str, str] | None = None) -> str:
        """Convert to flat transcript text with speaker labels."""
        lines = []
        for u in self.utterances:
            label = u.speaker
            if speaker_map and u.speaker in speaker_map:
                label = speaker_map[u.speaker].capitalize()
            lines.append(f"{label}: {u.text}")
        return "\n".join(lines)


class TranscriptionService:
    def __init__(self):
        if settings.ASSEMBLYAI_API_KEY:
            aai.settings.api_key = settings.ASSEMBLYAI_API_KEY
            self.ready = True
        else:
            self.ready = False

    def transcribe_with_diarization(self, audio_data: bytes) -> DiarizedTranscript:
        """Transcribe audio with speaker diarization via AssemblyAI.

        Args:
            audio_data: Raw audio bytes (WAV, MP3, MP4, WebM, etc.)

        Returns:
            DiarizedTranscript with utterances and speaker labels.
        """
        if not self.ready:
            raise RuntimeError("AssemblyAI API key not configured (ASSEMBLYAI_API_KEY)")

        config = aai.TranscriptionConfig(
            speaker_labels=True,
            language_code="en",
        )

        transcriber = aai.Transcriber()
        transcript = transcriber.transcribe(audio_data, config=config)

        if transcript.status == aai.TranscriptStatus.error:
            raise RuntimeError(f"AssemblyAI transcription failed: {transcript.error}")

        return self._parse_response(transcript)

    def _parse_response(self, transcript: aai.Transcript) -> DiarizedTranscript:
        """Parse AssemblyAI response into our DiarizedTranscript format."""
        result = DiarizedTranscript()

        if transcript.audio_duration:
            result.duration_seconds = transcript.audio_duration

        speakers_seen: set[str] = set()

        if transcript.utterances:
            for utt in transcript.utterances:
                speaker_label = f"speaker_{utt.speaker}"
                speakers_seen.add(speaker_label)
                result.utterances.append(Utterance(
                    speaker=speaker_label,
                    text=utt.text.strip(),
                    start_time=utt.start / 1000.0,  # AssemblyAI uses milliseconds
                    end_time=utt.end / 1000.0,
                    confidence=utt.confidence or 0.0,
                ))
        elif transcript.words:
            # Fallback: build utterances from word-level speaker info
            current_speaker = None
            current_words: list[str] = []
            current_start = 0.0

            for word in transcript.words:
                speaker_label = f"speaker_{word.speaker}" if word.speaker else "speaker_0"
                speakers_seen.add(speaker_label)

                if speaker_label != current_speaker:
                    if current_words and current_speaker:
                        result.utterances.append(Utterance(
                            speaker=current_speaker,
                            text=" ".join(current_words),
                            start_time=current_start / 1000.0,
                            end_time=word.start / 1000.0,
                            confidence=word.confidence or 0.0,
                        ))
                    current_speaker = speaker_label
                    current_words = [word.text]
                    current_start = word.start
                else:
                    current_words.append(word.text)

            if current_words and current_speaker:
                result.utterances.append(Utterance(
                    speaker=current_speaker,
                    text=" ".join(current_words),
                    start_time=current_start / 1000.0,
                    end_time=(transcript.words[-1].end or 0) / 1000.0,
                    confidence=0.0,
                ))

        result.speakers = sorted(speakers_seen)
        return result


transcription_service = TranscriptionService()
