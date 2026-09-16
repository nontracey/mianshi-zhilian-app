#!/usr/bin/env bash
# Use the same Flutter runner as CI; no separate assertion framework or SDK paths.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
args=()
for file in "$REPO_ROOT"/apps/client/test/coach/*_test.dart; do
  if [[ "$(basename "$file")" == *"${1:-}"* ]]; then
    args+=("$file")
  fi
done
if [ "${#args[@]}" -eq 0 ]; then
  echo 'No matching coach tests' >&2
  exit 2
fi
exec "$REPO_ROOT/scripts/flutter-env.sh" test --no-pub "${args[@]}"
