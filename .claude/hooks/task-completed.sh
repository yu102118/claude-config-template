#!/usr/bin/env bash
set -euo pipefail

# Run Django tests
if ! python manage.py test core --verbosity=0 2>&1; then
  echo "Tests failing. Fix before marking complete." >&2
  exit 2
fi

# Verify public retriever interface still exists
if ! grep -q "get_top_chunks_for_subject" core/services/retriever.py 2>/dev/null; then
  echo "Public retriever interface broken. pipeline.py depends on it." >&2
  exit 2
fi

echo "Quality gate passed."
exit 0
