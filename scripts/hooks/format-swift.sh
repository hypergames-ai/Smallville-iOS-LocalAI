#!/bin/bash
# PostToolUse hook: formats a Swift file right after Claude edits or writes it.
# Claude Code passes the tool call as JSON on stdin; we only need tool_input.file_path.
# Exits 0 always so a formatter problem never blocks the agent.

input=$(cat)
file=$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")' 2>/dev/null)

case "$file" in
  *.swift)
    if command -v swift >/dev/null 2>&1 && [ -f "$file" ]; then
      swift format --in-place "$file" >/dev/null 2>&1 || true
    fi
    ;;
esac
exit 0
