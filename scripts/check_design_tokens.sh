#!/usr/bin/env bash
#
# Flags widget code that bypasses Attune's design tokens
# (lib/app/theme/design_tokens.dart, app_colors.dart) in favor of raw,
# hardcoded values — the actual drift risk in a token system this mature
# is bypass, not absence of tokens to begin with.
#
# This is a grep-based signal, not a real analyzer: it will have false
# positives (e.g. EdgeInsets built from a non-token runtime value like
# `widget.size * 0.25`) and can't see every real violation. Treat its
# output as "worth a look", not an automatic failure.
#
# Usage:
#   scripts/check_design_tokens.sh              # scan all of lib/
#   scripts/check_design_tokens.sh lib/features/chat   # scan one path

set -euo pipefail

cd "$(dirname "$0")/.."

SCAN_PATH="${1:-lib}"
EXCLUDE_DIR="lib/app/theme/"
ISSUES=0

section() {
  echo ""
  echo "── $1 ──"
}

# Matches lines flagged by PATTERN, printed as file:line, excluding the
# theme folder itself (where raw values are the source of truth) and any
# EXTRA_EXCLUDE pattern (lines that already reference a token and would
# otherwise false-positive).
scan() {
  local label="$1"
  local pattern="$2"
  local extra_exclude="${3:-}"

  local matches
  if [ -n "$extra_exclude" ]; then
    matches=$(grep -rEn "$pattern" "$SCAN_PATH" --include="*.dart" 2>/dev/null \
      | grep -v "$EXCLUDE_DIR" \
      | grep -vE "$extra_exclude" || true)
  else
    matches=$(grep -rEn "$pattern" "$SCAN_PATH" --include="*.dart" 2>/dev/null \
      | grep -v "$EXCLUDE_DIR" || true)
  fi

  local count=0
  if [ -n "$matches" ]; then
    count=$(echo "$matches" | wc -l | tr -d ' ')
  fi

  if [ "$count" -gt 0 ]; then
    section "$label ($count)"
    echo "$matches"
    ISSUES=$((ISSUES + count))
  fi
}

echo "Scanning $SCAN_PATH for design-token bypasses..."

# Raw hex colors instead of AppColors/ColorScheme. const/final Color(0x...)
# or Color.fromARGB(...) outside the theme folder.
scan "Raw Color(0x...) instead of AppColors/colorScheme" \
  'Color(\.fromARGB)?\(0?x?[0-9A-Fa-f]{6,8}\)|Color\.fromARGB\('

# Hardcoded EdgeInsets numeric literals instead of Spacing.*. Excludes
# lines that already reference Spacing/BorderRadiusTokens, or use
# ScreenUtil's .w/.h (already a token-adjacent scaling call).
scan "Hardcoded EdgeInsets literal instead of Spacing.*" \
  'EdgeInsets\.(all|symmetric|only|fromLTRB)\([^)]*[0-9]+\.?[0-9]*[^)]*\)' \
  'Spacing\.|BorderRadiusTokens\.|\.w[,)]|\.h[,)]|\.w\)|\.h\)'

# Hardcoded BorderRadius.circular(N) instead of BorderRadiusTokens.*.
scan "Hardcoded BorderRadius.circular(N) instead of BorderRadiusTokens.*" \
  'BorderRadius\.circular\([0-9]+\.?[0-9]*\)' \
  'BorderRadiusTokens\.'

# Hardcoded Duration(milliseconds: N) instead of AnimationDurations.*.
scan "Hardcoded Duration(...) instead of AnimationDurations.*" \
  'Duration\(milliseconds: [0-9]+\)' \
  'AnimationDurations\.'

# Literal fontSize: N instead of FontSizeTokens.* or a named TextTheme style.
scan "Literal fontSize: N instead of FontSizeTokens.* or TextTheme" \
  'fontSize: [0-9]+\.?[0-9]*[,)]' \
  'FontSizeTokens\.|\.sp[,)]'

echo ""
if [ "$ISSUES" -eq 0 ]; then
  echo "No design-token bypasses found in $SCAN_PATH."
  exit 0
else
  echo "Found $ISSUES potential design-token bypass(es) above."
  echo "Each is worth a manual look — not every hit is a real violation."
  exit 1
fi
