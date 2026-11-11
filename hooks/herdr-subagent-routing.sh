#!/bin/sh
# SessionStart hook: inside Herdr, inject the subagent routing rule.
# Usage: herdr-subagent-routing.sh claude|codex|agy
# Outside Herdr it injects nothing.
set -u

format="${1:-claude}"
cat >/dev/null 2>&1 || true   # drain the hook payload on stdin

empty() { [ "$format" = agy ] && printf '{}\n'; exit 0; }

[ "${HERDR_ENV:-}" = "1" ] || empty
command -v python3 >/dev/null 2>&1 || empty

script_dir=$(cd "$(dirname "$0")" && pwd -P)
rule="$script_dir/herdr-subagent-routing.md"
[ -f "$rule" ] || empty

exec python3 - "$format" "$rule" <<'PY'
import json, sys
fmt, path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read().strip()
if fmt == "agy":
    out = {"injectSteps": [{"systemMessage": {"systemMessage": text}}]}
else:  # claude, codex
    out = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}
print(json.dumps(out, ensure_ascii=False))
PY
