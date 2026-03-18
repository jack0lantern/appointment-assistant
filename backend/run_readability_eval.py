#!/usr/bin/env python3
"""
Standalone script to run readability evaluation only on fixture transcripts.
"""
import asyncio
import sys
import time
from pathlib import Path

from app.services.ai_pipeline import run_pipeline
from app.services.evaluation_service import analyze_readability


async def main():
    fixture_dir = Path(__file__).resolve().parent / "evaluation" / "fixtures"
    txt_files = sorted(fixture_dir.glob("*.txt"))

    if not txt_files:
        print(f"❌ No fixture files found in {fixture_dir}")
        return 1

    print(f"📊 Running readability evaluation on {len(txt_files)} fixtures...\n")

    passed_readability = 0
    total = len(txt_files)

    for idx, txt_file in enumerate(txt_files, 1):
        transcript_text = txt_file.read_text()
        t0 = time.time()

        try:
            pipeline_result = await run_pipeline(transcript_text)
            elapsed = time.time() - t0

            tc = pipeline_result.therapist_content.model_dump()
            cc = pipeline_result.client_content.model_dump()

            readability = analyze_readability(tc, cc)

            status = "✅" if readability.target_met else "❌"
            print(f"{status} [{idx}/{total}] {txt_file.name}")
            print(f"     Client: {readability.client_scores.flesch_kincaid_grade:.1f}° | Therapist: {readability.therapist_scores.flesch_kincaid_grade:.1f}°")
            print(f"     Target (≤8.0°): {readability.target_met} | Separation: {readability.separation_ok}")
            print(f"     Generated in {elapsed:.2f}s\n")

            if readability.target_met:
                passed_readability += 1

        except Exception as e:
            status = "❌"
            elapsed = time.time() - t0
            print(f"{status} [{idx}/{total}] {txt_file.name}")
            print(f"     Error: {e}")
            print(f"     Failed after {elapsed:.2f}s\n")

    print(f"\n📈 Results: {passed_readability}/{total} passed readability target")
    return 0 if passed_readability == total else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
