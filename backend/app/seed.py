import asyncio
from pathlib import Path
from datetime import datetime, timezone

from sqlalchemy import select

from app.database import async_session_factory
from app.models import User, Therapist, Client, Session, Transcript
from app.services.auth_service import hash_password


async def main():
    async with async_session_factory() as session:
        # Check if seed data already exists
        existing = await session.execute(
            select(User).where(User.email == "therapist@tava.health")
        )
        if existing.scalar_one_or_none():
            print("Seed data already exists, skipping.")
            return

        # Create therapist user
        therapist_user = User(
            email="therapist@tava.health",
            name="Dr. Sarah Chen",
            role="therapist",
            password_hash=hash_password("demo123"),
        )
        session.add(therapist_user)
        await session.flush()

        # Create client user
        client_user = User(
            email="client@tava.health",
            name="Alex Rivera",
            role="client",
            password_hash=hash_password("demo123"),
        )
        session.add(client_user)
        await session.flush()

        # Create therapist profile
        therapist = Therapist(
            user_id=therapist_user.id,
            license_type="LCSW",
            specialties=["anxiety", "depression", "CBT"],
            preferences={},
        )
        session.add(therapist)
        await session.flush()

        # Create client profile linked to therapist
        client = Client(
            user_id=client_user.id,
            therapist_id=therapist.id,
            name="Alex Rivera",
        )
        session.add(client)
        await session.flush()

        # Read transcript fixture
        fixture_path = Path(__file__).resolve().parent.parent / "evaluation" / "fixtures" / "anxiety.txt"
        transcript_text = fixture_path.read_text()
        word_count = len(transcript_text.split())

        # Create session
        therapy_session = Session(
            therapist_id=therapist.id,
            client_id=client.id,
            session_date=datetime.now(timezone.utc),
            session_number=1,
            duration_minutes=50,
            status="completed",
        )
        session.add(therapy_session)
        await session.flush()

        # Create transcript
        transcript = Transcript(
            session_id=therapy_session.id,
            content=transcript_text,
            source_type="uploaded",
            word_count=word_count,
        )
        session.add(transcript)

        await session.commit()
        print("Seed data created successfully:")
        print(f"  Therapist user: {therapist_user.email} (id={therapist_user.id})")
        print(f"  Client user: {client_user.email} (id={client_user.id})")
        print(f"  Therapist profile: id={therapist.id}, license={therapist.license_type}")
        print(f"  Client profile: id={client.id}, name={client.name}")
        print(f"  Session: id={therapy_session.id}, session_number={therapy_session.session_number}")
        print(f"  Transcript: id={transcript.id}, word_count={transcript.word_count}")


if __name__ == "__main__":
    asyncio.run(main())
