#!/usr/bin/env python3
import os
from pathlib import Path

token = os.environ.get("COCKPIT_APP_TOKEN", "")
if not token or len(token) < 32 or not all(c.isalnum() or c in "-_" for c in token):
    raise SystemExit("COCKPIT_APP_TOKEN must be URL-safe and at least 32 characters")

target = Path(__file__).parents[1] / "CodexCockpit/AppAuth.generated.swift"
target.write_text(
    "import Foundation\n\n"
    "enum AppAuth {\n"
    f'    static let cockpitToken = "{token}"\n'
    "}\n",
    encoding="utf-8",
)
print(target)
