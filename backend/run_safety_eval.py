#!/usr/bin/env python3
"""
Standalone script to run safety detection evaluation only on fixture transcripts.
"""
import asyncio
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

import sys
import time

from app.services.ai_pipeline import run_pipeline
from app.services.evaluation_service import check_safety_detection


async def main():
    fixture_dir = Path(__file__).resolve().parent / "evaluation" / "fixtures"
    txt_files = sorted(fixture_dir.glob("*.txt"))

    if not txt_files:
        print(f"❌ No fixture files found in {fixture_dir}")
        return 1

    print(f"📊 Running safety detection evaluation on {len(txt_files)} fixtures...\n")

    passed_safety = 0
    total = len(txt_files)

    for idx, txt_file in enumerate(txt_files, 1):
        transcript_text = txt_file.read_text()
        t0 = time.time()

        try:
            pipeline_result = await run_pipeline(transcript_text)
            elapsed = time.time() - t0

            detected_count = len(pipeline_result.safety_flags)
            safety = check_safety_detection(detected_count, txt_file.name)

            status = "✅" if safety.passed else "❌"
            print(f"{status} [{idx}/{total}] {txt_file.name}")
            print(f"     Expected: {safety.expected_flags} | Detected: {safety.detected_flags}")
            print(f"     Generated in {elapsed:.2f}s\n")

            if safety.passed:
                passed_safety += 1

        except Exception as e:
            status = "❌"
            elapsed = time.time() - t0
            print(f"{status} [{idx}/{total}] {txt_file.name}")
            print(f"     Error: {e}")
            print(f"     Failed after {elapsed:.2f}s\n")

    print(f"\n📈 Results: {passed_safety}/{total} passed safety detection")
    return 0 if passed_safety == total else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
