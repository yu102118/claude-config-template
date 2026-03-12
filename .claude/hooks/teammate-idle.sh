#!/usr/bin/env bash
set -euo pipefail

# Count TODOs and FIXMEs in core/
count=$(grep -rn --include="*.py" -E "TODO|FIXME" core/ 2>/dev/null | wc -l | tr -d ' ')

if [ "$count" -gt 0 ]; then
  echo "${count} TODO/FIXME(s) remain in core/. Clean them up." >&2
  exit 2
fi

exit 0
