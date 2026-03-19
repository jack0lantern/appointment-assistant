#!/usr/bin/env python3
"""
Standalone script to run structural validation only on fixture transcripts.
"""
import asyncio
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

import sys
import time

from app.services.ai_pipeline import run_pipeline
from app.services.evaluation_service import validate_plan_structure


async def main():
    fixture_dir = Path(__file__).resolve().parent / "evaluation" / "fixtures"
    txt_files = sorted(fixture_dir.glob("*.txt"))

    if not txt_files:
        print(f"❌ No fixture files found in {fixture_dir}")
        return 1

    print(f"📊 Running structural validation on {len(txt_files)} fixtures...\n")

    passed_structural = 0
    total = len(txt_files)

    for idx, txt_file in enumerate(txt_files, 1):
        transcript_text = txt_file.read_text()
        transcript_lines = transcript_text.splitlines()
        t0 = time.time()

        try:
            pipeline_result = await run_pipeline(transcript_text)
            elapsed = time.time() - t0

            tc = pipeline_result.therapist_content.model_dump()
            cc = pipeline_result.client_content.model_dump()

            structural = validate_plan_structure(tc, cc, transcript_lines)

            status = "✅" if structural.valid else "❌"
            print(f"{status} [{idx}/{total}] {txt_file.name}")
            print(f"     Schema OK: {structural.missing_fields == [] and structural.errors == []}")
            print(f"     Citations Valid: {structural.citation_bounds_valid}")
            print(f"     No Jargon: {len(structural.jargon_found) == 0} {structural.jargon_found or ''}")
            print(f"     No Risk Data: {not structural.risk_data_found}")
            print(f"     Generated in {elapsed:.2f}s\n")

            if structural.valid:
                passed_structural += 1

        except Exception as e:
            status = "❌"
            elapsed = time.time() - t0
            print(f"{status} [{idx}/{total}] {txt_file.name}")
            print(f"     Error: {e}")
            print(f"     Failed after {elapsed:.2f}s\n")

    print(f"\n📈 Results: {passed_structural}/{total} passed structural validation")
    return 0 if passed_structural == total else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
