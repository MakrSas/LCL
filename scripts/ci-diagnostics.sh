#!/usr/bin/env bash
# Turn an .xcresult bundle into a compact Markdown report.
#
# Why this exists: development happens on Windows with no Xcode, so a raw xcodebuild log
# (tens of thousands of lines) is unreadable and blows the model's context budget. This
# emits the failing diagnostics only — the same shape BuildLogAnalyzer will later feed to
# the model (see docs/CONTEXT_ENGINE.md §5).
#
# Usage: ci-diagnostics.sh <path.xcresult> <path.log>

set -uo pipefail

RESULT_BUNDLE="${1:-}"
RAW_LOG="${2:-}"

emit_section() { # $1 = heading, $2 = body
  [ -z "${2:-}" ] && return 0
  printf '\n## %s\n\n```\n%s\n```\n' "$1" "$2"
}

echo "# Build diagnostics"
echo
echo "- Xcode: \`$(xcodebuild -version 2>/dev/null | head -1)\`"
echo "- Result bundle: \`${RESULT_BUNDLE}\`"

# ---------------------------------------------------------------------------
# Preferred path: structured results from xcresulttool.
# Xcode 16+ replaced the old `get --format json` with explicit subcommands; the old
# form now requires --legacy. Try new, then legacy, then fall back to the log.
# ---------------------------------------------------------------------------
STRUCTURED=""
if [ -n "$RESULT_BUNDLE" ] && [ -d "$RESULT_BUNDLE" ]; then
  STRUCTURED="$(xcrun xcresulttool get build-results \
                  --path "$RESULT_BUNDLE" --format json 2>/dev/null || true)"

  if [ -z "$STRUCTURED" ]; then
    STRUCTURED="$(xcrun xcresulttool get --legacy \
                    --path "$RESULT_BUNDLE" --format json 2>/dev/null || true)"
  fi
fi

if [ -n "$STRUCTURED" ] && command -v python3 >/dev/null 2>&1; then
  echo "$STRUCTURED" | python3 - <<'PY'
import json, sys, collections

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

errors, warnings = [], []

def walk(node):
    """The bundle shape differs between Xcode versions, so walk generically and
    collect anything that looks like a diagnostic rather than assuming a schema."""
    if isinstance(node, dict):
        kind = str(node.get("severity") or node.get("issueType") or "").lower()
        msg  = node.get("message") or node.get("title")
        if isinstance(msg, dict):
            msg = msg.get("text") or msg.get("_value")
        if msg:
            loc = node.get("documentLocationInCreatingWorkspace") or node.get("sourceURL") or {}
            if isinstance(loc, dict):
                loc = loc.get("url") or loc.get("_value") or ""
            entry = f"{loc}\n    {msg}" if loc else str(msg)
            if "error" in kind:
                errors.append(entry)
            elif "warn" in kind:
                warnings.append(entry)
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)

walk(data)

def dedupe(xs):
    return list(collections.OrderedDict.fromkeys(xs))

errors, warnings = dedupe(errors), dedupe(warnings)

if errors:
    print("\n## Errors\n")
    print("```")
    for e in errors[:60]:
        print(f"- {e}")
    if len(errors) > 60:
        print(f"... and {len(errors)-60} more")
    print("```")

if warnings:
    print("\n## Warnings\n")
    print("```")
    for w in warnings[:40]:
        print(f"- {w}")
    if len(warnings) > 40:
        print(f"... and {len(warnings)-40} more")
    print("```")

if not errors and not warnings:
    print("\nNo diagnostics found in result bundle.\n")
PY
else
  echo
  echo "_xcresulttool produced no structured output; falling back to log scraping._"
fi

# ---------------------------------------------------------------------------
# Fallback / supplement: scrape the raw log. Always useful for link errors and
# toolchain failures, which do not always land in the result bundle.
# ---------------------------------------------------------------------------
if [ -n "$RAW_LOG" ] && [ -f "$RAW_LOG" ]; then
  LOG_ERRORS="$(grep -E "(error:|fatal error:|ld: error|clang: error|Command .* failed)" "$RAW_LOG" \
                 | sed 's/^[[:space:]]*//' | sort -u | head -60 || true)"
  emit_section "Log errors" "$LOG_ERRORS"

  FAILED_TESTS="$(grep -E "^Test Case .* failed|XCTAssert.* failed" "$RAW_LOG" \
                   | sed 's/^[[:space:]]*//' | sort -u | head -40 || true)"
  emit_section "Failed tests" "$FAILED_TESTS"

  TAIL="$(grep -E "(BUILD FAILED|BUILD SUCCEEDED|TEST FAILED|TEST SUCCEEDED|Testing failed)" "$RAW_LOG" \
           | tail -5 || true)"
  emit_section "Outcome" "$TAIL"
fi

exit 0
