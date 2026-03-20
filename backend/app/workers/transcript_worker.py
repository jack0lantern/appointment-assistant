"""Background task: recording -> transcription -> diarized transcript.

Pipeline:
1. Download recording from S3
2. Transcribe with AssemblyAI (includes diarization)
3. Save raw utterances to Transcript record
4. Update session recording_status
"""

import asyncio
import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.storage_service import storage_service
from app.services.transcription_service import transcription_service

logger = logging.getLogger(__name__)


async def process_recording(session_id: int, db: AsyncSession) -> None:
    """Process a session recording: download, transcribe, diarize, save."""
    from app.models.session import Session
    from app.models.transcript import Transcript

    try:
        # 1. Fetch session
        session = await db.execute(
            select(Session).where(Session.id == session_id)
        )
        session = session.scalar_one_or_none()

        if not session or not session.recording_storage_path:
            logger.error("Session %d not found or has no recording path", session_id)
            return

        # 2. Download recording from S3
        logger.info("Downloading recording for session %d: %s", session_id, session.recording_storage_path)
        audio_data = await asyncio.to_thread(
            storage_service.download_file, session.recording_storage_path
        )
        logger.info("Downloaded %d bytes", len(audio_data))

        # 3. Transcribe with diarization (sync SDK, run in thread)
        logger.info("Starting transcription + diarization for session %d", session_id)
        diarized = await asyncio.to_thread(
            transcription_service.transcribe_with_diarization, audio_data
        )
        logger.info(
            "Transcription complete: %d utterances, %d speakers, %.1fs duration",
            len(diarized.utterances), len(diarized.speakers), diarized.duration_seconds,
        )

        # 4. Save transcript
        utterances_json = [u.to_dict() for u in diarized.utterances]
        flat_text = diarized.to_flat_text()
        word_count = len(flat_text.split())

        existing = await db.execute(
            select(Transcript).where(Transcript.session_id == session_id)
        )
        existing = existing.scalar_one_or_none()

        if existing:
            existing.content = flat_text
            existing.utterances = utterances_json
            existing.source_type = "recording"
            existing.word_count = word_count
        else:
            db.add(Transcript(
                session_id=session_id,
                content=flat_text,
                source_type="recording",
                word_count=word_count,
                utterances=utterances_json,
            ))

        # 5. Update session status
        session.recording_status = "complete"
        await db.commit()

        logger.info("Recording processing complete for session %d", session_id)

    except Exception:
        logger.exception("Failed to process recording for session %d", session_id)
        try:
            session = await db.execute(
                select(Session).where(Session.id == session_id)
            )
            session = session.scalar_one_or_none()
            if session:
                session.recording_status = "failed"
                await db.commit()
        except Exception:
            pass
