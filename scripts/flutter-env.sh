#!/usr/bin/env bash
# Portable wrapper: honor the caller's SDK and proxy, keep test loopback direct.
# FLUTTER_BIN=/path/to/flutter
# FLUTTER_ENV_PROXY=http://host:port (optional); off disables proxies.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
if [ "${FLUTTER_ENV_PROXY:-}" = off ]; then
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy
elif [ -n "${FLUTTER_ENV_PROXY:-}" ]; then
  export HTTP_PROXY="$FLUTTER_ENV_PROXY" HTTPS_PROXY="$FLUTTER_ENV_PROXY"
  export http_proxy="$FLUTTER_ENV_PROXY" https_proxy="$FLUTTER_ENV_PROXY"
fi
export NO_PROXY="${NO_PROXY:-${no_proxy:-}},127.0.0.1,localhost,::1"
export no_proxy="$NO_PROXY"
cd "$REPO_ROOT/apps/client"
exec "$FLUTTER_BIN" "$@"
