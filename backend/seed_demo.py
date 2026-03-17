"""
Seed additional rich demo data for Day 3 showcase:
- Acknowledge Alex Rivera's safety flags + approve plan (so client can view it)
- Add second client "Jordan Kim" with depression transcript + generated plan + approved
- Each client ends up with an approved plan visible to the client view
"""
import asyncio
from pathlib import Path
from datetime import datetime, timezone
from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parent / ".env")

from sqlalchemy import select

from app.database import async_session_factory
from app.models import User, Therapist, Client, Session, Transcript
from app.models.safety_flag import SafetyFlag
from app.models.treatment_plan import TreatmentPlan
from app.models.treatment_plan_version import TreatmentPlanVersion
from app.models.homework_item import HomeworkItem
from app.models.session_summary import SessionSummary
from app.services.auth_service import hash_password


async def acknowledge_and_approve_plan(db, plan_id: int, version_id: int):
    """Acknowledge all safety flags on a version and approve the plan."""
    flags_result = await db.execute(
        select(SafetyFlag).where(SafetyFlag.treatment_plan_version_id == version_id)
    )
    flags = flags_result.scalars().all()
    for flag in flags:
        flag.acknowledged = True
        flag.acknowledged_at = datetime.utcnow()

    plan_result = await db.execute(select(TreatmentPlan).where(TreatmentPlan.id == plan_id))
    plan = plan_result.scalar_one_or_none()
    if plan:
        plan.status = "approved"
    await db.flush()
    print(f"  Acknowledged {len(flags)} flags, approved plan {plan_id}")


async def create_client_with_plan(db, therapist, fixture_name: str, client_name: str, client_email: str):
    """Create a client user, session, and generate a treatment plan via the AI pipeline."""
    from app.services.ai_pipeline import run_pipeline

    # Check if already exists
    existing = await db.execute(select(User).where(User.email == client_email))
    if existing.scalar_one_or_none():
        print(f"  Client {client_email} already exists, skipping.")
        return

    # Create user
    user = User(
        email=client_email,
        name=client_name,
        role="client",
        password_hash=hash_password("demo123"),
    )
    db.add(user)
    await db.flush()

    # Create client profile
    client = Client(
        user_id=user.id,
        therapist_id=therapist.id,
        name=client_name,
    )
    db.add(client)
    await db.flush()

    # Read transcript fixture
    fixture_path = Path(__file__).resolve().parent / "evaluation" / "fixtures" / fixture_name
    transcript_text = fixture_path.read_text()

    # Create session
    therapy_session = Session(
        therapist_id=therapist.id,
        client_id=client.id,
        session_date=datetime.utcnow(),
        session_number=1,
        duration_minutes=50,
        status="completed",
    )
    db.add(therapy_session)
    await db.flush()

    # Create transcript
    transcript = Transcript(
        session_id=therapy_session.id,
        content=transcript_text,
        source_type="uploaded",
        word_count=len(transcript_text.split()),
    )
    db.add(transcript)
    await db.flush()

    print(f"  Running AI pipeline for {client_name} ({fixture_name})...")
    pipeline_result = await run_pipeline(transcript_text)

    # Create treatment plan
    plan = TreatmentPlan(
        client_id=client.id,
        therapist_id=therapist.id,
        status="draft",
    )
    db.add(plan)
    await db.flush()

    # Create version
    version = TreatmentPlanVersion(
        treatment_plan_id=plan.id,
        version_number=1,
        session_id=therapy_session.id,
        therapist_content=pipeline_result.therapist_content.model_dump(),
        client_content=pipeline_result.client_content.model_dump(),
        change_summary="AI-generated treatment plan",
        source="ai_generated",
        ai_metadata=pipeline_result.ai_metadata,
    )
    db.add(version)
    await db.flush()

    plan.current_version_id = version.id

    # Safety flags
    from app.models.safety_flag import SafetyFlag
    for sf in pipeline_result.safety_flags:
        flag = SafetyFlag(
            session_id=therapy_session.id,
            treatment_plan_version_id=version.id,
            flag_type=sf.flag_type.value if hasattr(sf.flag_type, "value") else sf.flag_type,
            severity=sf.severity.value if hasattr(sf.severity, "value") else sf.severity,
            description=sf.description,
            transcript_excerpt=sf.transcript_excerpt,
            line_start=sf.line_start,
            line_end=sf.line_end,
            source=sf.source,
        )
        db.add(flag)

    # Homework
    for hw_desc in pipeline_result.homework_items:
        hw = HomeworkItem(
            treatment_plan_version_id=version.id,
            client_id=client.id,
            description=hw_desc,
        )
        db.add(hw)

    # Session summary
    summary = SessionSummary(
        session_id=therapy_session.id,
        therapist_summary=pipeline_result.therapist_session_summary,
        client_summary=pipeline_result.client_session_summary,
        key_themes=pipeline_result.key_themes,
    )
    db.add(summary)
    await db.flush()

    print(f"  Safety flags: {len(pipeline_result.safety_flags)}, homework: {len(pipeline_result.homework_items)}")

    # Acknowledge flags + approve (for depression/anxiety — no real crisis)
    await acknowledge_and_approve_plan(db, plan.id, version.id)

    print(f"  Created and approved plan for {client_name} (plan_id={plan.id}, version_id={version.id})")
    return client


async def main():
    async with async_session_factory() as db:
        # Get therapist
        result = await db.execute(
            select(User).where(User.email == "therapist@tava.health")
        )
        therapist_user = result.scalar_one_or_none()
        if therapist_user is None:
            print("ERROR: Run app.seed first (therapist@tava.health not found)")
            return

        therapist = therapist_user.therapist_profile
        print(f"Therapist: {therapist_user.name} (id={therapist.id})")

        # 1. Approve Alex Rivera's plan with a clean new version from anxiety.txt
        print("\n1. Fixing Alex Rivera demo plan...")
        alex_result = await db.execute(select(Client).where(Client.name == "Alex Rivera"))
        alex = alex_result.scalar_one_or_none()
        if alex and alex.treatment_plan:
            plan = alex.treatment_plan
            if plan.status != "approved":
                # Acknowledge all flags and approve
                await acknowledge_and_approve_plan(db, plan.id, plan.current_version_id)
                print(f"  Alex Rivera's plan approved (plan_id={plan.id})")
            else:
                print("  Alex Rivera's plan already approved")

        # 2. Create second client Jordan Kim with depression transcript
        print("\n2. Creating Jordan Kim (depression scenario)...")
        await create_client_with_plan(
            db,
            therapist,
            fixture_name="depression.txt",
            client_name="Jordan Kim",
            client_email="jordan@demo.tava.health",
        )

        await db.commit()
        print("\nDemo seed complete!")
        print("Demo accounts:")
        print("  therapist@tava.health / demo123")
        print("  client@tava.health / demo123  (Alex Rivera — approved plan)")
        print("  jordan@demo.tava.health / demo123  (Jordan Kim — approved plan)")


if __name__ == "__main__":
    asyncio.run(main())
