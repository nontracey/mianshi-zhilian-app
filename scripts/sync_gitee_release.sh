#!/usr/bin/env bash
set -euo pipefail

asset_dir="${1:-release-assets}"
tag="${2:-${GITHUB_REF_NAME:-}}"
notes_file="${3:-release_notes.md}"

if [ -z "$tag" ]; then
  echo "Usage: scripts/sync_gitee_release.sh <asset_dir> <tag> [notes_file]" >&2
  exit 64
fi

if [ -z "${GITEE_TOKEN:-}" ]; then
  echo "GITEE_TOKEN is not set; skipping Gitee release sync."
  exit 0
fi

owner="${GITEE_OWNER:-nontracey}"
repo="${GITEE_REPO:-mianshi-zhilian-app}"
api_base="${GITEE_API_BASE_URL:-https://gitee.com/api/v5}"
target_commitish="${GITEE_TARGET_COMMITISH:-master}"

if [ ! -d "$asset_dir" ]; then
  echo "Asset directory not found: $asset_dir" >&2
  exit 66
fi

body="Release $tag"
if [ -f "$notes_file" ]; then
  body="$(cat "$notes_file")"
fi

release_json="$(mktemp)"
existing_assets="$(mktemp)"
trap 'rm -f "$release_json" "$existing_assets"' EXIT

status="$(
  curl -sS -o "$release_json" -w "%{http_code}" \
    "$api_base/repos/$owner/$repo/releases/tags/$tag?access_token=$GITEE_TOKEN"
)"

release_id=""
if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
  release_id="$(python3 - "$release_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print(data.get("id", "") if isinstance(data, dict) else "")
PY
)"
fi

if [ "$status" = "404" ] || [ -z "$release_id" ]; then
  status="$(
    curl -sS -o "$release_json" -w "%{http_code}" \
      -X POST "$api_base/repos/$owner/$repo/releases" \
      --data-urlencode "access_token=$GITEE_TOKEN" \
      --data-urlencode "tag_name=$tag" \
      --data-urlencode "name=$tag" \
      --data-urlencode "target_commitish=$target_commitish" \
      --data-urlencode "body=$body"
  )"
fi

if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
  echo "Failed to create or fetch Gitee release $tag, status=$status" >&2
  cat "$release_json" >&2
  exit 1
fi

release_id="$(python3 - "$release_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print(data.get("id", "") if isinstance(data, dict) else "")
PY
)"

if [ -z "$release_id" ]; then
  echo "Gitee release response did not include id:" >&2
  cat "$release_json" >&2
  exit 1
fi

python3 - "$release_json" > "$existing_assets" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

items = data.get("attach_files") or data.get("assets") or data.get("files") or []
for item in items:
    if not isinstance(item, dict):
        continue
    name = item.get("name") or item.get("filename")
    if name:
        print(name)
PY

while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  if grep -Fxq "$name" "$existing_assets"; then
    echo "Skipping existing Gitee asset $name"
    continue
  fi
  echo "Uploading $name to Gitee release $tag"
  status="$(
    curl -sS -o "$release_json" -w "%{http_code}" \
      -X POST "$api_base/repos/$owner/$repo/releases/$release_id/attach_files" \
      -F "access_token=$GITEE_TOKEN" \
      -F "file=@$file"
  )"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "Failed to upload $name to Gitee, status=$status" >&2
    cat "$release_json" >&2
    exit 1
  fi
done < <(find "$asset_dir" -maxdepth 1 -type f -print0 | sort -z)

echo "Gitee release synced: https://gitee.com/$owner/$repo/releases/tag/$tag"
