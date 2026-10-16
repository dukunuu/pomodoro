#!/usr/bin/env python3
"""Seal the optional feedback setup for a release build. Never print its contents.

Reads the setup bundle from FEEDBACK_SETUP_JSON (inline) or FEEDBACK_SETUP_FILE,
and the email domains allowed to open it from FEEDBACK_EMAIL_DOMAINS
(comma-separated, default nashatech.com). Writes the sealed file to the path
given, or removes a stale one when no setup is supplied.

The app opens it only while someone is signed in to Whistler with an address
on one of those domains. Sealing keeps it from being readable text in the
download; anyone holding a release can still recover it.
"""
import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import pomodoro_feedback as feedback  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output")
    output = Path(parser.parse_args().output)
    text = os.environ.get("FEEDBACK_SETUP_JSON", "").strip()
    if not text and os.environ.get("FEEDBACK_SETUP_FILE", "").strip():
        text = Path(os.environ["FEEDBACK_SETUP_FILE"]).read_text(encoding="utf-8")
    if not text:
        output.unlink(missing_ok=True)
        print("    no feedback setup supplied; users import their own in Feedback")
        return 0
    # CI passes an unset repository variable as an empty string, not as absent.
    domains = (os.environ.get("FEEDBACK_EMAIL_DOMAINS", "").strip() or "nashatech.com").split(",")
    try:
        bundle = json.loads(text)
        framework, form, members = feedback.merge_setup(
            None, None, {"importedAt": 0, "people": (bundle.get("members") or {}).get("people", [])}, bundle)
        resolved = feedback.resolve_members(form, framework, members)
        output.write_bytes(feedback.seal_setup(feedback.setup_bundle(framework, form, members), domains))
    except (json.JSONDecodeError, AttributeError, feedback.FeedbackError) as error:
        print(f"    ERROR: supplied feedback setup is not valid: {error}", file=sys.stderr)
        return 1
    if feedback.unseal_setup(output.read_bytes()) is None:
        print("    ERROR: the sealed feedback setup does not open again", file=sys.stderr)
        return 1
    print(f"    baked in feedback setup: {len(resolved)} members, opens for @{', @'.join(sorted(d.strip().lower().lstrip('@') for d in domains))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
