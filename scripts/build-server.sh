#!/usr/bin/env bash
#
# Builds the custom server binary from pinned upstream source plus our patches.
#
# Usage: ./scripts/build-server.sh [output-path]
# Requires: git, go, node, npm.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(readlink -f "${1:-$ROOT/dist/custom-server}")"
WORK="$ROOT/build/server"

# shellcheck source=../upstream.env
source "$ROOT/upstream.env"

echo "==> upstream $SERVER_TAG"
rm -rf "$WORK"; mkdir -p "$(dirname "$WORK")" "$(dirname "$OUT")"
git clone --quiet --depth 1 --branch "$SERVER_TAG" \
    https://github.com/mattermost/mattermost.git "$WORK"

for patch in "$ROOT"/patches/server/*.patch; do
    echo "    $(basename "$patch")"
    git -C "$WORK" apply "$patch"
done

# NOTE: no brand-asset replacement here — upstream artwork ships as-is.

# Upstream's own build does this and gitignores the result: the server module
# depends on server/public, and without a workspace Go resolves it to the
# published version, which lags the tree and fails to compile.
( cd "$WORK/server" && go work init . ./public )

( cd "$WORK/server" && go build -o "$OUT" ./cmd/mattermost )

# Two patches change only the web app, and the official image ships a prebuilt
# one. Without this step those patches are inert: the guest administration
# screens stay hidden and the licence badges stay put. Roughly four minutes.
if [ "${SKIP_WEBAPP:-}" != "1" ]; then
    echo "==> building the web app"
    ( cd "$WORK/webapp" && npm ci --no-audit --no-fund )
    ( cd "$WORK/webapp" && NODE_OPTIONS=--max-old-space-size=6144 npm run build )
    rm -rf "$(dirname "$OUT")/client"
    cp -r "$WORK/webapp/channels/dist" "$(dirname "$OUT")/client"
    echo "==> $(dirname "$OUT")/client"
fi

echo "==> $OUT"
