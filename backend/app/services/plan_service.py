# Services for plan versioning and diff computation

import difflib
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.treatment_plan_version import TreatmentPlanVersion


async def get_version_history(plan_id: int, db: AsyncSession) -> list[dict]:
    """Return list of version summaries sorted by version_number desc."""
    result = await db.execute(
        select(TreatmentPlanVersion)
        .where(TreatmentPlanVersion.treatment_plan_id == plan_id)
        .order_by(TreatmentPlanVersion.version_number.desc())
    )
    versions = result.scalars().all()
    return [
        {
            "id": v.id,
            "version_number": v.version_number,
            "source": v.source,
            "session_id": v.session_id,
            "change_summary": v.change_summary,
            "created_at": v.created_at.isoformat() if v.created_at else None,
        }
        for v in versions
    ]


def compute_diff(content1: dict, content2: dict) -> dict:
    """
    Compare two therapist_content dicts section by section using difflib.
    Returns per-section: status (unchanged|modified|added|removed), old_text, new_text, unified_diff
    Only compares string-list sections (keys not ending in _citations).
    """
    all_keys = sorted(set(list(content1.keys()) + list(content2.keys())))
    result = {}
    for key in all_keys:
        if key.endswith("_citations"):
            continue
        val1 = content1.get(key)
        val2 = content2.get(key)

        def to_text(val):
            if val is None:
                return ""
            if isinstance(val, list):
                lines = []
                for item in val:
                    if isinstance(item, str):
                        lines.append(item)
                    elif isinstance(item, dict):
                        lines.append(str(item))
                return "\n".join(lines)
            return str(val)

        text1 = to_text(val1)
        text2 = to_text(val2)

        if text1 == text2:
            status = "unchanged"
        elif val1 is None:
            status = "added"
        elif val2 is None:
            status = "removed"
        else:
            status = "modified"

        unified = list(difflib.unified_diff(
            text1.splitlines(),
            text2.splitlines(),
            lineterm="",
            n=2,
        ))

        result[key] = {
            "status": status,
            "old_text": text1,
            "new_text": text2,
            "unified_diff": "\n".join(unified),
        }
    return result
